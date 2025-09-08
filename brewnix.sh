#!/bin/bash
# brewnix.sh - Main orchestrator for Brewnix GitOps Firewall Management
# Replaces the monolithic deploy-gitops.sh with a modular architecture

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/scripts" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"
VENDOR_COMMON_DIR="${PROJECT_ROOT}/vendor/common"

# Export for modules
export SCRIPT_DIR PROJECT_ROOT BUILD_DIR VENDOR_COMMON_DIR

# Load core modules
# Source core modules
source "${SCRIPT_DIR}/core/init.sh"
source "${SCRIPT_DIR}/core/config.sh"
source "${SCRIPT_DIR}/core/logging.sh"

# Source feature modules
source "${SCRIPT_DIR}/backup/backup.sh"
# Conditionally source OPNsense module (only available in proxmox-firewall context)
if [[ -d "${SCRIPT_DIR}/../vendor/proxmox-firewall" && -f "${SCRIPT_DIR}/../vendor/proxmox-firewall/scripts/opnsense/opnsense.sh" && "$PWD" == *"/vendor/proxmox-firewall"* ]]; then
    source "${SCRIPT_DIR}/../vendor/proxmox-firewall/scripts/opnsense/opnsense.sh"
fi
source "${SCRIPT_DIR}/monitoring/monitoring.sh"
source "${SCRIPT_DIR}/gitops/gitops.sh"
source "${SCRIPT_DIR}/deployment/deployment.sh"
source "${SCRIPT_DIR}/utilities/utilities.sh"

# Default values
OPERATION="help"
SITE_CONFIG=""
VERBOSE=false

# Colors for output (loaded from logging module)
# RED, GREEN, YELLOW, BLUE, PURPLE, CYAN, NC

# Usage information
show_usage() {
    cat << EOF
Brewnix GitOps Firewall Management System

USAGE:
    $0 <MODULE> <OPERATION> [OPTIONS] <SITE_CONFIG>

MODULES:
    deployment     Firewall and network deployment operations
    backup         Backup and restore operations
    monitoring     Health monitoring and alerting
    opnsense       OPNsense firewall management (proxmox-firewall only)
    gitops         GitOps repository management
    usb            USB bootstrap operations
    test           Testing and validation operations

DEPLOYMENT OPERATIONS:
    deploy         Deploy firewall infrastructure
    network        Network configuration management
    devices        Device configuration management

BACKUP OPERATIONS:
    backup         Create system backup
    restore        Restore from backup
    list           List available backups
    cleanup        Clean up old backups

MONITORING OPERATIONS:
    health         Run health checks
    alerts         Manage alert notifications
    report         Generate monitoring reports

OPNSENSE OPERATIONS:
    config         Configuration management
    rules          Firewall rule management
    aliases        Alias management
    interfaces     Interface configuration
    api            Direct API operations

GITOPS OPERATIONS:
    sync           Sync with GitOps repository
    drift          Check configuration drift
    status         GitOps status and health

USB OPERATIONS:
    create         Create USB bootstrap image
    validate       Validate USB bootstrap

TEST OPERATIONS:
    run            Run test suite
    validate       Validate configurations
    integration    Run integration tests

OPTIONS:
    --verbose      Enable verbose output
    --dry-run      Show what would be done without executing
    --help         Show this help message

EXAMPLES:
    # Deploy firewall
    $0 deployment deploy config/sites/site.yml

    # Backup system
    $0 backup backup config/sites/site.yml

    # OPNsense rule management
    $0 opnsense rules list config/sites/site.yml

    # Health monitoring
    $0 monitoring health config/sites/site.yml

    # GitOps sync
    $0 gitops sync config/sites/site.yml

ENVIRONMENT VARIABLES:
    VERBOSE        Enable verbose output globally
    DRY_RUN        Enable dry-run mode globally

EOF
}

# Parse command line arguments
parse_args() {
    if [[ $# -lt 1 ]]; then
        show_usage
        exit 1
    fi

    MODULE="$1"
    shift

    if [[ $# -lt 1 ]]; then
        log_error "Operation required for module: $MODULE"
        show_usage
        exit 1
    fi

    OPERATION="$1"
    shift

    # Parse remaining arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [[ -z "$SITE_CONFIG" ]]; then
                    SITE_CONFIG="$1"
                else
                    log_error "Multiple site configurations specified"
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Validate site config if required
    if [[ -n "$SITE_CONFIG" && ! -f "$SITE_CONFIG" ]]; then
        log_error "Site configuration file not found: $SITE_CONFIG"
        exit 1
    fi
}

# Route to appropriate module
route_to_module() {
    local module="$1"
    shift

    case "$module" in
        backup)
            init_backup
            backup_main "$@"
            ;;
        opnsense)
            # Check if OPNsense module is available
            if type init_opnsense >/dev/null 2>&1; then
                init_opnsense
                opnsense_main "$@"
            else
                log_error "OPNsense module not available in this context"
                log_error "OPNsense functionality is only available in proxmox-firewall submodule"
                log_error "Navigate to: cd vendor/proxmox-firewall"
                exit 1
            fi
            ;;
        monitoring)
            init_monitoring
            monitoring_main "$@"
            ;;
        gitops)
            init_gitops
            gitops_main "$@"
            ;;
        deployment)
            init_deployment
            deployment_main "$@"
            ;;
        utilities|usb|test|validate|deps|docs)
            init_utilities
            utilities_main "$module" "$@"
            ;;
        help|--help|-h)
            show_usage
            exit 0
            ;;
        *)
            log_error "Unknown module: $module"
            show_usage
            exit 1
            ;;
    esac
}

# Main execution
main() {
    # Initialize environment
    init_environment

    # Parse arguments
    parse_args "$@"

    # Set global variables
    export VERBOSE
    export DRY_RUN
    export SITE_CONFIG
    export PROJECT_ROOT
    export SCRIPT_DIR

    # Route to module
    route_to_module "$MODULE" "$OPERATION"
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
