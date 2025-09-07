#!/bin/bash
# Brewnix Template - Universal Deployment Script
# Supports all vendor types: NAS, K3S Cluster, Development Server, Security/Firewall

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CONFIG_DIR="$PROJECT_ROOT/config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Usage information
usage() {
    cat << EOF
Brewnix Template - Universal Deployment Script

Usage: $0 <vendor_type> <site_config> [options]

Vendor Types:
  nas               Deploy Proxmox NAS (TrueNAS, PBS, Jellyfin, Samba)
  k3s-cluster       Deploy Kubernetes cluster (K3S multi-node)
  development       Deploy development environment (Code Server, GitLab, etc.)
  security          Deploy security infrastructure (OPNsense, IDS, monitoring)

Site Configuration:
  Site configuration file path (relative to config/sites/)
  Example: k3s-example/k3s-site.yml

Options:
  --check-only      Validate configuration without deployment
  --dry-run         Show what would be deployed without executing
  --tags <tags>     Run only specific Ansible tags (comma-separated)
  --skip-tags <tags> Skip specific Ansible tags (comma-separated)
  --verbose         Enable verbose output
  --help            Show this help message

Examples:
  # Deploy K3S cluster
  $0 k3s-cluster k3s-example/k3s-site.yml

  # Deploy NAS with specific tags
  $0 nas nas-example/nas-site.yml --tags storage,services

  # Validate security configuration
  $0 security security-example/security-site.yml --check-only

  # Deploy development environment with verbose output
  $0 development dev-example/dev-site.yml --verbose

Environment Variables:
  ANSIBLE_VAULT_PASSWORD_FILE  Path to Ansible vault password file
  PROXMOX_API_PASSWORD         Proxmox API password (can override config)
  
EOF
}

# Validate vendor type
validate_vendor_type() {
    local vendor_type="$1"
    local valid_vendors=("nas" "k3s-cluster" "development" "security")
    
    for valid in "${valid_vendors[@]}"; do
        if [[ "$vendor_type" == "$valid" ]]; then
            return 0
        fi
    done
    
    log_error "Invalid vendor type: $vendor_type"
    log_info "Valid vendor types: ${valid_vendors[*]}"
    return 1
}

# Validate site configuration
validate_site_config() {
    local site_config="$1"
    local full_path="$CONFIG_DIR/sites/$site_config"
    
    if [[ ! -f "$full_path" ]]; then
        log_error "Site configuration not found: $full_path"
        log_info "Available configurations:"
        find "$CONFIG_DIR/sites" -name "*.yml" -type f | sed "s|$CONFIG_DIR/sites/||" | sort
        return 1
    fi
    
    # Validate YAML syntax
    if ! python3 -c "import yaml; yaml.safe_load(open('$full_path'))" 2>/dev/null; then
        log_error "Invalid YAML syntax in: $full_path"
        return 1
    fi
    
    return 0
}

# Get vendor directory mapping
get_vendor_directory() {
    local vendor_type="$1"
    
    case "$vendor_type" in
        "nas")
            echo "proxmox-nas"
            ;;
        "k3s-cluster")
            echo "k3s-cluster"
            ;;
        "development")
            echo "development-server"
            ;;
        "security")
            echo "security-firewall"
            ;;
        *)
            log_error "Unknown vendor type: $vendor_type"
            return 1
            ;;
    esac
}

# Execute deployment
deploy() {
    local vendor_type="$1"
    local site_config="$2"
    shift 2
    local ansible_args=("$@")
    
    # Get vendor directory
    local vendor_dir
    vendor_dir=$(get_vendor_directory "$vendor_type")
    local playbook_dir="$PROJECT_ROOT/vendor/$vendor_dir/ansible"
    local playbook_path="$playbook_dir/site.yml"
    
    if [[ ! -f "$playbook_path" ]]; then
        log_error "Playbook not found: $playbook_path"
        return 1
    fi
    
    log_info "Starting deployment for vendor: $vendor_type"
    log_info "Site configuration: $site_config"
    log_info "Playbook: $playbook_path"
    
    # Change to playbook directory
    cd "$playbook_dir"
    
    # Build ansible-playbook command
    local ansible_cmd=(
        "ansible-playbook"
        "site.yml"
        "-e" "site_config_file=$CONFIG_DIR/sites/$site_config"
        "-e" "vendor_type=$vendor_type"
        "-e" "project_root=$PROJECT_ROOT"
    )
    
    # Add additional arguments
    ansible_cmd+=("${ansible_args[@]}")
    
    log_info "Executing: ${ansible_cmd[*]}"
    
    # Execute the playbook
    if "${ansible_cmd[@]}"; then
        log_success "Deployment completed successfully for $vendor_type"
        log_info "Check the deployment logs for details"
        return 0
    else
        log_error "Deployment failed for $vendor_type"
        return 1
    fi
}

# Main function
main() {
    local vendor_type=""
    local site_config=""
    local ansible_args=()
    local check_only=false
    local dry_run=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                usage
                exit 0
                ;;
            --check-only)
                check_only=true
                ansible_args+=("--check")
                shift
                ;;
            --dry-run)
                dry_run=true
                ansible_args+=("--check" "--diff")
                shift
                ;;
            --tags)
                ansible_args+=("--tags" "$2")
                shift 2
                ;;
            --skip-tags)
                ansible_args+=("--skip-tags" "$2")
                shift 2
                ;;
            --verbose|-v)
                ansible_args+=("-v")
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                if [[ -z "$vendor_type" ]]; then
                    vendor_type="$1"
                elif [[ -z "$site_config" ]]; then
                    site_config="$1"
                else
                    log_error "Too many arguments: $1"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "$vendor_type" || -z "$site_config" ]]; then
        log_error "Missing required arguments"
        usage
        exit 1
    fi
    
    # Validate vendor type and site configuration
    if ! validate_vendor_type "$vendor_type"; then
        exit 1
    fi
    
    if ! validate_site_config "$site_config"; then
        exit 1
    fi
    
    # Check for Ansible
    if ! command -v ansible-playbook &> /dev/null; then
        log_error "Ansible is not installed or not in PATH"
        log_info "Please install Ansible: sudo apt install ansible"
        exit 1
    fi
    
    # Execute deployment or check
    if [[ "$check_only" == true ]]; then
        log_info "Configuration validation mode"
    elif [[ "$dry_run" == true ]]; then
        log_info "Dry run mode - no changes will be made"
    fi
    
    if deploy "$vendor_type" "$site_config" "${ansible_args[@]}"; then
        log_success "Operation completed successfully!"
        
        # Show next steps based on vendor type
        case "$vendor_type" in
            "nas")
                log_info "Next steps: Access TrueNAS web UI and configure storage pools"
                ;;
            "k3s-cluster")
                log_info "Next steps: Configure kubectl and deploy applications to the cluster"
                ;;
            "development")
                log_info "Next steps: Access Code Server and set up development projects"
                ;;
            "security")
                log_info "Next steps: Configure firewall rules and security policies"
                ;;
        esac
    else
        log_error "Operation failed!"
        exit 1
    fi
}

# Execute main function
main "$@"
