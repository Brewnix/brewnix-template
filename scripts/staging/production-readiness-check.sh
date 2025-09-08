#!/bin/bash
# scripts/staging/production-readiness-check.sh - Production readiness assessment

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
            echo "Run production readiness assessment for staging environment"
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
READINESS_LOG="$STAGING_DIR/logs/production_readiness_check_$(date +%Y%m%d_%H%M%S).log"
READINESS_RESULTS="$STAGING_DIR/production_readiness_results.json"

# Create readiness check log
exec > >(tee -a "$READINESS_LOG") 2>&1

log_info "Starting production readiness check for $STAGING_ENVIRONMENT_ID"

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

log_info "Running production readiness check for $SITE_DISPLAY_NAME"

# Initialize production readiness results
cat > "$READINESS_RESULTS" << EOF
{
  "production_readiness_check": {
    "site_name": "$SITE_NAME",
    "site_display_name": "$SITE_DISPLAY_NAME",
    "staging_environment_id": "$STAGING_ENVIRONMENT_ID",
    "check_start": "$(date -Iseconds)",
    "readiness_criteria": [],
    "overall_assessment": {}
  }
}
EOF

# Readiness Criterion 1: Validation Results
log_step "Readiness Criterion 1: Validation Results Assessment"

VALIDATION_PASSED=true
VALIDATION_CHECKS=()

# Check comprehensive validation
if [[ -f "$STAGING_DIR/comprehensive_validation_passed" ]]; then
    VALIDATION_CHECKS+=("{\"criterion\": \"comprehensive_validation\", \"status\": \"passed\", \"message\": \"Comprehensive validation passed\"}")
    log_info "✅ Comprehensive validation passed"
elif [[ -f "$STAGING_DIR/comprehensive_validation_failed" ]]; then
    VALIDATION_CHECKS+=("{\"criterion\": \"comprehensive_validation\", \"status\": \"failed\", \"message\": \"Comprehensive validation failed\"}")
    VALIDATION_PASSED=false
    log_error "❌ Comprehensive validation failed"
else
    VALIDATION_CHECKS+=("{\"criterion\": \"comprehensive_validation\", \"status\": \"not_run\", \"message\": \"Comprehensive validation not executed\"}")
    VALIDATION_PASSED=false
    log_warn "⚠️ Comprehensive validation not executed"
fi

# Check performance test
if [[ -f "$STAGING_DIR/performance_test_passed" ]]; then
    VALIDATION_CHECKS+=("{\"criterion\": \"performance_test\", \"status\": \"passed\", \"message\": \"Performance test passed\"}")
    log_info "✅ Performance test passed"
elif [[ -f "$STAGING_DIR/performance_test_failed" ]]; then
    VALIDATION_CHECKS+=("{\"criterion\": \"performance_test\", \"status\": \"failed\", \"message\": \"Performance test failed\"}")
    VALIDATION_PASSED=false
    log_error "❌ Performance test failed"
else
    VALIDATION_CHECKS+=("{\"criterion\": \"performance_test\", \"status\": \"not_run\", \"message\": \"Performance test not executed\"}")
    VALIDATION_PASSED=false
    log_warn "⚠️ Performance test not executed"
fi

# Check security validation
if [[ -f "$STAGING_DIR/security_validation_passed" ]]; then
    VALIDATION_CHECKS+=("{\"criterion\": \"security_validation\", \"status\": \"passed\", \"message\": \"Security validation passed\"}")
    log_info "✅ Security validation passed"
elif [[ -f "$STAGING_DIR/security_validation_failed" ]]; then
    VALIDATION_CHECKS+=("{\"criterion\": \"security_validation\", \"status\": \"failed\", \"message\": \"Security validation failed\"}")
    VALIDATION_PASSED=false
    log_error "❌ Security validation failed"
else
    VALIDATION_CHECKS+=("{\"criterion\": \"security_validation\", \"status\": \"not_run\", \"message\": \"Security validation not executed\"}")
    VALIDATION_PASSED=false
    log_warn "⚠️ Security validation not executed"
fi

# Readiness Criterion 2: Infrastructure Readiness
log_step "Readiness Criterion 2: Infrastructure Readiness"

INFRASTRUCTURE_READY=true
INFRASTRUCTURE_CHECKS=()

# Check if staging environment is properly configured
if [[ -f "$STAGING_DIR/terraform.tfstate" ]]; then
    INFRASTRUCTURE_CHECKS+=("{\"criterion\": \"terraform_state\", \"status\": \"passed\", \"message\": \"Terraform state exists\"}")
    log_info "✅ Terraform state exists"
else
    INFRASTRUCTURE_CHECKS+=("{\"criterion\": \"terraform_state\", \"status\": \"failed\", \"message\": \"Terraform state not found\"}")
    INFRASTRUCTURE_READY=false
    log_error "❌ Terraform state not found"
fi

# Check Ansible inventory
if [[ -f "$ANSIBLE_INVENTORY" ]]; then
    INFRASTRUCTURE_CHECKS+=("{\"criterion\": \"ansible_inventory\", \"status\": \"passed\", \"message\": \"Ansible inventory exists\"}")
    log_info "✅ Ansible inventory exists"
else
    INFRASTRUCTURE_CHECKS+=("{\"criterion\": \"ansible_inventory\", \"status\": \"failed\", \"message\": \"Ansible inventory not found\"}")
    INFRASTRUCTURE_READY=false
    log_error "❌ Ansible inventory not found"
fi

# Check Proxmox connectivity
log_info "Checking Proxmox connectivity..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags ping \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_connectivity.yml" >/dev/null 2>&1; then
    INFRASTRUCTURE_CHECKS+=("{\"criterion\": \"proxmox_connectivity\", \"status\": \"passed\", \"message\": \"Proxmox connectivity verified\"}")
    log_info "✅ Proxmox connectivity verified"
else
    INFRASTRUCTURE_CHECKS+=("{\"criterion\": \"proxmox_connectivity\", \"status\": \"failed\", \"message\": \"Cannot connect to Proxmox\"}")
    INFRASTRUCTURE_READY=false
    log_error "❌ Proxmox connectivity failed"
fi

# Readiness Criterion 3: Application Readiness
log_step "Readiness Criterion 3: Application Readiness"

APPLICATION_READY=true
APPLICATION_CHECKS=()

# Check if application is deployed
log_info "Checking application deployment status..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags app_status \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_app_deployment.yml" >/dev/null 2>&1; then
    APPLICATION_CHECKS+=("{\"criterion\": \"application_deployment\", \"status\": \"passed\", \"message\": \"Application is deployed and running\"}")
    log_info "✅ Application is deployed and running"
else
    APPLICATION_CHECKS+=("{\"criterion\": \"application_deployment\", \"status\": \"failed\", \"message\": \"Application deployment issues detected\"}")
    APPLICATION_READY=false
    log_error "❌ Application deployment issues detected"
fi

# Check service health
log_info "Checking service health..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags health_check \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_service_health.yml" >/dev/null 2>&1; then
    APPLICATION_CHECKS+=("{\"criterion\": \"service_health\", \"status\": \"passed\", \"message\": \"All services are healthy\"}")
    log_info "✅ All services are healthy"
else
    APPLICATION_CHECKS+=("{\"criterion\": \"service_health\", \"status\": \"failed\", \"message\": \"Service health issues detected\"}")
    APPLICATION_READY=false
    log_error "❌ Service health issues detected"
fi

# Readiness Criterion 4: Monitoring and Alerting
log_step "Readiness Criterion 4: Monitoring and Alerting"

MONITORING_READY=true
MONITORING_CHECKS=()

# Check monitoring configuration
log_info "Checking monitoring configuration..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags monitoring \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_monitoring.yml" >/dev/null 2>&1; then
    MONITORING_CHECKS+=("{\"criterion\": \"monitoring_config\", \"status\": \"passed\", \"message\": \"Monitoring is properly configured\"}")
    log_info "✅ Monitoring is properly configured"
else
    MONITORING_CHECKS+=("{\"criterion\": \"monitoring_config\", \"status\": \"failed\", \"message\": \"Monitoring configuration issues detected\"}")
    MONITORING_READY=false
    log_error "❌ Monitoring configuration issues detected"
fi

# Check alerting configuration
log_info "Checking alerting configuration..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags alerting \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_alerting.yml" >/dev/null 2>&1; then
    MONITORING_CHECKS+=("{\"criterion\": \"alerting_config\", \"status\": \"passed\", \"message\": \"Alerting is properly configured\"}")
    log_info "✅ Alerting is properly configured"
else
    MONITORING_CHECKS+=("{\"criterion\": \"alerting_config\", \"status\": \"failed\", \"message\": \"Alerting configuration issues detected\"}")
    MONITORING_READY=false
    log_error "❌ Alerting configuration issues detected"
fi

# Readiness Criterion 5: Backup and Recovery
log_step "Readiness Criterion 5: Backup and Recovery"

BACKUP_READY=true
BACKUP_CHECKS=()

# Check backup configuration
log_info "Checking backup configuration..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags backup \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_backup.yml" >/dev/null 2>&1; then
    BACKUP_CHECKS+=("{\"criterion\": \"backup_config\", \"status\": \"passed\", \"message\": \"Backup configuration is valid\"}")
    log_info "✅ Backup configuration is valid"
else
    BACKUP_CHECKS+=("{\"criterion\": \"backup_config\", \"status\": \"failed\", \"message\": \"Backup configuration issues detected\"}")
    BACKUP_READY=false
    log_error "❌ Backup configuration issues detected"
fi

# Check recovery procedures
log_info "Checking recovery procedures..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags recovery \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/test_recovery.yml" >/dev/null 2>&1; then
    BACKUP_CHECKS+=("{\"criterion\": \"recovery_procedures\", \"status\": \"passed\", \"message\": \"Recovery procedures are in place\"}")
    log_info "✅ Recovery procedures are in place"
else
    BACKUP_CHECKS+=("{\"criterion\": \"recovery_procedures\", \"status\": \"failed\", \"message\": \"Recovery procedure issues detected\"}")
    BACKUP_READY=false
    log_error "❌ Recovery procedure issues detected"
fi

# Readiness Criterion 6: Documentation and Runbooks
log_step "Readiness Criterion 6: Documentation and Runbooks"

DOCUMENTATION_READY=true
DOCUMENTATION_CHECKS=()

# Check if deployment documentation exists
if [[ -f "$STAGING_DIR/deployment_documentation.md" ]]; then
    DOCUMENTATION_CHECKS+=("{\"criterion\": \"deployment_docs\", \"status\": \"passed\", \"message\": \"Deployment documentation exists\"}")
    log_info "✅ Deployment documentation exists"
else
    DOCUMENTATION_CHECKS+=("{\"criterion\": \"deployment_docs\", \"status\": \"warning\", \"message\": \"Deployment documentation not found\"}")
    log_warn "⚠️ Deployment documentation not found"
fi

# Check if runbooks exist
if [[ -f "$STAGING_DIR/runbooks.md" ]]; then
    DOCUMENTATION_CHECKS+=("{\"criterion\": \"runbooks\", \"status\": \"passed\", \"message\": \"Runbooks exist\"}")
    log_info "✅ Runbooks exist"
else
    DOCUMENTATION_CHECKS+=("{\"criterion\": \"runbooks\", \"status\": \"warning\", \"message\": \"Runbooks not found\"}")
    log_warn "⚠️ Runbooks not found"
fi

# Check if rollback procedures are documented
if [[ -f "$STAGING_DIR/rollback_procedures.md" ]]; then
    DOCUMENTATION_CHECKS+=("{\"criterion\": \"rollback_procedures\", \"status\": \"passed\", \"message\": \"Rollback procedures are documented\"}")
    log_info "✅ Rollback procedures are documented"
else
    DOCUMENTATION_CHECKS+=("{\"criterion\": \"rollback_procedures\", \"status\": \"failed\", \"message\": \"Rollback procedures not documented\"}")
    DOCUMENTATION_READY=false
    log_error "❌ Rollback procedures not documented"
fi

# Calculate overall readiness
log_step "Calculating overall production readiness"

OVERALL_READY=true
if [[ "$VALIDATION_PASSED" != "true" || "$INFRASTRUCTURE_READY" != "true" || "$APPLICATION_READY" != "true" || "$MONITORING_READY" != "true" || "$BACKUP_READY" != "true" || "$DOCUMENTATION_READY" != "true" ]]; then
    OVERALL_READY=false
fi

# Count total criteria and passed criteria
ALL_CRITERIA_JSON=$(printf '%s\n' "${VALIDATION_CHECKS[@]}" "${INFRASTRUCTURE_CHECKS[@]}" "${APPLICATION_CHECKS[@]}" "${MONITORING_CHECKS[@]}" "${BACKUP_CHECKS[@]}" "${DOCUMENTATION_CHECKS[@]}" | jq -s '.')
TOTAL_CRITERIA=$(echo "$ALL_CRITERIA_JSON" | jq length)
PASSED_CRITERIA=$(echo "$ALL_CRITERIA_JSON" | jq '[.[] | select(.status == "passed")] | length')
READINESS_RATE=$(( PASSED_CRITERIA * 100 / TOTAL_CRITERIA ))

# Update production readiness results
python3 -c "
import json
import sys
data = json.load(open('$READINESS_RESULTS'))

# Convert bash arrays to Python lists
validation_checks = [json.loads(check) for check in sys.argv[1].split('|') if check]
infra_checks = [json.loads(check) for check in sys.argv[2].split('|') if check]
app_checks = [json.loads(check) for check in sys.argv[3].split('|') if check]
monitoring_checks = [json.loads(check) for check in sys.argv[4].split('|') if check]
backup_checks = [json.loads(check) for check in sys.argv[5].split('|') if check]
doc_checks = [json.loads(check) for check in sys.argv[6].split('|') if check]

data['production_readiness_check']['check_end'] = '$(date -Iseconds)'
data['production_readiness_check']['readiness_criteria'] = validation_checks + infra_checks + app_checks + monitoring_checks + backup_checks + doc_checks
data['production_readiness_check']['overall_assessment'] = {
    'ready_for_production': $OVERALL_READY,
    'total_criteria': $TOTAL_CRITERIA,
    'passed_criteria': $PASSED_CRITERIA,
    'readiness_rate': $READINESS_RATE,
    'categories': {
        'validation': $VALIDATION_PASSED,
        'infrastructure': $INFRASTRUCTURE_READY,
        'application': $APPLICATION_READY,
        'monitoring': $MONITORING_READY,
        'backup_recovery': $BACKUP_READY,
        'documentation': $DOCUMENTATION_READY
    }
}
json.dump(data, open('$READINESS_RESULTS', 'w'), indent=2)
" "$(printf '%s|' "${VALIDATION_CHECKS[@]}")" "$(printf '%s|' "${INFRASTRUCTURE_CHECKS[@]}")" "$(printf '%s|' "${APPLICATION_CHECKS[@]}")" "$(printf '%s|' "${MONITORING_CHECKS[@]}")" "$(printf '%s|' "${BACKUP_CHECKS[@]}")" "$(printf '%s|' "${DOCUMENTATION_CHECKS[@]}")"

log_info "Production readiness check completed"
log_info "Overall readiness: $([ "$OVERALL_READY" = "true" ] && echo "READY" || echo "NOT READY")"
log_info "Readiness rate: ${READINESS_RATE}% ($PASSED_CRITERIA/$TOTAL_CRITERIA criteria passed)"

# Create production readiness summary
READINESS_SUMMARY="$STAGING_DIR/production_readiness_summary.json"

cat > "$READINESS_SUMMARY" << EOF
{
  "production_readiness_summary": {
    "site_name": "$SITE_NAME",
    "site_display_name": "$SITE_DISPLAY_NAME",
    "staging_environment_id": "$STAGING_ENVIRONMENT_ID",
    "assessment_timestamp": "$(date -Iseconds)",
    "overall_readiness": "$( [ "$OVERALL_READY" = "true" ] && echo "ready" || echo "not_ready" )",
    "readiness_rate": $READINESS_RATE,
    "total_criteria": $TOTAL_CRITERIA,
    "passed_criteria": $PASSED_CRITERIA,
    "categories": {
      "validation": "$( [ "$VALIDATION_PASSED" = "true" ] && echo "ready" || echo "not_ready" )",
      "infrastructure": "$( [ "$INFRASTRUCTURE_READY" = "true" ] && echo "ready" || echo "not_ready" )",
      "application": "$( [ "$APPLICATION_READY" = "true" ] && echo "ready" || echo "not_ready" )",
      "monitoring": "$( [ "$MONITORING_READY" = "true" ] && echo "ready" || echo "not_ready" )",
      "backup_recovery": "$( [ "$BACKUP_READY" = "true" ] && echo "ready" || echo "not_ready" )",
      "documentation": "$( [ "$DOCUMENTATION_READY" = "true" ] && echo "ready" || echo "not_ready" )"
    },
    "recommendations": [
      $(if [ $READINESS_RATE -ge 95 ]; then
          echo '"Environment is fully ready for production deployment"'
      elif [ $READINESS_RATE -ge 85 ]; then
          echo '"Environment is mostly ready - address minor issues before production"'
      elif [ $READINESS_RATE -ge 75 ]; then
          echo '"Environment needs attention - address critical issues before production"'
      else
          echo '"Environment is not ready for production - major issues must be resolved"'
      fi)
    ]
  },
  "readiness_check_log": "$READINESS_LOG",
  "readiness_check_results": "$READINESS_RESULTS"
}
EOF

log_info "Production readiness summary saved to: $READINESS_SUMMARY"
log_info "Production readiness results saved to: $READINESS_RESULTS"
log_info "Production readiness log saved to: $READINESS_LOG"

echo ""
echo "=========================================="
echo "PRODUCTION READINESS ASSESSMENT"
echo "=========================================="
echo "Site: $SITE_DISPLAY_NAME ($SITE_NAME)"
echo "Environment: $STAGING_ENVIRONMENT_ID"
echo "Overall Readiness: $([ "$OVERALL_READY" = "true" ] && echo "✅ READY" || echo "❌ NOT READY")"
echo "Readiness Rate: ${READINESS_RATE}%"
echo "Criteria: $PASSED_CRITERIA/$TOTAL_CRITERIA passed"
echo ""
echo "Category Status:"
echo "  Validation: $([ "$VALIDATION_PASSED" = "true" ] && echo "✅ READY" || echo "❌ NOT READY")"
echo "  Infrastructure: $([ "$INFRASTRUCTURE_READY" = "true" ] && echo "✅ READY" || echo "❌ NOT READY")"
echo "  Application: $([ "$APPLICATION_READY" = "true" ] && echo "✅ READY" || echo "❌ NOT READY")"
echo "  Monitoring: $([ "$MONITORING_READY" = "true" ] && echo "✅ READY" || echo "❌ NOT READY")"
echo "  Backup/Recovery: $([ "$BACKUP_READY" = "true" ] && echo "✅ READY" || echo "❌ NOT READY")"
echo "  Documentation: $([ "$DOCUMENTATION_READY" = "true" ] && echo "✅ READY" || echo "❌ NOT READY")"
echo ""
echo "Summary: $READINESS_SUMMARY"
echo "Results: $READINESS_RESULTS"
echo "Log: $READINESS_LOG"
echo "=========================================="

# Mark production readiness check as completed
if [[ "$OVERALL_READY" == "true" ]]; then
    echo "production_readiness_passed" > "$STAGING_DIR/production_readiness_passed"
else
    echo "production_readiness_failed" > "$STAGING_DIR/production_readiness_failed"
fi

# Exit with appropriate code
if [[ "$OVERALL_READY" != "true" ]]; then
    exit 1
fi
