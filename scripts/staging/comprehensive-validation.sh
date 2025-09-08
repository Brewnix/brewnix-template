#!/bin/bash
# scripts/staging/comprehensive-validation.sh - Comprehensive staging validation

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
STAGING_ENVIRONMENT_ID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: $0 <staging_environment_id>"
            echo "Run comprehensive staging validation"
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            exit 1
            ;;
        *)
            if [[ -z "$STAGING_ENVIRONMENT_ID" ]]; then
                STAGING_ENVIRONMENT_ID="$1"
            else
                log_error "Too many arguments"
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$STAGING_ENVIRONMENT_ID" ]]; then
    log_error "Staging environment ID is required"
    echo "Usage: $0 <staging_environment_id>"
    exit 1
fi

STAGING_DIR="$REPO_ROOT/staging/$STAGING_ENVIRONMENT_ID"
VALIDATION_LOG="$STAGING_DIR/logs/comprehensive_validation_$(date +%Y%m%d_%H%M%S).log"

# Create validation log
exec > >(tee -a "$VALIDATION_LOG") 2>&1

log_info "Starting comprehensive validation for $STAGING_ENVIRONMENT_ID"

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
SITE_NAME=$(python3 -c "import json; print(json.load(open('$STAGING_DIR/metadata.json'))['site_name'])")
SITE_DISPLAY_NAME=$(python3 -c "import json; print(json.load(open('$STAGING_DIR/metadata.json'))['site_display_name'])")
ANSIBLE_INVENTORY=$(python3 -c "import json; print(json.load(open('$STAGING_DIR/metadata.json'))['ansible_inventory'])")

log_info "Running comprehensive validation for $SITE_DISPLAY_NAME"

# Initialize validation results
VALIDATION_RESULTS="$STAGING_DIR/comprehensive_validation_results.json"
cat > "$VALIDATION_RESULTS" << EOF
{
  "validation_type": "comprehensive_staging",
  "site_name": "$SITE_NAME",
  "site_display_name": "$SITE_DISPLAY_NAME",
  "staging_environment_id": "$STAGING_ENVIRONMENT_ID",
  "validation_start": "$(date -Iseconds)",
  "validation_steps": []
}
EOF

# Validation Step 1: Infrastructure Validation
log_step "Step 1: Infrastructure Validation"

INFRASTRUCTURE_PASSED=true
INFRASTRUCTURE_CHECKS=()

# Check Proxmox connectivity
log_info "Checking Proxmox connectivity..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags connectivity \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_network_connectivity.yml" >/dev/null 2>&1; then
    INFRASTRUCTURE_CHECKS+=("{\"check\": \"proxmox_connectivity\", \"status\": \"passed\", \"message\": \"Proxmox host is reachable\"}")
    log_info "✅ Proxmox connectivity check passed"
else
    INFRASTRUCTURE_CHECKS+=("{\"check\": \"proxmox_connectivity\", \"status\": \"failed\", \"message\": \"Cannot connect to Proxmox host\"}")
    INFRASTRUCTURE_PASSED=false
    log_error "❌ Proxmox connectivity check failed"
fi

# Check VM/container status
log_info "Checking VM/container status..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags vm_status \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_vm_status.yml" >/dev/null 2>&1; then
    INFRASTRUCTURE_CHECKS+=("{\"check\": \"vm_container_status\", \"status\": \"passed\", \"message\": \"All VMs/containers are running\"}")
    log_info "✅ VM/container status check passed"
else
    INFRASTRUCTURE_CHECKS+=("{\"check\": \"vm_container_status\", \"status\": \"failed\", \"message\": \"Some VMs/containers are not running\"}")
    INFRASTRUCTURE_PASSED=false
    log_error "❌ VM/container status check failed"
fi

# Check network configuration
log_info "Checking network configuration..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags network_config \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_network_config.yml" >/dev/null 2>&1; then
    INFRASTRUCTURE_CHECKS+=("{\"check\": \"network_configuration\", \"status\": \"passed\", \"message\": \"Network configuration is correct\"}")
    log_info "✅ Network configuration check passed"
else
    INFRASTRUCTURE_CHECKS+=("{\"check\": \"network_configuration\", \"status\": \"failed\", \"message\": \"Network configuration has issues\"}")
    INFRASTRUCTURE_PASSED=false
    log_error "❌ Network configuration check failed"
fi

# Validation Step 2: Application Validation
log_step "Step 2: Application Validation"

APPLICATION_PASSED=true
APPLICATION_CHECKS=()

# Check service health
log_info "Checking service health..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags service_health \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_service_health.yml" >/dev/null 2>&1; then
    APPLICATION_CHECKS+=("{\"check\": \"service_health\", \"status\": \"passed\", \"message\": \"All services are healthy\"}")
    log_info "✅ Service health check passed"
else
    APPLICATION_CHECKS+=("{\"check\": \"service_health\", \"status\": \"failed\", \"message\": \"Some services are unhealthy\"}")
    APPLICATION_PASSED=false
    log_error "❌ Service health check failed"
fi

# Check application endpoints
log_info "Checking application endpoints..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags app_endpoints \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_app_endpoints.yml" >/dev/null 2>&1; then
    APPLICATION_CHECKS+=("{\"check\": \"application_endpoints\", \"status\": \"passed\", \"message\": \"All application endpoints are responding\"}")
    log_info "✅ Application endpoints check passed"
else
    APPLICATION_CHECKS+=("{\"check\": \"application_endpoints\", \"status\": \"failed\", \"message\": \"Some application endpoints are not responding\"}")
    APPLICATION_PASSED=false
    log_error "❌ Application endpoints check failed"
fi

# Check database connectivity
log_info "Checking database connectivity..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags database \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_database.yml" >/dev/null 2>&1; then
    APPLICATION_CHECKS+=("{\"check\": \"database_connectivity\", \"status\": \"passed\", \"message\": \"Database connectivity is working\"}")
    log_info "✅ Database connectivity check passed"
else
    APPLICATION_CHECKS+=("{\"check\": \"database_connectivity\", \"status\": \"warning\", \"message\": \"Database connectivity check failed\"}")
    log_warn "⚠️ Database connectivity check failed"
fi

# Validation Step 3: Security Validation
log_step "Step 3: Security Validation"

SECURITY_PASSED=true
SECURITY_CHECKS=()

# Check firewall rules
log_info "Checking firewall rules..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags firewall \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_firewall.yml" >/dev/null 2>&1; then
    SECURITY_CHECKS+=("{\"check\": \"firewall_rules\", \"status\": \"passed\", \"message\": \"Firewall rules are correctly configured\"}")
    log_info "✅ Firewall rules check passed"
else
    SECURITY_CHECKS+=("{\"check\": \"firewall_rules\", \"status\": \"failed\", \"message\": \"Firewall rules have issues\"}")
    SECURITY_PASSED=false
    log_error "❌ Firewall rules check failed"
fi

# Check SSL/TLS configuration
log_info "Checking SSL/TLS configuration..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags ssl_tls \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_ssl_tls.yml" >/dev/null 2>&1; then
    SECURITY_CHECKS+=("{\"check\": \"ssl_tls_config\", \"status\": \"passed\", \"message\": \"SSL/TLS configuration is correct\"}")
    log_info "✅ SSL/TLS configuration check passed"
else
    SECURITY_CHECKS+=("{\"check\": \"ssl_tls_config\", \"status\": \"failed\", \"message\": \"SSL/TLS configuration has issues\"}")
    SECURITY_PASSED=false
    log_error "❌ SSL/TLS configuration check failed"
fi

# Check security hardening
log_info "Checking security hardening..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags security_hardening \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_security_hardening.yml" >/dev/null 2>&1; then
    SECURITY_CHECKS+=("{\"check\": \"security_hardening\", \"status\": \"passed\", \"message\": \"Security hardening is applied\"}")
    log_info "✅ Security hardening check passed"
else
    SECURITY_CHECKS+=("{\"check\": \"security_hardening\", \"status\": \"warning\", \"message\": \"Security hardening check failed\"}")
    log_warn "⚠️ Security hardening check failed"
fi

# Validation Step 4: Performance Validation
log_step "Step 4: Performance Validation"

PERFORMANCE_PASSED=true
PERFORMANCE_CHECKS=()

# Check system resources
log_info "Checking system resources..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags system_resources \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_system_resources.yml" >/dev/null 2>&1; then
    PERFORMANCE_CHECKS+=("{\"check\": \"system_resources\", \"status\": \"passed\", \"message\": \"System resources are within acceptable limits\"}")
    log_info "✅ System resources check passed"
else
    PERFORMANCE_CHECKS+=("{\"check\": \"system_resources\", \"status\": \"warning\", \"message\": \"System resources are high\"}")
    log_warn "⚠️ System resources check failed"
fi

# Check application performance
log_info "Checking application performance..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags app_performance \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_app_performance.yml" >/dev/null 2>&1; then
    PERFORMANCE_CHECKS+=("{\"check\": \"application_performance\", \"status\": \"passed\", \"message\": \"Application performance is acceptable\"}")
    log_info "✅ Application performance check passed"
else
    PERFORMANCE_CHECKS+=("{\"check\": \"application_performance\", \"status\": \"failed\", \"message\": \"Application performance issues detected\"}")
    PERFORMANCE_PASSED=false
    log_error "❌ Application performance check failed"
fi

# Validation Step 5: Integration Validation
log_step "Step 5: Integration Validation"

INTEGRATION_PASSED=true
INTEGRATION_CHECKS=()

# Check inter-service communication
log_info "Checking inter-service communication..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags inter_service \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_inter_service.yml" >/dev/null 2>&1; then
    INTEGRATION_CHECKS+=("{\"check\": \"inter_service_communication\", \"status\": \"passed\", \"message\": \"Inter-service communication is working\"}")
    log_info "✅ Inter-service communication check passed"
else
    INTEGRATION_CHECKS+=("{\"check\": \"inter_service_communication\", \"status\": \"failed\", \"message\": \"Inter-service communication has issues\"}")
    INTEGRATION_PASSED=false
    log_error "❌ Inter-service communication check failed"
fi

# Check external integrations
log_info "Checking external integrations..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags external_integrations \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_external_integrations.yml" >/dev/null 2>&1; then
    INTEGRATION_CHECKS+=("{\"check\": \"external_integrations\", \"status\": \"passed\", \"message\": \"External integrations are working\"}")
    log_info "✅ External integrations check passed"
else
    INTEGRATION_CHECKS+=("{\"check\": \"external_integrations\", \"status\": \"warning\", \"message\": \"Some external integrations have issues\"}")
    log_warn "⚠️ External integrations check failed"
fi

# Calculate overall validation result
log_step "Calculating overall validation result"

OVERALL_PASSED=true
if [[ "$INFRASTRUCTURE_PASSED" != "true" || "$APPLICATION_PASSED" != "true" || "$SECURITY_PASSED" != "true" || "$PERFORMANCE_PASSED" != "true" || "$INTEGRATION_PASSED" != "true" ]]; then
    OVERALL_PASSED=false
fi

# Count total checks and passed checks
ALL_CHECKS_JSON=$(printf '%s\n' "${INFRASTRUCTURE_CHECKS[@]}" "${APPLICATION_CHECKS[@]}" "${SECURITY_CHECKS[@]}" "${PERFORMANCE_CHECKS[@]}" "${INTEGRATION_CHECKS[@]}" | jq -s '.')
TOTAL_CHECKS=$(echo "$ALL_CHECKS_JSON" | jq length)
PASSED_CHECKS=$(echo "$ALL_CHECKS_JSON" | jq '[.[] | select(.status == "passed")] | length')
SUCCESS_RATE=$(( PASSED_CHECKS * 100 / TOTAL_CHECKS ))

# Update validation results
python3 -c "
import json
import sys
data = json.load(open('$VALIDATION_RESULTS'))

# Convert bash arrays to Python lists
infra_checks = [json.loads(check) for check in sys.argv[1].split('|') if check]
app_checks = [json.loads(check) for check in sys.argv[2].split('|') if check]
sec_checks = [json.loads(check) for check in sys.argv[3].split('|') if check]
perf_checks = [json.loads(check) for check in sys.argv[4].split('|') if check]
int_checks = [json.loads(check) for check in sys.argv[5].split('|') if check]

data['validation_end'] = '$(date -Iseconds)'
data['infrastructure_validation'] = {'passed': $INFRASTRUCTURE_PASSED, 'checks': infra_checks}
data['application_validation'] = {'passed': $APPLICATION_PASSED, 'checks': app_checks}
data['security_validation'] = {'passed': $SECURITY_PASSED, 'checks': sec_checks}
data['performance_validation'] = {'passed': $PERFORMANCE_PASSED, 'checks': perf_checks}
data['integration_validation'] = {'passed': $INTEGRATION_PASSED, 'checks': int_checks}
data['overall_result'] = {'passed': $OVERALL_PASSED, 'total_checks': $TOTAL_CHECKS, 'passed_checks': $PASSED_CHECKS, 'success_rate': $SUCCESS_RATE}
json.dump(data, open('$VALIDATION_RESULTS', 'w'), indent=2)
" "$(printf '%s|' "${INFRASTRUCTURE_CHECKS[@]}")" "$(printf '%s|' "${APPLICATION_CHECKS[@]}")" "$(printf '%s|' "${SECURITY_CHECKS[@]}")" "$(printf '%s|' "${PERFORMANCE_CHECKS[@]}")" "$(printf '%s|' "${INTEGRATION_CHECKS[@]}")"

log_info "Comprehensive validation completed"
log_info "Overall result: $([ "$OVERALL_PASSED" = "true" ] && echo "PASSED" || echo "FAILED")"
log_info "Success rate: ${SUCCESS_RATE}% ($PASSED_CHECKS/$TOTAL_CHECKS checks passed)"

# Create validation summary
VALIDATION_SUMMARY="$STAGING_DIR/comprehensive_validation_summary.json"

cat > "$VALIDATION_SUMMARY" << EOF
{
  "validation_summary": {
    "site_name": "$SITE_NAME",
    "site_display_name": "$SITE_DISPLAY_NAME",
    "staging_environment_id": "$STAGING_ENVIRONMENT_ID",
    "validation_timestamp": "$(date -Iseconds)",
    "overall_status": "$( [ "$OVERALL_PASSED" = "true" ] && echo "passed" || echo "failed" )",
    "success_rate": $SUCCESS_RATE,
    "total_checks": $TOTAL_CHECKS,
    "passed_checks": $PASSED_CHECKS,
    "categories": {
      "infrastructure": "$( [ "$INFRASTRUCTURE_PASSED" = "true" ] && echo "passed" || echo "failed" )",
      "application": "$( [ "$APPLICATION_PASSED" = "true" ] && echo "passed" || echo "failed" )",
      "security": "$( [ "$SECURITY_PASSED" = "true" ] && echo "passed" || echo "failed" )",
      "performance": "$( [ "$PERFORMANCE_PASSED" = "true" ] && echo "passed" || echo "failed" )",
      "integration": "$( [ "$INTEGRATION_PASSED" = "true" ] && echo "passed" || echo "failed" )"
    },
    "recommendations": [
      $(if [ $SUCCESS_RATE -ge 95 ]; then
          echo '"Environment validation successful - ready for production"'
      elif [ $SUCCESS_RATE -ge 85 ]; then
          echo '"Environment validation mostly successful - minor issues to address"'
      elif [ $SUCCESS_RATE -ge 75 ]; then
          echo '"Environment validation has issues - address critical problems before proceeding"'
      else
          echo '"Environment validation failed - do not proceed with production deployment"'
      fi)
    ]
  },
  "validation_log": "$VALIDATION_LOG",
  "validation_results": "$VALIDATION_RESULTS"
}
EOF

log_info "Comprehensive validation summary saved to: $VALIDATION_SUMMARY"
log_info "Comprehensive validation results saved to: $VALIDATION_RESULTS"
log_info "Comprehensive validation log saved to: $VALIDATION_LOG"

echo ""
echo "=========================================="
echo "COMPREHENSIVE VALIDATION SUMMARY"
echo "=========================================="
echo "Site: $SITE_DISPLAY_NAME ($SITE_NAME)"
echo "Environment: $STAGING_ENVIRONMENT_ID"
echo "Overall Status: $([ "$OVERALL_PASSED" = "true" ] && echo "✅ PASSED" || echo "❌ FAILED")"
echo "Success Rate: ${SUCCESS_RATE}%"
echo "Checks: $PASSED_CHECKS/$TOTAL_CHECKS passed"
echo ""
echo "Category Results:"
echo "  Infrastructure: $([ "$INFRASTRUCTURE_PASSED" = "true" ] && echo "✅ PASSED" || echo "❌ FAILED")"
echo "  Application: $([ "$APPLICATION_PASSED" = "true" ] && echo "✅ PASSED" || echo "❌ FAILED")"
echo "  Security: $([ "$SECURITY_PASSED" = "true" ] && echo "✅ PASSED" || echo "❌ FAILED")"
echo "  Performance: $([ "$PERFORMANCE_PASSED" = "true" ] && echo "✅ PASSED" || echo "❌ FAILED")"
echo "  Integration: $([ "$INTEGRATION_PASSED" = "true" ] && echo "✅ PASSED" || echo "❌ FAILED")"
echo ""
echo "Summary: $VALIDATION_SUMMARY"
echo "Results: $VALIDATION_RESULTS"
echo "Log: $VALIDATION_LOG"
echo "=========================================="

# Mark validation as completed
if [[ "$OVERALL_PASSED" == "true" ]]; then
    echo "comprehensive_validation_passed" > "$STAGING_DIR/comprehensive_validation_passed"
else
    echo "comprehensive_validation_failed" > "$STAGING_DIR/comprehensive_validation_failed"
fi

# Exit with appropriate code
if [[ "$OVERALL_PASSED" != "true" ]]; then
    exit 1
fi
