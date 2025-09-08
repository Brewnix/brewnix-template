#!/bin/bash
# scripts/staging/security-validation.sh - Security validation for staging environments

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
            echo "Run security validation for staging environment"
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
SECURITY_LOG="$STAGING_DIR/logs/security_validation_$(date +%Y%m%d_%H%M%S).log"
SECURITY_RESULTS="$STAGING_DIR/security_validation_results.json"

# Create security validation log
exec > >(tee -a "$SECURITY_LOG") 2>&1

log_info "Starting security validation for $STAGING_ENVIRONMENT_ID"

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

log_info "Running security validation for $SITE_DISPLAY_NAME"

# Initialize security validation results
cat > "$SECURITY_RESULTS" << EOF
{
  "validation_type": "security_validation",
  "site_name": "$SITE_NAME",
  "site_display_name": "$SITE_DISPLAY_NAME",
  "staging_environment_id": "$STAGING_ENVIRONMENT_ID",
  "validation_start": "$(date -Iseconds)",
  "security_checks": []
}
EOF

# Security Check 1: Firewall Configuration
log_step "Security Check 1: Firewall Configuration"

FIREWALL_PASSED=true
FIREWALL_CHECKS=()

# Check firewall rules
log_info "Checking firewall rules..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags firewall_audit \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/security_firewall_audit.yml" >/dev/null 2>&1; then
    FIREWALL_CHECKS+=("{\"check\": \"firewall_rules\", \"status\": \"passed\", \"message\": \"Firewall rules are properly configured\"}")
    log_info "✅ Firewall rules check passed"
else
    FIREWALL_CHECKS+=("{\"check\": \"firewall_rules\", \"status\": \"failed\", \"message\": \"Firewall rules have security issues\"}")
    FIREWALL_PASSED=false
    log_error "❌ Firewall rules check failed"
fi

# Check for open ports
log_info "Checking for unauthorized open ports..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags port_scan \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/security_port_scan.yml" >/dev/null 2>&1; then
    FIREWALL_CHECKS+=("{\"check\": \"open_ports\", \"status\": \"passed\", \"message\": \"No unauthorized ports are open\"}")
    log_info "✅ Open ports check passed"
else
    FIREWALL_CHECKS+=("{\"check\": \"open_ports\", \"status\": \"failed\", \"message\": \"Unauthorized ports are open\"}")
    FIREWALL_PASSED=false
    log_error "❌ Open ports check failed"
fi

# Security Check 2: SSL/TLS Configuration
log_step "Security Check 2: SSL/TLS Configuration"

SSL_PASSED=true
SSL_CHECKS=()

# Check SSL/TLS certificates
log_info "Checking SSL/TLS certificates..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags ssl_certificates \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/security_ssl_certificates.yml" >/dev/null 2>&1; then
    SSL_CHECKS+=("{\"check\": \"ssl_certificates\", \"status\": \"passed\", \"message\": \"SSL/TLS certificates are valid and properly configured\"}")
    log_info "✅ SSL certificates check passed"
else
    SSL_CHECKS+=("{\"check\": \"ssl_certificates\", \"status\": \"failed\", \"message\": \"SSL/TLS certificate issues detected\"}")
    SSL_PASSED=false
    log_error "❌ SSL certificates check failed"
fi

# Check SSL/TLS protocols
log_info "Checking SSL/TLS protocols..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags ssl_protocols \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/security_ssl_protocols.yml" >/dev/null 2>&1; then
    SSL_CHECKS+=("{\"check\": \"ssl_protocols\", \"status\": \"passed\", \"message\": \"SSL/TLS protocols are secure\"}")
    log_info "✅ SSL protocols check passed"
else
    SSL_CHECKS+=("{\"check\": \"ssl_protocols\", \"status\": \"failed\", \"message\": \"Insecure SSL/TLS protocols detected\"}")
    SSL_PASSED=false
    log_error "❌ SSL protocols check failed"
fi

# Security Check 3: Authentication and Authorization
log_step "Security Check 3: Authentication and Authorization"

AUTH_PASSED=true
AUTH_CHECKS=()

# Check authentication mechanisms
log_info "Checking authentication mechanisms..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags authentication \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/security_authentication.yml" >/dev/null 2>&1; then
    AUTH_CHECKS+=("{\"check\": \"authentication\", \"status\": \"passed\", \"message\": \"Authentication mechanisms are properly configured\"}")
    log_info "✅ Authentication check passed"
else
    AUTH_CHECKS+=("{\"check\": \"authentication\", \"status\": \"failed\", \"message\": \"Authentication configuration issues detected\"}")
    AUTH_PASSED=false
    log_error "❌ Authentication check failed"
fi

# Check authorization policies
log_info "Checking authorization policies..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags authorization \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/security_authorization.yml" >/dev/null 2>&1; then
    AUTH_CHECKS+=("{\"check\": \"authorization\", \"status\": \"passed\", \"message\": \"Authorization policies are correctly implemented\"}")
    log_info "✅ Authorization check passed"
else
    AUTH_CHECKS+=("{\"check\": \"authorization\", \"status\": \"failed\", \"message\": \"Authorization policy issues detected\"}")
    AUTH_PASSED=false
    log_error "❌ Authorization check failed"
fi

# Security Check 4: Vulnerability Assessment
log_step "Security Check 4: Vulnerability Assessment"

VULN_PASSED=true
VULN_CHECKS=()

# Check for known vulnerabilities
log_info "Checking for known vulnerabilities..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags vulnerability_scan \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/security_vulnerability_scan.yml" >/dev/null 2>&1; then
    VULN_CHECKS+=("{\"check\": \"vulnerability_scan\", \"status\": \"passed\", \"message\": \"No critical vulnerabilities detected\"}")
    log_info "✅ Vulnerability scan passed"
else
    VULN_CHECKS+=("{\"check\": \"vulnerability_scan\", \"status\": \"warning\", \"message\": \"Vulnerabilities detected - review required\"}")
    log_warn "⚠️ Vulnerability scan found issues"
fi

# Check security updates
log_info "Checking security updates..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags security_updates \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/security_updates.yml" >/dev/null 2>&1; then
    VULN_CHECKS+=("{\"check\": \"security_updates\", \"status\": \"passed\", \"message\": \"Security updates are current\"}")
    log_info "✅ Security updates check passed"
else
    VULN_CHECKS+=("{\"check\": \"security_updates\", \"status\": \"failed\", \"message\": \"Security updates are missing\"}")
    VULN_PASSED=false
    log_error "❌ Security updates check failed"
fi

# Security Check 5: Data Protection
log_step "Security Check 5: Data Protection"

DATA_PASSED=true
DATA_CHECKS=()

# Check data encryption
log_info "Checking data encryption..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags data_encryption \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/security_data_encryption.yml" >/dev/null 2>&1; then
    DATA_CHECKS+=("{\"check\": \"data_encryption\", \"status\": \"passed\", \"message\": \"Data encryption is properly implemented\"}")
    log_info "✅ Data encryption check passed"
else
    DATA_CHECKS+=("{\"check\": \"data_encryption\", \"status\": \"failed\", \"message\": \"Data encryption issues detected\"}")
    DATA_PASSED=false
    log_error "❌ Data encryption check failed"
fi

# Check data backup security
log_info "Checking data backup security..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags backup_security \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/security_backup_security.yml" >/dev/null 2>&1; then
    DATA_CHECKS+=("{\"check\": \"backup_security\", \"status\": \"passed\", \"message\": \"Data backups are secure\"}")
    log_info "✅ Backup security check passed"
else
    DATA_CHECKS+=("{\"check\": \"backup_security\", \"status\": \"warning\", \"message\": \"Backup security issues detected\"}")
    log_warn "⚠️ Backup security check failed"
fi

# Security Check 6: Intrusion Detection
log_step "Security Check 6: Intrusion Detection"

INTRUSION_PASSED=true
INTRUSION_CHECKS=()

# Check intrusion detection systems
log_info "Checking intrusion detection systems..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags intrusion_detection \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/security_intrusion_detection.yml" >/dev/null 2>&1; then
    INTRUSION_CHECKS+=("{\"check\": \"intrusion_detection\", \"status\": \"passed\", \"message\": \"Intrusion detection systems are active\"}")
    log_info "✅ Intrusion detection check passed"
else
    INTRUSION_CHECKS+=("{\"check\": \"intrusion_detection\", \"status\": \"warning\", \"message\": \"Intrusion detection system issues detected\"}")
    log_warn "⚠️ Intrusion detection check failed"
fi

# Check log monitoring
log_info "Checking log monitoring..."
if ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags log_monitoring \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/security_log_monitoring.yml" >/dev/null 2>&1; then
    INTRUSION_CHECKS+=("{\"check\": \"log_monitoring\", \"status\": \"passed\", \"message\": \"Log monitoring is properly configured\"}")
    log_info "✅ Log monitoring check passed"
else
    INTRUSION_CHECKS+=("{\"check\": \"log_monitoring\", \"status\": \"failed\", \"message\": \"Log monitoring configuration issues detected\"}")
    INTRUSION_PASSED=false
    log_error "❌ Log monitoring check failed"
fi

# Calculate overall security validation result
log_step "Calculating overall security validation result"

OVERALL_SECURITY_PASSED=true
if [[ "$FIREWALL_PASSED" != "true" || "$SSL_PASSED" != "true" || "$AUTH_PASSED" != "true" || "$VULN_PASSED" != "true" || "$DATA_PASSED" != "true" || "$INTRUSION_PASSED" != "true" ]]; then
    OVERALL_SECURITY_PASSED=false
fi

# Count total checks and passed checks
ALL_SECURITY_CHECKS_JSON=$(printf '%s\n' "${FIREWALL_CHECKS[@]}" "${SSL_CHECKS[@]}" "${AUTH_CHECKS[@]}" "${VULN_CHECKS[@]}" "${DATA_CHECKS[@]}" "${INTRUSION_CHECKS[@]}" | jq -s '.')
TOTAL_SECURITY_CHECKS=$(echo "$ALL_SECURITY_CHECKS_JSON" | jq length)
PASSED_SECURITY_CHECKS=$(echo "$ALL_SECURITY_CHECKS_JSON" | jq '[.[] | select(.status == "passed")] | length')
SECURITY_SUCCESS_RATE=$(( PASSED_SECURITY_CHECKS * 100 / TOTAL_SECURITY_CHECKS ))

# Update security validation results
python3 -c "
import json
import sys
data = json.load(open('$SECURITY_RESULTS'))

# Convert bash arrays to Python lists
firewall_checks = [json.loads(check) for check in sys.argv[1].split('|') if check]
ssl_checks = [json.loads(check) for check in sys.argv[2].split('|') if check]
auth_checks = [json.loads(check) for check in sys.argv[3].split('|') if check]
vuln_checks = [json.loads(check) for check in sys.argv[4].split('|') if check]
data_checks = [json.loads(check) for check in sys.argv[5].split('|') if check]
intrusion_checks = [json.loads(check) for check in sys.argv[6].split('|') if check]

data['validation_end'] = '$(date -Iseconds)'
data['firewall_validation'] = {'passed': $FIREWALL_PASSED, 'checks': firewall_checks}
data['ssl_validation'] = {'passed': $SSL_PASSED, 'checks': ssl_checks}
data['authentication_validation'] = {'passed': $AUTH_PASSED, 'checks': auth_checks}
data['vulnerability_validation'] = {'passed': $VULN_PASSED, 'checks': vuln_checks}
data['data_protection_validation'] = {'passed': $DATA_PASSED, 'checks': data_checks}
data['intrusion_detection_validation'] = {'passed': $INTRUSION_PASSED, 'checks': intrusion_checks}
data['overall_result'] = {'passed': $OVERALL_SECURITY_PASSED, 'total_checks': $TOTAL_SECURITY_CHECKS, 'passed_checks': $PASSED_SECURITY_CHECKS, 'success_rate': $SECURITY_SUCCESS_RATE}
json.dump(data, open('$SECURITY_RESULTS', 'w'), indent=2)
" "$(printf '%s|' "${FIREWALL_CHECKS[@]}")" "$(printf '%s|' "${SSL_CHECKS[@]}")" "$(printf '%s|' "${AUTH_CHECKS[@]}")" "$(printf '%s|' "${VULN_CHECKS[@]}")" "$(printf '%s|' "${DATA_CHECKS[@]}")" "$(printf '%s|' "${INTRUSION_CHECKS[@]}")"

log_info "Security validation completed"
log_info "Overall result: $([ "$OVERALL_SECURITY_PASSED" = "true" ] && echo "PASSED" || echo "FAILED")"
log_info "Success rate: ${SECURITY_SUCCESS_RATE}% ($PASSED_SECURITY_CHECKS/$TOTAL_SECURITY_CHECKS checks passed)"

# Create security validation summary
SECURITY_SUMMARY="$STAGING_DIR/security_validation_summary.json"

cat > "$SECURITY_SUMMARY" << EOF
{
  "security_validation_summary": {
    "site_name": "$SITE_NAME",
    "site_display_name": "$SITE_DISPLAY_NAME",
    "staging_environment_id": "$STAGING_ENVIRONMENT_ID",
    "validation_timestamp": "$(date -Iseconds)",
    "overall_status": "$( [ "$OVERALL_SECURITY_PASSED" = "true" ] && echo "passed" || echo "failed" )",
    "success_rate": $SECURITY_SUCCESS_RATE,
    "total_checks": $TOTAL_SECURITY_CHECKS,
    "passed_checks": $PASSED_SECURITY_CHECKS,
    "categories": {
      "firewall": "$( [ "$FIREWALL_PASSED" = "true" ] && echo "passed" || echo "failed" )",
      "ssl_tls": "$( [ "$SSL_PASSED" = "true" ] && echo "passed" || echo "failed" )",
      "authentication": "$( [ "$AUTH_PASSED" = "true" ] && echo "passed" || echo "failed" )",
      "vulnerability": "$( [ "$VULN_PASSED" = "true" ] && echo "passed" || echo "failed" )",
      "data_protection": "$( [ "$DATA_PASSED" = "true" ] && echo "passed" || echo "failed" )",
      "intrusion_detection": "$( [ "$INTRUSION_PASSED" = "true" ] && echo "passed" || echo "failed" )"
    },
    "recommendations": [
      $(if [ $SECURITY_SUCCESS_RATE -ge 95 ]; then
          echo '"Security validation successful - environment is secure"'
      elif [ $SECURITY_SUCCESS_RATE -ge 85 ]; then
          echo '"Security validation mostly successful - minor security issues to address"'
      elif [ $SECURITY_SUCCESS_RATE -ge 75 ]; then
          echo '"Security validation has issues - address critical security problems before proceeding"'
      else
          echo '"Security validation failed - do not proceed with production deployment due to security risks"'
      fi)
    ]
  },
  "security_validation_log": "$SECURITY_LOG",
  "security_validation_results": "$SECURITY_RESULTS"
}
EOF

log_info "Security validation summary saved to: $SECURITY_SUMMARY"
log_info "Security validation results saved to: $SECURITY_RESULTS"
log_info "Security validation log saved to: $SECURITY_LOG"

echo ""
echo "=========================================="
echo "SECURITY VALIDATION SUMMARY"
echo "=========================================="
echo "Site: $SITE_DISPLAY_NAME ($SITE_NAME)"
echo "Environment: $STAGING_ENVIRONMENT_ID"
echo "Overall Status: $([ "$OVERALL_SECURITY_PASSED" = "true" ] && echo "✅ PASSED" || echo "❌ FAILED")"
echo "Success Rate: ${SECURITY_SUCCESS_RATE}%"
echo "Checks: $PASSED_SECURITY_CHECKS/$TOTAL_SECURITY_CHECKS passed"
echo ""
echo "Category Results:"
echo "  Firewall: $([ "$FIREWALL_PASSED" = "true" ] && echo "✅ PASSED" || echo "❌ FAILED")"
echo "  SSL/TLS: $([ "$SSL_PASSED" = "true" ] && echo "✅ PASSED" || echo "❌ FAILED")"
echo "  Authentication: $([ "$AUTH_PASSED" = "true" ] && echo "✅ PASSED" || echo "❌ FAILED")"
echo "  Vulnerability: $([ "$VULN_PASSED" = "true" ] && echo "✅ PASSED" || echo "❌ FAILED")"
echo "  Data Protection: $([ "$DATA_PASSED" = "true" ] && echo "✅ PASSED" || echo "❌ FAILED")"
echo "  Intrusion Detection: $([ "$INTRUSION_PASSED" = "true" ] && echo "✅ PASSED" || echo "❌ FAILED")"
echo ""
echo "Summary: $SECURITY_SUMMARY"
echo "Results: $SECURITY_RESULTS"
echo "Log: $SECURITY_LOG"
echo "=========================================="

# Mark security validation as completed
if [[ "$OVERALL_SECURITY_PASSED" == "true" ]]; then
    echo "security_validation_passed" > "$STAGING_DIR/security_validation_passed"
else
    echo "security_validation_failed" > "$STAGING_DIR/security_validation_failed"
fi

# Exit with appropriate code
if [[ "$OVERALL_SECURITY_PASSED" != "true" ]]; then
    exit 1
fi
