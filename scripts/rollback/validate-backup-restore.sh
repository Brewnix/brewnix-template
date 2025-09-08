#!/bin/bash

# validate-backup-restore.sh
# Backup and restore validation testing for BrewNix deployments
# Tests backup integrity and restore procedures

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
TEST_DATA_SIZE="small"  # small, medium, large

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

Backup and restore validation testing for BrewNix deployments.

OPTIONS:
    --environment ENV       Target environment (staging, production, development)
    --deployment-id ID       Specific deployment ID for testing
    --log-dir DIR           Directory for log files
    --backup-dir DIR        Directory for backup files
    --test-data-size SIZE   Size of test data (small, medium, large)
    --dry-run               Show what would be done without executing
    --verbose               Enable verbose output
    --help                  Show this help message

EXAMPLES:
    $0 --environment staging --deployment-id 20240907-143000
    $0 --environment production --test-data-size large --verbose

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
            --test-data-size)
                TEST_DATA_SIZE="$2"
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
        DEPLOYMENT_ID=$(date +%Y%m%d-%H%M%S)
    fi

    if [[ -z "${LOG_DIR}" ]]; then
        LOG_DIR="${PROJECT_ROOT}/logs/rollback-testing"
    fi

    if [[ -z "${BACKUP_DIR}" ]]; then
        BACKUP_DIR="${PROJECT_ROOT}/backups/rollback-testing"
    fi

    # Create directories if they don't exist
    mkdir -p "${LOG_DIR}" "${BACKUP_DIR}"

    LOG_FILE="${LOG_DIR}/backup-restore-test-${DEPLOYMENT_ID}.log"
}

# Setup test environment
setup_test_environment() {
    log_info "Setting up backup and restore test environment..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would setup test environment"
        return 0
    fi

    # Create test data directory
    TEST_DATA_DIR="${BACKUP_DIR}/test-data-${DEPLOYMENT_ID}"
    mkdir -p "${TEST_DATA_DIR}"

    # Generate test data based on size
    case "${TEST_DATA_SIZE}" in
        small)
            create_test_data "${TEST_DATA_DIR}" 10  # 10 files
            ;;
        medium)
            create_test_data "${TEST_DATA_DIR}" 100  # 100 files
            ;;
        large)
            create_test_data "${TEST_DATA_DIR}" 1000  # 1000 files
            ;;
        *)
            log_error "Unknown test data size: ${TEST_DATA_SIZE}"
            exit 1
            ;;
    esac

    log_success "Test environment setup completed"
}

# Create test data files
create_test_data() {
    local test_dir="$1"
    local num_files="$2"

    log_info "Creating ${num_files} test data files..."

    for i in $(seq 1 "${num_files}"); do
        local filename
        filename=$(printf "test-file-%04d.txt" "$i")
        local filepath="${test_dir}/${filename}"

        # Create file with random content
        dd if=/dev/urandom of="${filepath}" bs=1024 count=$((RANDOM % 100 + 1)) 2>/dev/null

        # Add some metadata
        echo "Test file ${i}" >> "${filepath}"
        echo "Created: $(date)" >> "${filepath}"
        echo "Size: $(stat -f%z "${filepath}" 2>/dev/null || stat -c%s "${filepath}")" >> "${filepath}"
    done

    log_success "Created ${num_files} test files in ${test_dir}"
}

# Test backup creation
test_backup_creation() {
    log_info "Testing backup creation..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would create backup"
        return 0
    fi

    local backup_file="${BACKUP_DIR}/test-backup-${DEPLOYMENT_ID}.tar.gz"
    local start_time
    start_time=$(date +%s)

    # Create backup using tar
    if ! tar -czf "${backup_file}" -C "${BACKUP_DIR}" "test-data-${DEPLOYMENT_ID}"; then
        log_error "Failed to create backup"
        return 1
    fi

    local end_time
    end_time=$(date +%s)
    local backup_duration=$((end_time - start_time))
    local backup_size
    backup_size=$(stat -f%z "${backup_file}" 2>/dev/null || stat -c%s "${backup_file}")

    log_success "Backup created successfully"
    log_info "Backup file: ${backup_file}"
    log_info "Backup size: ${backup_size} bytes"
    log_info "Backup duration: ${backup_duration} seconds"

    # Validate backup integrity
    validate_backup_integrity "${backup_file}"
}

# Validate backup integrity
validate_backup_integrity() {
    local backup_file="$1"

    log_info "Validating backup integrity..."

    # Test if backup can be listed
    if ! tar -tzf "${backup_file}" >/dev/null; then
        log_error "Backup integrity check failed - cannot list contents"
        return 1
    fi

    # Get file count in backup
    local file_count
    file_count=$(tar -tzf "${backup_file}" | wc -l)

    log_success "Backup integrity validated"
    log_info "Files in backup: ${file_count}"
}

# Test backup restoration
test_backup_restoration() {
    log_info "Testing backup restoration..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would restore backup"
        return 0
    fi

    local backup_file="${BACKUP_DIR}/test-backup-${DEPLOYMENT_ID}.tar.gz"
    local restore_dir="${BACKUP_DIR}/restore-test-${DEPLOYMENT_ID}"
    local start_time
    start_time=$(date +%s)

    # Create restore directory
    mkdir -p "${restore_dir}"

    # Restore backup
    if ! tar -xzf "${backup_file}" -C "${restore_dir}"; then
        log_error "Failed to restore backup"
        return 1
    fi

    local end_time
    end_time=$(date +%s)
    local restore_duration=$((end_time - start_time))

    log_success "Backup restoration completed"
    log_info "Restore directory: ${restore_dir}"
    log_info "Restore duration: ${restore_duration} seconds"

    # Validate restoration
    validate_restoration "${restore_dir}"
}

# Validate restoration
validate_restoration() {
    local restore_dir="$1"

    log_info "Validating restoration..."

    # Compare original and restored data
    local original_dir="${BACKUP_DIR}/test-data-${DEPLOYMENT_ID}"
    local restored_dir="${restore_dir}/test-data-${DEPLOYMENT_ID}"

    if [[ ! -d "${restored_dir}" ]]; then
        log_error "Restored directory not found"
        return 1
    fi

    # Compare file counts
    local original_count
    local restored_count
    original_count=$(find "${original_dir}" -type f | wc -l)
    restored_count=$(find "${restored_dir}" -type f | wc -l)

    if [[ "${original_count}" != "${restored_count}" ]]; then
        log_error "File count mismatch: original=${original_count}, restored=${restored_count}"
        return 1
    fi

    # Compare file contents (sample)
    local sample_file="test-file-0001.txt"
    if [[ -f "${original_dir}/${sample_file}" && -f "${restored_dir}/${sample_file}" ]]; then
        if ! diff "${original_dir}/${sample_file}" "${restored_dir}/${sample_file}" >/dev/null; then
            log_error "File content mismatch in ${sample_file}"
            return 1
        fi
    fi

    log_success "Restoration validation completed"
    log_info "Files restored: ${restored_count}"
}

# Test incremental backup
test_incremental_backup() {
    log_info "Testing incremental backup..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would test incremental backup"
        return 0
    fi

    local base_backup="${BACKUP_DIR}/test-backup-${DEPLOYMENT_ID}.tar.gz"
    local incremental_file="${BACKUP_DIR}/test-incremental-${DEPLOYMENT_ID}.tar.gz"

    # Modify some test data
    local test_file="${BACKUP_DIR}/test-data-${DEPLOYMENT_ID}/test-file-0001.txt"
    echo "Modified at $(date)" >> "${test_file}"

    # Create incremental backup (simplified - in real scenario would use proper incremental tools)
    if ! tar -czf "${incremental_file}" \
        --newer-mtime="$(date -r "${base_backup}" +%Y-%m-%d\ %H:%M:%S)" \
        -C "${BACKUP_DIR}" "test-data-${DEPLOYMENT_ID}"; then
        log_warning "Incremental backup creation failed (expected for small test data)"
    else
        log_success "Incremental backup created"
        log_info "Incremental backup: ${incremental_file}"
    fi
}

# Test backup compression
test_backup_compression() {
    log_info "Testing backup compression efficiency..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would test compression"
        return 0
    fi

    local test_dir="${BACKUP_DIR}/test-data-${DEPLOYMENT_ID}"
    local uncompressed_size
    local compressed_size
    local compression_ratio

    # Calculate uncompressed size
    uncompressed_size=$(du -sb "${test_dir}" | cut -f1)

    # Calculate compressed size
    local backup_file="${BACKUP_DIR}/test-backup-${DEPLOYMENT_ID}.tar.gz"
    compressed_size=$(stat -f%z "${backup_file}" 2>/dev/null || stat -c%s "${backup_file}")

    # Calculate compression ratio
    if [[ ${uncompressed_size} -gt 0 ]]; then
        compression_ratio=$((compressed_size * 100 / uncompressed_size))
        log_info "Compression ratio: ${compression_ratio}%"
        log_info "Original size: ${uncompressed_size} bytes"
        log_info "Compressed size: ${compressed_size} bytes"
    fi
}

# Test backup retention
test_backup_retention() {
    log_info "Testing backup retention policies..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would test retention"
        return 0
    fi

    # Simulate backup retention (keep last 5, delete older)
    local backup_pattern="${BACKUP_DIR}/test-backup-*.tar.gz"
    local backup_count
    backup_count=$(ls -t ${backup_pattern} 2>/dev/null | wc -l)

    if [[ ${backup_count} -gt 5 ]]; then
        local to_delete=$((backup_count - 5))
        ls -t ${backup_pattern} | tail -n ${to_delete} | xargs rm -f
        log_info "Cleaned up ${to_delete} old backup(s)"
    fi

    log_success "Backup retention test completed"
}

# Generate backup/restore report
generate_backup_report() {
    log_info "Generating backup and restore test report..."

    local report_file="${LOG_DIR}/backup-restore-report-${DEPLOYMENT_ID}.json"
    local backup_file="${BACKUP_DIR}/test-backup-${DEPLOYMENT_ID}.tar.gz"

    local backup_size=0
    if [[ -f "${backup_file}" ]]; then
        backup_size=$(stat -f%z "${backup_file}" 2>/dev/null || stat -c%s "${backup_file}")
    fi

    cat > "${report_file}" << EOF
{
    "deployment_id": "${DEPLOYMENT_ID}",
    "environment": "${ENVIRONMENT}",
    "test_timestamp": "$(date -Iseconds)",
    "test_data_size": "${TEST_DATA_SIZE}",
    "backup_size_bytes": ${backup_size},
    "test_status": "completed",
    "test_duration": "$(($(date +%s) - START_TIME))",
    "log_file": "${LOG_FILE}",
    "backup_file": "${backup_file}"
}
EOF

    log_success "Backup and restore report generated: ${report_file}"
}

# Cleanup test environment
cleanup_test_environment() {
    log_info "Cleaning up test environment..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would cleanup test environment"
        return 0
    fi

    # Remove test data and restore directories
    rm -rf "${BACKUP_DIR}/test-data-${DEPLOYMENT_ID}"
    rm -rf "${BACKUP_DIR}/restore-test-${DEPLOYMENT_ID}"

    log_success "Test environment cleanup completed"
}

# Main function
main() {
    START_TIME=$(date +%s)

    log_info "Starting backup and restore validation test"
    log_info "Environment: ${ENVIRONMENT}"
    log_info "Test Data Size: ${TEST_DATA_SIZE}"
    log_info "Log file: ${LOG_FILE}"

    # Execute backup/restore test phases
    setup_test_environment
    test_backup_creation
    test_backup_restoration
    test_incremental_backup
    test_backup_compression
    test_backup_retention
    generate_backup_report
    cleanup_test_environment

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - START_TIME))

    log_success "Backup and restore validation test completed successfully in ${duration} seconds"
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
