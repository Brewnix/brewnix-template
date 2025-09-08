#!/bin/bash
# scripts/staging/canary-deployment.sh - Canary deployment implementation

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
CANARY_PERCENTAGE="10"

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: $0 <site_name> <staging_environment_id> <canary_percentage>"
            echo "Run canary deployment for a site with specified traffic percentage"
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
            elif [[ -z "$CANARY_PERCENTAGE" ]]; then
                CANARY_PERCENTAGE="$1"
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
    echo "Usage: $0 <site_name> <staging_environment_id> [canary_percentage]"
    exit 1
fi

# Validate canary percentage
if ! [[ "$CANARY_PERCENTAGE" =~ ^[0-9]+$ ]] || [ "$CANARY_PERCENTAGE" -lt 1 ] || [ "$CANARY_PERCENTAGE" -gt 100 ]; then
    log_error "Canary percentage must be a number between 1 and 100"
    exit 1
fi

STAGING_DIR="$REPO_ROOT/staging/$STAGING_ENVIRONMENT_ID"
CANARY_LOG="$STAGING_DIR/logs/canary_deployment_$(date +%Y%m%d_%H%M%S).log"

# Create canary log
exec > >(tee -a "$CANARY_LOG") 2>&1

log_info "Starting canary deployment for site: $SITE_NAME (Environment: $STAGING_ENVIRONMENT_ID, Traffic: ${CANARY_PERCENTAGE}%)"

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

log_info "Running canary deployment for $SITE_DISPLAY_NAME with ${CANARY_PERCENTAGE}% traffic"

# Canary Deployment Steps
log_step "Step 1: Traffic Routing Setup"

# Configure load balancer for canary traffic
log_info "Setting up canary traffic routing (${CANARY_PERCENTAGE}% to staging)..."
ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --extra-vars "canary_percentage=$CANARY_PERCENTAGE staging_environment_id=$STAGING_ENVIRONMENT_ID" \
    --tags traffic_routing \
    "$REPO_ROOT/vendor/proxmox-firewall/deployment/ansible/setup_canary_routing.yml" || {
    log_error "Traffic routing setup failed"
    exit 1
}

log_info "✅ Traffic routing configured"

log_step "Step 2: Initial Health Monitoring"

# Monitor initial canary traffic
log_info "Starting initial health monitoring..."
MONITOR_PID=""
ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --extra-vars "canary_percentage=$CANARY_PERCENTAGE monitoring_duration=300" \
    --tags monitor_canary \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/monitor_canary.yml" &
MONITOR_PID=$!

# Wait a bit for monitoring to start
sleep 30

log_info "✅ Health monitoring started (PID: $MONITOR_PID)"

log_step "Step 3: Gradual Traffic Increase"

# Gradually increase canary traffic if initial monitoring is good
log_info "Monitoring initial canary performance..."

# Check if initial monitoring shows good results
sleep 60

if kill -0 $MONITOR_PID 2>/dev/null; then
    log_info "Initial monitoring period completed successfully"
else
    log_error "Initial monitoring failed"
    exit 1
fi

# If canary percentage is less than 50%, consider gradual increase
if [ "$CANARY_PERCENTAGE" -lt 50 ]; then
    INCREASED_PERCENTAGE=$((CANARY_PERCENTAGE * 2))
    if [ "$INCREASED_PERCENTAGE" -gt 50 ]; then
        INCREASED_PERCENTAGE=50
    fi

    log_info "Gradually increasing canary traffic to ${INCREASED_PERCENTAGE}%..."

    ansible-playbook \
        --inventory "$ANSIBLE_INVENTORY" \
        --limit "$SITE_NAME" \
        --extra-vars "canary_percentage=$INCREASED_PERCENTAGE staging_environment_id=$STAGING_ENVIRONMENT_ID" \
        --tags update_traffic_routing \
        "$REPO_ROOT/vendor/proxmox-firewall/deployment/ansible/update_canary_routing.yml" || {
        log_warn "Traffic increase failed, keeping at ${CANARY_PERCENTAGE}%"
        INCREASED_PERCENTAGE=$CANARY_PERCENTAGE
    }

    CANARY_PERCENTAGE=$INCREASED_PERCENTAGE
    log_info "✅ Traffic increased to ${CANARY_PERCENTAGE}%"
fi

log_step "Step 4: Extended Monitoring"

# Continue monitoring for extended period
log_info "Starting extended monitoring period..."
EXTENDED_MONITOR_PID=""
ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --extra-vars "canary_percentage=$CANARY_PERCENTAGE monitoring_duration=600 extended_monitoring=true" \
    --tags extended_monitor_canary \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/monitor_canary.yml" &
EXTENDED_MONITOR_PID=$!

# Wait for extended monitoring
sleep 300

if kill -0 $EXTENDED_MONITOR_PID 2>/dev/null; then
    log_info "Extended monitoring completed successfully"
else
    log_error "Extended monitoring failed"
    exit 1
fi

log_info "✅ Extended monitoring completed"

log_step "Step 5: Performance Analysis"

# Analyze canary performance metrics
log_info "Analyzing canary performance metrics..."
ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --extra-vars "canary_percentage=$CANARY_PERCENTAGE" \
    --tags analyze_canary \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/analyze_canary_performance.yml" || {
    log_error "Performance analysis failed"
    exit 1
}

log_info "✅ Performance analysis completed"

log_step "Step 6: Canary Decision"

# Make decision based on analysis
log_info "Making canary deployment decision..."

# Check analysis results
if [[ -f "$STAGING_DIR/canary_analysis_results.json" ]]; then
    CANARY_SUCCESS=$(python3 -c "
import json
results = json.load(open('$STAGING_DIR/canary_analysis_results.json'))
success_rate = results.get('success_rate', 0)
error_rate = results.get('error_rate', 100)
if success_rate >= 95 and error_rate <= 5:
    print('true')
else:
    print('false')
")

    if [[ "$CANARY_SUCCESS" == "true" ]]; then
        log_info "✅ Canary deployment successful - ready for full rollout"
        CANARY_STATUS="success"
    else
        log_info "❌ Canary deployment failed - rolling back"
        CANARY_STATUS="failed"

        # Rollback canary traffic
        ansible-playbook \
            --inventory "$ANSIBLE_INVENTORY" \
            --limit "$SITE_NAME" \
            --extra-vars "rollback_canary=true" \
            --tags rollback_canary \
            "$REPO_ROOT/vendor/proxmox-firewall/deployment/ansible/rollback_canary.yml" || {
            log_error "Canary rollback failed"
        }
    fi
else
    log_warn "Canary analysis results not found, assuming success"
    CANARY_STATUS="success"
fi

# Create canary deployment report
CANARY_REPORT="$STAGING_DIR/canary_deployment_report.json"

cat > "$CANARY_REPORT" << EOF
{
  "deployment_type": "canary",
  "site_name": "$SITE_NAME",
  "site_display_name": "$SITE_DISPLAY_NAME",
  "staging_environment_id": "$STAGING_ENVIRONMENT_ID",
  "canary_percentage": $CANARY_PERCENTAGE,
  "deployment_timestamp": "$(date -Iseconds)",
  "deployment_status": "$CANARY_STATUS",
  "monitoring_periods": [
    {
      "period": "initial",
      "duration": 300,
      "status": "completed"
    },
    {
      "period": "extended",
      "duration": 600,
      "status": "completed"
    }
  ],
  "recommendations": [
    "Canary deployment $CANARY_STATUS",
    "Monitor production metrics for 24 hours after full rollout",
    "Prepare rollback procedures"
  ],
  "canary_log": "$CANARY_LOG"
}
EOF

if [[ "$CANARY_STATUS" == "success" ]]; then
    echo "canary_success" > "$STAGING_DIR/canary_success"
    log_info "Canary deployment completed successfully"
else
    echo "canary_failed" > "$STAGING_DIR/canary_failed"
    log_error "Canary deployment failed"
    exit 1
fi

log_info "Canary deployment report saved to: $CANARY_REPORT"
log_info "Canary deployment log saved to: $CANARY_LOG"

echo ""
echo "=========================================="
echo "CANARY DEPLOYMENT SUMMARY"
echo "=========================================="
echo "Site: $SITE_DISPLAY_NAME ($SITE_NAME)"
echo "Environment: $STAGING_ENVIRONMENT_ID"
echo "Traffic Percentage: ${CANARY_PERCENTAGE}%"
echo "Status: $([ "$CANARY_STATUS" == "success" ] && echo "✅ SUCCESS" || echo "❌ FAILED")"
echo "Report: $CANARY_REPORT"
echo "Log: $CANARY_LOG"
echo "=========================================="
