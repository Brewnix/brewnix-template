#!/bin/bash
# scripts/utilities/utilities.sh - Utility functions for USB bootstrap and testing

# Source core modules
source "${SCRIPT_DIR}/core/init.sh"
source "${SCRIPT_DIR}/core/config.sh"
source "${SCRIPT_DIR}/core/logging.sh"

# USB bootstrap configuration
USB_DEVICE="${USB_DEVICE:-/dev/sdb}"
USB_MOUNT_POINT="${USB_MOUNT_POINT:-/mnt/usb}"
BOOTSTRAP_CONFIG="${BOOTSTRAP_CONFIG:-${PROJECT_ROOT}/bootstrap/initial-config.sh}"

# Initialize utilities
init_utilities() {
    log_info "Utilities module initialized"
}

# USB bootstrap functions
prepare_usb_bootstrap() {
    local usb_device="${1:-$USB_DEVICE}"

    log_section "Preparing USB bootstrap device: $usb_device"

    # Check if device exists
    if [[ ! -b "$usb_device" ]]; then
        log_error "USB device not found: $usb_device"
        return 1
    fi

    # Check if device is mounted
    if mount | grep -q "$usb_device"; then
        log_warn "USB device is mounted, unmounting..."
        umount "${usb_device}"* 2>/dev/null || true
    fi

    # Create partition table
    log_command parted -s "$usb_device" mklabel msdos

    # Create boot partition
    log_command parted -s "$usb_device" mkpart primary fat32 1MiB 512MiB
    log_command parted -s "$usb_device" set 1 boot on

    # Create root partition
    log_command parted -s "$usb_device" mkpart primary ext4 512MiB 100%

    # Format partitions
    log_command mkfs.vfat -F 32 "${usb_device}1"
    log_command mkfs.ext4 "${usb_device}2"

    log_info "USB device prepared successfully"
}

install_bootstrap_files() {
    local usb_device="${1:-$USB_DEVICE}"
    local mount_point="${2:-$USB_MOUNT_POINT}"

    log_section "Installing bootstrap files to USB device"

    # Mount USB device
    mkdir -p "$mount_point"
    mount "${usb_device}2" "$mount_point"

    if [[ $? -ne 0 ]]; then
        log_error "Failed to mount USB device"
        return 1
    fi

    # Copy bootstrap files
    cp -r "${PROJECT_ROOT}/bootstrap/"* "$mount_point/"

    # Copy configuration
    cp "${PROJECT_ROOT}/config.yml" "$mount_point/" 2>/dev/null || true

    # Make scripts executable
    find "$mount_point" -name "*.sh" -exec chmod +x {} \;

    # Create bootstrap configuration
    cat > "${mount_point}/bootstrap.conf" << EOF
# BrewNix Bootstrap Configuration
BOOTSTRAP_VERSION="$(date +%Y%m%d_%H%M%S)"
PROJECT_ROOT="/opt/brewnix"
CONFIG_FILE="config.yml"
LOG_FILE="/var/log/brewnix_bootstrap.log"
EOF

    # Unmount device
    umount "$mount_point"
    rmdir "$mount_point"

    log_info "Bootstrap files installed successfully"
}

create_bootable_usb() {
    local usb_device="${1:-$USB_DEVICE}"
    local iso_file="$2"

    if [[ -z "$iso_file" ]]; then
        log_error "ISO file required"
        return 1
    fi

    if [[ ! -f "$iso_file" ]]; then
        log_error "ISO file not found: $iso_file"
        return 1
    fi

    log_section "Creating bootable USB from ISO: $iso_file"

    # Write ISO to USB device
    log_command dd if="$iso_file" of="$usb_device" bs=4M status=progress

    if [[ $? -eq 0 ]]; then
        log_info "Bootable USB created successfully"
        return 0
    else
        log_error "Failed to create bootable USB"
        return 1
    fi
}

# Testing utilities
run_tests() {
    local test_type="${1:-all}"
    local verbose="${2:-false}"

    log_section "Running tests: $test_type"

    case "$test_type" in
        unit)
            run_unit_tests "$verbose"
            ;;
        integration)
            run_integration_tests "$verbose"
            ;;
        all)
            run_unit_tests "$verbose" && run_integration_tests "$verbose"
            ;;
        *)
            log_error "Unknown test type: $test_type"
            echo "Usage: run_tests <unit|integration|all> [verbose]"
            return 1
            ;;
    esac
}

run_unit_tests() {
    local verbose="$1"

    log_info "Running unit tests..."

    # Find and run Python unit tests
    if [[ -d "${VENDOR_ROOT}/tests" ]]; then
        cd "${VENDOR_ROOT}/tests" || return 1

        if [[ "$verbose" == "true" ]]; then
            python3 -m pytest -v
        else
            python3 -m pytest
        fi

        local test_result=$?
        cd - >/dev/null || return 1
        return $test_result
    else
        log_warn "No unit tests found"
        return 0
    fi
}

run_integration_tests() {
    local verbose="$1"

    log_info "Running integration tests..."

    # Run Ansible integration tests
    local test_playbook="${VENDOR_ROOT}/docker-test-framework/test_integration.py"

    if [[ -f "$test_playbook" ]]; then
        if [[ "$verbose" == "true" ]]; then
            python3 "$test_playbook" -v
        else
            python3 "$test_playbook"
        fi
        return $?
    else
        log_warn "No integration tests found"
        return 0
    fi
}

validate_configuration() {
    local config_file="${1:-${PROJECT_ROOT}/config.yml}"

    log_info "Validating configuration: $config_file"

    # Load and validate configuration
    if ! load_config "$config_file"; then
        log_error "Failed to load configuration"
        return 1
    fi

    if ! validate_config; then
        log_error "Configuration validation failed"
        return 1
    fi

    # Validate site configurations
    local sites
    sites=$(list_sites)

    for site in $sites; do
        log_debug "Validating site: $site"

        local site_config
        site_config=$(get_site_config "$site")

        if [[ -z "$site_config" ]]; then
            log_error "Invalid site configuration: $site"
            return 1
        fi

        # Validate required site components
        local required_components=("network" "devices")

        for component in "${required_components[@]}"; do
            if ! echo "$site_config" | python3 -c "
import yaml
import sys
try:
    data = yaml.safe_load(sys.stdin.read())
    if '$component' not in data:
        sys.exit(1)
except:
    sys.exit(1)
" 2>/dev/null; then
                log_error "Missing required component '$component' in site: $site"
                return 1
            fi
        done
    done

    log_info "Configuration validation passed"
    return 0
}

check_dependencies() {
    log_info "Checking system dependencies..."

    local missing_deps=()
    local optional_deps=()

    # Required dependencies
    local required=("ansible" "git" "python3" "curl" "jq")

    # Optional dependencies
    local optional=("docker" "docker-compose" "terraform" "pvesh")

    for dep in "${required[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    for dep in "${optional[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            optional_deps+=("$dep")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install missing dependencies and try again"
        return 1
    fi

    if [[ ${#optional_deps[@]} -gt 0 ]]; then
        log_warn "Optional dependencies not found: ${optional_deps[*]}"
        log_warn "Some features may not be available"
    fi

    log_info "Dependency check completed"
    return 0
}

generate_documentation() {
    local output_dir="${1:-${BUILD_DIR}/docs}"

    log_info "Generating documentation..."

    mkdir -p "$output_dir"

    # Generate configuration reference
    cat > "${output_dir}/configuration.md" << 'EOF'
# BrewNix Configuration Reference

## Main Configuration (config.yml)

```yaml
network:
  prefix: "10.0.0.0/8"
  dns_servers:
    - "8.8.8.8"
    - "1.1.1.1"

sites:
  site1:
    proxmox:
      hosts:
        - "pve01.example.com"
        - "pve02.example.com"
      api_key: "your-api-key"
    opnsense:
      hosts:
        - "fw01.example.com"
      api_key: "your-api-key"
      api_secret: "your-api-secret"
    devices:
      - type: "camera"
        name: "front-door"
        ip: "192.168.1.100"
      - type: "nas"
        name: "storage"
        ip: "192.168.1.200"

gitops:
  repo_url: "https://github.com/yourorg/brewnix-config"
  branch: "main"
  ssh_key: "/path/to/ssh/key"

monitoring:
  alert_email: "admin@example.com"
  interval: 300
```
EOF

    # Generate command reference
    cat > "${output_dir}/commands.md" << 'EOF'
# BrewNix Command Reference

## Main Commands

- `brewnix backup <create|restore|list|cleanup|proxmox|opnsense>`
- `brewnix opnsense <rules|aliases|interfaces|status|apply>`
- `brewnix monitoring <check|report|start|stop|status>`
- `brewnix gitops <sync|push|pull|drift|webhook|start|stop|status>`
- `brewnix deployment <network|devices|firewall|validate|rollback|site|inventory>`

## Utility Commands

- `brewnix usb <prepare|install|create>`
- `brewnix test <unit|integration|all>`
- `brewnix validate`
- `brewnix deps`
- `brewnix docs`
EOF

    log_info "Documentation generated in: $output_dir"
    echo "$output_dir"
}

# Main utilities function
utilities_main() {
    local command="$1"
    shift

    case "$command" in
        usb)
            case "${1:-help}" in
                prepare) prepare_usb_bootstrap "$@" ;;
                install) install_bootstrap_files "$@" ;;
                create) create_bootable_usb "$@" ;;
                *) echo "Usage: usb <prepare|install|create> [options]" ;;
            esac
            ;;
        test)
            run_tests "$@"
            ;;
        validate)
            validate_configuration "$@"
            ;;
        deps)
            check_dependencies
            ;;
        docs)
            generate_documentation "$@"
            ;;
        *)
            log_error "Unknown utilities command: $command"
            echo "Usage: $0 utilities <usb|test|validate|deps|docs> [options]"
            return 1
            ;;
    esac
}

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_environment
    init_logging
    init_utilities
    utilities_main "$@"
fi
