#!/bin/bash

# BrewNix Cross-Submodule Core Module Dependency Test
# Phase 2.1.2 - Cross-Submodule Integration Testing
#
# This test validates that core modules are properly synchronized across submodules

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Test configuration
TEST_NAME="core-module-sync"
EXPECTED_CORE_MODULES=("config.sh" "logging.sh" "init.sh")

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

# Test core module existence
test_core_module_existence() {
    log_info "Testing core module existence..."

    local core_dir="${PROJECT_ROOT}/scripts/core"
    local missing_modules=()

    for module in "${EXPECTED_CORE_MODULES[@]}"; do
        if [ -f "${core_dir}/${module}" ]; then
            log_info "✓ Core module found: $module"
        else
            log_error "✗ Core module missing: $module"
            missing_modules+=("$module")
        fi
    done

    if [ ${#missing_modules[@]} -gt 0 ]; then
        log_error "Missing core modules: ${missing_modules[*]}"
        return 1
    fi

    log_info "All expected core modules are present"
    return 0
}

# Test core module permissions
test_core_module_permissions() {
    log_info "Testing core module permissions..."

    local core_dir="${PROJECT_ROOT}/scripts/core"
    local incorrect_permissions=()

    for module in "${EXPECTED_CORE_MODULES[@]}"; do
        local module_path="${core_dir}/${module}"

        if [ -f "$module_path" ]; then
            if [ -x "$module_path" ]; then
                log_info "✓ Core module executable: $module"
            else
                log_error "✗ Core module not executable: $module"
                incorrect_permissions+=("$module")
            fi
        fi
    done

    if [ ${#incorrect_permissions[@]} -gt 0 ]; then
        log_error "Modules with incorrect permissions: ${incorrect_permissions[*]}"
        return 1
    fi

    log_info "All core modules have correct permissions"
    return 0
}

# Test core module syntax
test_core_module_syntax() {
    log_info "Testing core module syntax..."

    local core_dir="${PROJECT_ROOT}/scripts/core"
    local syntax_errors=()

    for module in "${EXPECTED_CORE_MODULES[@]}"; do
        local module_path="${core_dir}/${module}"

        if [ -f "$module_path" ]; then
            # Basic syntax check using bash -n
            if bash -n "$module_path" 2>/dev/null; then
                log_info "✓ Core module syntax OK: $module"
            else
                log_error "✗ Core module syntax error: $module"
                syntax_errors+=("$module")
            fi
        fi
    done

    if [ ${#syntax_errors[@]} -gt 0 ]; then
        log_error "Modules with syntax errors: ${syntax_errors[*]}"
        return 1
    fi

    log_info "All core modules have valid syntax"
    return 0
}

# Test core module dependencies
test_core_module_dependencies() {
    log_info "Testing core module dependencies..."

    local core_dir="${PROJECT_ROOT}/scripts/core"
    local dependency_issues=()

    # Test that config.sh doesn't depend on other modules
    if [ -f "${core_dir}/config.sh" ]; then
        if grep -q "source.*logging\.sh\|source.*init\.sh" "${core_dir}/config.sh"; then
            log_error "✗ config.sh has unexpected dependencies"
            dependency_issues+=("config-dependencies")
        else
            log_info "✓ config.sh has no unexpected dependencies"
        fi
    fi

    # Test that logging.sh only depends on config.sh
    if [ -f "${core_dir}/logging.sh" ]; then
        if grep -q "source.*init\.sh" "${core_dir}/logging.sh"; then
            log_error "✗ logging.sh depends on init.sh (circular dependency risk)"
            dependency_issues+=("logging-circular-dep")
        elif grep -q "source.*config\.sh" "${core_dir}/logging.sh"; then
            log_info "✓ logging.sh properly depends on config.sh"
        else
            log_warning "⚠ logging.sh doesn't depend on config.sh (may be intentional)"
        fi
    fi

    # Test that init.sh can depend on both config.sh and logging.sh
    if [ -f "${core_dir}/init.sh" ]; then
        local has_config_dep
        local has_logging_dep

        if grep -q "source.*config\.sh" "${core_dir}/init.sh"; then
            has_config_dep=true
        fi

        if grep -q "source.*logging\.sh" "${core_dir}/init.sh"; then
            has_logging_dep=true
        fi

        if [ "${has_config_dep:-false}" = true ] && [ "${has_logging_dep:-false}" = true ]; then
            log_info "✓ init.sh properly depends on both config.sh and logging.sh"
        elif [ "${has_config_dep:-false}" = true ]; then
            log_info "✓ init.sh depends on config.sh (logging.sh dependency optional)"
        else
            log_warning "⚠ init.sh doesn't depend on config.sh (may be intentional)"
        fi
    fi

    if [ ${#dependency_issues[@]} -gt 0 ]; then
        log_error "Dependency issues found: ${dependency_issues[*]}"
        return 1
    fi

    log_info "Core module dependencies are properly structured"
    return 0
}

# Test core module sourcing
test_core_module_sourcing() {
    log_info "Testing core module sourcing..."

    local core_dir="${PROJECT_ROOT}/scripts/core"
    local sourcing_errors=()

    # Create a test script that tries to source the modules
    local test_script="/tmp/test-core-sourcing.sh"

    cat > "$test_script" << 'EOF'
#!/bin/bash
set -euo pipefail

# Test sourcing core modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
CORE_DIR="${PROJECT_ROOT}/scripts/core"

echo "Testing core module sourcing..."

# Test sourcing config.sh
if [ -f "${CORE_DIR}/config.sh" ]; then
    source "${CORE_DIR}/config.sh"
    echo "✓ config.sh sourced successfully"
else
    echo "✗ config.sh not found"
    exit 1
fi

# Test sourcing logging.sh
if [ -f "${CORE_DIR}/logging.sh" ]; then
    source "${CORE_DIR}/logging.sh"
    echo "✓ logging.sh sourced successfully"
else
    echo "✗ logging.sh not found"
    exit 1
fi

# Test sourcing init.sh
if [ -f "${CORE_DIR}/init.sh" ]; then
    source "${CORE_DIR}/init.sh"
    echo "✓ init.sh sourced successfully"
else
    echo "✗ init.sh not found"
    exit 1
fi

echo "All core modules sourced successfully"
EOF

    chmod +x "$test_script"

    # Run the test script
    if bash "$test_script"; then
        log_info "✓ Core modules can be sourced successfully"
    else
        log_error "✗ Core module sourcing failed"
        sourcing_errors+=("sourcing-failed")
    fi

    # Cleanup
    rm -f "$test_script"

    if [ ${#sourcing_errors[@]} -gt 0 ]; then
        log_error "Sourcing errors: ${sourcing_errors[*]}"
        return 1
    fi

    return 0
}

# Main test execution
main() {
    log_info "Starting core module dependency test..."

    local test_start
    test_start=$(date +%s)
    local test_status=0

    # Run all test functions
    if ! test_core_module_existence; then
        test_status=1
    fi

    if ! test_core_module_permissions; then
        test_status=1
    fi

    if ! test_core_module_syntax; then
        test_status=1
    fi

    if ! test_core_module_dependencies; then
        test_status=1
    fi

    if ! test_core_module_sourcing; then
        test_status=1
    fi

    local test_end
    test_end=$(date +%s)
    local test_duration=$(( test_end - test_start ))

    if [ $test_status -eq 0 ]; then
        log_info "✅ Core module dependency test PASSED (${test_duration}s)"
        echo "Test Results: PASS"
    else
        log_error "❌ Core module dependency test FAILED (${test_duration}s)"
        echo "Test Results: FAIL"
        exit 1
    fi
}

# Execute main function
main "$@"
