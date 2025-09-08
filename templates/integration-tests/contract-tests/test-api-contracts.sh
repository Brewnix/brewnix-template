#!/bin/bash

# BrewNix Submodule API Contract Test
# Phase 2.1.2 - Cross-Submodule Integration Testing
#
# This test validates API contracts and interfaces between BrewNix submodules

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Test configuration
TEST_NAME="api-contract-validation"

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[${TEST_NAME}]${NC} $1"
}

log_error() {
    echo -e "${RED}[${TEST_NAME}]${NC} $1"
}

log_warning() {
 echo -e "${YELLOW}[${TEST_NAME}]${NC} $1"
}

# Test function contracts
test_function_contracts() {
    log_info "Testing function contracts between submodules..."

    local contract_issues=()

    # Test that core functions are available and have expected signatures

    # Test config.sh functions
    if [ -f "${PROJECT_ROOT}/scripts/core/config.sh" ]; then
        log_info "Testing config.sh function contracts..."

        # Check for expected functions
        local expected_config_functions=("load_config" "validate_config" "save_config")

        for func in "${expected_config_functions[@]}"; do
            if grep -q "^function $func\|^$func()" "${PROJECT_ROOT}/scripts/core/config.sh"; then
                log_info "✓ Function found: $func"
            else
                log_warning "⚠ Function not found: $func"
                contract_issues+=("missing-config-function-$func")
            fi
        done
    fi

    # Test logging.sh functions
    if [ -f "${PROJECT_ROOT}/scripts/core/logging.sh" ]; then
        log_info "Testing logging.sh function contracts..."

        local expected_logging_functions=("log_info" "log_error" "log_warning" "setup_logging")

        for func in "${expected_logging_functions[@]}"; do
            if grep -q "^function $func\|^$func()" "${PROJECT_ROOT}/scripts/core/logging.sh"; then
                log_info "✓ Function found: $func"
            else
                log_warning "⚠ Function not found: $func"
                contract_issues+=("missing-logging-function-$func")
            fi
        done
    fi

    # Test init.sh functions
    if [ -f "${PROJECT_ROOT}/scripts/core/init.sh" ]; then
        log_info "Testing init.sh function contracts..."

        local expected_init_functions=("initialize_system" "check_dependencies" "setup_environment")

        for func in "${expected_init_functions[@]}"; do
            if grep -q "^function $func\|^$func()" "${PROJECT_ROOT}/scripts/core/init.sh"; then
                log_info "✓ Function found: $func"
            else
                log_warning "⚠ Function not found: $func"
                contract_issues+=("missing-init-function-$func")
            fi
        done
    fi

    if [ ${#contract_issues[@]} -gt 0 ]; then
        log_error "Contract issues found: ${contract_issues[*]}"
        return 1
    fi

    log_info "Function contracts validated successfully"
    return 0
}

# Test variable contracts
test_variable_contracts() {
    log_info "Testing variable contracts between submodules..."

    local contract_issues=()

    # Test that expected global variables are defined

    # Test config.sh variables
    if [ -f "${PROJECT_ROOT}/scripts/core/config.sh" ]; then
        log_info "Testing config.sh variable contracts..."

        local expected_config_vars=("CONFIG_FILE" "CONFIG_DIR" "DEFAULT_CONFIG")

        for var in "${expected_config_vars[@]}"; do
            if grep -q "^$var=" "${PROJECT_ROOT}/scripts/core/config.sh"; then
                log_info "✓ Variable found: $var"
            else
                log_warning "⚠ Variable not found: $var"
                contract_issues+=("missing-config-var-$var")
            fi
        done
    fi

    # Test logging.sh variables
    if [ -f "${PROJECT_ROOT}/scripts/core/logging.sh" ]; then
        log_info "Testing logging.sh variable contracts..."

        local expected_logging_vars=("LOG_FILE" "LOG_LEVEL" "LOG_FORMAT")

        for var in "${expected_logging_vars[@]}"; do
            if grep -q "^$var=" "${PROJECT_ROOT}/scripts/core/logging.sh"; then
                log_info "✓ Variable found: $var"
            else
                log_warning "⚠ Variable not found: $var"
                contract_issues+=("missing-logging-var-$var")
            fi
        done
    fi

    if [ ${#contract_issues[@]} -gt 0 ]; then
        log_error "Variable contract issues found: ${contract_issues[*]}"
        return 1
    fi

    log_info "Variable contracts validated successfully"
    return 0
}

# Test exit code contracts
test_exit_code_contracts() {
    log_info "Testing exit code contracts..."

    local contract_issues=()

    # Test that functions return expected exit codes

    # Create a test script to validate exit codes
    local test_script="/tmp/test-exit-codes.sh"

    cat > "$test_script" << 'EOF'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

echo "Testing exit code contracts..."

# Source core modules
source "${PROJECT_ROOT}/scripts/core/config.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/scripts/core/logging.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/scripts/core/init.sh" 2>/dev/null || true

# Test function exit codes
exit_code_issues=()

# Test validate_config function (should return 0 on success, 1 on failure)
if command -v validate_config >/dev/null 2>&1; then
    # Test with valid config (should succeed)
    if validate_config 2>/dev/null; then
        echo "✓ validate_config returns 0 on success"
    else
        echo "✗ validate_config should return 0 on success"
        exit_code_issues+=("validate_config-success")
    fi

    # Test with invalid config (should fail)
    if validate_config "/nonexistent/config.yml" 2>/dev/null; then
        echo "✗ validate_config should return non-zero on failure"
        exit_code_issues+=("validate_config-failure")
    else
        echo "✓ validate_config returns non-zero on failure"
    fi
else
    echo "⚠ validate_config function not available"
fi

# Test log_info function (should always return 0)
if command -v log_info >/dev/null 2>&1; then
    if log_info "test message" 2>/dev/null; then
        echo "✓ log_info returns 0"
    else
        echo "✗ log_info should always return 0"
        exit_code_issues+=("log_info")
    fi
else
    echo "⚠ log_info function not available"
fi

# Output results
if [ ${#exit_code_issues[@]} -gt 0 ]; then
    echo "Exit code issues: ${exit_code_issues[*]}"
    exit 1
else
    echo "All exit code contracts validated"
    exit 0
fi
EOF

    chmod +x "$test_script"

    # Run the test script
    if bash "$test_script"; then
        log_info "✓ Exit code contracts validated"
    else
        log_error "✗ Exit code contract validation failed"
        contract_issues+=("exit-code-contracts")
    fi

    # Cleanup
    rm -f "$test_script"

    if [ ${#contract_issues[@]} -gt 0 ]; then
        return 1
    fi

    return 0
}

# Test API compatibility
test_api_compatibility() {
    log_info "Testing API compatibility between submodules..."

    local compatibility_issues=()

    # Test that submodules can communicate through expected APIs

    # Create a test script to validate API compatibility
    local test_script="/tmp/test-api-compatibility.sh"

    cat > "$test_script" << 'EOF'
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

echo "Testing API compatibility..."

# Source core modules
source "${PROJECT_ROOT}/scripts/core/config.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/scripts/core/logging.sh" 2>/dev/null || true

api_issues=()

# Test that logging functions work with config data
if command -v log_info >/dev/null 2>&1 && [ -n "${CONFIG_FILE:-}" ]; then
    if log_info "Config file location: ${CONFIG_FILE}" 2>/dev/null; then
        echo "✓ Logging API compatible with config data"
    else
        echo "✗ Logging API not compatible with config data"
        api_issues+=("logging-config-compatibility")
    fi
else
    echo "⚠ Cannot test logging-config API compatibility"
fi

# Test that config functions work with logging
if command -v validate_config >/dev/null 2>&1 && command -v log_info >/dev/null 2>&1; then
    # This is a basic compatibility test
    echo "✓ Config and logging APIs available for integration"
else
    echo "⚠ Config or logging API not fully available"
fi

# Output results
if [ ${#api_issues[@]} -gt 0 ]; then
    echo "API compatibility issues: ${api_issues[*]}"
    exit 1
else
    echo "API compatibility validated"
    exit 0
fi
EOF

    chmod +x "$test_script"

    # Run the test script
    if bash "$test_script"; then
        log_info "✓ API compatibility validated"
    else
        log_error "✗ API compatibility validation failed"
        compatibility_issues+=("api-compatibility")
    fi

    # Cleanup
    rm -f "$test_script"

    if [ ${#compatibility_issues[@]} -gt 0 ]; then
        return 1
    fi

    return 0
}

# Main test execution
main() {
    log_info "Starting API contract validation test..."

    local test_start
    test_start=$(date +%s)
    local test_status=0

    # Run all test functions
    if ! test_function_contracts; then
        test_status=1
    fi

    if ! test_variable_contracts; then
        test_status=1
    fi

    if ! test_exit_code_contracts; then
        test_status=1
    fi

    if ! test_api_compatibility; then
        test_status=1
    fi

    local test_end
    test_end=$(date +%s)
    local test_duration=$(( test_end - test_start ))

    if [ $test_status -eq 0 ]; then
        log_info "✅ API contract validation test PASSED (${test_duration}s)"
        echo "Test Results: PASS"
    else
        log_error "❌ API contract validation test FAILED (${test_duration}s)"
        echo "Test Results: FAIL"
        exit 1
    fi
}

# Execute main function
main "$@"
