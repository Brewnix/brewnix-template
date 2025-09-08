#!/bin/bash
# scripts/staging/monitor-environment.sh - Monitor staging environment health

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
MONITOR_DURATION="300"

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: $0 <staging_environment_id> [monitor_duration_seconds]"
            echo "Monitor staging environment health for specified duration"
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            exit 1
            ;;
        *)
            if [[ -z "$STAGING_ENVIRONMENT_ID" ]]; then
                STAGING_ENVIRONMENT_ID="$1"
            elif [[ -z "$MONITOR_DURATION" ]]; then
                MONITOR_DURATION="$1"
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
    echo "Usage: $0 <staging_environment_id> [monitor_duration_seconds]"
    exit 1
fi

# Validate monitor duration
if ! [[ "$MONITOR_DURATION" =~ ^[0-9]+$ ]] || [ "$MONITOR_DURATION" -lt 60 ]; then
    log_error "Monitor duration must be a number >= 60 seconds"
    exit 1
fi

STAGING_DIR="$REPO_ROOT/staging/$STAGING_ENVIRONMENT_ID"
MONITOR_LOG="$STAGING_DIR/logs/environment_monitor_$(date +%Y%m%d_%H%M%S).log"

# Create monitor log
exec > >(tee -a "$MONITOR_LOG") 2>&1

log_info "Starting environment monitoring for $STAGING_ENVIRONMENT_ID (Duration: ${MONITOR_DURATION}s)"

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

log_info "Monitoring $SITE_DISPLAY_NAME environment"

# Initialize monitoring data
MONITOR_DATA="$STAGING_DIR/monitor_data.json"
cat > "$MONITOR_DATA" << EOF
{
  "monitoring_start": "$(date -Iseconds)",
  "site_name": "$SITE_NAME",
  "site_display_name": "$SITE_DISPLAY_NAME",
  "staging_environment_id": "$STAGING_ENVIRONMENT_ID",
  "duration_seconds": $MONITOR_DURATION,
  "check_interval": 30,
  "checks": []
}
EOF

# Monitoring loop
END_TIME=$(( $(date +%s) + MONITOR_DURATION ))
CHECK_COUNT=0

log_step "Starting monitoring loop (Duration: ${MONITOR_DURATION}s, Interval: 30s)"

while [ "$(date +%s)" -lt "$END_TIME" ]; do
    CHECK_COUNT=$((CHECK_COUNT + 1))
    CHECK_TIMESTAMP=$(date -Iseconds)

    log_info "Monitoring check #$CHECK_COUNT at $CHECK_TIMESTAMP"

    # Health check
    HEALTH_STATUS="unknown"
    if ansible-playbook \
        --inventory "$ANSIBLE_INVENTORY" \
        --limit "$SITE_NAME" \
        --tags health_check \
        "$REPO_ROOT/vendor/proxmox-firewall/tests/test_health_checks.yml" >/dev/null 2>&1; then
        HEALTH_STATUS="healthy"
        log_info "✅ Health check passed"
    else
        HEALTH_STATUS="unhealthy"
        log_warn "❌ Health check failed"
    fi

    # Service check
    SERVICE_STATUS="unknown"
    if ansible-playbook \
        --inventory "$ANSIBLE_INVENTORY" \
        --limit "$SITE_NAME" \
        --tags service_check \
        "$REPO_ROOT/vendor/proxmox-firewall/tests/test_services.yml" >/dev/null 2>&1; then
        SERVICE_STATUS="running"
        log_info "✅ Service check passed"
    else
        SERVICE_STATUS="failed"
        log_warn "❌ Service check failed"
    fi

    # Connectivity check
    CONNECTIVITY_STATUS="unknown"
    if ansible-playbook \
        --inventory "$ANSIBLE_INVENTORY" \
        --limit "$SITE_NAME" \
        --tags connectivity \
        "$REPO_ROOT/vendor/proxmox-firewall/tests/test_network_connectivity.yml" >/dev/null 2>&1; then
        CONNECTIVITY_STATUS="connected"
        log_info "✅ Connectivity check passed"
    else
        CONNECTIVITY_STATUS="disconnected"
        log_warn "❌ Connectivity check failed"
    fi

    # Collect basic metrics
    CPU_USAGE="unknown"
    MEMORY_USAGE="unknown"
    DISK_USAGE="unknown"

    # Try to collect system metrics
    if ansible-playbook \
        --inventory "$ANSIBLE_INVENTORY" \
        --limit "$SITE_NAME" \
        --tags collect_metrics \
        --extra-vars "output_file=$STAGING_DIR/metrics_$CHECK_COUNT.json" \
        "$REPO_ROOT/vendor/proxmox-firewall/tests/collect_system_metrics.yml" >/dev/null 2>&1; then

        if [[ -f "$STAGING_DIR/metrics_$CHECK_COUNT.json" ]]; then
            CPU_USAGE=$(python3 -c "import json; print(json.load(open('$STAGING_DIR/metrics_$CHECK_COUNT.json')).get('cpu_usage', 'unknown'))" 2>/dev/null || echo "unknown")
            MEMORY_USAGE=$(python3 -c "import json; print(json.load(open('$STAGING_DIR/metrics_$CHECK_COUNT.json')).get('memory_usage', 'unknown'))" 2>/dev/null || echo "unknown")
            DISK_USAGE=$(python3 -c "import json; print(json.load(open('$STAGING_DIR/metrics_$CHECK_COUNT.json')).get('disk_usage', 'unknown'))" 2>/dev/null || echo "unknown")
        fi
    fi

    # Add check data to monitoring data
    python3 -c "
import json
data = json.load(open('$MONITOR_DATA'))
data['checks'].append({
    'check_number': $CHECK_COUNT,
    'timestamp': '$CHECK_TIMESTAMP',
    'health_status': '$HEALTH_STATUS',
    'service_status': '$SERVICE_STATUS',
    'connectivity_status': '$CONNECTIVITY_STATUS',
    'cpu_usage': '$CPU_USAGE',
    'memory_usage': '$MEMORY_USAGE',
    'disk_usage': '$DISK_USAGE'
})
json.dump(data, open('$MONITOR_DATA', 'w'), indent=2)
"

    # Determine overall status
    OVERALL_STATUS="healthy"
    if [[ "$HEALTH_STATUS" != "healthy" || "$SERVICE_STATUS" != "running" || "$CONNECTIVITY_STATUS" != "connected" ]]; then
        OVERALL_STATUS="unhealthy"
    fi

    log_info "Check #$CHECK_COUNT completed - Overall status: $OVERALL_STATUS"

    # Wait for next check (30 seconds)
    sleep 30
done

log_step "Monitoring completed"

# Analyze monitoring results
log_info "Analyzing monitoring results..."

TOTAL_CHECKS=$CHECK_COUNT
HEALTHY_CHECKS=$(python3 -c "
import json
data = json.load(open('$MONITOR_DATA'))
healthy = sum(1 for check in data['checks'] if check['health_status'] == 'healthy' and check['service_status'] == 'running' and check['connectivity_status'] == 'connected')
print(healthy)
")

SUCCESS_RATE=$(( HEALTHY_CHECKS * 100 / TOTAL_CHECKS ))

log_info "Monitoring Results:"
log_info "  Total checks: $TOTAL_CHECKS"
log_info "  Healthy checks: $HEALTHY_CHECKS"
log_info "  Success rate: ${SUCCESS_RATE}%"

# Determine final monitoring status
if [ $SUCCESS_RATE -ge 95 ]; then
    MONITOR_STATUS="success"
    log_info "✅ Environment monitoring successful (${SUCCESS_RATE}% success rate)"
elif [ $SUCCESS_RATE -ge 80 ]; then
    MONITOR_STATUS="warning"
    log_warn "⚠️ Environment monitoring completed with warnings (${SUCCESS_RATE}% success rate)"
else
    MONITOR_STATUS="failure"
    log_error "❌ Environment monitoring failed (${SUCCESS_RATE}% success rate)"
fi

# Update monitoring data with final results
python3 -c "
import json
data = json.load(open('$MONITOR_DATA'))
data['monitoring_end'] = '$(date -Iseconds)'
data['total_checks'] = $TOTAL_CHECKS
data['healthy_checks'] = $HEALTHY_CHECKS
data['success_rate'] = $SUCCESS_RATE
data['final_status'] = '$MONITOR_STATUS'
json.dump(data, open('$MONITOR_DATA', 'w'), indent=2)
"

# Create monitoring report
MONITOR_REPORT="$STAGING_DIR/environment_monitor_report.json"

cat > "$MONITOR_REPORT" << EOF
{
  "monitoring_type": "environment_health",
  "site_name": "$SITE_NAME",
  "site_display_name": "$SITE_DISPLAY_NAME",
  "staging_environment_id": "$STAGING_ENVIRONMENT_ID",
  "monitoring_start": "$(python3 -c "import json; print(json.load(open('$MONITOR_DATA'))['monitoring_start'])")",
  "monitoring_end": "$(date -Iseconds)",
  "duration_seconds": $MONITOR_DURATION,
  "total_checks": $TOTAL_CHECKS,
  "healthy_checks": $HEALTHY_CHECKS,
  "success_rate": $SUCCESS_RATE,
  "final_status": "$MONITOR_STATUS",
  "recommendations": [
    $(if [ $SUCCESS_RATE -ge 95 ]; then
        echo '"Environment is healthy and stable"'
    elif [ $SUCCESS_RATE -ge 80 ]; then
        echo '"Environment has minor issues, monitor closely"'
    else
        echo '"Environment has significant issues, consider rollback"'
    fi)
  ],
  "monitor_log": "$MONITOR_LOG",
  "monitor_data": "$MONITOR_DATA"
}
EOF

log_info "Environment monitoring report saved to: $MONITOR_REPORT"
log_info "Environment monitoring data saved to: $MONITOR_DATA"
log_info "Environment monitoring log saved to: $MONITOR_LOG"

echo ""
echo "=========================================="
echo "ENVIRONMENT MONITORING SUMMARY"
echo "=========================================="
echo "Site: $SITE_DISPLAY_NAME ($SITE_NAME)"
echo "Environment: $STAGING_ENVIRONMENT_ID"
echo "Duration: ${MONITOR_DURATION}s"
echo "Checks: $TOTAL_CHECKS"
echo "Success Rate: ${SUCCESS_RATE}%"
echo "Status: $([ "$MONITOR_STATUS" == "success" ] && echo "✅ SUCCESS" || [ "$MONITOR_STATUS" == "warning" ] && echo "⚠️ WARNING" || echo "❌ FAILURE")"
echo "Report: $MONITOR_REPORT"
echo "Data: $MONITOR_DATA"
echo "Log: $MONITOR_LOG"
echo "=========================================="

# Exit with appropriate code
if [[ "$MONITOR_STATUS" == "failure" ]]; then
    exit 1
fi
