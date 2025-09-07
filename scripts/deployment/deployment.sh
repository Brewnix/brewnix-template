#!/bin/bash
# scripts/deployment/deployment.sh - Network deployment and device management

# Source core modules
source "${SCRIPT_DIR}/core/init.sh"
source "${SCRIPT_DIR}/core/config.sh"
source "${SCRIPT_DIR}/core/logging.sh"

# Deployment configuration
DEPLOYMENT_DRY_RUN="${DEPLOYMENT_DRY_RUN:-false}"
DEPLOYMENT_TIMEOUT="${DEPLOYMENT_TIMEOUT:-300}"
ANSIBLE_INVENTORY="${BUILD_DIR}/inventory.ini"

# Initialize deployment system
init_deployment() {
    mkdir -p "$BUILD_DIR"
    log_info "Deployment system initialized"
    log_debug "Dry run: $DEPLOYMENT_DRY_RUN"
    log_debug "Timeout: $DEPLOYMENT_TIMEOUT seconds"
}

# Generate Ansible inventory
generate_inventory() {
    local site_name="$1"

    if [[ -z "$site_name" ]]; then
        log_error "Site name required"
        return 1
    fi

    log_info "Generating Ansible inventory for site: $site_name"

    # Get site configuration
    local site_config
    site_config=$(get_site_config "$site_name")

    if [[ -z "$site_config" ]]; then
        log_error "Site configuration not found: $site_name"
        return 1
    fi

    # Create inventory file
    cat > "$ANSIBLE_INVENTORY" << EOF
[all:vars]
ansible_user=root
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

[proxmox]
EOF

    # Add Proxmox hosts
    local proxmox_hosts
    proxmox_hosts=$(echo "$site_config" | python3 -c "
import yaml
import sys
try:
    data = yaml.safe_load(sys.stdin.read())
    if 'proxmox' in data and 'hosts' in data['proxmox']:
        for host in data['proxmox']['hosts']:
            print(host)
except:
    pass
" 2>/dev/null)

    for host in $proxmox_hosts; do
        echo "$host" >> "$ANSIBLE_INVENTORY"
    done

    # Add OPNsense hosts
    cat >> "$ANSIBLE_INVENTORY" << EOF

[opnsense]
EOF

    local opnsense_hosts
    opnsense_hosts=$(echo "$site_config" | python3 -c "
import yaml
import sys
try:
    data = yaml.safe_load(sys.stdin.read())
    if 'opnsense' in data and 'hosts' in data['opnsense']:
        for host in data['opnsense']['hosts']:
            print(host)
except:
    pass
" 2>/dev/null)

    for host in $opnsense_hosts; do
        echo "$host" >> "$ANSIBLE_INVENTORY"
    done

    log_info "Inventory generated: $ANSIBLE_INVENTORY"
    echo "$ANSIBLE_INVENTORY"
}

# Deploy network configuration
deploy_network() {
    local site_name="$1"

    if [[ -z "$site_name" ]]; then
        log_error "Site name required"
        return 1
    fi

    log_section "Deploying network configuration for site: $site_name"

    # Generate inventory
    local inventory_file
    inventory_file=$(generate_inventory "$site_name")

    if [[ $? -ne 0 ]]; then
        log_error "Failed to generate inventory"
        return 1
    fi

    # Run network deployment playbook
    local playbook="${VENDOR_ROOT}/deployment/ansible/network_deploy.yml"

    if [[ ! -f "$playbook" ]]; then
        log_error "Network deployment playbook not found: $playbook"
        return 1
    fi

    log_command ansible-playbook \
        -i "$inventory_file" \
        "$playbook" \
        --extra-vars "site_name=$site_name" \
        ${DEPLOYMENT_DRY_RUN:+--check}

    if [[ $? -eq 0 ]]; then
        log_info "Network deployment completed successfully"
        return 0
    else
        log_error "Network deployment failed"
        return 1
    fi
}

# Deploy devices
deploy_devices() {
    local site_name="$1"
    local device_type="${2:-all}"

    if [[ -z "$site_name" ]]; then
        log_error "Site name required"
        return 1
    fi

    log_section "Deploying devices for site: $site_name (type: $device_type)"

    # Generate inventory
    local inventory_file
    inventory_file=$(generate_inventory "$site_name")

    if [[ $? -ne 0 ]]; then
        log_error "Failed to generate inventory"
        return 1
    fi

    # Run device deployment playbook
    local playbook="${VENDOR_ROOT}/deployment/ansible/device_deploy.yml"

    if [[ ! -f "$playbook" ]]; then
        log_error "Device deployment playbook not found: $playbook"
        return 1
    fi

    log_command ansible-playbook \
        -i "$inventory_file" \
        "$playbook" \
        --extra-vars "site_name=$site_name device_type=$device_type" \
        ${DEPLOYMENT_DRY_RUN:+--check}

    if [[ $? -eq 0 ]]; then
        log_info "Device deployment completed successfully"
        return 0
    else
        log_error "Device deployment failed"
        return 1
    fi
}

# Deploy firewall rules
deploy_firewall() {
    local site_name="$1"

    if [[ -z "$site_name" ]]; then
        log_error "Site name required"
        return 1
    fi

    log_section "Deploying firewall configuration for site: $site_name"

    # Generate inventory
    local inventory_file
    inventory_file=$(generate_inventory "$site_name")

    if [[ $? -ne 0 ]]; then
        log_error "Failed to generate inventory"
        return 1
    fi

    # Run firewall deployment playbook
    local playbook="${VENDOR_ROOT}/deployment/ansible/firewall_deploy.yml"

    if [[ ! -f "$playbook" ]]; then
        log_error "Firewall deployment playbook not found: $playbook"
        return 1
    fi

    log_command ansible-playbook \
        -i "$inventory_file" \
        "$playbook" \
        --extra-vars "site_name=$site_name" \
        ${DEPLOYMENT_DRY_RUN:+--check}

    if [[ $? -eq 0 ]]; then
        log_info "Firewall deployment completed successfully"
        return 0
    else
        log_error "Firewall deployment failed"
        return 1
    fi
}

# Validate deployment
validate_deployment() {
    local site_name="$1"

    if [[ -z "$site_name" ]]; then
        log_error "Site name required"
        return 1
    fi

    log_section "Validating deployment for site: $site_name"

    # Generate inventory
    local inventory_file
    inventory_file=$(generate_inventory "$site_name")

    if [[ $? -ne 0 ]]; then
        log_error "Failed to generate inventory"
        return 1
    fi

    # Run validation playbook
    local playbook="${VENDOR_ROOT}/deployment/ansible/validate_deploy.yml"

    if [[ ! -f "$playbook" ]]; then
        log_error "Validation playbook not found: $playbook"
        return 1
    fi

    log_command ansible-playbook \
        -i "$inventory_file" \
        "$playbook" \
        --extra-vars "site_name=$site_name"

    if [[ $? -eq 0 ]]; then
        log_info "Deployment validation completed successfully"
        return 0
    else
        log_error "Deployment validation failed"
        return 1
    fi
}

# Rollback deployment
rollback_deployment() {
    local site_name="$1"
    local backup_file="$2"

    if [[ -z "$site_name" ]]; then
        log_error "Site name required"
        return 1
    fi

    if [[ -z "$backup_file" ]]; then
        log_error "Backup file required for rollback"
        return 1
    fi

    log_section "Rolling back deployment for site: $site_name"

    # Generate inventory
    local inventory_file
    inventory_file=$(generate_inventory "$site_name")

    if [[ $? -ne 0 ]]; then
        log_error "Failed to generate inventory"
        return 1
    fi

    # Run rollback playbook
    local playbook="${VENDOR_ROOT}/deployment/ansible/rollback_deploy.yml"

    if [[ ! -f "$playbook" ]]; then
        log_error "Rollback playbook not found: $playbook"
        return 1
    fi

    log_command ansible-playbook \
        -i "$inventory_file" \
        "$playbook" \
        --extra-vars "site_name=$site_name backup_file=$backup_file"

    if [[ $? -eq 0 ]]; then
        log_info "Deployment rollback completed successfully"
        return 0
    else
        log_error "Deployment rollback failed"
        return 1
    fi
}

# Deploy complete site
deploy_site() {
    local site_name="$1"
    local skip_validation="${2:-false}"

    if [[ -z "$site_name" ]]; then
        log_error "Site name required"
        return 1
    fi

    log_section "Deploying complete site: $site_name"

    # Create backup before deployment
    local backup_file
    backup_file=$(create_backup "pre_site_deploy_${site_name}")

    if [[ $? -ne 0 ]]; then
        log_error "Failed to create backup"
        return 1
    fi

    log_info "Pre-deployment backup created: $backup_file"

    # Deploy network configuration
    if ! deploy_network "$site_name"; then
        log_error "Network deployment failed"
        return 1
    fi

    # Deploy devices
    if ! deploy_devices "$site_name"; then
        log_error "Device deployment failed"
        return 1
    fi

    # Deploy firewall
    if ! deploy_firewall "$site_name"; then
        log_error "Firewall deployment failed"
        return 1
    fi

    # Validate deployment
    if [[ "$skip_validation" != "true" ]]; then
        if ! validate_deployment "$site_name"; then
            log_error "Deployment validation failed"
            log_warn "Consider rolling back using: rollback $site_name $backup_file"
            return 1
        fi
    fi

    log_info "Site deployment completed successfully"
    return 0
}

# Main deployment function
deployment_main() {
    local command="$1"
    shift

    case "$command" in
        network)
            deploy_network "$@"
            ;;
        devices)
            deploy_devices "$@"
            ;;
        firewall)
            deploy_firewall "$@"
            ;;
        validate)
            validate_deployment "$@"
            ;;
        rollback)
            rollback_deployment "$@"
            ;;
        site)
            deploy_site "$@"
            ;;
        inventory)
            generate_inventory "$@"
            ;;
        *)
            log_error "Unknown deployment command: $command"
            echo "Usage: $0 deployment <network|devices|firewall|validate|rollback|site|inventory> [options]"
            return 1
            ;;
    esac
}

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_environment
    init_logging
    init_deployment
    deployment_main "$@"
fi
