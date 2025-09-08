#!/bin/bash
# scripts/staging/generate-deployment-plan.sh - Generate production deployment plan

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
DEPLOYMENT_STRATEGY="blue-green"  # blue-green, canary, rolling

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: $0 <staging_environment_id> [options]"
            echo "Options:"
            echo "  --strategy <strategy>    Deployment strategy: blue-green, canary, rolling (default: blue-green)"
            exit 0
            ;;
        --strategy)
            DEPLOYMENT_STRATEGY="$2"
            shift 2
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
    echo "Usage: $0 <staging_environment_id> [options]"
    exit 1
fi

STAGING_DIR="$REPO_ROOT/staging/$STAGING_ENVIRONMENT_ID"
PLAN_LOG="$STAGING_DIR/logs/generate_deployment_plan_$(date +%Y%m%d_%H%M%S).log"
DEPLOYMENT_PLAN="$STAGING_DIR/production_deployment_plan.json"

# Create deployment plan log
exec > >(tee -a "$PLAN_LOG") 2>&1

log_info "Starting deployment plan generation for $STAGING_ENVIRONMENT_ID"
log_info "Deployment strategy: $DEPLOYMENT_STRATEGY"

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

log_info "Generating deployment plan for $SITE_DISPLAY_NAME"

# Check if environment is ready for production
if [[ ! -f "$STAGING_DIR/production_readiness_passed" ]]; then
    log_error "Environment is not ready for production deployment"
    log_error "Please run production-readiness-check.sh first"
    exit 1
fi

# Initialize deployment plan
cat > "$DEPLOYMENT_PLAN" << EOF
{
  "deployment_plan": {
    "site_name": "$SITE_NAME",
    "site_display_name": "$SITE_DISPLAY_NAME",
    "staging_environment_id": "$STAGING_ENVIRONMENT_ID",
    "deployment_strategy": "$DEPLOYMENT_STRATEGY",
    "plan_generated": "$(date -Iseconds)",
    "deployment_phases": [],
    "rollback_plan": {},
    "risk_assessment": {},
    "timeline": {}
  }
}
EOF

# Phase 1: Pre-deployment Preparation
log_step "Phase 1: Pre-deployment Preparation"

PRE_DEPLOYMENT_TASKS=()

# Backup current production environment
PRE_DEPLOYMENT_TASKS+=("{\"task\": \"backup_production\", \"description\": \"Create backup of current production environment\", \"duration_minutes\": 30, \"risk_level\": \"low\", \"automated\": true}")

# Validate production environment health
PRE_DEPLOYMENT_TASKS+=("{\"task\": \"validate_production_health\", \"description\": \"Validate current production environment health\", \"duration_minutes\": 15, \"risk_level\": \"low\", \"automated\": true}")

# Prepare deployment artifacts
PRE_DEPLOYMENT_TASKS+=("{\"task\": \"prepare_artifacts\", \"description\": \"Prepare and validate deployment artifacts\", \"duration_minutes\": 20, \"risk_level\": \"low\", \"automated\": true}")

# Notify stakeholders
PRE_DEPLOYMENT_TASKS+=("{\"task\": \"notify_stakeholders\", \"description\": \"Notify stakeholders of upcoming deployment\", \"duration_minutes\": 5, \"risk_level\": \"low\", \"automated\": false}")

# Phase 2: Deployment Execution
log_step "Phase 2: Deployment Execution"

DEPLOYMENT_TASKS=()

if [[ "$DEPLOYMENT_STRATEGY" == "blue-green" ]]; then
    # Blue-green deployment tasks
    DEPLOYMENT_TASKS+=("{\"task\": \"deploy_blue_environment\", \"description\": \"Deploy new version to blue environment\", \"duration_minutes\": 45, \"risk_level\": \"medium\", \"automated\": true}")
    DEPLOYMENT_TASKS+=("{\"task\": \"validate_blue_environment\", \"description\": \"Validate blue environment functionality\", \"duration_minutes\": 20, \"risk_level\": \"medium\", \"automated\": true}")
    DEPLOYMENT_TASKS+=("{\"task\": \"switch_traffic_to_blue\", \"description\": \"Switch traffic from green to blue environment\", \"duration_minutes\": 10, \"risk_level\": \"high\", \"automated\": true}")
    DEPLOYMENT_TASKS+=("{\"task\": \"monitor_blue_environment\", \"description\": \"Monitor blue environment for 30 minutes\", \"duration_minutes\": 30, \"risk_level\": \"medium\", \"automated\": true}")
    DEPLOYMENT_TASKS+=("{\"task\": \"complete_switch\", \"description\": \"Complete traffic switch and cleanup green environment\", \"duration_minutes\": 15, \"risk_level\": \"medium\", \"automated\": true}")

elif [[ "$DEPLOYMENT_STRATEGY" == "canary" ]]; then
    # Canary deployment tasks
    DEPLOYMENT_TASKS+=("{\"task\": \"deploy_canary_group\", \"description\": \"Deploy new version to initial canary group (10%)\", \"duration_minutes\": 30, \"risk_level\": \"medium\", \"automated\": true}")
    DEPLOYMENT_TASKS+=("{\"task\": \"monitor_canary_initial\", \"description\": \"Monitor initial canary group for 15 minutes\", \"duration_minutes\": 15, \"risk_level\": \"medium\", \"automated\": true}")
    DEPLOYMENT_TASKS+=("{\"task\": \"expand_canary_25\", \"description\": \"Expand canary to 25% of traffic\", \"duration_minutes\": 20, \"risk_level\": \"medium\", \"automated\": true}")
    DEPLOYMENT_TASKS+=("{\"task\": \"monitor_canary_25\", \"description\": \"Monitor 25% canary deployment for 20 minutes\", \"duration_minutes\": 20, \"risk_level\": \"medium\", \"automated\": true}")
    DEPLOYMENT_TASKS+=("{\"task\": \"expand_canary_50\", \"description\": \"Expand canary to 50% of traffic\", \"duration_minutes\": 25, \"risk_level\": \"high\", \"automated\": true}")
    DEPLOYMENT_TASKS+=("{\"task\": \"monitor_canary_50\", \"description\": \"Monitor 50% canary deployment for 30 minutes\", \"duration_minutes\": 30, \"risk_level\": \"high\", \"automated\": true}")
    DEPLOYMENT_TASKS+=("{\"task\": \"complete_canary_rollout\", \"description\": \"Complete canary rollout to 100%\", \"duration_minutes\": 20, \"risk_level\": \"high\", \"automated\": true}")

elif [[ "$DEPLOYMENT_STRATEGY" == "rolling" ]]; then
    # Rolling deployment tasks
    DEPLOYMENT_TASKS+=("{\"task\": \"rolling_update_batch1\", \"description\": \"Update first batch of servers (25%)\", \"duration_minutes\": 35, \"risk_level\": \"medium\", \"automated\": true}")
    DEPLOYMENT_TASKS+=("{\"task\": \"monitor_batch1\", \"description\": \"Monitor first batch for 10 minutes\", \"duration_minutes\": 10, \"risk_level\": \"medium\", \"automated\": true}")
    DEPLOYMENT_TASKS+=("{\"task\": \"rolling_update_batch2\", \"description\": \"Update second batch of servers (50% total)\", \"duration_minutes\": 40, \"risk_level\": \"high\", \"automated\": true}")
    DEPLOYMENT_TASKS+=("{\"task\": \"monitor_batch2\", \"description\": \"Monitor second batch for 15 minutes\", \"duration_minutes\": 15, \"risk_level\": \"high\", \"automated\": true}")
    DEPLOYMENT_TASKS+=("{\"task\": \"rolling_update_batch3\", \"description\": \"Update third batch of servers (75% total)\", \"duration_minutes\": 45, \"risk_level\": \"high\", \"automated\": true}")
    DEPLOYMENT_TASKS+=("{\"task\": \"monitor_batch3\", \"description\": \"Monitor third batch for 20 minutes\", \"duration_minutes\": 20, \"risk_level\": \"high\", \"automated\": true}")
    DEPLOYMENT_TASKS+=("{\"task\": \"rolling_update_final\", \"description\": \"Update final batch of servers (100%)\", \"duration_minutes\": 35, \"risk_level\": \"high\", \"automated\": true}")
fi

# Phase 3: Post-deployment Validation
log_step "Phase 3: Post-deployment Validation"

POST_DEPLOYMENT_TASKS=()

# Validate deployment success
POST_DEPLOYMENT_TASKS+=("{\"task\": \"validate_deployment\", \"description\": \"Validate successful deployment and functionality\", \"duration_minutes\": 20, \"risk_level\": \"medium\", \"automated\": true}")

# Performance validation
POST_DEPLOYMENT_TASKS+=("{\"task\": \"performance_validation\", \"description\": \"Run performance validation tests\", \"duration_minutes\": 30, \"risk_level\": \"low\", \"automated\": true}")

# Security validation
POST_DEPLOYMENT_TASKS+=("{\"task\": \"security_validation\", \"description\": \"Run security validation checks\", \"duration_minutes\": 25, \"risk_level\": \"low\", \"automated\": true}")

# Phase 4: Go-live and Monitoring
log_step "Phase 4: Go-live and Monitoring"

GO_LIVE_TASKS=()

# Announce successful deployment
GO_LIVE_TASKS+=("{\"task\": \"announce_deployment\", \"description\": \"Announce successful deployment to stakeholders\", \"duration_minutes\": 5, \"risk_level\": \"low\", \"automated\": false}")

# Extended monitoring
GO_LIVE_TASKS+=("{\"task\": \"extended_monitoring\", \"description\": \"Monitor deployment for 2 hours post-go-live\", \"duration_minutes\": 120, \"risk_level\": \"low\", \"automated\": true}")

# Create rollback plan
log_step "Creating rollback plan"

ROLLBACK_TASKS=()

if [[ "$DEPLOYMENT_STRATEGY" == "blue-green" ]]; then
    ROLLBACK_TASKS+=("{\"task\": \"switch_traffic_back\", \"description\": \"Switch traffic back to previous environment\", \"duration_minutes\": 10, \"risk_level\": \"high\", \"automated\": true}")
    ROLLBACK_TASKS+=("{\"task\": \"validate_rollback\", \"description\": \"Validate rollback success\", \"duration_minutes\": 15, \"risk_level\": \"medium\", \"automated\": true}")
elif [[ "$DEPLOYMENT_STRATEGY" == "canary" ]]; then
    ROLLBACK_TASKS+=("{\"task\": \"rollback_canary\", \"description\": \"Rollback canary deployment to previous version\", \"duration_minutes\": 20, \"risk_level\": \"high\", \"automated\": true}")
    ROLLBACK_TASKS+=("{\"task\": \"validate_rollback\", \"description\": \"Validate rollback success\", \"duration_minutes\": 15, \"risk_level\": \"medium\", \"automated\": true}")
elif [[ "$DEPLOYMENT_STRATEGY" == "rolling" ]]; then
    ROLLBACK_TASKS+=("{\"task\": \"rolling_rollback\", \"description\": \"Perform rolling rollback to previous version\", \"duration_minutes\": 60, \"risk_level\": \"high\", \"automated\": true}")
    ROLLBACK_TASKS+=("{\"task\": \"validate_rollback\", \"description\": \"Validate rollback success\", \"duration_minutes\": 20, \"risk_level\": \"medium\", \"automated\": true}")
fi

# Calculate timeline and risks
log_step "Calculating deployment timeline and risk assessment"

# Calculate total duration
PRE_DEPLOY_DURATION=$(printf '%s\n' "${PRE_DEPLOYMENT_TASKS[@]}" | jq -r 'fromjson? | .duration_minutes' | paste -sd+ | bc || echo "0")
DEPLOY_DURATION=$(printf '%s\n' "${DEPLOYMENT_TASKS[@]}" | jq -r 'fromjson? | .duration_minutes' | paste -sd+ | bc || echo "0")
POST_DEPLOY_DURATION=$(printf '%s\n' "${POST_DEPLOYMENT_TASKS[@]}" | jq -r 'fromjson? | .duration_minutes' | paste -sd+ | bc || echo "0")
GO_LIVE_DURATION=$(printf '%s\n' "${GO_LIVE_TASKS[@]}" | jq -r 'fromjson? | .duration_minutes' | paste -sd+ | bc || echo "0")
ROLLBACK_DURATION=$(printf '%s\n' "${ROLLBACK_TASKS[@]}" | jq -r 'fromjson? | .duration_minutes' | paste -sd+ | bc || echo "0")

TOTAL_DURATION=$((PRE_DEPLOY_DURATION + DEPLOY_DURATION + POST_DEPLOY_DURATION + GO_LIVE_DURATION))

# Risk assessment
ALL_DEPLOY_TASKS_JSON=$(printf '%s\n' "${DEPLOYMENT_TASKS[@]}" "${ROLLBACK_TASKS[@]}" | jq -s '.')
HIGH_RISK_TASKS=$(echo "$ALL_DEPLOY_TASKS_JSON" | jq '[.[] | fromjson? | select(.risk_level == "high")] | length')
MEDIUM_RISK_TASKS=$(echo "$ALL_DEPLOY_TASKS_JSON" | jq '[.[] | fromjson? | select(.risk_level == "medium")] | length')

if [[ $HIGH_RISK_TASKS -gt 0 ]]; then
    OVERALL_RISK="high"
elif [[ $MEDIUM_RISK_TASKS -gt 2 ]]; then
    OVERALL_RISK="medium"
else
    OVERALL_RISK="low"
fi

# Update deployment plan
python3 -c "
import json
import sys
data = json.load(open('$DEPLOYMENT_PLAN'))

# Convert bash arrays to Python lists
pre_deploy_tasks = [json.loads(task) for task in sys.argv[1].split('|') if task]
deploy_tasks = [json.loads(task) for task in sys.argv[2].split('|') if task]
post_deploy_tasks = [json.loads(task) for task in sys.argv[3].split('|') if task]
go_live_tasks = [json.loads(task) for task in sys.argv[4].split('|') if task]
rollback_tasks = [json.loads(task) for task in sys.argv[5].split('|') if task]

data['deployment_plan']['deployment_phases'] = [
    {
        'phase': 'pre_deployment',
        'description': 'Pre-deployment preparation',
        'tasks': pre_deploy_tasks,
        'duration_minutes': $PRE_DEPLOY_DURATION
    },
    {
        'phase': 'deployment',
        'description': 'Main deployment execution',
        'tasks': deploy_tasks,
        'duration_minutes': $DEPLOY_DURATION
    },
    {
        'phase': 'post_deployment',
        'description': 'Post-deployment validation',
        'tasks': post_deploy_tasks,
        'duration_minutes': $POST_DEPLOY_DURATION
    },
    {
        'phase': 'go_live',
        'description': 'Go-live and monitoring',
        'tasks': go_live_tasks,
        'duration_minutes': $GO_LIVE_DURATION
    }
]

data['deployment_plan']['rollback_plan'] = {
    'description': 'Rollback plan for $DEPLOYMENT_STRATEGY deployment',
    'tasks': rollback_tasks,
    'estimated_duration_minutes': $ROLLBACK_DURATION,
    'risk_level': '$OVERALL_RISK'
}

data['deployment_plan']['risk_assessment'] = {
    'overall_risk_level': '$OVERALL_RISK',
    'high_risk_tasks': $HIGH_RISK_TASKS,
    'medium_risk_tasks': $MEDIUM_RISK_TASKS,
    'automated_tasks': len([t for t in deploy_tasks if t.get('automated', False)]),
    'manual_tasks': len([t for t in deploy_tasks if not t.get('automated', False)])
}

data['deployment_plan']['timeline'] = {
    'total_estimated_duration_minutes': $TOTAL_DURATION,
    'pre_deployment_duration': $PRE_DEPLOY_DURATION,
    'deployment_duration': $DEPLOY_DURATION,
    'post_deployment_duration': $POST_DEPLOY_DURATION,
    'go_live_duration': $GO_LIVE_DURATION,
    'rollback_duration': $ROLLBACK_DURATION
}

json.dump(data, open('$DEPLOYMENT_PLAN', 'w'), indent=2)
" "$(printf '%s|' "${PRE_DEPLOYMENT_TASKS[@]}")" "$(printf '%s|' "${DEPLOYMENT_TASKS[@]}")" "$(printf '%s|' "${POST_DEPLOYMENT_TASKS[@]}")" "$(printf '%s|' "${GO_LIVE_TASKS[@]}")" "$(printf '%s|' "${ROLLBACK_TASKS[@]}")"

log_info "Deployment plan generated: $DEPLOYMENT_PLAN"

# Create deployment plan summary
DEPLOYMENT_SUMMARY="$STAGING_DIR/deployment_plan_summary.md"

cat > "$DEPLOYMENT_SUMMARY" << EOF
# Production Deployment Plan

## Overview
- **Site**: $SITE_DISPLAY_NAME ($SITE_NAME)
- **Environment**: $STAGING_ENVIRONMENT_ID
- **Strategy**: $DEPLOYMENT_STRATEGY
- **Generated**: $(date -Iseconds)

## Timeline Summary
- **Total Duration**: ${TOTAL_DURATION} minutes (~$((TOTAL_DURATION / 60)) hours $((TOTAL_DURATION % 60)) minutes)
- **Pre-deployment**: ${PRE_DEPLOY_DURATION} minutes
- **Deployment**: ${DEPLOY_DURATION} minutes
- **Post-deployment**: ${POST_DEPLOY_DURATION} minutes
- **Go-live**: ${GO_LIVE_DURATION} minutes

## Risk Assessment
- **Overall Risk**: $OVERALL_RISK
- **High Risk Tasks**: $HIGH_RISK_TASKS
- **Medium Risk Tasks**: $MEDIUM_RISK_TASKS

## Deployment Phases

### Phase 1: Pre-deployment Preparation
$(printf '%s\n' "${PRE_DEPLOYMENT_TASKS[@]}" | jq -r 'fromjson? | "- **\(.task)**: \(.description) (\(.duration_minutes)min, \(.risk_level) risk)"' 2>/dev/null || echo "- Tasks will be listed in JSON plan")

### Phase 2: Deployment Execution
$(printf '%s\n' "${DEPLOYMENT_TASKS[@]}" | jq -r 'fromjson? | "- **\(.task)**: \(.description) (\(.duration_minutes)min, \(.risk_level) risk)"' 2>/dev/null || echo "- Tasks will be listed in JSON plan")

### Phase 3: Post-deployment Validation
$(printf '%s\n' "${POST_DEPLOYMENT_TASKS[@]}" | jq -r 'fromjson? | "- **\(.task)**: \(.description) (\(.duration_minutes)min, \(.risk_level) risk)"' 2>/dev/null || echo "- Tasks will be listed in JSON plan")

### Phase 4: Go-live and Monitoring
$(printf '%s\n' "${GO_LIVE_TASKS[@]}" | jq -r 'fromjson? | "- **\(.task)**: \(.description) (\(.duration_minutes)min, \(.risk_level) risk)"' 2>/dev/null || echo "- Tasks will be listed in JSON plan")

## Rollback Plan
$(printf '%s\n' "${ROLLBACK_TASKS[@]}" | jq -r 'fromjson? | "- **\(.task)**: \(.description) (\(.duration_minutes)min, \(.risk_level) risk)"' 2>/dev/null || echo "- Rollback tasks will be listed in JSON plan")

## Success Criteria
- All automated tasks complete successfully
- No critical alerts during deployment
- Application health checks pass
- Performance metrics within acceptable ranges
- Stakeholder approval for manual tasks

## Emergency Contacts
- DevOps Team: [contact information]
- Development Team: [contact information]
- Business Stakeholders: [contact information]

## Files Generated
- Deployment Plan (JSON): $DEPLOYMENT_PLAN
- Deployment Plan (Markdown): $DEPLOYMENT_SUMMARY
- Deployment Log: $PLAN_LOG
EOF

log_info "Deployment plan summary generated: $DEPLOYMENT_SUMMARY"

echo ""
echo "=========================================="
echo "PRODUCTION DEPLOYMENT PLAN"
echo "=========================================="
echo "Site: $SITE_DISPLAY_NAME ($SITE_NAME)"
echo "Environment: $STAGING_ENVIRONMENT_ID"
echo "Strategy: $DEPLOYMENT_STRATEGY"
echo ""
echo "Timeline:"
echo "  Total Duration: ${TOTAL_DURATION} minutes (~$((TOTAL_DURATION / 60)) hours $((TOTAL_DURATION % 60)) minutes)"
echo "  Pre-deployment: ${PRE_DEPLOY_DURATION} minutes"
echo "  Deployment: ${DEPLOY_DURATION} minutes"
echo "  Post-deployment: ${POST_DEPLOY_DURATION} minutes"
echo "  Go-live: ${GO_LIVE_DURATION} minutes"
echo ""
echo "Risk Assessment:"
echo "  Overall Risk: $OVERALL_RISK"
echo "  High Risk Tasks: $HIGH_RISK_TASKS"
echo "  Medium Risk Tasks: $MEDIUM_RISK_TASKS"
echo ""
echo "Files Generated:"
echo "  JSON Plan: $DEPLOYMENT_PLAN"
echo "  Markdown Summary: $DEPLOYMENT_SUMMARY"
echo "  Log: $PLAN_LOG"
echo "=========================================="

log_info "Deployment plan generation completed successfully"
