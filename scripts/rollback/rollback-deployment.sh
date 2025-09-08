#!/bin/bash

# rollback-deployment.sh
# Automated rollback testing for BrewNix deployments
# Tests rollback procedures for different deployment strategies

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_FILE=""
BACKUP_DIR=""
DEPLOYMENT_ID=""
ENVIRONMENT=""
DRY_RUN=false
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Automated rollback testing for BrewNix deployments.

OPTIONS:
    --environment ENV       Target environment (staging, production, development)
    --deployment-id ID       Specific deployment ID to rollback
    --log-dir DIR           Directory for log files
    --backup-dir DIR        Directory for backup files
    --dry-run               Show what would be done without executing
    --verbose               Enable verbose output
    --help                  Show this help message

EXAMPLES:
    $0 --environment staging --deployment-id 20240907-143000
    $0 --environment production --dry-run --verbose

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --deployment-id)
                DEPLOYMENT_ID="$2"
                shift 2
                ;;
            --log-dir)
                LOG_DIR="$2"
                shift 2
                ;;
            --backup-dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Validate inputs
validate_inputs() {
    if [[ -z "${ENVIRONMENT}" ]]; then
        log_error "Environment is required. Use --environment"
        exit 1
    fi

    if [[ -z "${DEPLOYMENT_ID}" ]]; then
        log_error "Deployment ID is required. Use --deployment-id"
        exit 1
    fi

    if [[ -z "${LOG_DIR}" ]]; then
        LOG_DIR="${PROJECT_ROOT}/logs/rollback-testing"
    fi

    if [[ -z "${BACKUP_DIR}" ]]; then
        BACKUP_DIR="${PROJECT_ROOT}/backups/rollback-testing"
    fi

    # Create directories if they don't exist
    mkdir -p "${LOG_DIR}" "${BACKUP_DIR}"

    LOG_FILE="${LOG_DIR}/rollback-test-${DEPLOYMENT_ID}.log"
}

# Setup SSH connection to target environment
setup_ssh_connection() {
    log_info "Setting up SSH connection to ${ENVIRONMENT} environment..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would setup SSH connection"
        return 0
    fi

    # Add target environment to known hosts
    local target_host
    case "${ENVIRONMENT}" in
        staging)
            target_host="${STAGING_HOST:-staging.brewnix.local}"
            ;;
        production)
            target_host="${PRODUCTION_HOST:-prod.brewnix.local}"
            ;;
        development)
            target_host="${DEV_HOST:-dev.brewnix.local}"
            ;;
        *)
            log_error "Unknown environment: ${ENVIRONMENT}"
            exit 1
            ;;
    esac

    # Test SSH connection
    if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "${target_host}" "echo 'SSH connection successful'" 2>/dev/null; then
        log_error "Failed to establish SSH connection to ${target_host}"
        exit 1
    fi

    log_success "SSH connection established to ${target_host}"
}

# Get deployment information
get_deployment_info() {
    log_info "Retrieving deployment information for ${DEPLOYMENT_ID}..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would retrieve deployment info"
        return 0
    fi

    # Check if deployment exists
    local deployment_file="${PROJECT_ROOT}/vendor/build/deployment-${DEPLOYMENT_ID}.json"
    if [[ ! -f "${deployment_file}" ]]; then
        log_error "Deployment file not found: ${deployment_file}"
        exit 1
    fi

    # Parse deployment information
    DEPLOYMENT_TYPE=$(jq -r '.type // "unknown"' "${deployment_file}")
    DEPLOYMENT_STRATEGY=$(jq -r '.strategy // "standard"' "${deployment_file}")
    DEPLOYMENT_SERVICES=$(jq -r '.services // [] | join(",")' "${deployment_file}")

    log_info "Deployment Type: ${DEPLOYMENT_TYPE}"
    log_info "Deployment Strategy: ${DEPLOYMENT_STRATEGY}"
    log_info "Services: ${DEPLOYMENT_SERVICES}"
}

# Create pre-rollback backup
create_rollback_backup() {
    log_info "Creating pre-rollback backup..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create rollback backup"
        return 0
    fi

    local backup_timestamp
    backup_timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="${BACKUP_DIR}/pre-rollback-${DEPLOYMENT_ID}-${backup_timestamp}.tar.gz"

    # Create backup of current state
    if ! tar -czf "${backup_file}" -C "${PROJECT_ROOT}" . 2>/dev/null; then
        log_warning "Failed to create full backup, continuing with rollback..."
    else
        log_success "Pre-rollback backup created: ${backup_file}"
    fi
}

# Execute rollback based on deployment strategy
execute_rollback() {
    log_info "Executing rollback for ${DEPLOYMENT_STRATEGY} deployment..."

    case "${DEPLOYMENT_STRATEGY}" in
        blue-green)
            rollback_blue_green
            ;;
        canary)
            rollback_canary
            ;;
        rolling)
            rollback_rolling
            ;;
        standard|*)
            rollback_standard
            ;;
    esac
}

# Rollback blue-green deployment
rollback_blue_green() {
    log_info "Rolling back blue-green deployment..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would rollback blue-green deployment"
        return 0
    fi

    # Switch traffic back to previous version
    if ! "${SCRIPT_DIR}/../staging/traffic-switch.sh" --environment "${ENVIRONMENT}" --rollback; then
        log_error "Failed to switch traffic during blue-green rollback"
        return 1
    fi

    log_success "Blue-green rollback completed"
}

# Rollback canary deployment
rollback_canary() {
    log_info "Rolling back canary deployment..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would rollback canary deployment"
        return 0
    fi

    # Gradually reduce canary traffic to 0%
    if ! "${SCRIPT_DIR}/../staging/canary-deployment.sh" --environment "${ENVIRONMENT}" --rollback --percentage 0; then
        log_error "Failed to rollback canary deployment"
        return 1
    fi

    log_success "Canary rollback completed"
}

# Rollback rolling deployment
rollback_rolling() {
    log_info "Rolling back rolling deployment..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would rollback rolling deployment"
        return 0
    fi

    # Use Ansible to rollback services
    if ! ansible-playbook "${PROJECT_ROOT}/common/ansible/rollback.yml" \
        -e "deployment_id=${DEPLOYMENT_ID}" \
        -e "environment=${ENVIRONMENT}"; then
        log_error "Failed to rollback rolling deployment"
        return 1
    fi

    log_success "Rolling rollback completed"
}

# Rollback standard deployment
rollback_standard() {
    log_info "Rolling back standard deployment..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would rollback standard deployment"
        return 0
    fi

    # Use deployment script to rollback
    if ! "${SCRIPT_DIR}/../deployment/deployment.sh" --environment "${ENVIRONMENT}" --rollback "${DEPLOYMENT_ID}"; then
        log_error "Failed to rollback standard deployment"
        return 1
    fi

    log_success "Standard rollback completed"
}

# Validate rollback success
validate_rollback() {
    log_info "Validating rollback success..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would validate rollback"
        return 0
    fi

    # Run health checks
    if ! "${SCRIPT_DIR}/../staging/monitor-environment.sh" --environment "${ENVIRONMENT}" --quick-check; then
        log_error "Health checks failed after rollback"
        return 1
    fi

    # Validate service functionality
    if ! "${SCRIPT_DIR}/../staging/comprehensive-validation.sh" --environment "${ENVIRONMENT}" --quick-validation; then
        log_error "Service validation failed after rollback"
        return 1
    fi

    log_success "Rollback validation completed successfully"
}

# Generate rollback report
generate_rollback_report() {
    log_info "Generating rollback test report..."

    local report_file="${LOG_DIR}/rollback-report-${DEPLOYMENT_ID}.json"

    cat > "${report_file}" << EOF
{
    "deployment_id": "${DEPLOYMENT_ID}",
    "environment": "${ENVIRONMENT}",
    "deployment_strategy": "${DEPLOYMENT_STRATEGY}",
    "rollback_timestamp": "$(date -Iseconds)",
    "test_status": "completed",
    "rollback_duration": "$(($(date +%s) - START_TIME))",
    "log_file": "${LOG_FILE}",
    "backup_created": $(find "${BACKUP_DIR}" -name "pre-rollback-${DEPLOYMENT_ID}-*.tar.gz" -type f | grep -q . && echo "true" || echo "false")
}
EOF

    log_success "Rollback report generated: ${report_file}"
}

# Main function
main() {
    START_TIME=$(date +%s)

    log_info "Starting automated rollback test for deployment ${DEPLOYMENT_ID}"
    log_info "Environment: ${ENVIRONMENT}"
    log_info "Log file: ${LOG_FILE}"

    # Execute rollback test phases
    setup_ssh_connection
    get_deployment_info
    create_rollback_backup
    execute_rollback
    validate_rollback
    generate_rollback_report

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - START_TIME))

    log_success "Automated rollback test completed successfully in ${duration} seconds"
    log_info "Test results saved to: ${LOG_FILE}"
}

# Initialize script
parse_args "$@"
validate_inputs

# Run main function
if [[ "${VERBOSE}" == "true" ]]; then
    set -x
fi

main "$@"
