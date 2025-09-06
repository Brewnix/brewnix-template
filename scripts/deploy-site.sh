#!/bin/bash
# Site Deployment Script for Brewnix GitOps
# This script deploys a specific site using GitOps principles

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
ENVIRONMENT="production"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --staging)
            ENVIRONMENT="staging"
            shift
            ;;
        --production)
            ENVIRONMENT="production"
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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
    echo "Usage: $0 <site_name> [--staging|--production] [--dry-run]"
    exit 1
fi

# Validate site exists
if [[ ! -d "$REPO_ROOT/sites/$SITE_NAME" ]]; then
    log_error "Site '$SITE_NAME' not found in sites/ directory"
    exit 1
fi

log_info "Starting deployment for site: $SITE_NAME ($ENVIRONMENT)"

# Load site configuration
SITE_CONFIG="$REPO_ROOT/sites/$SITE_NAME/config/site.conf"
if [[ ! -f "$SITE_CONFIG" ]]; then
    log_error "Site configuration not found: $SITE_CONFIG"
    exit 1
fi

source "$SITE_CONFIG"
log_info "Loaded configuration for $SITE_DISPLAY_NAME"

# Set environment-specific variables
case $ENVIRONMENT in
    staging)
        PROXMOX_HOST="${STAGING_PROXMOX_HOST:-$PROXMOX_HOST}"
        ;;
    production)
        PROXMOX_HOST="${PRODUCTION_PROXMOX_HOST:-$PROXMOX_HOST}"
        ;;
    *)
        log_error "Unknown environment: $ENVIRONMENT"
        exit 1
        ;;
esac

# Export environment variables for Terraform and Ansible
export TF_VAR_site_name="$SITE_NAME"
export TF_VAR_site_display_name="$SITE_DISPLAY_NAME"
export TF_VAR_network_prefix="$NETWORK_PREFIX"
export TF_VAR_domain="$DOMAIN"
export TF_VAR_proxmox_host="$PROXMOX_HOST"
export TF_VAR_environment="$ENVIRONMENT"

export ANSIBLE_HOST_KEY_CHECKING=False
export ANSIBLE_SSH_PRIVATE_KEY_FILE="/root/.ssh/sites/deployment_key"

# Create deployment log
DEPLOY_LOG="/var/log/brewnix/${SITE_NAME}_deployment_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$DEPLOY_LOG")"

exec > >(tee -a "$DEPLOY_LOG") 2>&1

log_step "Starting deployment process for $SITE_NAME"

# Pre-deployment checks
log_step "Running pre-deployment checks..."

# Check connectivity to Proxmox host
if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@$PROXMOX_HOST" "echo 'Proxmox host reachable'" 2>/dev/null; then
    log_error "Cannot connect to Proxmox host: $PROXMOX_HOST"
    exit 1
fi

# Check if required files exist
required_files=(
    "$REPO_ROOT/sites/$SITE_NAME/config/site.conf"
    "$REPO_ROOT/vendor/proxmox-firewall/ansible/playbooks"
    "$REPO_ROOT/vendor/proxmox-firewall/terraform"
)

for file in "${required_files[@]}"; do
    if [[ ! -e "$file" ]]; then
        log_error "Required file/directory not found: $file"
        exit 1
    fi
done

log_info "Pre-deployment checks passed"

# Update submodules if needed
log_step "Ensuring submodules are up to date..."
cd "$REPO_ROOT"
git submodule update --init --recursive

# Create site-specific directories
log_step "Setting up site directories..."
mkdir -p "$REPO_ROOT/sites/$SITE_NAME/terraform/state"
mkdir -p "$REPO_ROOT/sites/$SITE_NAME/ansible/inventory"
mkdir -p "$REPO_ROOT/sites/$SITE_NAME/logs"

# Generate site-specific configuration
log_step "Generating site configuration..."
cd "$REPO_ROOT/vendor/proxmox-firewall/deployment/scripts"

# Create site-specific environment file
cat > "$REPO_ROOT/sites/$SITE_NAME/.env" << EOF
# Site-specific environment variables
SITE_NAME="$SITE_NAME"
SITE_DISPLAY_NAME="$SITE_DISPLAY_NAME"
NETWORK_PREFIX="$NETWORK_PREFIX"
DOMAIN="$DOMAIN"
PROXMOX_HOST="$PROXMOX_HOST"
ENVIRONMENT="$ENVIRONMENT"

# Generated at $(date)
EOF

# Create Ansible inventory for this site
cat > "$REPO_ROOT/sites/$SITE_NAME/ansible/inventory/hosts.yml" << EOF
all:
  children:
    proxmox:
      hosts:
        proxmox01:
          ansible_host: $PROXMOX_HOST
          ansible_user: root
    $SITE_NAME:
      children:
        proxmox
  vars:
    site_name: $SITE_NAME
    network_prefix: $NETWORK_PREFIX
    domain: $DOMAIN
    environment: $ENVIRONMENT
EOF

# Terraform deployment
log_step "Running Terraform deployment..."
cd "$REPO_ROOT/sites/$SITE_NAME/terraform"

# Initialize Terraform with site-specific state
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "DRY RUN: Would initialize Terraform"
else
    terraform init -backend-config="path=state/terraform.tfstate"
fi

# Plan Terraform changes
log_info "Planning Terraform changes..."
if [[ "$DRY_RUN" == "true" ]]; then
    terraform plan -var-file="$REPO_ROOT/sites/$SITE_NAME/config/terraform.tfvars" -out=tfplan
else
    terraform plan -var-file="$REPO_ROOT/sites/$SITE_NAME/config/terraform.tfvars" -out=tfplan
fi

# Apply Terraform changes
log_step "Applying Terraform changes..."
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "DRY RUN: Would apply Terraform plan"
    terraform show tfplan
else
    terraform apply tfplan
fi

# Ansible deployment
log_step "Running Ansible deployment..."
cd "$REPO_ROOT"

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "DRY RUN: Would run Ansible playbooks"
    ansible-playbook \
        --inventory "$REPO_ROOT/sites/$SITE_NAME/ansible/inventory/hosts.yml" \
        --limit "$SITE_NAME" \
        --check \
        vendor/proxmox-firewall/deployment/ansible/master_playbook.yml
else
    ansible-playbook \
        --inventory "$REPO_ROOT/sites/$SITE_NAME/ansible/inventory/hosts.yml" \
        --limit "$SITE_NAME" \
        vendor/proxmox-firewall/deployment/ansible/master_playbook.yml
fi

# Post-deployment verification
log_step "Running post-deployment verification..."
cd "$REPO_ROOT/proxmox-firewall/tests"

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "DRY RUN: Would run verification tests"
else
    # Run basic connectivity test
    ansible-playbook \
        --inventory "$REPO_ROOT/sites/$SITE_NAME/ansible/inventory/hosts.yml" \
        --limit "$SITE_NAME" \
        --tags connectivity \
        vendor/proxmox-firewall/tests/test_network_connectivity.yml || log_warn "Connectivity test failed"
fi

# Backup state
log_step "Backing up deployment state..."
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "DRY RUN: Would backup state"
else
    "$SCRIPT_DIR/backup-state.sh" "$SITE_NAME"
fi

log_info "Deployment completed successfully for site: $SITE_NAME"
log_info "Deployment log saved to: $DEPLOY_LOG"

# Summary
echo ""
echo "=========================================="
echo "DEPLOYMENT SUMMARY"
echo "=========================================="
echo "Site: $SITE_DISPLAY_NAME ($SITE_NAME)"
echo "Environment: $ENVIRONMENT"
echo "Proxmox Host: $PROXMOX_HOST"
echo "Network: $NETWORK_PREFIX.0.0/16"
echo "Domain: $DOMAIN"
echo "Timestamp: $(date)"
echo "Log: $DEPLOY_LOG"
echo "=========================================="

if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "This was a DRY RUN - no actual changes were made"
fi
