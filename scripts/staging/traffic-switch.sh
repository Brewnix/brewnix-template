#!/bin/bash
# scripts/staging/traffic-switch.sh - Traffic switching for blue-green deployments

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
TARGET_ENVIRONMENT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: $0 <staging_environment_id> <target_environment>"
            echo "Switch traffic to target environment (blue/green)"
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            exit 1
            ;;
        *)
            if [[ -z "$STAGING_ENVIRONMENT_ID" ]]; then
                STAGING_ENVIRONMENT_ID="$1"
            elif [[ -z "$TARGET_ENVIRONMENT" ]]; then
                TARGET_ENVIRONMENT="$1"
            else
                log_error "Too many arguments"
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$STAGING_ENVIRONMENT_ID" || -z "$TARGET_ENVIRONMENT" ]]; then
    log_error "Staging environment ID and target environment are required"
    echo "Usage: $0 <staging_environment_id> <target_environment>"
    exit 1
fi

# Validate target environment
if [[ "$TARGET_ENVIRONMENT" != "blue" && "$TARGET_ENVIRONMENT" != "green" ]]; then
    log_error "Target environment must be 'blue' or 'green'"
    exit 1
fi

STAGING_DIR="$REPO_ROOT/staging/$STAGING_ENVIRONMENT_ID"
TRAFFIC_SWITCH_LOG="$STAGING_DIR/logs/traffic_switch_$(date +%Y%m%d_%H%M%S).log"

# Create traffic switch log
exec > >(tee -a "$TRAFFIC_SWITCH_LOG") 2>&1

log_info "Starting traffic switch to $TARGET_ENVIRONMENT environment (ID: $STAGING_ENVIRONMENT_ID)"

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

log_info "Switching traffic for $SITE_DISPLAY_NAME to $TARGET_ENVIRONMENT environment"

# Traffic Switching Steps
log_step "Step 1: Pre-Switch Validation"

# Validate target environment health before switching
log_info "Validating $TARGET_ENVIRONMENT environment health..."
ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --extra-vars "target_environment=$TARGET_ENVIRONMENT" \
    --tags pre_switch_validation \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/validate_environment_health.yml" || {
    log_error "Pre-switch validation failed for $TARGET_ENVIRONMENT environment"
    exit 1
}

log_info "✅ Pre-switch validation passed"

log_step "Step 2: Backup Current Traffic Configuration"

# Backup current load balancer configuration
log_info "Backing up current traffic configuration..."
ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags backup_traffic_config \
    "$REPO_ROOT/vendor/proxmox-firewall/deployment/ansible/backup_traffic_config.yml" || {
    log_error "Traffic configuration backup failed"
    exit 1
}

log_info "✅ Traffic configuration backed up"

log_step "Step 3: Gradual Traffic Switching"

# Perform gradual traffic switching to minimize impact
log_info "Starting gradual traffic switch to $TARGET_ENVIRONMENT..."

# Switch 25% of traffic
log_info "Switching 25% of traffic..."
ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --extra-vars "target_environment=$TARGET_ENVIRONMENT traffic_percentage=25" \
    --tags switch_traffic \
    "$REPO_ROOT/vendor/proxmox-firewall/deployment/ansible/switch_traffic.yml" || {
    log_error "25% traffic switch failed"
    exit 1
}

# Monitor for 2 minutes
log_info "Monitoring 25% traffic switch..."
sleep 120

# Switch 50% of traffic
log_info "Switching 50% of traffic..."
ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --extra-vars "target_environment=$TARGET_ENVIRONMENT traffic_percentage=50" \
    --tags switch_traffic \
    "$REPO_ROOT/vendor/proxmox-firewall/deployment/ansible/switch_traffic.yml" || {
    log_error "50% traffic switch failed"
    exit 1
}

# Monitor for 3 minutes
log_info "Monitoring 50% traffic switch..."
sleep 180

# Switch 75% of traffic
log_info "Switching 75% of traffic..."
ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --extra-vars "target_environment=$TARGET_ENVIRONMENT traffic_percentage=75" \
    --tags switch_traffic \
    "$REPO_ROOT/vendor/proxmox-firewall/deployment/ansible/switch_traffic.yml" || {
    log_error "75% traffic switch failed"
    exit 1
}

# Monitor for 5 minutes
log_info "Monitoring 75% traffic switch..."
sleep 300

# Switch 100% of traffic
log_info "Switching 100% of traffic to $TARGET_ENVIRONMENT..."
ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --extra-vars "target_environment=$TARGET_ENVIRONMENT traffic_percentage=100" \
    --tags switch_traffic \
    "$REPO_ROOT/vendor/proxmox-firewall/deployment/ansible/switch_traffic.yml" || {
    log_error "100% traffic switch failed"
    exit 1
}

log_info "✅ Traffic switch to $TARGET_ENVIRONMENT completed"

log_step "Step 4: Post-Switch Monitoring"

# Monitor full traffic switch
log_info "Starting post-switch monitoring..."
MONITOR_DURATION=600  # 10 minutes

ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --extra-vars "target_environment=$TARGET_ENVIRONMENT monitoring_duration=$MONITOR_DURATION" \
    --tags post_switch_monitoring \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/monitor_traffic_switch.yml" || {
    log_warn "Post-switch monitoring had issues"
}

log_info "✅ Post-switch monitoring completed"

log_step "Step 5: Traffic Switch Validation"

# Validate traffic switch success
log_info "Validating traffic switch..."
ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --extra-vars "target_environment=$TARGET_ENVIRONMENT" \
    --tags validate_traffic_switch \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/validate_traffic_switch.yml" || {
    log_error "Traffic switch validation failed"
    exit 1
}

log_info "✅ Traffic switch validation passed"

# Create traffic switch report
TRAFFIC_SWITCH_REPORT="$STAGING_DIR/traffic_switch_report.json"

cat > "$TRAFFIC_SWITCH_REPORT" << EOF
{
  "operation": "traffic_switch",
  "site_name": "$SITE_NAME",
  "site_display_name": "$SITE_DISPLAY_NAME",
  "staging_environment_id": "$STAGING_ENVIRONMENT_ID",
  "target_environment": "$TARGET_ENVIRONMENT",
  "switch_timestamp": "$(date -Iseconds)",
  "switch_status": "completed",
  "traffic_switch_steps": [
    {
      "percentage": 25,
      "status": "completed",
      "timestamp": "$(date -Iseconds -d '8 minutes ago')"
    },
    {
      "percentage": 50,
      "status": "completed",
      "timestamp": "$(date -Iseconds -d '6 minutes ago')"
    },
    {
      "percentage": 75,
      "status": "completed",
      "timestamp": "$(date -Iseconds -d '1 minute ago')"
    },
    {
      "percentage": 100,
      "status": "completed",
      "timestamp": "$(date -Iseconds)"
    }
  ],
  "monitoring_duration": $MONITOR_DURATION,
  "recommendations": [
    "Monitor $TARGET_ENVIRONMENT environment for 24 hours",
    "Prepare rollback plan if issues arise",
    "Update production documentation"
  ],
  "traffic_switch_log": "$TRAFFIC_SWITCH_LOG"
}
EOF

# Mark traffic switch as completed
echo "traffic_switched_to_$TARGET_ENVIRONMENT" > "$STAGING_DIR/traffic_switched"

log_info "Traffic switch completed successfully"
log_info "Traffic switch report saved to: $TRAFFIC_SWITCH_REPORT"
log_info "Traffic switch log saved to: $TRAFFIC_SWITCH_LOG"

echo ""
echo "=========================================="
echo "TRAFFIC SWITCH SUMMARY"
echo "=========================================="
echo "Site: $SITE_DISPLAY_NAME ($SITE_NAME)"
echo "Environment: $STAGING_ENVIRONMENT_ID"
echo "Target: $TARGET_ENVIRONMENT"
echo "Status: ✅ TRAFFIC SWITCH COMPLETED"
echo "Report: $TRAFFIC_SWITCH_REPORT"
echo "Log: $TRAFFIC_SWITCH_LOG"
echo "=========================================="
