#!/bin/bash
# scripts/staging/monitor-canary.sh - Monitor canary deployment

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
MONITOR_DURATION="600"

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: $0 <staging_environment_id> [monitor_duration_seconds]"
            echo "Monitor canary deployment for specified duration"
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
CANARY_MONITOR_LOG="$STAGING_DIR/logs/canary_monitor_$(date +%Y%m%d_%H%M%S).log"

# Create canary monitor log
exec > >(tee -a "$CANARY_MONITOR_LOG") 2>&1

log_info "Starting canary monitoring for $STAGING_ENVIRONMENT_ID (Duration: ${MONITOR_DURATION}s)"

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

# Get canary percentage from canary deployment report
CANARY_PERCENTAGE=10
if [[ -f "$STAGING_DIR/canary_deployment_report.json" ]]; then
    CANARY_PERCENTAGE=$(python3 -c "import json; print(json.load(open('$STAGING_DIR/canary_deployment_report.json')).get('canary_percentage', 10))")
fi

log_info "Monitoring canary deployment for $SITE_DISPLAY_NAME (${CANARY_PERCENTAGE}% traffic)"

# Initialize canary monitoring data
CANARY_MONITOR_DATA="$STAGING_DIR/canary_monitor_data.json"
cat > "$CANARY_MONITOR_DATA" << EOF
{
  "monitoring_type": "canary_deployment",
  "site_name": "$SITE_NAME",
  "site_display_name": "$SITE_DISPLAY_NAME",
  "staging_environment_id": "$STAGING_ENVIRONMENT_ID",
  "canary_percentage": $CANARY_PERCENTAGE,
  "monitoring_start": "$(date -Iseconds)",
  "duration_seconds": $MONITOR_DURATION,
  "check_interval": 30,
  "metrics": []
}
EOF

# Monitoring loop
END_TIME=$(( $(date +%s) + MONITOR_DURATION ))
CHECK_COUNT=0

log_step "Starting canary monitoring loop (Duration: ${MONITOR_DURATION}s, Interval: 30s)"

while [ "$(date +%s)" -lt "$END_TIME" ]; do
    CHECK_COUNT=$((CHECK_COUNT + 1))
    CHECK_TIMESTAMP=$(date -Iseconds)

    log_info "Canary monitoring check #$CHECK_COUNT at $CHECK_TIMESTAMP"

    # Collect canary-specific metrics
    CANARY_METRICS="$STAGING_DIR/canary_metrics_$CHECK_COUNT.json"

    # Run canary metrics collection
    if ansible-playbook \
        --inventory "$ANSIBLE_INVENTORY" \
        --limit "$SITE_NAME" \
        --extra-vars "canary_percentage=$CANARY_PERCENTAGE output_file=$CANARY_METRICS" \
        --tags collect_canary_metrics \
        "$REPO_ROOT/vendor/proxmox-firewall/tests/collect_canary_metrics.yml" >/dev/null 2>&1; then

        # Parse metrics if collection was successful
        if [[ -f "$CANARY_METRICS" ]]; then
            REQUESTS_TOTAL=$(python3 -c "import json; print(json.load(open('$CANARY_METRICS')).get('requests_total', 0))" 2>/dev/null || echo "0")
            REQUESTS_SUCCESS=$(python3 -c "import json; print(json.load(open('$CANARY_METRICS')).get('requests_success', 0))" 2>/dev/null || echo "0")
            REQUESTS_ERROR=$(python3 -c "import json; print(json.load(open('$CANARY_METRICS')).get('requests_error', 0))" 2>/dev/null || echo "0")
            RESPONSE_TIME_AVG=$(python3 -c "import json; print(json.load(open('$CANARY_METRICS')).get('response_time_avg', 0))" 2>/dev/null || echo "0")
            ERROR_RATE=$(python3 -c "import json; print(json.load(open('$CANARY_METRICS')).get('error_rate', 0))" 2>/dev/null || echo "0")

            SUCCESS_RATE=$(( REQUESTS_TOTAL > 0 ? (REQUESTS_SUCCESS * 100) / REQUESTS_TOTAL : 0 ))

            log_info "Canary metrics - Total: $REQUESTS_TOTAL, Success: $REQUESTS_SUCCESS, Errors: $REQUESTS_ERROR, Success Rate: ${SUCCESS_RATE}%, Avg Response: ${RESPONSE_TIME_AVG}ms"
        else
            REQUESTS_TOTAL=0
            REQUESTS_SUCCESS=0
            REQUESTS_ERROR=0
            RESPONSE_TIME_AVG=0
            ERROR_RATE=0
            SUCCESS_RATE=0
        fi
    else
        log_warn "Failed to collect canary metrics"
        REQUESTS_TOTAL=0
        REQUESTS_SUCCESS=0
        REQUESTS_ERROR=0
        RESPONSE_TIME_AVG=0
        ERROR_RATE=0
        SUCCESS_RATE=0
    fi

    # Determine canary health status
    CANARY_STATUS="unknown"
    if [ $SUCCESS_RATE -ge 95 ] && [ "$ERROR_RATE" != "null" ] && [ "$(echo "$ERROR_RATE < 5" | bc -l 2>/dev/null || echo "1")" = "1" ]; then
        CANARY_STATUS="healthy"
        log_info "✅ Canary status: healthy"
    elif [ $SUCCESS_RATE -ge 80 ]; then
        CANARY_STATUS="warning"
        log_warn "⚠️ Canary status: warning"
    else
        CANARY_STATUS="unhealthy"
        log_error "❌ Canary status: unhealthy"
    fi

    # Add metrics to monitoring data
    python3 -c "
import json
data = json.load(open('$CANARY_MONITOR_DATA'))
data['metrics'].append({
    'check_number': $CHECK_COUNT,
    'timestamp': '$CHECK_TIMESTAMP',
    'requests_total': $REQUESTS_TOTAL,
    'requests_success': $REQUESTS_SUCCESS,
    'requests_error': $REQUESTS_ERROR,
    'success_rate': $SUCCESS_RATE,
    'error_rate': $ERROR_RATE,
    'response_time_avg': $RESPONSE_TIME_AVG,
    'canary_status': '$CANARY_STATUS'
})
json.dump(data, open('$CANARY_MONITOR_DATA', 'w'), indent=2)
"

    # Wait for next check (30 seconds)
    sleep 30
done

log_step "Canary monitoring completed"

# Analyze canary monitoring results
log_info "Analyzing canary monitoring results..."

TOTAL_CHECKS=$CHECK_COUNT
HEALTHY_CHECKS=$(python3 -c "
import json
data = json.load(open('$CANARY_MONITOR_DATA'))
healthy = sum(1 for metric in data['metrics'] if metric['canary_status'] == 'healthy')
print(healthy)
")

WARNING_CHECKS=$(python3 -c "
import json
data = json.load(open('$CANARY_MONITOR_DATA'))
warning = sum(1 for metric in data['metrics'] if metric['canary_status'] == 'warning')
print(warning)
")

UNHEALTHY_CHECKS=$(python3 -c "
import json
data = json.load(open('$CANARY_MONITOR_DATA'))
unhealthy = sum(1 for metric in data['metrics'] if metric['canary_status'] == 'unhealthy')
print(unhealthy)
")

OVERALL_SUCCESS_RATE=$(( TOTAL_CHECKS > 0 ? (HEALTHY_CHECKS * 100) / TOTAL_CHECKS : 0 ))

log_info "Canary Monitoring Results:"
log_info "  Total checks: $TOTAL_CHECKS"
log_info "  Healthy checks: $HEALTHY_CHECKS"
log_info "  Warning checks: $WARNING_CHECKS"
log_info "  Unhealthy checks: $UNHEALTHY_CHECKS"
log_info "  Overall success rate: ${OVERALL_SUCCESS_RATE}%"

# Determine final canary monitoring status
if [ $OVERALL_SUCCESS_RATE -ge 90 ] && [ $UNHEALTHY_CHECKS -eq 0 ]; then
    CANARY_MONITOR_STATUS="success"
    log_info "✅ Canary monitoring successful (${OVERALL_SUCCESS_RATE}% success rate)"
elif [ $OVERALL_SUCCESS_RATE -ge 75 ]; then
    CANARY_MONITOR_STATUS="warning"
    log_warn "⚠️ Canary monitoring completed with warnings (${OVERALL_SUCCESS_RATE}% success rate)"
else
    CANARY_MONITOR_STATUS="failure"
    log_error "❌ Canary monitoring failed (${OVERALL_SUCCESS_RATE}% success rate)"
fi

# Calculate average metrics
AVG_RESPONSE_TIME=$(python3 -c "
import json
data = json.load(open('$CANARY_MONITOR_DATA'))
times = [m['response_time_avg'] for m in data['metrics'] if m['response_time_avg'] > 0]
print(sum(times) // len(times) if times else 0)
")

AVG_ERROR_RATE=$(python3 -c "
import json
data = json.load(open('$CANARY_MONITOR_DATA'))
rates = [m['error_rate'] for m in data['metrics'] if m['error_rate'] > 0]
print(sum(rates) // len(rates) if rates else 0)
")

# Update monitoring data with final results
python3 -c "
import json
data = json.load(open('$CANARY_MONITOR_DATA'))
data['monitoring_end'] = '$(date -Iseconds)'
data['total_checks'] = $TOTAL_CHECKS
data['healthy_checks'] = $HEALTHY_CHECKS
data['warning_checks'] = $WARNING_CHECKS
data['unhealthy_checks'] = $UNHEALTHY_CHECKS
data['overall_success_rate'] = $OVERALL_SUCCESS_RATE
data['average_response_time'] = $AVG_RESPONSE_TIME
data['average_error_rate'] = $AVG_ERROR_RATE
data['final_status'] = '$CANARY_MONITOR_STATUS'
json.dump(data, open('$CANARY_MONITOR_DATA', 'w'), indent=2)
"

# Create canary monitoring report
CANARY_MONITOR_REPORT="$STAGING_DIR/canary_monitor_report.json"

cat > "$CANARY_MONITOR_REPORT" << EOF
{
  "monitoring_type": "canary_deployment",
  "site_name": "$SITE_NAME",
  "site_display_name": "$SITE_DISPLAY_NAME",
  "staging_environment_id": "$STAGING_ENVIRONMENT_ID",
  "canary_percentage": $CANARY_PERCENTAGE,
  "monitoring_start": "$(python3 -c "import json; print(json.load(open('$CANARY_MONITOR_DATA'))['monitoring_start'])")",
  "monitoring_end": "$(date -Iseconds)",
  "duration_seconds": $MONITOR_DURATION,
  "total_checks": $TOTAL_CHECKS,
  "healthy_checks": $HEALTHY_CHECKS,
  "warning_checks": $WARNING_CHECKS,
  "unhealthy_checks": $UNHEALTHY_CHECKS,
  "overall_success_rate": $OVERALL_SUCCESS_RATE,
  "average_response_time": $AVG_RESPONSE_TIME,
  "average_error_rate": $AVG_ERROR_RATE,
  "final_status": "$CANARY_MONITOR_STATUS",
  "recommendations": [
    $(if [ $OVERALL_SUCCESS_RATE -ge 90 ] && [ $UNHEALTHY_CHECKS -eq 0 ]; then
        echo '"Canary deployment is performing well, consider increasing traffic"'
    elif [ $OVERALL_SUCCESS_RATE -ge 75 ]; then
        echo '"Canary deployment has some issues, monitor closely before increasing traffic"'
    else
        echo '"Canary deployment has significant issues, consider rollback"'
    fi)
  ],
  "canary_monitor_log": "$CANARY_MONITOR_LOG",
  "canary_monitor_data": "$CANARY_MONITOR_DATA"
}
EOF

log_info "Canary monitoring report saved to: $CANARY_MONITOR_REPORT"
log_info "Canary monitoring data saved to: $CANARY_MONITOR_DATA"
log_info "Canary monitoring log saved to: $CANARY_MONITOR_LOG"

echo ""
echo "=========================================="
echo "CANARY MONITORING SUMMARY"
echo "=========================================="
echo "Site: $SITE_DISPLAY_NAME ($SITE_NAME)"
echo "Environment: $STAGING_ENVIRONMENT_ID"
echo "Canary Traffic: ${CANARY_PERCENTAGE}%"
echo "Duration: ${MONITOR_DURATION}s"
echo "Checks: $TOTAL_CHECKS"
echo "Success Rate: ${OVERALL_SUCCESS_RATE}%"
echo "Avg Response Time: ${AVG_RESPONSE_TIME}ms"
echo "Avg Error Rate: ${AVG_ERROR_RATE}%"
echo "Status: $([ "$CANARY_MONITOR_STATUS" == "success" ] && echo "✅ SUCCESS" || [ "$CANARY_MONITOR_STATUS" == "warning" ] && echo "⚠️ WARNING" || echo "❌ FAILURE")"
echo "Report: $CANARY_MONITOR_REPORT"
echo "Data: $CANARY_MONITOR_DATA"
echo "Log: $CANARY_MONITOR_LOG"
echo "=========================================="

# Exit with appropriate code
if [[ "$CANARY_MONITOR_STATUS" == "failure" ]]; then
    exit 1
fi
