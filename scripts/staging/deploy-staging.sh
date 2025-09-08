#!/bin/bash
# scripts/staging/deploy-staging.sh - Deploy site to staging environment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

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
STAGING_ENVIRONMENT_ID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: $0 <site_name> <staging_environment_id>"
            echo "Deploy a site to a specific staging environment"
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            exit 1
            ;;
        *)
            if [[ -z "$SITE_NAME" ]]; then
                SITE_NAME="$1"
            elif [[ -z "$STAGING_ENVIRONMENT_ID" ]]; then
                STAGING_ENVIRONMENT_ID="$1"
            else
                log_error "Too many arguments"
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$SITE_NAME" || -z "$STAGING_ENVIRONMENT_ID" ]]; then
    log_error "Site name and staging environment ID are required"
    echo "Usage: $0 <site_name> <staging_environment_id>"
    exit 1
fi

# Validate site exists
if [[ ! -d "$REPO_ROOT/sites/$SITE_NAME" ]]; then
    log_error "Site '$SITE_NAME' not found in sites/ directory"
    exit 1
fi

log_info "Starting staging deployment for site: $SITE_NAME (Environment: $STAGING_ENVIRONMENT_ID)"

# Create staging environment directory
STAGING_DIR="$REPO_ROOT/staging/$STAGING_ENVIRONMENT_ID"
mkdir -p "$STAGING_DIR/logs"
mkdir -p "$STAGING_DIR/config"

# Load site configuration
SITE_CONFIG="$REPO_ROOT/sites/$SITE_NAME/config/site.conf"
if [[ ! -f "$SITE_CONFIG" ]]; then
    log_error "Site configuration not found: $SITE_CONFIG"
    exit 1
fi

source "$SITE_CONFIG"
log_info "Loaded configuration for $SITE_DISPLAY_NAME"

# Set staging-specific variables
export TF_VAR_site_name="$SITE_NAME"
export TF_VAR_site_display_name="$SITE_DISPLAY_NAME"
export TF_VAR_network_prefix="$NETWORK_PREFIX"
export TF_VAR_domain="$DOMAIN"
export TF_VAR_proxmox_host="${STAGING_PROXMOX_HOST:-$PROXMOX_HOST}"
export TF_VAR_environment="staging"
export TF_VAR_staging_environment_id="$STAGING_ENVIRONMENT_ID"

export ANSIBLE_HOST_KEY_CHECKING=False

# Create deployment log
DEPLOY_LOG="$STAGING_DIR/logs/${SITE_NAME}_staging_deployment_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$DEPLOY_LOG") 2>&1

log_step "Starting staging deployment process for $SITE_NAME"

# Pre-deployment checks
log_step "Running pre-deployment checks..."

# Check connectivity to Proxmox host
if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@$TF_VAR_proxmox_host" "echo 'Staging Proxmox host reachable'" 2>/dev/null; then
    log_error "Cannot connect to staging Proxmox host: $TF_VAR_proxmox_host"
    exit 1
fi

# Check if required files exist
required_files=(
    "$REPO_ROOT/sites/$SITE_NAME/config/site.conf"
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

# Create site-specific directories for staging
log_step "Setting up staging site directories..."
mkdir -p "$STAGING_DIR/sites/$SITE_NAME/terraform/state"
mkdir -p "$STAGING_DIR/sites/$SITE_NAME/ansible/inventory"
mkdir -p "$STAGING_DIR/sites/$SITE_NAME/logs"

# Generate site-specific configuration for staging
log_step "Generating staging site configuration..."

# Create staging-specific environment file
cat > "$STAGING_DIR/sites/$SITE_NAME/.env" << EOF
# Staging site-specific environment variables
SITE_NAME="$SITE_NAME"
SITE_DISPLAY_NAME="$SITE_DISPLAY_NAME"
NETWORK_PREFIX="$NETWORK_PREFIX"
DOMAIN="$DOMAIN"
PROXMOX_HOST="$TF_VAR_proxmox_host"
ENVIRONMENT="staging"
STAGING_ENVIRONMENT_ID="$STAGING_ENVIRONMENT_ID"

# Generated at $(date)
EOF

# Create Ansible inventory for staging site
cat > "$STAGING_DIR/sites/$SITE_NAME/ansible/inventory/hosts.yml" << EOF
all:
  children:
    proxmox:
      hosts:
        proxmox01:
          ansible_host: $TF_VAR_proxmox_host
          ansible_user: root
    $SITE_NAME:
      children:
        proxmox
  vars:
    site_name: $SITE_NAME
    network_prefix: $NETWORK_PREFIX
    domain: $DOMAIN
    environment: staging
    staging_environment_id: $STAGING_ENVIRONMENT_ID
EOF

# Terraform deployment for staging
log_step "Running Terraform deployment for staging..."

# Create symbolic links to actual terraform configs
ln -sf "$REPO_ROOT/sites/$SITE_NAME/terraform" "$STAGING_DIR/sites/$SITE_NAME/terraform/config"

cd "$STAGING_DIR/sites/$SITE_NAME/terraform"

# Initialize Terraform with staging-specific state
terraform init -backend-config="path=state/terraform.tfstate"

# Plan Terraform changes for staging
log_info "Planning Terraform changes for staging..."
terraform plan -var-file="$REPO_ROOT/sites/$SITE_NAME/config/terraform.tfvars" -out=tfplan

# Apply Terraform changes for staging
log_step "Applying Terraform changes for staging..."
terraform apply tfplan

# Ansible deployment for staging
log_step "Running Ansible deployment for staging..."
cd "$REPO_ROOT"

# Create symbolic link to ansible playbooks
ln -sf "$REPO_ROOT/vendor/proxmox-firewall/deployment/ansible" "$STAGING_DIR/ansible"

ansible-playbook \
    --inventory "$STAGING_DIR/sites/$SITE_NAME/ansible/inventory/hosts.yml" \
    --limit "$SITE_NAME" \
    "$STAGING_DIR/ansible/master_playbook.yml"

# Post-deployment verification for staging
log_step "Running post-deployment verification for staging..."

# Run basic connectivity test
ansible-playbook \
    --inventory "$STAGING_DIR/sites/$SITE_NAME/ansible/inventory/hosts.yml" \
    --limit "$SITE_NAME" \
    --tags connectivity \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_network_connectivity.yml" || log_warn "Connectivity test failed"

# Create staging environment metadata
cat > "$STAGING_DIR/metadata.json" << EOF
{
  "environment_id": "$STAGING_ENVIRONMENT_ID",
  "site_name": "$SITE_NAME",
  "site_display_name": "$SITE_DISPLAY_NAME",
  "created_at": "$(date -Iseconds)",
  "terraform_state": "$STAGING_DIR/sites/$SITE_NAME/terraform/state",
  "ansible_inventory": "$STAGING_DIR/sites/$SITE_NAME/ansible/inventory/hosts.yml",
  "logs": "$STAGING_DIR/logs",
  "status": "deployed"
}
EOF

log_info "Staging deployment completed successfully for site: $SITE_NAME"
log_info "Staging environment ID: $STAGING_ENVIRONMENT_ID"
log_info "Staging metadata saved to: $STAGING_DIR/metadata.json"
log_info "Deployment log saved to: $DEPLOY_LOG"

# Summary
echo ""
echo "=========================================="
echo "STAGING DEPLOYMENT SUMMARY"
echo "=========================================="
echo "Site: $SITE_DISPLAY_NAME ($SITE_NAME)"
echo "Environment: Staging"
echo "Environment ID: $STAGING_ENVIRONMENT_ID"
echo "Proxmox Host: $TF_VAR_proxmox_host"
echo "Network: $NETWORK_PREFIX.0.0/16"
echo "Domain: $DOMAIN"
echo "Timestamp: $(date)"
echo "Metadata: $STAGING_DIR/metadata.json"
echo "Log: $DEPLOY_LOG"
echo "=========================================="
