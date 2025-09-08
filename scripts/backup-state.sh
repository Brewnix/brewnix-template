#!/bin/bash
# State Backup Script for Brewnix GitOps
# This script backs up Terraform state and other deployment state

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Parse arguments
SITE_NAME=""
BACKUP_TYPE="full"

while [[ $# -gt 0 ]]; do
    case $1 in
        --terraform-only)
            BACKUP_TYPE="terraform"
            shift
            ;;
        --ansible-only)
            BACKUP_TYPE="ansible"
            shift
            ;;
        --full)
            BACKUP_TYPE="full"
            shift
            ;;
        -*)
            log_error "Unknown option: $1"
            exit 1
            ;;
        *)
            if [[ -z "$SITE_NAME" ]]; then
                SITE_NAME="$1"
            else
                log_error "Multiple site names provided"
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$SITE_NAME" ]]; then
    log_error "Site name is required"
    echo "Usage: $0 <site_name> [--terraform-only|--ansible-only|--full]"
    exit 1
fi

# Validate site exists
if [[ ! -d "$REPO_ROOT/sites/$SITE_NAME" ]]; then
    log_error "Site '$SITE_NAME' not found in sites/ directory"
    exit 1
fi

log_info "Starting state backup for site: $SITE_NAME ($BACKUP_TYPE)"

# Create backup directory structure
BACKUP_ROOT="/var/backup/brewnix"
BACKUP_DIR="$BACKUP_ROOT/$SITE_NAME/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup Terraform state
if [[ "$BACKUP_TYPE" == "full" || "$BACKUP_TYPE" == "terraform" ]]; then
    log_step "Backing up Terraform state..."

    TF_STATE_DIR="$REPO_ROOT/sites/$SITE_NAME/terraform/state"
    if [[ -d "$TF_STATE_DIR" ]]; then
        cp -r "$TF_STATE_DIR" "$BACKUP_DIR/terraform_state"

        # Also backup terraform.tfstate from working directory
        TF_WORKING_STATE="$REPO_ROOT/sites/$SITE_NAME/terraform/terraform.tfstate"
        if [[ -f "$TF_WORKING_STATE" ]]; then
            cp "$TF_WORKING_STATE" "$BACKUP_DIR/terraform_state/"
        fi

        log_info "Terraform state backed up to: $BACKUP_DIR/terraform_state"
    else
        log_warn "Terraform state directory not found: $TF_STATE_DIR"
    fi
fi

# Backup Ansible facts and variables
if [[ "$BACKUP_TYPE" == "full" || "$BACKUP_TYPE" == "ansible" ]]; then
    log_step "Backing up Ansible state..."

    ANSIBLE_DIR="$REPO_ROOT/sites/$SITE_NAME/ansible"
    if [[ -d "$ANSIBLE_DIR" ]]; then
        # Backup inventory
        if [[ -d "$ANSIBLE_DIR/inventory" ]]; then
            cp -r "$ANSIBLE_DIR/inventory" "$BACKUP_DIR/ansible_inventory"
        fi

        # Backup any cached facts
        if [[ -d "$ANSIBLE_DIR/facts" ]]; then
            cp -r "$ANSIBLE_DIR/facts" "$BACKUP_DIR/ansible_facts"
        fi

        log_info "Ansible state backed up to: $BACKUP_DIR/ansible_*"
    fi
fi

# Backup site configuration
if [[ "$BACKUP_TYPE" == "full" ]]; then
    log_step "Backing up site configuration..."

    SITE_CONFIG_DIR="$REPO_ROOT/sites/$SITE_NAME/config"
    if [[ -d "$SITE_CONFIG_DIR" ]]; then
        cp -r "$SITE_CONFIG_DIR" "$BACKUP_DIR/site_config"
        log_info "Site configuration backed up to: $BACKUP_DIR/site_config"
    fi

    # Backup environment file
    ENV_FILE="$REPO_ROOT/sites/$SITE_NAME/.env"
    if [[ -f "$ENV_FILE" ]]; then
        cp "$ENV_FILE" "$BACKUP_DIR/"
        log_info "Environment file backed up to: $BACKUP_DIR/.env"
    fi
fi

# Backup logs
log_step "Backing up recent logs..."
LOG_BACKUP_DIR="$BACKUP_DIR/logs"
mkdir -p "$LOG_BACKUP_DIR"

# Copy recent deployment logs
find /var/log/brewnix -name "*${SITE_NAME}*" -mtime -7 -exec cp {} "$LOG_BACKUP_DIR/" \;

# Backup current git state
log_step "Recording git state..."
cd "$REPO_ROOT"
GIT_INFO="$BACKUP_DIR/git_info.txt"
{
    echo "Git State Backup - $(date)"
    echo "================================"
    echo ""
    echo "Current commit:"
    git log --oneline -1
    echo ""
    echo "Status:"
    git status --porcelain
    echo ""
    echo "Submodule status:"
    git submodule status
    echo ""
    echo "Recent commits:"
    git log --oneline -10
} > "$GIT_INFO"

# Create backup manifest
log_step "Creating backup manifest..."
MANIFEST="$BACKUP_DIR/BACKUP_MANIFEST.txt"
{
    echo "Brewnix State Backup Manifest"
    echo "======================================"
    echo ""
    echo "Site: $SITE_NAME"
    echo "Timestamp: $(date)"
    echo "Backup Type: $BACKUP_TYPE"
    echo "Backup Directory: $BACKUP_DIR"
    echo ""
    echo "Contents:"
    find "$BACKUP_DIR" -type f | sed "s|$BACKUP_DIR/||" | sort
    echo ""
    echo "Backup Size: $(du -sh "$BACKUP_DIR" | cut -f1)"
} > "$MANIFEST"

# Compress backup
log_step "Compressing backup..."
BACKUP_ARCHIVE="$BACKUP_ROOT/${SITE_NAME}_$(date +%Y%m%d_%H%M%S).tar.gz"
cd "$BACKUP_ROOT"
tar -czf "$BACKUP_ARCHIVE" -C "$BACKUP_ROOT" "$(basename "$BACKUP_DIR")"

# Clean up uncompressed backup
rm -rf "$BACKUP_DIR"

log_info "Backup compressed to: $BACKUP_ARCHIVE"

# Git-based backup (optional, for GitOps)
if [[ -n "$GIT_BACKUP_ENABLED" ]]; then
    log_step "Creating git-based backup..."

    # Create backup branch
    BACKUP_BRANCH="backup/${SITE_NAME}/$(date +%Y%m%d_%H%M%S)"

    git checkout -b "$BACKUP_BRANCH"
    git add "$BACKUP_ARCHIVE"
    git commit -m "Backup: $SITE_NAME state - $(date)"

    # Push to remote (optional)
    if git remote get-url origin &>/dev/null; then
        git push origin "$BACKUP_BRANCH"
        log_info "Backup pushed to branch: $BACKUP_BRANCH"
    fi

    # Return to original branch
    git checkout -
fi

# Cleanup old backups
log_step "Cleaning up old backups..."
cd "$BACKUP_ROOT"

# Keep only last 30 days of backups for this site
find . -name "${SITE_NAME}_*.tar.gz" -mtime +30 -delete

# Keep only last 10 backups for this site
BACKUP_COUNT=$(ls -t ${SITE_NAME}_*.tar.gz 2>/dev/null | wc -l)
if [[ $BACKUP_COUNT -gt 10 ]]; then
    ls -t ${SITE_NAME}_*.tar.gz | tail -n +11 | xargs rm -f
fi

log_info "Old backups cleaned up"

# Verify backup integrity
log_step "Verifying backup integrity..."
if [[ -f "$BACKUP_ARCHIVE" ]]; then
    if tar -tzf "$BACKUP_ARCHIVE" &>/dev/null; then
        log_info "Backup integrity verified"
    else
        log_error "Backup integrity check failed"
        exit 1
    fi
else
    log_error "Backup archive not found"
    exit 1
fi

# Summary
echo ""
echo "=========================================="
echo "BACKUP SUMMARY"
echo "=========================================="
echo "Site: $SITE_NAME"
echo "Type: $BACKUP_TYPE"
echo "Archive: $BACKUP_ARCHIVE"
echo "Size: $(du -sh "$BACKUP_ARCHIVE" | cut -f1)"
echo "Timestamp: $(date)"
echo "=========================================="

log_info "State backup completed successfully"
