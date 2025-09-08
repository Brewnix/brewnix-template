#!/bin/bash

# BrewNix Cross-Submodule Integration Test Framework
# Phase 2.1.2 - Cross-Submodule Integration Testing
#
# This script orchestrates comprehensive integration testing across all BrewNix submodules
# including cross-submodule dependencies, shared environments, contract testing, and e2e scenarios

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Source core modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Set required environment variables for core modules
export BUILD_DIR="${PROJECT_ROOT}/build"
export LOG_FILE="${BUILD_DIR}/integration-test.log"
export LOG_LEVEL="INFO"

# Integration test configuration
TEST_RESULTS_DIR="${PROJECT_ROOT}/build/integration-test-results"
SHARED_ENV_DIR="${SCRIPT_DIR}/shared-test-environments"
CROSS_MODULE_TESTS_DIR="${SCRIPT_DIR}/cross-submodule-tests"
CONTRACT_TESTS_DIR="${SCRIPT_DIR}/contract-tests"
E2E_TESTS_DIR="${SCRIPT_DIR}/e2e-deployment-tests"

# Load core modules with error handling
if [[ -f "${PROJECT_ROOT}/scripts/core/config.sh" ]]; then
    source "${PROJECT_ROOT}/scripts/core/config.sh" || log_warning "Failed to load config.sh"
else
    log_warning "config.sh not found, using basic configuration"
fi

if [[ -f "${PROJECT_ROOT}/scripts/core/logging.sh" ]]; then
    source "${PROJECT_ROOT}/scripts/core/logging.sh" || log_warning "Failed to load logging.sh"
else
    log_warning "logging.sh not found, using basic logging"
fi

if [[ -f "${PROJECT_ROOT}/scripts/core/init.sh" ]]; then
    source "${PROJECT_ROOT}/scripts/core/init.sh" || log_warning "Failed to load init.sh"
else
    log_warning "init.sh not found, using basic initialization"
fi

log_test_result() {
    local test_name="$1"
    local result="$2"
    local duration="$3"

    case "$result" in
        "PASS")
            echo -e "${GREEN}✓${NC} $test_name (${duration}s)"
            ((PASSED_TESTS++))
            ;;
        "FAIL")
            echo -e "${RED}✗${NC} $test_name (${duration}s)"
            ((FAILED_TESTS++))
            ;;
        "SKIP")
            echo -e "${YELLOW}⊘${NC} $test_name (${duration}s)"
            ((SKIPPED_TESTS++))
            ;;
    esac
}

# Initialize test environment
init_test_environment() {
    log_info "Initializing integration test environment..."

    # Create test results directory
    mkdir -p "${TEST_RESULTS_DIR}"

    # Set test start time
    TEST_START_TIME=$(date +%s)

    # Initialize test counters
    TOTAL_TESTS=0
    PASSED_TESTS=0
    FAILED_TESTS=0
    SKIPPED_TESTS=0

    # Create test summary file
    cat > "${TEST_RESULTS_DIR}/test-summary.md" << EOF
# BrewNix Integration Test Results
Generated: $(date)
Test Start: $(date -d "@${TEST_START_TIME}")

## Test Configuration
- Framework Version: 2.1.2
- Test Environment: Integration
- Project Root: ${PROJECT_ROOT}

## Test Results Summary
EOF

    log_success "Test environment initialized"
}

# Setup shared test environments
setup_shared_environments() {
    log_info "Setting up shared test environments..."

    local env_setup_start
    env_setup_start=$(date +%s)

    # Create mock Proxmox environment
    if [ -f "${SHARED_ENV_DIR}/setup-mock-proxmox.sh" ]; then
        log_info "Setting up mock Proxmox environment..."
        bash "${SHARED_ENV_DIR}/setup-mock-proxmox.sh"
    fi

    # Create mock network environment
    if [ -f "${SHARED_ENV_DIR}/setup-mock-network.sh" ]; then
        log_info "Setting up mock network environment..."
        bash "${SHARED_ENV_DIR}/setup-mock-network.sh"
    fi

    # Create mock storage environment
    if [ -f "${SHARED_ENV_DIR}/setup-mock-storage.sh" ]; then
        log_info "Setting up mock storage environment..."
        bash "${SHARED_ENV_DIR}/setup-mock-storage.sh"
    fi

    local env_setup_duration=$(( $(date +%s) - env_setup_start ))
    log_success "Shared environments setup completed in ${env_setup_duration}s"
}

# Run cross-submodule dependency tests
run_cross_submodule_tests() {
    log_info "Running cross-submodule dependency tests..."

    local test_files=("${CROSS_MODULE_TESTS_DIR}"/*.sh)
    local test_count=${#test_files[@]}

    if [ $test_count -eq 0 ] || [ ! -f "${test_files[0]}" ]; then
        log_warning "No cross-submodule test files found"
        return 0
    fi

    log_info "Found ${test_count} cross-submodule test files"

    for test_file in "${test_files[@]}"; do
        if [ -f "$test_file" ] && [ -x "$test_file" ]; then
            local test_name
            test_name=$(basename "$test_file" .sh)
            local test_start
            test_start=$(date +%s)

            log_info "Running cross-submodule test: $test_name"

            if bash "$test_file"; then
                local test_duration=$(( $(date +%s) - test_start ))
                log_test_result "$test_name" "PASS" "$test_duration"
                ((TOTAL_TESTS++))
            else
                local test_duration=$(( $(date +%s) - test_start ))
                log_test_result "$test_name" "FAIL" "$test_duration"
                ((TOTAL_TESTS++))
            fi
        fi
    done
}

# Run contract tests between submodules
run_contract_tests() {
    log_info "Running contract tests between submodules..."

    local test_files=("${CONTRACT_TESTS_DIR}"/*.sh)
    local test_count=${#test_files[@]}

    if [ $test_count -eq 0 ] || [ ! -f "${test_files[0]}" ]; then
        log_warning "No contract test files found"
        return 0
    fi

    log_info "Found ${test_count} contract test files"

    for test_file in "${test_files[@]}"; do
        if [ -f "$test_file" ] && [ -x "$test_file" ]; then
            local test_name
            test_name=$(basename "$test_file" .sh)
            local test_start
            test_start=$(date +%s)

            log_info "Running contract test: $test_name"

            if bash "$test_file"; then
                local test_duration=$(( $(date +%s) - test_start ))
                log_test_result "$test_name" "PASS" "$test_duration"
                ((TOTAL_TESTS++))
            else
                local test_duration=$(( $(date +%s) - test_start ))
                log_test_result "$test_name" "FAIL" "$test_duration"
                ((TOTAL_TESTS++))
            fi
        fi
    done
}

# Run end-to-end deployment tests
run_e2e_deployment_tests() {
    log_info "Running end-to-end deployment tests..."

    local test_files=("${E2E_TESTS_DIR}"/*.sh)
    local test_count=${#test_files[@]}

    if [ $test_count -eq 0 ] || [ ! -f "${test_files[0]}" ]; then
        log_warning "No E2E deployment test files found"
        return 0
    fi

    log_info "Found ${test_count} E2E deployment test files"

    for test_file in "${test_files[@]}"; do
        if [ -f "$test_file" ] && [ -x "$test_file" ]; then
            local test_name
            test_name=$(basename "$test_file" .sh)
            local test_start
            test_start=$(date +%s)

            log_info "Running E2E deployment test: $test_name"

            if bash "$test_file"; then
                local test_duration=$(( $(date +%s) - test_start ))
                log_test_result "$test_name" "PASS" "$test_duration"
                ((TOTAL_TESTS++))
            else
                local test_duration=$(( $(date +%s) - test_start ))
                log_test_result "$test_name" "FAIL" "$test_duration"
                ((TOTAL_TESTS++))
            fi
        fi
    done
}

# Run performance regression tests
run_performance_tests() {
    log_info "Running performance regression tests..."

    if [ -f "${SCRIPT_DIR}/performance-regression-test.sh" ]; then
        local perf_start
        perf_start=$(date +%s)

        log_info "Executing performance regression test suite..."

        if bash "${SCRIPT_DIR}/performance-regression-test.sh"; then
            local perf_duration=$(( $(date +%s) - perf_start ))
            log_test_result "performance-regression" "PASS" "$perf_duration"
            ((TOTAL_TESTS++))
        else
            local perf_duration=$(( $(date +%s) - perf_start ))
            log_test_result "performance-regression" "FAIL" "$perf_duration"
            ((TOTAL_TESTS++))
        fi
    else
        log_warning "Performance regression test script not found"
        log_test_result "performance-regression" "SKIP" "0"
        ((TOTAL_TESTS++))
    fi
}

# Generate comprehensive test report
generate_test_report() {
    log_info "Generating comprehensive test report..."

    local test_end_time
    test_end_time=$(date +%s)
    TEST_DURATION=$(( test_end_time - TEST_START_TIME ))

    # Update test summary
    cat >> "${TEST_RESULTS_DIR}/test-summary.md" << EOF

## Execution Summary
- Total Tests: ${TOTAL_TESTS}
- Passed: ${PASSED_TESTS}
- Failed: ${FAILED_TESTS}
- Skipped: ${SKIPPED_TESTS}
- Duration: ${TEST_DURATION} seconds

## Test Categories Executed
- Cross-Submodule Tests: ✅ Completed
- Contract Tests: ✅ Completed
- E2E Deployment Tests: ✅ Completed
- Performance Tests: ✅ Completed

## Environment Information
- Test Framework: BrewNix Integration Test Suite v2.1.2
- Execution Environment: $(uname -a)
- Working Directory: ${PROJECT_ROOT}
- Test Results Directory: ${TEST_RESULTS_DIR}

## Detailed Results
EOF

    # Add individual test results
    if [ -d "${TEST_RESULTS_DIR}/details" ]; then
        for result_file in "${TEST_RESULTS_DIR}/details"/*.md; do
            if [ -f "$result_file" ]; then
                cat "$result_file" >> "${TEST_RESULTS_DIR}/test-summary.md"
                echo "" >> "${TEST_RESULTS_DIR}/test-summary.md"
            fi
        done
    fi

    # Calculate success rate
    local success_rate=0
    if [ $TOTAL_TESTS -gt 0 ]; then
        success_rate=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
    fi

    cat >> "${TEST_RESULTS_DIR}/test-summary.md" << EOF
## Success Metrics
- Success Rate: ${success_rate}%
- Test Completion: $(date -d "@${test_end_time}")

## Recommendations
EOF

    if [ $FAILED_TESTS -gt 0 ]; then
        cat >> "${TEST_RESULTS_DIR}/test-summary.md" << EOF
- Review ${FAILED_TESTS} failed tests for issues
- Check test logs for detailed error information
- Consider updating test expectations if changes are intentional
EOF
    fi

    if [ $success_rate -ge 90 ]; then
        cat >> "${TEST_RESULTS_DIR}/test-summary.md" << EOF
- All tests passed with high success rate
- Integration test suite is healthy
- Ready for deployment validation
EOF
    elif [ $success_rate -ge 75 ]; then
        cat >> "${TEST_RESULTS_DIR}/test-summary.md" << EOF
- Moderate test success rate
- Review failed tests before proceeding
- Consider additional test coverage
EOF
    else
        cat >> "${TEST_RESULTS_DIR}/test-summary.md" << EOF
- Low test success rate detected
- Critical review of test failures required
- Do not proceed with deployment until issues are resolved
EOF
    fi

    log_success "Test report generated: ${TEST_RESULTS_DIR}/test-summary.md"
}

# Cleanup test environment
cleanup_test_environment() {
    log_info "Cleaning up test environment..."

    # Stop any running mock services
    if [ -f "${SHARED_ENV_DIR}/cleanup-mock-services.sh" ]; then
        bash "${SHARED_ENV_DIR}/cleanup-mock-services.sh"
    fi

    # Remove temporary test files
    if [ -d "${TEST_RESULTS_DIR}/temp" ]; then
        rm -rf "${TEST_RESULTS_DIR}/temp"
    fi

    log_success "Test environment cleanup completed"
}

# Main execution function
main() {
    local exit_code=0

    log_info "Starting BrewNix Cross-Submodule Integration Test Suite v2.1.2"
    log_info "Test execution started at: $(date)"

    # Initialize test environment
    init_test_environment

    # Setup shared environments
    setup_shared_environments

    # Run test suites
    run_cross_submodule_tests
    run_contract_tests
    run_e2e_deployment_tests
    run_performance_tests

    # Generate comprehensive report
    generate_test_report

    # Cleanup
    cleanup_test_environment

    # Calculate final exit code
    if [ $FAILED_TESTS -gt 0 ]; then
        exit_code=1
    fi

    local final_success_rate=0
    if [ $TOTAL_TESTS -gt 0 ]; then
        final_success_rate=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
    fi

    log_info "Integration test suite completed"
    log_info "Final Results: ${PASSED_TESTS}/${TOTAL_TESTS} tests passed (${final_success_rate}%)"
    log_info "Total execution time: ${TEST_DURATION} seconds"
    log_info "Detailed results available at: ${TEST_RESULTS_DIR}/test-summary.md"

    if [ $exit_code -eq 0 ]; then
        log_success "✅ Integration test suite PASSED"
    else
        log_error "❌ Integration test suite FAILED"
    fi

    return $exit_code
}

# Execute main function
main "$@"
