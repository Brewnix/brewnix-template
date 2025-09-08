#!/bin/bash

# generate-test-report.sh
# Generate comprehensive test reports for rollback and recovery testing
# Aggregates results from all test phases and generates formatted reports

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ARTIFACTS_DIR=""
OUTPUT_DIR=""
DEPLOYMENT_ID=""
TEST_TYPE="comprehensive"
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

Generate comprehensive test reports for rollback and recovery testing.

OPTIONS:
    --artifacts-dir DIR     Directory containing test artifacts
    --output-dir DIR        Directory for generated reports
    --deployment-id ID      Deployment ID for the test run
    --test-type TYPE        Type of test (comprehensive, rollback-only, etc.)
    --dry-run               Show what would be done without executing
    --verbose               Enable verbose output
    --help                  Show this help message

EXAMPLES:
    $0 --artifacts-dir test-artifacts --output-dir reports --deployment-id 20240907-143000
    $0 --artifacts-dir artifacts --output-dir output --test-type rollback-only

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --artifacts-dir)
                ARTIFACTS_DIR="$2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --deployment-id)
                DEPLOYMENT_ID="$2"
                shift 2
                ;;
            --test-type)
                TEST_TYPE="$2"
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
    if [[ -z "${ARTIFACTS_DIR}" ]]; then
        log_error "Artifacts directory is required. Use --artifacts-dir"
        exit 1
    fi

    if [[ -z "${OUTPUT_DIR}" ]]; then
        OUTPUT_DIR="${PROJECT_ROOT}/reports"
    fi

    if [[ -z "${DEPLOYMENT_ID}" ]]; then
        DEPLOYMENT_ID=$(date +%Y%m%d-%H%M%S)
    fi

    # Create output directory if it doesn't exist
    mkdir -p "${OUTPUT_DIR}"
}

# Collect test results
collect_test_results() {
    log_info "Collecting test results from artifacts..."

    # Initialize results structure
    declare -A test_results
    declare -A test_logs
    declare -A test_metrics

    # Find all test result files
    while IFS= read -r -d '' log_file; do
        local test_name
        test_name=$(basename "${log_file}" | sed 's/-.*//')

        case "${test_name}" in
            rollback)
                test_results["rollback"]=$(extract_test_status "${log_file}")
                test_logs["rollback"]="${log_file}"
                ;;
            backup)
                test_results["backup_restore"]=$(extract_test_status "${log_file}")
                test_logs["backup_restore"]="${log_file}"
                ;;
            chaos)
                test_results["chaos_engineering"]=$(extract_test_status "${log_file}")
                test_logs["chaos_engineering"]="${log_file}"
                ;;
            disaster)
                test_results["disaster_recovery"]=$(extract_test_status "${log_file}")
                test_logs["disaster_recovery"]="${log_file}"
                ;;
        esac
    done < <(find "${ARTIFACTS_DIR}" -name "*.log" -print0)

    # Find JSON report files
    while IFS= read -r -d '' json_file; do
        local test_name
        test_name=$(basename "${json_file}" | sed 's/-report.*//')

        case "${test_name}" in
            rollback)
                test_metrics["rollback"]=$(cat "${json_file}")
                ;;
            backup)
                test_metrics["backup_restore"]=$(cat "${json_file}")
                ;;
            chaos)
                test_metrics["chaos_engineering"]=$(cat "${json_file}")
                ;;
            disaster)
                test_metrics["disaster_recovery"]=$(cat "${json_file}")
                ;;
        esac
    done < <(find "${ARTIFACTS_DIR}" -name "*-report*.json" -print0)
}

# Extract test status from log file
extract_test_status() {
    local log_file="$1"

    if grep -q "completed successfully" "${log_file}"; then
        echo "PASSED"
    elif grep -q "failed\|error" "${log_file}"; then
        echo "FAILED"
    else
        echo "UNKNOWN"
    fi
}

# Generate JSON report
generate_json_report() {
    log_info "Generating JSON test report..."

    local json_report="${OUTPUT_DIR}/rollback-recovery-test-report-${DEPLOYMENT_ID}.json"

    cat > "${json_report}" << EOF
{
    "deployment_id": "${DEPLOYMENT_ID}",
    "test_type": "${TEST_TYPE}",
    "timestamp": "$(date -Iseconds)",
    "summary": {
        "rollback_test": "${test_results[rollback]:-NOT_RUN}",
        "backup_restore_test": "${test_results[backup_restore]:-NOT_RUN}",
        "chaos_engineering_test": "${test_results[chaos_engineering]:-NOT_RUN}",
        "disaster_recovery_test": "${test_results[disaster_recovery]:-NOT_RUN}"
    },
    "overall_status": "$(calculate_overall_status)",
    "test_duration": "$(calculate_total_duration)",
    "artifacts_directory": "${ARTIFACTS_DIR}",
    "log_files": {
        "rollback": "${test_logs[rollback]:-N/A}",
        "backup_restore": "${test_logs[backup_restore]:-N/A}",
        "chaos_engineering": "${test_logs[chaos_engineering]:-N/A}",
        "disaster_recovery": "${test_logs[disaster_recovery]:-N/A}"
    },
    "detailed_metrics": {
        "rollback": ${test_metrics[rollback]:-null},
        "backup_restore": ${test_metrics[backup_restore]:-null},
        "chaos_engineering": ${test_metrics[chaos_engineering]:-null},
        "disaster_recovery": ${test_metrics[disaster_recovery]:-null}
    }
}
EOF

    log_success "JSON report generated: ${json_report}"
}

# Calculate overall test status
calculate_overall_status() {
    local failed_tests=0
    local total_tests=0

    for status in "${test_results[@]}"; do
        ((total_tests++))
        if [[ "${status}" == "FAILED" ]]; then
            ((failed_tests++))
        fi
    done

    if [[ ${failed_tests} -eq 0 ]]; then
        echo "PASSED"
    elif [[ ${failed_tests} -eq ${total_tests} ]]; then
        echo "FAILED"
    else
        echo "PARTIAL"
    fi
}

# Calculate total test duration
calculate_total_duration() {
    local total_duration=0

    # Extract durations from metrics
    for metrics in "${test_metrics[@]}"; do
        if [[ -n "${metrics}" && "${metrics}" != "null" ]]; then
            local duration
            duration=$(echo "${metrics}" | jq -r '.test_duration // 0' 2>/dev/null || echo "0")
            total_duration=$((total_duration + duration))
        fi
    done

    echo "${total_duration}"
}

# Generate HTML report
generate_html_report() {
    log_info "Generating HTML test report..."

    local html_report="${OUTPUT_DIR}/rollback-recovery-test-report-${DEPLOYMENT_ID}.html"
    local overall_status
    overall_status=$(calculate_overall_status)

    cat > "${html_report}" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>BrewNix Rollback & Recovery Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f8f9fa; padding: 20px; border-radius: 5px; margin-bottom: 20px; }
        .summary { display: flex; gap: 20px; margin-bottom: 20px; }
        .metric { flex: 1; padding: 15px; border-radius: 5px; text-align: center; }
        .passed { background-color: #d4edda; color: #155724; }
        .failed { background-color: #f8d7da; color: #721c24; }
        .unknown { background-color: #fff3cd; color: #856404; }
        .not-run { background-color: #e2e3e5; color: #383d41; }
        .details { margin-top: 20px; }
        .test-section { margin-bottom: 20px; padding: 15px; border: 1px solid #dee2e6; border-radius: 5px; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { padding: 8px; text-align: left; border-bottom: 1px solid #dee2e6; }
        th { background-color: #f8f9fa; }
    </style>
</head>
<body>
    <div class="header">
        <h1>BrewNix Rollback & Recovery Test Report</h1>
        <p><strong>Deployment ID:</strong> ${DEPLOYMENT_ID}</p>
        <p><strong>Test Type:</strong> ${TEST_TYPE}</p>
        <p><strong>Timestamp:</strong> $(date)</p>
    </div>

    <div class="summary">
        <div class="metric $(get_status_class "${test_results[rollback]:-NOT_RUN}")">
            <h3>Rollback Test</h3>
            <p>${test_results[rollback]:-NOT_RUN}</p>
        </div>
        <div class="metric $(get_status_class "${test_results[backup_restore]:-NOT_RUN}")">
            <h3>Backup & Restore</h3>
            <p>${test_results[backup_restore]:-NOT_RUN}</p>
        </div>
        <div class="metric $(get_status_class "${test_results[chaos_engineering]:-NOT_RUN}")">
            <h3>Chaos Engineering</h3>
            <p>${test_results[chaos_engineering]:-NOT_RUN}</p>
        </div>
        <div class="metric $(get_status_class "${test_results[disaster_recovery]:-NOT_RUN}")">
            <h3>Disaster Recovery</h3>
            <p>${test_results[disaster_recovery]:-NOT_RUN}</p>
        </div>
    </div>

    <div class="details">
        <div class="test-section">
            <h2>Test Summary</h2>
            <table>
                <tr><th>Test</th><th>Status</th><th>Duration</th><th>Log File</th></tr>
                <tr><td>Rollback Test</td><td>${test_results[rollback]:-NOT_RUN}</td><td>$(get_test_duration "rollback")s</td><td>${test_logs[rollback]:-N/A}</td></tr>
                <tr><td>Backup & Restore</td><td>${test_results[backup_restore]:-NOT_RUN}</td><td>$(get_test_duration "backup_restore")s</td><td>${test_logs[backup_restore]:-N/A}</td></tr>
                <tr><td>Chaos Engineering</td><td>${test_results[chaos_engineering]:-NOT_RUN}</td><td>$(get_test_duration "chaos_engineering")s</td><td>${test_logs[chaos_engineering]:-N/A}</td></tr>
                <tr><td>Disaster Recovery</td><td>${test_results[disaster_recovery]:-NOT_RUN}</td><td>$(get_test_duration "disaster_recovery")s</td><td>${test_logs[disaster_recovery]:-N/A}</td></tr>
            </table>
        </div>

        <div class="test-section">
            <h2>Overall Assessment</h2>
            <p><strong>Overall Status:</strong> <span class="$(get_status_class "${overall_status}")">${overall_status}</span></p>
            <p><strong>Total Duration:</strong> $(calculate_total_duration) seconds</p>
            <p><strong>Artifacts Location:</strong> ${ARTIFACTS_DIR}</p>
        </div>
    </div>
</body>
</html>
EOF

    log_success "HTML report generated: ${html_report}"
}

# Get CSS class for status
get_status_class() {
    local status="$1"
    case "${status}" in
        PASSED)
            echo "passed"
            ;;
        FAILED)
            echo "failed"
            ;;
        UNKNOWN)
            echo "unknown"
            ;;
        *)
            echo "not-run"
            ;;
    esac
}

# Get test duration
get_test_duration() {
    local test_name="$1"
    local metrics="${test_metrics[${test_name}]:-}"

    if [[ -n "${metrics}" && "${metrics}" != "null" ]]; then
        echo "${metrics}" | jq -r '.test_duration // 0' 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Generate summary report
generate_summary_report() {
    log_info "Generating summary report..."

    local summary_file="${OUTPUT_DIR}/test-summary-${DEPLOYMENT_ID}.txt"
    local overall_status
    overall_status=$(calculate_overall_status)

    cat > "${summary_file}" << EOF
BrewNix Rollback & Recovery Test Summary
========================================

Deployment ID: ${DEPLOYMENT_ID}
Test Type: ${TEST_TYPE}
Timestamp: $(date)
Overall Status: ${overall_status}

Test Results:
--------------
Rollback Test: ${test_results[rollback]:-NOT_RUN}
Backup & Restore: ${test_results[backup_restore]:-NOT_RUN}
Chaos Engineering: ${test_results[chaos_engineering]:-NOT_RUN}
Disaster Recovery: ${test_results[disaster_recovery]:-NOT_RUN}

Duration Summary:
-----------------
Total Duration: $(calculate_total_duration) seconds

Artifacts Location: ${ARTIFACTS_DIR}
Reports Location: ${OUTPUT_DIR}

Log Files:
----------
$(format_log_files)

EOF

    log_success "Summary report generated: ${summary_file}"
}

# Format log files for summary
format_log_files() {
    for test in "${!test_logs[@]}"; do
        echo "${test}: ${test_logs[${test}]}"
    done
}

# Main function
main() {
    log_info "Starting test report generation..."
    log_info "Artifacts directory: ${ARTIFACTS_DIR}"
    log_info "Output directory: ${OUTPUT_DIR}"
    log_info "Deployment ID: ${DEPLOYMENT_ID}"

    # Execute report generation phases
    collect_test_results
    generate_json_report
    generate_html_report
    generate_summary_report

    log_success "Test report generation completed successfully"
    log_info "Reports saved to: ${OUTPUT_DIR}"
}

# Initialize script
parse_args "$@"
validate_inputs

# Run main function
if [[ "${VERBOSE}" == "true" ]]; then
    set -x
fi

main "$@"
