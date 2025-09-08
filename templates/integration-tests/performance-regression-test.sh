#!/bin/bash

# BrewNix Performance Regression Test
# Phase 2.1.2 - Cross-Submodule Integration Testing
#
# This script performs performance regression testing to detect performance degradation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Test configuration
TEST_NAME="performance-regression"
PERFORMANCE_BASELINE_FILE="${SCRIPT_DIR}/performance-baseline.json"
PERFORMANCE_RESULTS_FILE="${SCRIPT_DIR}/performance-results.json"

# Performance thresholds (in seconds)
MAX_CORE_MODULE_LOAD_TIME=2.0
MAX_CONFIG_VALIDATION_TIME=5.0
MAX_INIT_TIME=10.0
MAX_DEPLOYMENT_SIMULATION_TIME=30.0

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[${TEST_NAME}]${NC} $1"
}

log_error() {
    echo -e "${RED}[${TEST_NAME}]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[${TEST_NAME}]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[${TEST_NAME}]${NC} $1"
}

# Initialize performance results
init_performance_results() {
    cat > "$PERFORMANCE_RESULTS_FILE" << EOF
{
  "test_run": "$(date -Iseconds)",
  "results": {},
  "summary": {
    "total_tests": 0,
    "passed": 0,
    "failed": 0,
    "regressions": 0
  }
}
EOF
}

# Measure core module load time
measure_core_module_load_time() {
    log_info "Measuring core module load times..."

    local core_modules=("config.sh" "logging.sh" "init.sh")
    local results=()

    for module in "${core_modules[@]}"; do
        local module_path="${PROJECT_ROOT}/scripts/core/${module}"

        if [ -f "$module_path" ]; then
            local start_time
            start_time=$(date +%s.%N)

            # Load the module
            bash -c "source '$module_path'" 2>/dev/null || true

            local end_time
            end_time=$(date +%s.%N)

            # Calculate load time
            local load_time
            load_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")

            results+=("$module:$load_time")

            if (( $(echo "$load_time < $MAX_CORE_MODULE_LOAD_TIME" | bc -l 2>/dev/null || echo "1") )); then
                log_info "✓ $module loaded in ${load_time}s"
            else
                log_warning "⚠ $module load time (${load_time}s) exceeds threshold (${MAX_CORE_MODULE_LOAD_TIME}s)"
            fi
        else
            log_warning "⚠ Core module not found: $module"
            results+=("$module:0")
        fi
    done

    echo "${results[@]}"
}

# Measure configuration validation time
measure_config_validation_time() {
    log_info "Measuring configuration validation time..."

    local config_file="${PROJECT_ROOT}/config/site-example.yml"
    local start_time
    local end_time
    local validation_time

    if [ -f "$config_file" ]; then
        start_time=$(date +%s.%N)

        # Perform configuration validation
        if [ -f "${PROJECT_ROOT}/scripts/core/config.sh" ]; then
            bash -c "source '${PROJECT_ROOT}/scripts/core/config.sh'; validate_config '$config_file'" 2>/dev/null || true
        fi

        end_time=$(date +%s.%N)
        validation_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")

        if (( $(echo "$validation_time < $MAX_CONFIG_VALIDATION_TIME" | bc -l 2>/dev/null || echo "1") )); then
            log_info "✓ Configuration validation completed in ${validation_time}s"
        else
            log_warning "⚠ Configuration validation time (${validation_time}s) exceeds threshold (${MAX_CONFIG_VALIDATION_TIME}s)"
        fi
    else
        log_warning "⚠ Configuration file not found: $config_file"
        validation_time="0"
    fi

    echo "$validation_time"
}

# Measure initialization time
measure_init_time() {
    log_info "Measuring system initialization time..."

    local start_time
    local end_time
    local init_time

    start_time=$(date +%s.%N)

    # Perform system initialization
    if [ -f "${PROJECT_ROOT}/scripts/core/init.sh" ]; then
        bash -c "source '${PROJECT_ROOT}/scripts/core/init.sh'; initialize_system" 2>/dev/null || true
    fi

    end_time=$(date +%s.%N)
    init_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")

    if (( $(echo "$init_time < $MAX_INIT_TIME" | bc -l 2>/dev/null || echo "1") )); then
        log_info "✓ System initialization completed in ${init_time}s"
    else
        log_warning "⚠ System initialization time (${init_time}s) exceeds threshold (${MAX_INIT_TIME}s)"
    fi

    echo "$init_time"
}

# Measure deployment simulation time
measure_deployment_simulation_time() {
    log_info "Measuring deployment simulation time..."

    local start_time
    local end_time
    local deployment_time

    start_time=$(date +%s.%N)

    # Perform deployment simulation
    if [ -f "${PROJECT_ROOT}/scripts/deployment/deployment.sh" ]; then
        timeout 60 bash -c "source '${PROJECT_ROOT}/scripts/deployment/deployment.sh'; simulate_deployment" 2>/dev/null || true
    fi

    end_time=$(date +%s.%N)
    deployment_time=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "0")

    if (( $(echo "$deployment_time < $MAX_DEPLOYMENT_SIMULATION_TIME" | bc -l 2>/dev/null || echo "1") )); then
        log_info "✓ Deployment simulation completed in ${deployment_time}s"
    else
        log_warning "⚠ Deployment simulation time (${deployment_time}s) exceeds threshold (${MAX_DEPLOYMENT_SIMULATION_TIME}s)"
    fi

    echo "$deployment_time"
}

# Load performance baseline
load_performance_baseline() {
    if [ -f "$PERFORMANCE_BASELINE_FILE" ]; then
        log_info "Loading performance baseline..."
        cat "$PERFORMANCE_BASELINE_FILE"
    else
        log_warning "Performance baseline file not found, creating default baseline..."
        cat << EOF
{
  "core_module_load_times": {
    "config.sh": 0.5,
    "logging.sh": 0.3,
    "init.sh": 0.8
  },
  "config_validation_time": 2.0,
  "init_time": 3.0,
  "deployment_simulation_time": 15.0,
  "created": "$(date -Iseconds)"
}
EOF
    fi
}

# Compare with baseline
compare_with_baseline() {
    local current_results="$1"
    local baseline_data="$2"

    log_info "Comparing current performance with baseline..."

    local regressions=0

    # Parse current results and compare
    local core_load_times
    local config_validation_time
    local init_time
    local deployment_time

    # Extract values from current results (simplified parsing)
    core_load_times=$(echo "$current_results" | grep -o "core_module_load_times:.*" | cut -d: -f2-)
    config_validation_time=$(echo "$current_results" | grep -o "config_validation_time:.*" | cut -d: -f2-)
    init_time=$(echo "$current_results" | grep -o "init_time:.*" | cut -d: -f2-)
    deployment_time=$(echo "$current_results" | grep -o "deployment_simulation_time:.*" | cut -d: -f2-)

    # Compare core module load times
    if [ -n "$core_load_times" ]; then
        log_info "Core module load times: $core_load_times"
    fi

    # Compare config validation time
    if [ -n "$config_validation_time" ]; then
        local baseline_config_time
        baseline_config_time=$(echo "$baseline_data" | grep -o '"config_validation_time":\s*[0-9.]*' | grep -o '[0-9.]*')

        if [ -n "$baseline_config_time" ] && (( $(echo "$config_validation_time > $baseline_config_time * 1.2" | bc -l 2>/dev/null || echo "0") )); then
            log_error "❌ Config validation performance regression detected"
            ((regressions++))
        else
            log_success "✓ Config validation performance OK"
        fi
    fi

    # Compare init time
    if [ -n "$init_time" ]; then
        local baseline_init_time
        baseline_init_time=$(echo "$baseline_data" | grep -o '"init_time":\s*[0-9.]*' | grep -o '[0-9.]*')

        if [ -n "$baseline_init_time" ] && (( $(echo "$init_time > $baseline_init_time * 1.2" | bc -l 2>/dev/null || echo "0") )); then
            log_error "❌ Initialization performance regression detected"
            ((regressions++))
        else
            log_success "✓ Initialization performance OK"
        fi
    fi

    # Compare deployment time
    if [ -n "$deployment_time" ]; then
        local baseline_deployment_time
        baseline_deployment_time=$(echo "$baseline_data" | grep -o '"deployment_simulation_time":\s*[0-9.]*' | grep -o '[0-9.]*')

        if [ -n "$baseline_deployment_time" ] && (( $(echo "$deployment_time > $baseline_deployment_time * 1.2" | bc -l 2>/dev/null || echo "0") )); then
            log_error "❌ Deployment simulation performance regression detected"
            ((regressions++))
        else
            log_success "✓ Deployment simulation performance OK"
        fi
    fi

    echo "$regressions"
}

# Save performance results
save_performance_results() {
    local results="$1"
    local regressions="$2"

    log_info "Saving performance test results..."

    # Update results file with the results string
    jq --arg results "$results" \
       --argjson regressions "$regressions" \
       '.results = $results | .summary.regressions = $regressions' \
       "$PERFORMANCE_RESULTS_FILE" > "${PERFORMANCE_RESULTS_FILE}.tmp" 2>/dev/null || true

    if [ -f "${PERFORMANCE_RESULTS_FILE}.tmp" ]; then
        mv "${PERFORMANCE_RESULTS_FILE}.tmp" "$PERFORMANCE_RESULTS_FILE"
    fi

    log_success "Performance results saved to: $PERFORMANCE_RESULTS_FILE"
}

# Main performance test execution
main() {
    log_info "Starting performance regression test..."

    local test_start
    test_start=$(date +%s)
    local test_status=0

    # Initialize results
    init_performance_results

    # Load baseline
    local baseline_data
    baseline_data=$(load_performance_baseline)

    # Run performance measurements
    local core_load_times
    local config_validation_time
    local init_time
    local deployment_time

    core_load_times=$(measure_core_module_load_time)
    config_validation_time=$(measure_config_validation_time)
    init_time=$(measure_init_time)
    deployment_time=$(measure_deployment_simulation_time)

    # Compile results as a string
    local current_results="core_module_load_times:$core_load_times config_validation_time:$config_validation_time init_time:$init_time deployment_simulation_time:$deployment_time"

    # Compare with baseline
    local regressions
    regressions=$(compare_with_baseline "$current_results" "$baseline_data")

    # Save results
    save_performance_results "$current_results" "$regressions"

    local test_end
    test_end=$(date +%s)
    local test_duration=$(( test_end - test_start ))

    # Determine test status
    if [ "$regressions" -gt 0 ]; then
        test_status=1
        log_error "❌ Performance regression test FAILED - $regressions regression(s) detected (${test_duration}s)"
        echo "Test Results: FAIL"
    else
        log_success "✅ Performance regression test PASSED - No regressions detected (${test_duration}s)"
        echo "Test Results: PASS"
    fi

    # Output performance summary
    log_info "Performance Test Summary:"
    log_info "  - Core module load times: $core_load_times"
    log_info "  - Config validation time: ${config_validation_time}s"
    log_info "  - Init time: ${init_time}s"
    log_info "  - Deployment simulation time: ${deployment_time}s"
    log_info "  - Regressions detected: $regressions"

    return $test_status
}

# Execute main function
main "$@"
