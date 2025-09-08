#!/bin/bash

# BrewNix Local Testing Script
# This script duplicates CI/CD checks for local debugging before submission

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Lint checking function (similar to CI)
run_lint_checks() {
    log_info "Running lint checks..."

    # Check shell scripts with shellcheck
    if command_exists shellcheck; then
        log_info "Checking shell scripts with shellcheck..."
        find . -name "*.sh" -type f -exec shellcheck {} \; 2>/dev/null || log_warning "Shellcheck found issues"
    else
        log_warning "shellcheck not installed - skipping shell script linting"
    fi

    # Check YAML files
    if command_exists yamllint; then
        log_info "Checking YAML files..."
        find . \( -name "*.yml" -o -name "*.yaml" \) -print0 | xargs -0 yamllint 2>/dev/null || log_warning "YAML linting found issues"
    else
        log_warning "yamllint not installed - skipping YAML validation"
    fi

    log_success "Lint checks completed"
}

# Security scanning function
run_security_checks() {
    log_info "Running security checks..."

    # Check for potential secrets
    if grep -r "password\|secret\|key\|token" --include="*.sh" --include="*.yml" --include="*.yaml" . | grep -v "example\|template\|test\|README"; then
        log_warning "Potential secrets found - please review"
    else
        log_success "No obvious secrets detected"
    fi

    # Check file permissions
    log_info "Checking file permissions..."
    find . -name "*.sh" -type f ! -executable | while read -r file; do
        log_warning "Shell script not executable: $file"
    done

    log_success "Security checks completed"
}

# Sanity checks function
run_sanity_checks() {
    log_info "Running sanity checks..."

    # Check required files
    required_files=("README.md" "LICENSE")
    for file in "${required_files[@]}"; do
        if [ -f "$file" ]; then
            log_success "Found required file: $file"
        else
            log_error "Missing required file: $file"
        fi
    done

    # Check directory structure
    required_dirs=("scripts" "config" "docs")
    for dir in "${required_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log_success "Found required directory: $dir"
        else
            log_warning "Missing recommended directory: $dir"
        fi
    done

    log_success "Sanity checks completed"
}

# Documentation validation
run_docs_validation() {
    log_info "Running documentation validation..."

    # Check markdown files
    if command_exists markdownlint; then
        log_info "Checking markdown files..."
        find . -name "*.md" -type f -exec markdownlint {} \; 2>/dev/null || log_warning "Markdown linting found issues"
    else
        log_warning "markdownlint not installed - skipping markdown validation"
    fi

    log_success "Documentation validation completed"
}

# Dependency analysis
run_dependency_checks() {
    log_info "Running dependency checks..."

    # Check for external dependencies in scripts
    log_info "Analyzing script dependencies..."
    find . -name "*.sh" -type f -exec grep -l "curl\|wget\|git\|docker\|ansible" {} \; | while read -r file; do
        log_info "Script uses external tools: $file"
    done

    log_success "Dependency checks completed"
}

# Container testing (similar to CI)
run_container_tests() {
    log_info "Running container tests..."

    if command_exists docker; then
        if [ -f "Dockerfile" ] || [ -f "docker/Dockerfile" ]; then
            log_info "Dockerfile found - testing build..."
            dockerfile="Dockerfile"
            [ -f "docker/Dockerfile" ] && dockerfile="docker/Dockerfile"

            # Test docker build (dry run)
            if docker build --dry-run -f "$dockerfile" . 2>/dev/null; then
                log_success "Docker build syntax is valid"
            else
                log_warning "Docker build syntax issues found"
            fi
        else
            log_info "No Dockerfile found - creating basic test container..."
            echo "FROM ubuntu:22.04" > Dockerfile.test
            echo "RUN apt-get update && apt-get install -y bash curl git" >> Dockerfile.test
            log_success "Basic test Dockerfile created"
        fi
    else
        log_warning "Docker not installed - skipping container tests"
    fi

    log_success "Container tests completed"
}

# Mock deployment testing
run_mock_deployment() {
    log_info "Running mock deployment tests..."

    # Test configuration validation
    if [ -f "./validate-config.sh" ]; then
        log_info "Running configuration validation..."
        chmod +x ./validate-config.sh
        if ./validate-config.sh; then
            log_success "Configuration validation passed"
        else
            log_warning "Configuration validation failed"
        fi
    else
        log_warning "validate-config.sh not found"
    fi

    # Test deployment scripts
    if [ -f "scripts/deploy-site.sh" ]; then
        log_info "Testing deployment script syntax..."
        bash -n scripts/deploy-site.sh && log_success "Deployment script syntax OK" || log_error "Deployment script syntax error"
    fi

    log_success "Mock deployment tests completed"
}

# Integration testing
run_integration_tests() {
    log_info "Running integration tests..."

    # Test core module integration
    core_modules=("scripts/core/init.sh" "scripts/core/config.sh" "scripts/core/logging.sh")
    for module in "${core_modules[@]}"; do
        if [ -f "$module" ]; then
            log_success "Core module found: $module"
            # Test module loading
            if bash -c "source $module" 2>/dev/null; then
                log_success "Module loads successfully: $module"
            else
                log_warning "Module loading issues: $module"
            fi
        else
            log_warning "Core module missing: $module"
        fi
    done

    log_success "Integration tests completed"
}

# Performance testing
run_performance_tests() {
    log_info "Running performance tests..."

    start_time=$(date +%s)

    # Test script execution time
    if [ -f "./local-test.sh" ]; then
        log_info "Measuring script execution time..."
        timeout 300 bash ./local-test.sh >/dev/null 2>&1 || true
    fi

    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log_info "Test execution time: ${duration} seconds"

    # Basic resource check
    log_info "System resources:"
    echo "Memory usage:"
    free -h | head -2
    echo "Disk usage:"
    df -h . | tail -1

    log_success "Performance tests completed"
}

# Main execution
main() {
    log_info "Starting BrewNix local testing suite..."
    log_info "Project root: $PROJECT_ROOT"
    cd "$PROJECT_ROOT"

    # Run all test suites
    run_lint_checks
    echo
    run_security_checks
    echo
    run_sanity_checks
    echo
    run_docs_validation
    echo
    run_dependency_checks
    echo
    run_container_tests
    echo
    run_mock_deployment
    echo
    run_integration_tests
    echo
    run_performance_tests

    echo
    log_success "Local testing suite completed!"
    log_info "Review any warnings or errors above before submitting your changes."
    log_info "For CI/CD pipeline testing, push to the 'test' branch."
}

# Run main function
main "$@"
