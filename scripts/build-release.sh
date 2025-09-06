#!/bin/bash
# Brewnix Generalized Build and Release Workflow
# Supports all server types: proxmox-nas, proxmox-firewall, k3s-cluster

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BOOTSTRAP_DIR="$PROJECT_ROOT/bootstrap"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"
WEB_UI_DIR="$PROJECT_ROOT/web-ui"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Validate configuration
validate_config() {
    local site_config="$1"

    if [[ ! -f "$site_config" ]]; then
        log_error "Site configuration file not found: $site_config"
        return 1
    fi

    # Check required fields
    local required_fields=("site_name" "server_type" "network")
    for field in "${required_fields[@]}"; do
        if ! grep -q "^$field:" "$site_config"; then
            log_error "Required field missing in config: $field"
            return 1
        fi
    done

    # Validate server type
    local server_type
    server_type=$(grep "^server_type:" "$site_config" | cut -d'"' -f2)
    case "$server_type" in
        proxmox-nas|proxmox-firewall|k3s-cluster)
            log_info "Validated server type: $server_type"
            ;;
        *)
            log_error "Invalid server type: $server_type"
            log_error "Supported types: proxmox-nas, proxmox-firewall, k3s-cluster"
            return 1
            ;;
    esac

    log_success "Configuration validation passed"
    return 0
}

# Generate bootstrap USB for specific server type
generate_bootstrap() {
    local site_config="$1"
    local server_type
    server_type=$(grep "^server_type:" "$site_config" | cut -d'"' -f2)

    log_info "Generating bootstrap USB for server type: $server_type"

    case "$server_type" in
        proxmox-nas)
            bash "$BOOTSTRAP_DIR/create-bootstrap.sh" "$site_config"
            ;;
        proxmox-firewall)
            bash "$BOOTSTRAP_DIR/create-firewall-usb.sh" "$site_config"
            ;;
        k3s-cluster)
            bash "$BOOTSTRAP_DIR/create-k3s-usb.sh" "$site_config"
            ;;
        *)
            log_error "Unsupported server type for bootstrap: $server_type"
            return 1
            ;;
    esac

    log_success "Bootstrap USB generated successfully"
}

# Deploy site configuration
deploy_site() {
    local site_config="$1"
    local site_name
    site_name=$(grep "^site_name:" "$site_config" | cut -d'"' -f2)

    log_info "Deploying site: $site_name"

    # Run deployment script
    if [[ -f "$SCRIPTS_DIR/deploy-site.sh" ]]; then
        bash "$SCRIPTS_DIR/deploy-site.sh" "$site_config"
    else
        log_warning "Deployment script not found, skipping deployment"
    fi

    log_success "Site deployment completed"
}

# Update web UI with new site
update_web_ui() {
    local site_config="$1"

    log_info "Updating web UI with new site configuration"

    # Copy site config to web UI data directory
    local site_name
    site_name=$(grep "^site_name:" "$site_config" | cut -d'"' -f2)

    mkdir -p "$WEB_UI_DIR/data/sites"
    cp "$site_config" "$WEB_UI_DIR/data/sites/$site_name.yml"

    # Restart web UI if running
    if pgrep -f "python.*app.py" > /dev/null; then
        log_info "Restarting web UI service"
        pkill -f "python.*app.py"
        sleep 2
        cd "$WEB_UI_DIR" && python app.py &
    fi

    log_success "Web UI updated successfully"
}

# Register devices for the site
register_devices() {
    local site_config="$1"

    log_info "Registering devices for site"

    if [[ -f "$SCRIPTS_DIR/manage-devices.sh" ]]; then
        bash "$SCRIPTS_DIR/manage-devices.sh" register-from-config "$site_config"
    else
        log_warning "Device management script not found, skipping device registration"
    fi

    log_success "Device registration completed"
}

# Generate deployment artifacts
generate_artifacts() {
    local site_config="$1"
    local output_dir="$2"

    log_info "Generating deployment artifacts"

    mkdir -p "$output_dir"

    # Copy configuration
    cp "$site_config" "$output_dir/"

    # Generate Ansible inventory
    local site_name
    site_name=$(grep "^site_name:" "$site_config" | cut -d'"' -f2)
    local server_type
    server_type=$(grep "^server_type:" "$site_config" | cut -d'"' -f2)

    cat > "$output_dir/inventory.ini" << EOF
[all]
${site_name} ansible_host=localhost ansible_connection=local

[${server_type}]
${site_name}

[${server_type}:vars]
server_type=${server_type}
site_config=${site_config}
EOF

    # Generate deployment manifest
    cat > "$output_dir/deploy-manifest.yml" << EOF
apiVersion: v1
kind: DeploymentManifest
metadata:
  name: ${site_name}
  server-type: ${server_type}
  created: $(date -Iseconds)
spec:
  site: ${site_name}
  serverType: ${server_type}
  configFile: ${site_config}
  artifacts:
    - bootstrap-usb
    - ansible-inventory
    - site-config
EOF

    log_success "Deployment artifacts generated in: $output_dir"
}

# Main build workflow
build_workflow() {
    local site_config="$1"
    local output_dir="${2:-$PROJECT_ROOT/build/$(basename "$site_config" .yml)}"

    log_info "Starting generalized build workflow"
    log_info "Site config: $site_config"
    log_info "Output directory: $output_dir"

    # Validate configuration
    validate_config "$site_config" || exit 1

    # Generate bootstrap USB
    generate_bootstrap "$site_config"

    # Generate deployment artifacts
    generate_artifacts "$site_config" "$output_dir"

    # Deploy site (optional, can be run separately)
    if [[ "${DEPLOY_SITE:-false}" == "true" ]]; then
        deploy_site "$site_config"
    fi

    # Update web UI
    update_web_ui "$site_config"

    # Register devices
    register_devices "$site_config"

    log_success "Build workflow completed successfully"
    log_info "Output available in: $output_dir"
}

# Release workflow
release_workflow() {
    local site_config="$1"
    local version="${2:-$(date +%Y%m%d-%H%M%S)}"
    local release_dir="$PROJECT_ROOT/releases/$version"

    log_info "Starting release workflow for version: $version"

    # Build first
    build_workflow "$site_config" "$release_dir/build"

    # Create release archive
    mkdir -p "$release_dir"
    cd "$PROJECT_ROOT"
    tar -czf "$release_dir/brewnix-${version}.tar.gz" \
        --exclude='.git' \
        --exclude='__pycache__' \
        --exclude='*.log' \
        --exclude='releases' \
        .

    # Generate release notes
    cat > "$release_dir/RELEASE_NOTES.md" << EOF
# Brewnix Release ${version}

## Site Configuration
- Site: $(grep "^site_name:" "$site_config" | cut -d'"' -f2)
- Server Type: $(grep "^server_type:" "$site_config" | cut -d'"' -f2)
- Location: $(grep "^location:" "$site_config" | cut -d'"' -f2)

## Build Artifacts
- Bootstrap USB image
- Ansible inventory and playbooks
- Site configuration files
- Web UI updates

## Deployment Instructions
1. Boot server from generated USB image
2. Run bootstrap process
3. Deploy using Ansible playbooks
4. Access web UI for management

## Generated: $(date)
EOF

    log_success "Release ${version} created successfully"
    log_info "Release archive: $release_dir/brewnix-${version}.tar.gz"
}

# Main script logic
main() {
    local command="$1"
    local site_config="$2"
    local extra_arg="$3"

    case "$command" in
        build)
            if [[ -z "$site_config" ]]; then
                log_error "Usage: $0 build <site-config.yml> [output-dir]"
                exit 1
            fi
            build_workflow "$site_config" "$extra_arg"
            ;;
        release)
            if [[ -z "$site_config" ]]; then
                log_error "Usage: $0 release <site-config.yml> [version]"
                exit 1
            fi
            release_workflow "$site_config" "$extra_arg"
            ;;
        validate)
            if [[ -z "$site_config" ]]; then
                log_error "Usage: $0 validate <site-config.yml>"
                exit 1
            fi
            validate_config "$site_config"
            ;;
        bootstrap)
            if [[ -z "$site_config" ]]; then
                log_error "Usage: $0 bootstrap <site-config.yml>"
                exit 1
            fi
            generate_bootstrap "$site_config"
            ;;
        *)
            echo "Brewnix Generalized Build and Release Workflow"
            echo ""
            echo "Usage: $0 <command> <site-config.yml> [options]"
            echo ""
            echo "Commands:"
            echo "  build     Build deployment artifacts for a site"
            echo "  release   Create a release package with build artifacts"
            echo "  validate  Validate site configuration"
            echo "  bootstrap Generate bootstrap USB for site"
            echo ""
            echo "Environment Variables:"
            echo "  DEPLOY_SITE=true  Automatically deploy site after build"
            echo ""
            echo "Examples:"
            echo "  $0 build config/sites/home-lab.yml"
            echo "  $0 release config/sites/home-lab.yml v1.0.0"
            echo "  $0 validate config/sites/home-lab.yml"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
