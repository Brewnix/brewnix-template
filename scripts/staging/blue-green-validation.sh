#!/bin/bash
# scripts/staging/blue-green-validation.sh - Blue-Green deployment validation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Parse arguments
SITE_NAME=""
STAGING_ENVIRONMENT_ID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: $0 <site_name> <staging_environment_id>"
            echo "Validate blue-green deployment for a site"
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            exit 1
            ;;
        *)
            if [[ -z "$SITE_NAME" ]]; then
                SITE_NAME="$1"
            elif [[ -z "$STAGING_ENVIRONMENT_ID" ]]; then
                STAGING_ENVIRONMENT_ID="$1"
            else
                log_error "Too many arguments"
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$SITE_NAME" || -z "$STAGING_ENVIRONMENT_ID" ]]; then
    log_error "Site name and staging environment ID are required"
    echo "Usage: $0 <site_name> <staging_environment_id>"
    exit 1
fi

STAGING_DIR="$REPO_ROOT/staging/$STAGING_ENVIRONMENT_ID"
VALIDATION_LOG="$STAGING_DIR/logs/blue_green_validation_$(date +%Y%m%d_%H%M%S).log"

# Create validation log
exec > >(tee -a "$VALIDATION_LOG") 2>&1

log_info "Starting blue-green validation for site: $SITE_NAME (Environment: $STAGING_ENVIRONMENT_ID)"

# Check if staging environment exists
if [[ ! -d "$STAGING_DIR" ]]; then
    log_error "Staging environment not found: $STAGING_DIR"
    exit 1
fi

# Load staging metadata
if [[ ! -f "$STAGING_DIR/metadata.json" ]]; then
    log_error "Staging metadata not found: $STAGING_DIR/metadata.json"
    exit 1
fi

# Parse metadata
SITE_DISPLAY_NAME=$(python3 -c "import json; print(json.load(open('$STAGING_DIR/metadata.json'))['site_display_name'])")
ANSIBLE_INVENTORY=$(python3 -c "import json; print(json.load(open('$STAGING_DIR/metadata.json'))['ansible_inventory'])")

log_info "Validating blue-green deployment for $SITE_DISPLAY_NAME"

# Blue-Green Validation Steps
log_step "Step 1: Health Check Validation"

# Run health checks on staging environment
log_info "Running health checks..."
ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags health_check \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_health_checks.yml" || {
    log_error "Health checks failed"
    exit 1
}

log_info "✅ Health checks passed"

log_step "Step 2: Service Functionality Validation"

# Test core services
log_info "Testing core services..."
ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags service_test \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_services.yml" || {
    log_error "Service tests failed"
    exit 1
}

log_info "✅ Service functionality tests passed"

log_step "Step 3: Network Connectivity Validation"

# Test network connectivity
log_info "Testing network connectivity..."
ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags connectivity \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_network_connectivity.yml" || {
    log_error "Network connectivity tests failed"
    exit 1
}

log_info "✅ Network connectivity tests passed"

log_step "Step 4: Load Testing"

# Run basic load test
log_info "Running load tests..."
ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags load_test \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_load.yml" || {
    log_warn "Load tests had issues (non-critical)"
}

log_info "✅ Load tests completed"

log_step "Step 5: Data Consistency Validation"

# Check data consistency
log_info "Validating data consistency..."
ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags data_consistency \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_data_consistency.yml" || {
    log_error "Data consistency validation failed"
    exit 1
}

log_info "✅ Data consistency validation passed"

log_step "Step 6: Security Validation"

# Run security checks
log_info "Running security validation..."
ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags security \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_security.yml" || {
    log_error "Security validation failed"
    exit 1
}

log_info "✅ Security validation passed"

log_step "Step 7: Performance Metrics Collection"

# Collect performance metrics
log_info "Collecting performance metrics..."
ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags metrics \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/collect_metrics.yml" || {
    log_warn "Metrics collection had issues (non-critical)"
}

log_info "✅ Performance metrics collected"

# Create validation report
VALIDATION_REPORT="$STAGING_DIR/blue_green_validation_report.json"

cat > "$VALIDATION_REPORT" << EOF
{
  "validation_type": "blue_green",
  "site_name": "$SITE_NAME",
  "site_display_name": "$SITE_DISPLAY_NAME",
  "staging_environment_id": "$STAGING_ENVIRONMENT_ID",
  "validation_timestamp": "$(date -Iseconds)",
  "validation_status": "passed",
  "validation_steps": [
    {
      "step": "health_check",
      "status": "passed",
      "timestamp": "$(date -Iseconds)"
    },
    {
      "step": "service_test",
      "status": "passed",
      "timestamp": "$(date -Iseconds)"
    },
    {
      "step": "connectivity_test",
      "status": "passed",
      "timestamp": "$(date -Iseconds)"
    },
    {
      "step": "load_test",
      "status": "completed",
      "timestamp": "$(date -Iseconds)"
    },
    {
      "step": "data_consistency",
      "status": "passed",
      "timestamp": "$(date -Iseconds)"
    },
    {
      "step": "security_validation",
      "status": "passed",
      "timestamp": "$(date -Iseconds)"
    },
    {
      "step": "metrics_collection",
      "status": "completed",
      "timestamp": "$(date -Iseconds)"
    }
  ],
  "recommendations": [
    "Ready for traffic switching",
    "Monitor performance metrics for first 24 hours",
    "Prepare rollback plan"
  ],
  "validation_log": "$VALIDATION_LOG"
}
EOF

log_info "Blue-green validation completed successfully"
log_info "Validation report saved to: $VALIDATION_REPORT"
log_info "Validation log saved to: $VALIDATION_LOG"

# Mark as ready for traffic switching
echo "blue_green_ready" > "$STAGING_DIR/blue_green_ready"

echo ""
echo "=========================================="
echo "BLUE-GREEN VALIDATION SUMMARY"
echo "=========================================="
echo "Site: $SITE_DISPLAY_NAME ($SITE_NAME)"
echo "Environment: $STAGING_ENVIRONMENT_ID"
echo "Status: ✅ VALIDATION PASSED"
echo "Ready for: Traffic Switching"
echo "Report: $VALIDATION_REPORT"
echo "Log: $VALIDATION_LOG"
echo "=========================================="
