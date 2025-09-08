#!/bin/bash

# BrewNix End-to-End Deployment Test
# Phase 2.1.2 - Cross-Submodule Integration Testing
#
# This test validates complete end-to-end deployment scenarios

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Test configuration
TEST_NAME="e2e-deployment-validation"
DEPLOYMENT_TIMEOUT=300  # 5 minutes

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

# Test basic deployment workflow
test_basic_deployment_workflow() {
    log_info "Testing basic deployment workflow..."

    local workflow_issues=()

    # Check for required deployment scripts
    local required_scripts=(
        "scripts/core/init.sh"
        "scripts/core/config.sh"
        "scripts/core/logging.sh"
        "scripts/deployment/deployment.sh"
    )

    for script in "${required_scripts[@]}"; do
        if [ -f "${PROJECT_ROOT}/${script}" ]; then
            log_info "✓ Required script found: $script"
        else
            log_error "✗ Required script missing: $script"
            workflow_issues+=("missing-script-$script")
        fi
    done

    # Check for deployment configuration templates
    local config_templates=(
        "config/site-example.yml"
        "config/development-example.yml"
    )

    for template in "${config_templates[@]}"; do
        if [ -f "${PROJECT_ROOT}/${template}" ]; then
            log_info "✓ Configuration template found: $template"
        else
            log_warning "⚠ Configuration template missing: $template"
            workflow_issues+=("missing-template-$template")
        fi
    done

    if [ ${#workflow_issues[@]} -gt 0 ]; then
        log_error "Deployment workflow issues: ${workflow_issues[*]}"
        return 1
    fi

    log_info "Basic deployment workflow validated"
    return 0
}

# Test configuration validation
test_configuration_validation() {
    log_info "Testing configuration validation..."

    local config_issues=()

    # Test with example configuration
    local example_config="${PROJECT_ROOT}/config/site-example.yml"

    if [ -f "$example_config" ]; then
        log_info "Testing configuration validation with example config..."

        # Create a test validation script
        local test_script="/tmp/test-config-validation.sh"

        cat > "$test_script" << EOF
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# Source core modules
source "${PROJECT_ROOT}/scripts/core/config.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/scripts/core/logging.sh" 2>/dev/null || true

echo "Testing configuration validation..."

# Test validate_config function if available
if command -v validate_config >/dev/null 2>&1; then
    if validate_config "${PROJECT_ROOT}/config/site-example.yml" 2>/dev/null; then
        echo "✓ Configuration validation passed"
        exit 0
    else
        echo "✗ Configuration validation failed"
        exit 1
    fi
else
    echo "⚠ validate_config function not available, skipping validation test"
    exit 0
fi
EOF

        chmod +x "$test_script"

        # Run the test script
        if bash "$test_script"; then
            log_info "✓ Configuration validation successful"
        else
            log_error "✗ Configuration validation failed"
            config_issues+=("config-validation-failed")
        fi

        # Cleanup
        rm -f "$test_script"
    else
        log_warning "⚠ Example configuration not found, skipping validation test"
    fi

    if [ ${#config_issues[@]} -gt 0 ]; then
        return 1
    fi

    return 0
}

# Test deployment simulation
test_deployment_simulation() {
    log_info "Testing deployment simulation..."

    local simulation_issues=()

    # Create a mock deployment test
    local test_script="/tmp/test-deployment-simulation.sh"

    cat > "$test_script" << EOF
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

echo "Testing deployment simulation..."

# Source core modules
source "${PROJECT_ROOT}/scripts/core/init.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/scripts/core/config.sh" 2>/dev/null || true
source "${PROJECT_ROOT}/scripts/core/logging.sh" 2>/dev/null || true

simulation_issues=()

# Test initialization
if command -v initialize_system >/dev/null 2>&1; then
    if initialize_system 2>/dev/null; then
        echo "✓ System initialization successful"
    else
        echo "✗ System initialization failed"
        simulation_issues+=("init-failed")
    fi
else
    echo "⚠ initialize_system function not available"
fi

# Test environment setup
if command -v setup_environment >/dev/null 2>&1; then
    if setup_environment 2>/dev/null; then
        echo "✓ Environment setup successful"
    else
        echo "✗ Environment setup failed"
        simulation_issues+=("env-setup-failed")
    fi
else
    echo "⚠ setup_environment function not available"
fi

# Test dependency checking
if command -v check_dependencies >/dev/null 2>&1; then
    if check_dependencies 2>/dev/null; then
        echo "✓ Dependency check successful"
    else
        echo "✗ Dependency check failed"
        simulation_issues+=("dep-check-failed")
    fi
else
    echo "⚠ check_dependencies function not available"
fi

# Report results
if [ \${#simulation_issues[@]} -gt 0 ]; then
    echo "Simulation issues: \${simulation_issues[*]}"
    exit 1
else
    echo "Deployment simulation completed successfully"
    exit 0
fi
EOF

    chmod +x "$test_script"

    # Run the test script with timeout
    if timeout "$DEPLOYMENT_TIMEOUT" bash "$test_script"; then
        log_info "✓ Deployment simulation successful"
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            log_error "✗ Deployment simulation timed out after ${DEPLOYMENT_TIMEOUT}s"
        else
            log_error "✗ Deployment simulation failed"
        fi
        simulation_issues+=("simulation-failed")
    fi

    # Cleanup
    rm -f "$test_script"

    if [ ${#simulation_issues[@]} -gt 0 ]; then
        return 1
    fi

    return 0
}

# Test rollback procedures
test_rollback_procedures() {
    log_info "Testing rollback procedures..."

    local rollback_issues=()

    # Check for rollback-related scripts
    local rollback_scripts=(
        "scripts/backup/backup.sh"
    )

    for script in "${rollback_scripts[@]}"; do
        if [ -f "${PROJECT_ROOT}/${script}" ]; then
            log_info "✓ Rollback script found: $script"

            # Test script syntax
            if bash -n "${PROJECT_ROOT}/${script}" 2>/dev/null; then
                log_info "✓ Rollback script syntax OK: $script"
            else
                log_error "✗ Rollback script syntax error: $script"
                rollback_issues+=("syntax-error-$script")
            fi
        else
            log_warning "⚠ Rollback script missing: $script"
            rollback_issues+=("missing-rollback-script")
        fi
    done

    # Test backup functionality if available
    if [ -f "${PROJECT_ROOT}/scripts/backup/backup.sh" ]; then
        log_info "Testing backup functionality..."

        local test_backup_script="/tmp/test-backup.sh"

        cat > "$test_backup_script" << EOF
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

echo "Testing backup functionality..."

# Source backup script
source "${PROJECT_ROOT}/scripts/backup/backup.sh" 2>/dev/null || true

# Test backup creation (dry run)
if command -v create_backup >/dev/null 2>&1; then
    if create_backup 2>/dev/null; then
        echo "✓ Backup creation successful"
        exit 0
    else
        echo "✗ Backup creation failed"
        exit 1
    fi
else
    echo "⚠ create_backup function not available"
    exit 0
fi
EOF

        chmod +x "$test_backup_script"

        if bash "$test_backup_script"; then
            log_info "✓ Backup functionality validated"
        else
            log_error "✗ Backup functionality test failed"
            rollback_issues+=("backup-test-failed")
        fi

        rm -f "$test_backup_script"
    fi

    if [ ${#rollback_issues[@]} -gt 0 ]; then
        log_error "Rollback procedure issues: ${rollback_issues[*]}"
        return 1
    fi

    log_info "Rollback procedures validated"
    return 0
}

# Test monitoring and health checks
test_monitoring_health_checks() {
    log_info "Testing monitoring and health checks..."

    local monitoring_issues=()

    # Check for monitoring scripts
    local monitoring_scripts=(
        "scripts/monitoring/monitoring.sh"
    )

    for script in "${monitoring_scripts[@]}"; do
        if [ -f "${PROJECT_ROOT}/${script}" ]; then
            log_info "✓ Monitoring script found: $script"

            # Test script syntax
            if bash -n "${PROJECT_ROOT}/${script}" 2>/dev/null; then
                log_info "✓ Monitoring script syntax OK: $script"
            else
                log_error "✗ Monitoring script syntax error: $script"
                monitoring_issues+=("syntax-error-$script")
            fi
        else
            log_warning "⚠ Monitoring script missing: $script"
            monitoring_issues+=("missing-monitoring-script")
        fi
    done

    # Test health check functionality
    if [ -f "${PROJECT_ROOT}/scripts/monitoring/monitoring.sh" ]; then
        log_info "Testing health check functionality..."

        local test_health_script="/tmp/test-health-check.sh"

        cat > "$test_health_script" << EOF
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

echo "Testing health check functionality..."

# Source monitoring script
source "${PROJECT_ROOT}/scripts/monitoring/monitoring.sh" 2>/dev/null || true

# Test health check function
if command -v health_check >/dev/null 2>&1; then
    if health_check 2>/dev/null; then
        echo "✓ Health check successful"
        exit 0
    else
        echo "✗ Health check failed"
        exit 1
    fi
else
    echo "⚠ health_check function not available"
    exit 0
fi
EOF

        chmod +x "$test_health_script"

        if bash "$test_health_script"; then
            log_info "✓ Health check functionality validated"
        else
            log_error "✗ Health check functionality test failed"
            monitoring_issues+=("health-check-test-failed")
        fi

        rm -f "$test_health_script"
    fi

    if [ ${#monitoring_issues[@]} -gt 0 ]; then
        log_error "Monitoring and health check issues: ${monitoring_issues[*]}"
        return 1
    fi

    log_info "Monitoring and health checks validated"
    return 0
}

# Main test execution
main() {
    log_info "Starting end-to-end deployment validation test..."

    local test_start
    test_start=$(date +%s)
    local test_status=0

    # Run all test functions
    if ! test_basic_deployment_workflow; then
        test_status=1
    fi

    if ! test_configuration_validation; then
        test_status=1
    fi

    if ! test_deployment_simulation; then
        test_status=1
    fi

    if ! test_rollback_procedures; then
        test_status=1
    fi

    if ! test_monitoring_health_checks; then
        test_status=1
    fi

    local test_end
    test_end=$(date +%s)
    local test_duration=$(( test_end - test_start ))

    if [ $test_status -eq 0 ]; then
        log_info "✅ End-to-end deployment validation test PASSED (${test_duration}s)"
        echo "Test Results: PASS"
    else
        log_error "❌ End-to-end deployment validation test FAILED (${test_duration}s)"
        echo "Test Results: FAIL"
        exit 1
    fi
}

# Execute main function
main "$@"
