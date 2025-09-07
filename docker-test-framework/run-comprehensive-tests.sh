#!/bin/bash
# Brewnix Template - Comprehensive Test Runner
# Universal testing framework for all vendor deployments

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Test configuration
RUN_UNIT_TESTS=true
RUN_INTEGRATION_TESTS=true
RUN_DEPLOYMENT_TESTS=true
VERBOSE=false
CLEANUP_AFTER=true
PARALLEL_TESTS=false

# Test results
UNIT_TEST_RESULTS=""
INTEGRATION_TEST_RESULTS=""
DEPLOYMENT_TEST_RESULTS=""
OVERALL_SUCCESS=true

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --unit-only         Run only unit tests"
    echo "  --integration-only  Run only integration tests"
    echo "  --deployment-only   Run only deployment tests"
    echo "  --no-cleanup        Don't cleanup Docker containers after tests"
    echo "  --parallel          Run tests in parallel where possible"
    echo "  -v, --verbose       Verbose output"
    echo "  -h, --help          Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                  # Run all tests"
    echo "  $0 --unit-only     # Run only unit tests (fast)"
    echo "  $0 --deployment-only --verbose  # Run deployment tests with verbose output"
}

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

log_section() {
    echo -e "\n${PURPLE}=== $1 ===${NC}"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --unit-only)
            RUN_INTEGRATION_TESTS=false
            RUN_DEPLOYMENT_TESTS=false
            shift
            ;;
        --integration-only)
            RUN_UNIT_TESTS=false
            RUN_DEPLOYMENT_TESTS=false
            shift
            ;;
        --deployment-only)
            RUN_UNIT_TESTS=false
            RUN_INTEGRATION_TESTS=false
            shift
            ;;
        --no-cleanup)
            CLEANUP_AFTER=false
            shift
            ;;
        --parallel)
            PARALLEL_TESTS=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    log_section "Checking Prerequisites"

    local missing_tools=()

    # Check for required tools
    if ! command -v python3 >/dev/null 2>&1; then
        missing_tools+=("python3")
    fi

    if ! command -v docker >/dev/null 2>&1; then
        missing_tools+=("docker")
    fi

    if ! command -v docker-compose >/dev/null 2>&1; then
        missing_tools+=("docker-compose")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and try again"
        exit 1
    fi

    # Check Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi

    # Check Python packages
    if ! python3 -c "import yaml, requests" >/dev/null 2>&1; then
        log_warning "Some Python packages may be missing. Installing..."
        pip3 install pyyaml requests >/dev/null 2>&1 || true
    fi

    log_success "Prerequisites check passed"
}

# Setup test environment
setup_test_environment() {
    log_section "Setting Up Test Environment"

    cd "$SCRIPT_DIR"

    # Create test directories
    mkdir -p test-results logs reports

    # Clean up any existing test containers
    if [[ "$CLEANUP_AFTER" == "true" ]]; then
        log_info "Cleaning up existing test containers..."
        docker-compose down >/dev/null 2>&1 || true
    fi

    # Set environment variables for tests
    export TEST_PROJECT_ROOT="$PROJECT_ROOT"
    export TEST_SCRIPT_DIR="$SCRIPT_DIR"
    export TEST_VERBOSE="$VERBOSE"

    log_success "Test environment setup complete"
}

# Run unit tests
run_unit_tests() {
    log_section "Running Unit Tests"

    local unit_test_start
    unit_test_start=$(date +%s)
    local unit_test_success=true

    cd "$PROJECT_ROOT"

    # Test deployment script functionality
    log_info "Testing deployment script functionality..."
    if bash scripts/deploy-vendor.sh --help >/dev/null 2>&1; then
        log_success "Deployment script help works"
    else
        log_error "Deployment script help failed"
        unit_test_success=false
    fi

    # Test vendor type validation
    log_info "Testing vendor type validation..."
    local vendor_errors=0

    # Test valid vendors
    for vendor in nas k3s-cluster development security; do
        if ! bash scripts/deploy-vendor.sh "$vendor" non-existent.yml --check-only 2>&1 | grep -q "Site configuration not found"; then
            log_error "Vendor $vendor validation failed"
            ((vendor_errors++))
        fi
    done

    # Test invalid vendor
    if bash scripts/deploy-vendor.sh invalid-vendor test.yml --check-only 2>&1 | grep -q "Invalid vendor type"; then
        log_success "Invalid vendor type properly rejected"
    else
        log_error "Invalid vendor type not properly rejected"
        ((vendor_errors++))
    fi

    if [[ $vendor_errors -eq 0 ]]; then
        log_success "All vendor type validations passed"
    else
        log_error "Found $vendor_errors vendor validation issues"
        unit_test_success=false
    fi

    # Run YAML syntax validation
    log_info "Running YAML syntax validation..."
    local yaml_errors=0

    # Check site configurations
    if [[ -d "config/sites" ]]; then
        while IFS= read -r -d '' yaml_file; do
            if ! python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" 2>/dev/null; then
                log_error "YAML syntax error in: $yaml_file"
                ((yaml_errors++))
            fi
        done < <(find config/sites -name "*.yml" -print0)
    fi

    # Check vendor playbooks
    while IFS= read -r -d '' yaml_file; do
        if ! python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" 2>/dev/null; then
            log_error "YAML syntax error in: $yaml_file"
            ((yaml_errors++))
        fi
    done < <(find vendor -name "site.yml" -print0)

    if [[ $yaml_errors -eq 0 ]]; then
        log_success "All YAML files have valid syntax"
    else
        log_error "Found $yaml_errors YAML syntax errors"
        unit_test_success=false
    fi

    # Test ansible.cfg configurations
    log_info "Testing Ansible configuration files..."
    local ansible_errors=0

    for ansible_cfg in vendor/*/ansible/ansible.cfg; do
        if [[ -f "$ansible_cfg" ]]; then
            vendor=$(echo "$ansible_cfg" | cut -d'/' -f2)
            if grep -q "common/ansible/roles" "$ansible_cfg"; then
                log_success "$vendor ansible.cfg configured correctly"
            else
                log_error "$vendor ansible.cfg missing common framework path"
                ((ansible_errors++))
            fi
        fi
    done

    if [[ $ansible_errors -eq 0 ]]; then
        log_success "All Ansible configurations are correct"
    else
        log_error "Found $ansible_errors Ansible configuration issues"
        unit_test_success=false
    fi

    local unit_test_end
    unit_test_end=$(date +%s)
    local unit_test_duration=$((unit_test_end - unit_test_start))

    if [[ "$unit_test_success" == "true" ]]; then
        UNIT_TEST_RESULTS="✓ PASSED (${unit_test_duration}s)"
        log_success "Unit tests completed successfully in ${unit_test_duration}s"
    else
        UNIT_TEST_RESULTS="✗ FAILED (${unit_test_duration}s)"
        log_error "Unit tests failed in ${unit_test_duration}s"
        OVERALL_SUCCESS=false
    fi
}

# Create minimal mock services
create_mock_services() {
    log_info "Creating mock services for testing..."

    cd "$SCRIPT_DIR"

    # Create compose directory
    mkdir -p compose

    # Create minimal docker-compose
    cat > compose/docker-compose.minimal.yml << 'EOF'
version: '3.8'

services:
  proxmox-mock:
    build:
      context: ./proxmox-mock
      dockerfile: Dockerfile
    ports:
      - "8006:8006"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8006/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  test-runner:
    build:
      context: ./test-runner
      dockerfile: Dockerfile
    depends_on:
      - proxmox-mock
    volumes:
      - ../:/workspace
    working_dir: /workspace
EOF

    # Create Proxmox mock
    mkdir -p proxmox-mock
    cat > proxmox-mock/Dockerfile << 'EOF'
FROM python:3.11-slim

RUN pip install flask

COPY app.py /app/app.py

WORKDIR /app
EXPOSE 8006

CMD ["python", "app.py"]
EOF

    cat > proxmox-mock/app.py << 'EOF'
from flask import Flask, jsonify
import os

app = Flask(__name__)

@app.route('/health')
def health():
    return jsonify({"status": "healthy"})

@app.route('/api/version')
def version():
    return jsonify({"version": "mock-8.0"})

@app.route('/api/nodes')
def nodes():
    return jsonify({"data": [{"node": "pve1", "status": "online"}]})

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8006))
    app.run(host='0.0.0.0', port=port)
EOF

    # Create test runner
    mkdir -p test-runner
    cat > test-runner/Dockerfile << 'EOF'
FROM python:3.11-slim

RUN apt-get update && apt-get install -y \
    curl \
    bash \
    && rm -rf /var/lib/apt/lists/*

RUN pip install pyyaml requests pytest

CMD ["bash"]
EOF

    log_success "Mock services created"
}

# Start mock services
start_mock_services() {
    log_info "Starting mock services..."

    cd "$SCRIPT_DIR"

    # Create mock services if they don't exist
    if [[ ! -f "compose/docker-compose.minimal.yml" ]]; then
        create_mock_services
    fi

    # Start Docker Compose services
    if [[ "$VERBOSE" == "true" ]]; then
        docker-compose -f compose/docker-compose.minimal.yml up -d
    else
        docker-compose -f compose/docker-compose.minimal.yml up -d >/dev/null 2>&1
    fi

    # Wait for services to be ready
    log_info "Waiting for mock services to be ready..."
    local max_attempts=30
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        if curl -s http://localhost:8006/health >/dev/null 2>&1; then
            log_success "Mock services are ready"
            return 0
        fi

        ((attempt++))
        sleep 2
    done

    log_error "Mock services failed to start within timeout"
    docker-compose -f compose/docker-compose.minimal.yml logs
    return 1
}

# Run integration tests
run_integration_tests() {
    log_section "Running Integration Tests"

    local integration_test_start
    integration_test_start=$(date +%s)
    local integration_test_success=true

    cd "$SCRIPT_DIR"

    # Start mock services
    if ! start_mock_services; then
        INTEGRATION_TEST_RESULTS="✗ FAILED (mock services)"
        OVERALL_SUCCESS=false
        return 1
    fi

    # Test mock service connectivity
    log_info "Testing mock service connectivity..."
    if curl -s http://localhost:8006/health | grep -q "healthy"; then
        log_success "Mock Proxmox service is responding"
    else
        log_error "Mock Proxmox service not responding"
        integration_test_success=false
    fi

    # Test API endpoints
    log_info "Testing API endpoints..."
    if curl -s http://localhost:8006/api/version | grep -q "mock"; then
        log_success "API version endpoint working"
    else
        log_error "API version endpoint failed"
        integration_test_success=false
    fi

    # Test Docker Compose validation
    log_info "Validating Docker Compose configurations..."
    if docker-compose -f compose/docker-compose.minimal.yml config >/dev/null 2>&1; then
        log_success "Docker Compose configuration is valid"
    else
        log_error "Docker Compose configuration validation failed"
        integration_test_success=false
    fi

    # Test common framework role accessibility
    log_info "Testing common framework role accessibility..."
    local role_errors=0

    for vendor_dir in "$PROJECT_ROOT"/vendor/*/ansible; do
        if [[ -d "$vendor_dir" ]]; then
            vendor=$(basename "$(dirname "$vendor_dir")")
            cd "$vendor_dir"
            
            if [[ -f "ansible.cfg" ]]; then
                if ansible-config dump 2>/dev/null | grep -q "common/ansible/roles"; then
                    log_success "$vendor can access common framework roles"
                else
                    log_error "$vendor cannot access common framework roles"
                    ((role_errors++))
                fi
            fi
            
            cd - >/dev/null
        fi
    done

    if [[ $role_errors -eq 0 ]]; then
        log_success "All vendors can access common framework"
    else
        log_error "Found $role_errors role accessibility issues"
        integration_test_success=false
    fi

    local integration_test_end
    integration_test_end=$(date +%s)
    local integration_test_duration=$((integration_test_end - integration_test_start))

    if [[ "$integration_test_success" == "true" ]]; then
        INTEGRATION_TEST_RESULTS="✓ PASSED (${integration_test_duration}s)"
        log_success "Integration tests completed successfully in ${integration_test_duration}s"
    else
        INTEGRATION_TEST_RESULTS="✗ FAILED (${integration_test_duration}s)"
        log_error "Integration tests failed in ${integration_test_duration}s"
        OVERALL_SUCCESS=false
    fi
}

# Run deployment tests
run_deployment_tests() {
    log_section "Running Deployment Tests"

    local deployment_test_start
    deployment_test_start=$(date +%s)
    local deployment_test_success=true

    cd "$PROJECT_ROOT"

    # Test each vendor deployment in dry-run mode
    log_info "Testing vendor deployments in dry-run mode..."
    local deployment_errors=0

    for site_config in config/sites/*/; do
        if [[ -d "$site_config" ]]; then
            site_name=$(basename "$site_config")
            local config_files=("$site_config"/*.yml)
            
            if [[ -f "${config_files[0]}" ]]; then
                vendor_type=""
                case "$site_name" in
                    *nas*) vendor_type="nas" ;;
                    *k3s*) vendor_type="k3s-cluster" ;;
                    *dev*) vendor_type="development" ;;
                    *security*) vendor_type="security" ;;
                esac
                
                if [[ -n "$vendor_type" ]]; then
                    log_info "Testing $vendor_type deployment with $site_name"
                    relative_path="${config_files[0]#config/sites/}"
                    
                    if bash scripts/deploy-vendor.sh "$vendor_type" "$relative_path" --dry-run 2>&1 | tee "logs/${vendor_type}-deployment-test.log"; then
                        log_success "$vendor_type deployment test passed"
                    else
                        log_error "$vendor_type deployment test failed"
                        ((deployment_errors++))
                    fi
                fi
            fi
        fi
    done

    if [[ $deployment_errors -eq 0 ]]; then
        log_success "All deployment tests passed"
    else
        log_error "Found $deployment_errors deployment test failures"
        deployment_test_success=false
    fi

    # Test USB bootstrap functionality
    log_info "Testing USB bootstrap functionality..."
    if [[ -f "bootstrap/usb-bootstrap.sh" ]]; then
        if bash -n bootstrap/usb-bootstrap.sh; then
            log_success "USB bootstrap script syntax is valid"
        else
            log_error "USB bootstrap script has syntax errors"
            deployment_test_success=false
        fi
    else
        log_warning "USB bootstrap script not found"
    fi

    local deployment_test_end
    deployment_test_end=$(date +%s)
    local deployment_test_duration=$((deployment_test_end - deployment_test_start))

    if [[ "$deployment_test_success" == "true" ]]; then
        DEPLOYMENT_TEST_RESULTS="✓ PASSED (${deployment_test_duration}s)"
        log_success "Deployment tests completed successfully in ${deployment_test_duration}s"
    else
        DEPLOYMENT_TEST_RESULTS="✗ FAILED (${deployment_test_duration}s)"
        log_error "Deployment tests failed in ${deployment_test_duration}s"
        OVERALL_SUCCESS=false
    fi
}

# Cleanup
cleanup() {
    if [[ "$CLEANUP_AFTER" == "true" ]]; then
        log_section "Cleaning Up"
        cd "$SCRIPT_DIR"

        log_info "Stopping Docker containers..."
        docker-compose -f compose/docker-compose.minimal.yml down >/dev/null 2>&1 || true

        log_success "Cleanup completed"
    fi
}

# Generate test report
generate_report() {
    log_section "Test Results Summary"

    local report_file
    report_file="$SCRIPT_DIR/reports/test-report-$(date +%Y%m%d-%H%M%S).json"
    mkdir -p "$(dirname "$report_file")"

    # Create JSON report
    cat > "$report_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "overall_success": $OVERALL_SUCCESS,
  "test_results": {
    "unit_tests": {
      "enabled": $RUN_UNIT_TESTS,
      "result": "$UNIT_TEST_RESULTS"
    },
    "integration_tests": {
      "enabled": $RUN_INTEGRATION_TESTS,
      "result": "$INTEGRATION_TEST_RESULTS"
    },
    "deployment_tests": {
      "enabled": $RUN_DEPLOYMENT_TESTS,
      "result": "$DEPLOYMENT_TEST_RESULTS"
    }
  },
  "configuration": {
    "verbose": $VERBOSE,
    "parallel": $PARALLEL_TESTS,
    "cleanup": $CLEANUP_AFTER
  }
}
EOF

    # Display summary
    echo -e "\n${BLUE}╔══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         BREWNIX TEST SUMMARY         ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════╣${NC}"

    if [[ "$RUN_UNIT_TESTS" == "true" ]]; then
        echo -e "${BLUE}║${NC} Unit Tests:        $UNIT_TEST_RESULTS"
    fi

    if [[ "$RUN_INTEGRATION_TESTS" == "true" ]]; then
        echo -e "${BLUE}║${NC} Integration Tests: $INTEGRATION_TEST_RESULTS"
    fi

    if [[ "$RUN_DEPLOYMENT_TESTS" == "true" ]]; then
        echo -e "${BLUE}║${NC} Deployment Tests:  $DEPLOYMENT_TEST_RESULTS"
    fi

    echo -e "${BLUE}╠══════════════════════════════════════╣${NC}"

    if [[ "$OVERALL_SUCCESS" == "true" ]]; then
        echo -e "${BLUE}║${NC} ${GREEN}Overall Result: ✓ ALL TESTS PASSED${NC}   ${BLUE}║${NC}"
    else
        echo -e "${BLUE}║${NC} ${RED}Overall Result: ✗ SOME TESTS FAILED${NC}  ${BLUE}║${NC}"
    fi

    echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"

    log_info "Detailed report saved to: $report_file"
}

# Main execution
main() {
    local start_time
    start_time=$(date +%s)

    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                Brewnix Template Test Suite                  ║"
    echo "║              Universal Infrastructure Testing               ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    # Setup
    check_prerequisites
    setup_test_environment

    # Run tests based on configuration
    if [[ "$RUN_UNIT_TESTS" == "true" ]]; then
        run_unit_tests
    fi

    if [[ "$RUN_INTEGRATION_TESTS" == "true" ]]; then
        run_integration_tests
    fi

    if [[ "$RUN_DEPLOYMENT_TESTS" == "true" ]]; then
        run_deployment_tests
    fi

    # Cleanup and report
    cleanup
    generate_report

    local end_time
    end_time=$(date +%s)
    local total_duration=$((end_time - start_time))

    log_info "Total test execution time: ${total_duration}s"

    # Exit with appropriate code
    if [[ "$OVERALL_SUCCESS" == "true" ]]; then
        exit 0
    else
        exit 1
    fi
}

# Trap cleanup on exit
trap cleanup EXIT

# Run main function
main "$@"
