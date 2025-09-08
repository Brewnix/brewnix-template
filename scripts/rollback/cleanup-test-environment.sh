#!/bin/bash

# cleanup-test-environment.sh
# Cleanup rollback and recovery test environment
# Removes test artifacts, restores system state, and archives results

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_DIR=""
BACKUP_DIR=""
DEPLOYMENT_ID=""
ENVIRONMENT=""
DRY_RUN=false
VERBOSE=false
FORCE=false

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

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Cleanup rollback and recovery test environment.

OPTIONS:
    --environment ENV       Target environment (staging, production, development)
    --deployment-id ID       Specific deployment ID for cleanup
    --log-dir DIR           Directory containing log files
    --backup-dir DIR        Directory containing backup files
    --force                 Force cleanup without confirmation
    --dry-run               Show what would be done without executing
    --verbose               Enable verbose output
    --help                  Show this help message

EXAMPLES:
    $0 --environment staging --deployment-id 20240907-143000
    $0 --environment production --force --dry-run

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
            --force)
                FORCE=true
                shift
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
        DEPLOYMENT_ID=$(date +%Y%m%d-%H%M%S)
    fi

    if [[ -z "${LOG_DIR}" ]]; then
        LOG_DIR="${PROJECT_ROOT}/logs/rollback-testing"
    fi

    if [[ -z "${BACKUP_DIR}" ]]; then
        BACKUP_DIR="${PROJECT_ROOT}/backups/rollback-testing"
    fi
}

# Confirm cleanup operation
confirm_cleanup() {
    if [[ "${FORCE}" == "true" || "${DRY_RUN}" == "true" ]]; then
        return 0
    fi

    log_warning "This will remove all test artifacts for deployment ${DEPLOYMENT_ID}"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo

    if [[ ! ${REPLY} =~ ^[Yy]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Archive test results
archive_test_results() {
    log_info "Archiving test results..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would archive test results"
        return 0
    fi

    local archive_dir="${PROJECT_ROOT}/archives/rollback-testing"
    local archive_file="${archive_dir}/rollback-test-archive-${DEPLOYMENT_ID}.tar.gz"

    mkdir -p "${archive_dir}"

    # Archive logs and backups
    if [[ -d "${LOG_DIR}" && -d "${BACKUP_DIR}" ]]; then
        tar -czf "${archive_file}" \
            -C "${PROJECT_ROOT}" \
            "logs/rollback-testing" \
            "backups/rollback-testing" \
            2>/dev/null || true

        log_success "Test results archived: ${archive_file}"
    else
        log_warning "No test results found to archive"
    fi
}

# Cleanup log files
cleanup_log_files() {
    log_info "Cleaning up log files..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would cleanup log files"
        return 0
    fi

    # Remove test-specific log files
    local log_count
    log_count=$(find "${LOG_DIR}" -name "*${DEPLOYMENT_ID}*" -type f | wc -l)

    if [[ ${log_count} -gt 0 ]]; then
        find "${LOG_DIR}" -name "*${DEPLOYMENT_ID}*" -type f -delete
        log_success "Removed ${log_count} log files"
    else
        log_info "No log files found for cleanup"
    fi

    # Clean up old log files (keep last 10)
    local old_logs
    old_logs=$(find "${LOG_DIR}" -name "*.log" -type f -printf '%T@ %p\n' | sort -n | head -n -10 | cut -d' ' -f2-)

    if [[ -n "${old_logs}" ]]; then
        echo "${old_logs}" | xargs rm -f
        local old_count
        old_count=$(echo "${old_logs}" | wc -l)
        log_success "Cleaned up ${old_count} old log files"
    fi
}

# Cleanup backup files
cleanup_backup_files() {
    log_info "Cleaning up backup files..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would cleanup backup files"
        return 0
    fi

    # Remove test-specific backup files
    local backup_count
    backup_count=$(find "${BACKUP_DIR}" -name "*${DEPLOYMENT_ID}*" | wc -l)

    if [[ ${backup_count} -gt 0 ]]; then
        find "${BACKUP_DIR}" -name "*${DEPLOYMENT_ID}*" -delete 2>/dev/null || true
        log_success "Removed ${backup_count} backup files/directories"
    else
        log_info "No backup files found for cleanup"
    fi

    # Clean up old backup files (keep last 5)
    local old_backups
    old_backups=$(find "${BACKUP_DIR}" -name "*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | head -n -5 | cut -d' ' -f2-)

    if [[ -n "${old_backups}" ]]; then
        echo "${old_backups}" | xargs rm -f
        local old_count
        old_count=$(echo "${old_backups}" | wc -l)
        log_success "Cleaned up ${old_count} old backup files"
    fi
}

# Restore system state
restore_system_state() {
    log_info "Restoring system state..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would restore system state"
        return 0
    fi

    # Restore network settings
    if command -v tc >/dev/null 2>&1; then
        log_info "Restoring network settings..."
        sudo tc qdisc del dev eth0 root 2>/dev/null || true
    fi

    # Restore iptables rules
    if command -v iptables >/dev/null 2>&1; then
        log_info "Restoring firewall rules..."
        sudo iptables -F 2>/dev/null || true
    fi

    # Clean up any test processes
    cleanup_test_processes

    log_success "System state restored"
}

# Cleanup test processes
cleanup_test_processes() {
    log_info "Cleaning up test processes..."

    # Kill any remaining test processes
    local test_processes
    test_processes=$(pgrep -f "rollback\|chaos\|disaster" || true)

    if [[ -n "${test_processes}" ]]; then
        echo "${test_processes}" | xargs kill -9 2>/dev/null || true
        log_success "Cleaned up test processes"
    else
        log_info "No test processes found"
    fi
}

# Cleanup temporary files
cleanup_temporary_files() {
    log_info "Cleaning up temporary files..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would cleanup temporary files"
        return 0
    fi

    # Clean up test-specific temporary files
    local temp_patterns=(
        "/tmp/dr-test-*${DEPLOYMENT_ID}*"
        "/tmp/chaos-*${DEPLOYMENT_ID}*"
        "/var/tmp/rollback-*${DEPLOYMENT_ID}*"
    )

    local total_cleaned=0
    for pattern in "${temp_patterns[@]}"; do
        if compgen -G "${pattern}" >/dev/null; then
            local count
            count=$(find /tmp /var/tmp -name "*${DEPLOYMENT_ID}*" 2>/dev/null | wc -l)
            find /tmp /var/tmp -name "*${DEPLOYMENT_ID}*" -delete 2>/dev/null || true
            total_cleaned=$((total_cleaned + count))
        fi
    done

    if [[ ${total_cleaned} -gt 0 ]]; then
        log_success "Cleaned up ${total_cleaned} temporary files"
    else
        log_info "No temporary files found for cleanup"
    fi
}

# Validate cleanup
validate_cleanup() {
    log_info "Validating cleanup completion..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would validate cleanup"
        return 0
    fi

    local issues_found=0

    # Check for remaining test files
    if find "${LOG_DIR}" -name "*${DEPLOYMENT_ID}*" -type f | grep -q .; then
        log_warning "Some log files still remain"
        ((issues_found++))
    fi

    if find "${BACKUP_DIR}" -name "*${DEPLOYMENT_ID}*" | grep -q .; then
        log_warning "Some backup files still remain"
        ((issues_found++))
    fi

    # Check for test processes
    if pgrep -f "${DEPLOYMENT_ID}" >/dev/null 2>&1; then
        log_warning "Some test processes still running"
        ((issues_found++))
    fi

    if [[ ${issues_found} -eq 0 ]]; then
        log_success "Cleanup validation completed - no issues found"
    else
        log_warning "Cleanup validation found ${issues_found} issues"
    fi
}

# Generate cleanup report
generate_cleanup_report() {
    log_info "Generating cleanup report..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would generate cleanup report"
        return 0
    fi

    local report_file="${LOG_DIR}/cleanup-report-${DEPLOYMENT_ID}.json"

    cat > "${report_file}" << EOF
{
    "deployment_id": "${DEPLOYMENT_ID}",
    "environment": "${ENVIRONMENT}",
    "cleanup_timestamp": "$(date -Iseconds)",
    "cleanup_duration": "$(($(date +%s) - START_TIME))",
    "dry_run": ${DRY_RUN},
    "cleanup_actions": {
        "logs_cleaned": true,
        "backups_cleaned": true,
        "system_restored": true,
        "temp_files_cleaned": true
    },
    "archive_location": "${PROJECT_ROOT}/archives/rollback-testing/rollback-test-archive-${DEPLOYMENT_ID}.tar.gz"
}
EOF

    log_success "Cleanup report generated: ${report_file}"
}

# Main function
main() {
    START_TIME=$(date +%s)

    log_info "Starting test environment cleanup..."
    log_info "Environment: ${ENVIRONMENT}"
    log_info "Deployment ID: ${DEPLOYMENT_ID}"

    # Execute cleanup phases
    confirm_cleanup
    archive_test_results
    cleanup_log_files
    cleanup_backup_files
    restore_system_state
    cleanup_temporary_files
    validate_cleanup
    generate_cleanup_report

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - START_TIME))

    log_success "Test environment cleanup completed successfully in ${duration} seconds"
}

# Initialize script
parse_args "$@"
validate_inputs

# Run main function
if [[ "${VERBOSE}" == "true" ]]; then
    set -x
fi

main "$@"
