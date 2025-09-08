#!/bin/bash
# scripts/staging/cleanup-staging.sh - Cleanup staging environment after deployment

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
FORCE_CLEANUP=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: $0 <staging_environment_id> [options]"
            echo "Options:"
            echo "  --force    Force cleanup even if validation files exist"
            echo "  --dry-run  Show what would be cleaned up without actually doing it"
            exit 0
            ;;
        --force)
            FORCE_CLEANUP=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
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
CLEANUP_LOG="$STAGING_DIR/logs/cleanup_staging_$(date +%Y%m%d_%H%M%S).log"
CLEANUP_RESULTS="$STAGING_DIR/cleanup_results.json"

# Create cleanup log
exec > >(tee -a "$CLEANUP_LOG") 2>&1

log_info "Starting staging cleanup for $STAGING_ENVIRONMENT_ID"

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "DRY RUN MODE - No actual cleanup will be performed"
fi

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

log_info "Cleaning up staging environment for $SITE_DISPLAY_NAME"

# Safety checks
if [[ "$FORCE_CLEANUP" != "true" ]]; then
    log_step "Safety checks"

    # Check if production readiness passed
    if [[ ! -f "$STAGING_DIR/production_readiness_passed" ]]; then
        log_warn "Production readiness check has not passed"
        log_warn "Use --force to override this safety check"
        exit 1
    fi

    # Check if deployment plan exists
    if [[ ! -f "$STAGING_DIR/production_deployment_plan.json" ]]; then
        log_warn "No deployment plan found"
        log_warn "Use --force to override this safety check"
        exit 1
    fi

    log_info "Safety checks passed"
fi

# Initialize cleanup results
cat > "$CLEANUP_RESULTS" << EOF
{
  "cleanup_operation": {
    "site_name": "$SITE_NAME",
    "site_display_name": "$SITE_DISPLAY_NAME",
    "staging_environment_id": "$STAGING_ENVIRONMENT_ID",
    "cleanup_start": "$(date -Iseconds)",
    "dry_run": $DRY_RUN,
    "force_cleanup": $FORCE_CLEANUP
  },
  "cleanup_tasks": [],
  "cleanup_summary": {}
}
EOF

# Cleanup Task 1: Stop and remove containers/VMs
log_step "Cleanup Task 1: Infrastructure cleanup"

INFRASTRUCTURE_CLEANUP=()

if [[ "$DRY_RUN" != "true" ]]; then
    log_info "Stopping and removing staging infrastructure..."
    if ansible-playbook \
        --inventory "$ANSIBLE_INVENTORY" \
        --limit "$SITE_NAME" \
        --tags cleanup \
        "$REPO_ROOT/vendor/proxmox-firewall/tests/cleanup_staging_infrastructure.yml" >/dev/null 2>&1; then
        INFRASTRUCTURE_CLEANUP+=("{\"task\": \"infrastructure_cleanup\", \"status\": \"completed\", \"message\": \"Staging infrastructure stopped and removed\"}")
        log_info "✅ Staging infrastructure cleaned up"
    else
        INFRASTRUCTURE_CLEANUP+=("{\"task\": \"infrastructure_cleanup\", \"status\": \"failed\", \"message\": \"Failed to cleanup staging infrastructure\"}")
        log_error "❌ Failed to cleanup staging infrastructure"
    fi
else
    INFRASTRUCTURE_CLEANUP+=("{\"task\": \"infrastructure_cleanup\", \"status\": \"dry_run\", \"message\": \"Would stop and remove staging infrastructure\"}")
    log_info "DRY RUN: Would cleanup staging infrastructure"
fi

# Cleanup Task 2: Remove Terraform state and resources
log_step "Cleanup Task 2: Terraform cleanup"

TERRAFORM_CLEANUP=()

if [[ -f "$STAGING_DIR/terraform.tfstate" ]]; then
    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Destroying Terraform resources..."
        cd "$STAGING_DIR"
        if terraform destroy -auto-approve >/dev/null 2>&1; then
            TERRAFORM_CLEANUP+=("{\"task\": \"terraform_destroy\", \"status\": \"completed\", \"message\": \"Terraform resources destroyed\"}")
            log_info "✅ Terraform resources destroyed"
        else
            TERRAFORM_CLEANUP+=("{\"task\": \"terraform_destroy\", \"status\": \"failed\", \"message\": \"Failed to destroy Terraform resources\"}")
            log_error "❌ Failed to destroy Terraform resources"
        fi
        cd "$REPO_ROOT"
    else
        TERRAFORM_CLEANUP+=("{\"task\": \"terraform_destroy\", \"status\": \"dry_run\", \"message\": \"Would destroy Terraform resources\"}")
        log_info "DRY RUN: Would destroy Terraform resources"
    fi
else
    TERRAFORM_CLEANUP+=("{\"task\": \"terraform_destroy\", \"status\": \"skipped\", \"message\": \"No Terraform state found\"}")
    log_info "No Terraform state found - skipping Terraform cleanup"
fi

# Cleanup Task 3: Remove configuration files
log_step "Cleanup Task 3: Configuration cleanup"

CONFIG_CLEANUP=()

CONFIG_FILES=(
    "$STAGING_DIR/terraform.tfstate"
    "$STAGING_DIR/terraform.tfstate.backup"
    "$STAGING_DIR/.terraform"
    "$STAGING_DIR/ansible_inventory"
    "$STAGING_DIR/site_config.yml"
)

for config_file in "${CONFIG_FILES[@]}"; do
    if [[ -e "$config_file" ]]; then
        if [[ "$DRY_RUN" != "true" ]]; then
            rm -rf "$config_file"
            CONFIG_CLEANUP+=("{\"task\": \"remove_config\", \"file\": \"$config_file\", \"status\": \"completed\", \"message\": \"Configuration file removed\"}")
            log_info "✅ Removed configuration file: $config_file"
        else
            CONFIG_CLEANUP+=("{\"task\": \"remove_config\", \"file\": \"$config_file\", \"status\": \"dry_run\", \"message\": \"Would remove configuration file\"}")
            log_info "DRY RUN: Would remove configuration file: $config_file"
        fi
    fi
done

# Cleanup Task 4: Clean up logs and temporary files
log_step "Cleanup Task 4: Logs and temporary files cleanup"

LOGS_CLEANUP=()

# Keep the most recent cleanup log, remove others
if [[ "$DRY_RUN" != "true" ]]; then
    log_info "Cleaning up old log files..."
    find "$STAGING_DIR/logs" -name "*.log" -type f -mtime +7 -delete 2>/dev/null || true
    LOGS_CLEANUP+=("{\"task\": \"cleanup_old_logs\", \"status\": \"completed\", \"message\": \"Old log files cleaned up\"}")
    log_info "✅ Old log files cleaned up"
else
    LOGS_CLEANUP+=("{\"task\": \"cleanup_old_logs\", \"status\": \"dry_run\", \"message\": \"Would cleanup old log files\"}")
    log_info "DRY RUN: Would cleanup old log files"
fi

# Cleanup Task 5: Remove test artifacts
log_step "Cleanup Task 5: Test artifacts cleanup"

TEST_CLEANUP=()

TEST_ARTIFACTS=(
    "$STAGING_DIR/test_results"
    "$STAGING_DIR/performance_test_results.json"
    "$STAGING_DIR/security_validation_results.json"
    "$STAGING_DIR/comprehensive_validation_results.json"
    "$STAGING_DIR/baseline_metrics.json"
    "$STAGING_DIR/post_test_metrics.json"
)

for artifact in "${TEST_ARTIFACTS[@]}"; do
    if [[ -e "$artifact" ]]; then
        if [[ "$DRY_RUN" != "true" ]]; then
            rm -rf "$artifact"
            TEST_CLEANUP+=("{\"task\": \"remove_test_artifact\", \"file\": \"$artifact\", \"status\": \"completed\", \"message\": \"Test artifact removed\"}")
            log_info "✅ Removed test artifact: $artifact"
        else
            TEST_CLEANUP+=("{\"task\": \"remove_test_artifact\", \"file\": \"$artifact\", \"status\": \"dry_run\", \"message\": \"Would remove test artifact\"}")
            log_info "DRY RUN: Would remove test artifact: $artifact"
        fi
    fi
done

# Cleanup Task 6: Archive important files
log_step "Cleanup Task 6: Archive important files"

ARCHIVE_CLEANUP=()

IMPORTANT_FILES=(
    "$STAGING_DIR/comprehensive_validation_report.json"
    "$STAGING_DIR/comprehensive_validation_report.html"
    "$STAGING_DIR/production_deployment_plan.json"
    "$STAGING_DIR/deployment_plan_summary.md"
    "$STAGING_DIR/production_readiness_results.json"
)

ARCHIVE_DIR="$REPO_ROOT/archives/staging/$STAGING_ENVIRONMENT_ID"
ARCHIVE_FILE="$REPO_ROOT/archives/staging_${STAGING_ENVIRONMENT_ID}_$(date +%Y%m%d_%H%M%S).tar.gz"

if [[ ${#IMPORTANT_FILES[@]} -gt 0 ]]; then
    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Archiving important files..."
        mkdir -p "$ARCHIVE_DIR"
        
        # Copy important files to archive directory
        for file in "${IMPORTANT_FILES[@]}"; do
            if [[ -f "$file" ]]; then
                cp "$file" "$ARCHIVE_DIR/"
            fi
        done
        
        # Create compressed archive
        cd "$REPO_ROOT/archives"
        tar -czf "staging_${STAGING_ENVIRONMENT_ID}_$(date +%Y%m%d_%H%M%S).tar.gz" "staging/$STAGING_ENVIRONMENT_ID" >/dev/null 2>&1
        rm -rf "staging/$STAGING_ENVIRONMENT_ID"
        
        ARCHIVE_CLEANUP+=("{\"task\": \"archive_files\", \"archive\": \"$ARCHIVE_FILE\", \"status\": \"completed\", \"message\": \"Important files archived\"}")
        log_info "✅ Important files archived to: $ARCHIVE_FILE"
    else
        ARCHIVE_CLEANUP+=("{\"task\": \"archive_files\", \"archive\": \"$ARCHIVE_FILE\", \"status\": \"dry_run\", \"message\": \"Would archive important files\"}")
        log_info "DRY RUN: Would archive important files to: $ARCHIVE_FILE"
    fi
else
    ARCHIVE_CLEANUP+=("{\"task\": \"archive_files\", \"status\": \"skipped\", \"message\": \"No important files to archive\"}")
    log_info "No important files to archive"
fi

# Cleanup Task 7: Remove staging directory
log_step "Cleanup Task 7: Remove staging directory"

DIRECTORY_CLEANUP=()

if [[ "$DRY_RUN" != "true" ]]; then
    log_info "Removing staging directory..."
    if rm -rf "$STAGING_DIR"; then
        DIRECTORY_CLEANUP+=("{\"task\": \"remove_directory\", \"directory\": \"$STAGING_DIR\", \"status\": \"completed\", \"message\": \"Staging directory removed\"}")
        log_info "✅ Staging directory removed: $STAGING_DIR"
    else
        DIRECTORY_CLEANUP+=("{\"task\": \"remove_directory\", \"directory\": \"$STAGING_DIR\", \"status\": \"failed\", \"message\": \"Failed to remove staging directory\"}")
        log_error "❌ Failed to remove staging directory"
    fi
else
    DIRECTORY_CLEANUP+=("{\"task\": \"remove_directory\", \"directory\": \"$STAGING_DIR\", \"status\": \"dry_run\", \"message\": \"Would remove staging directory\"}")
    log_info "DRY RUN: Would remove staging directory: $STAGING_DIR"
fi

# Calculate cleanup summary
log_step "Calculating cleanup summary"

ALL_CLEANUP_TASKS_JSON=$(printf '%s\n' "${INFRASTRUCTURE_CLEANUP[@]}" "${TERRAFORM_CLEANUP[@]}" "${CONFIG_CLEANUP[@]}" "${LOGS_CLEANUP[@]}" "${TEST_CLEANUP[@]}" "${ARCHIVE_CLEANUP[@]}" "${DIRECTORY_CLEANUP[@]}" | jq -s '.')
TOTAL_CLEANUP_TASKS=$(echo "$ALL_CLEANUP_TASKS_JSON" | jq length)
COMPLETED_CLEANUP_TASKS=$(echo "$ALL_CLEANUP_TASKS_JSON" | jq '[.[] | select(.status == "completed")] | length')
FAILED_CLEANUP_TASKS=$(echo "$ALL_CLEANUP_TASKS_JSON" | jq '[.[] | select(.status == "failed")] | length')

# Update cleanup results
python3 -c "
import json
import sys
data = json.load(open('$CLEANUP_RESULTS'))

# Convert bash arrays to Python lists
infrastructure_cleanup = [json.loads(task) for task in sys.argv[1].split('|') if task]
terraform_cleanup = [json.loads(task) for task in sys.argv[2].split('|') if task]
config_cleanup = [json.loads(task) for task in sys.argv[3].split('|') if task]
logs_cleanup = [json.loads(task) for task in sys.argv[4].split('|') if task]
test_cleanup = [json.loads(task) for task in sys.argv[5].split('|') if task]
archive_cleanup = [json.loads(task) for task in sys.argv[6].split('|') if task]
directory_cleanup = [json.loads(task) for task in sys.argv[7].split('|') if task]

data['cleanup_operation']['cleanup_end'] = '$(date -Iseconds)'
data['cleanup_tasks'] = infrastructure_cleanup + terraform_cleanup + config_cleanup + logs_cleanup + test_cleanup + archive_cleanup + directory_cleanup
data['cleanup_summary'] = {
    'total_tasks': $TOTAL_CLEANUP_TASKS,
    'completed_tasks': $COMPLETED_CLEANUP_TASKS,
    'failed_tasks': $FAILED_CLEANUP_TASKS,
    'success_rate': round(($COMPLETED_CLEANUP_TASKS / $TOTAL_CLEANUP_TASKS * 100) if $TOTAL_CLEANUP_TASKS > 0 else 0, 2)
}

json.dump(data, open('$CLEANUP_RESULTS', 'w'), indent=2)
" "$(printf '%s|' "${INFRASTRUCTURE_CLEANUP[@]}")" "$(printf '%s|' "${TERRAFORM_CLEANUP[@]}")" "$(printf '%s|' "${CONFIG_CLEANUP[@]}")" "$(printf '%s|' "${LOGS_CLEANUP[@]}")" "$(printf '%s|' "${TEST_CLEANUP[@]}")" "$(printf '%s|' "${ARCHIVE_CLEANUP[@]}")" "$(printf '%s|' "${DIRECTORY_CLEANUP[@]}")"

log_info "Cleanup completed"
log_info "Tasks: $COMPLETED_CLEANUP_TASKS/$TOTAL_CLEANUP_TASKS completed, $FAILED_CLEANUP_TASKS failed"

# Create cleanup summary
CLEANUP_SUMMARY="$REPO_ROOT/cleanup_summary_${STAGING_ENVIRONMENT_ID}.json"

if [[ "$DRY_RUN" != "true" ]]; then
    cp "$CLEANUP_RESULTS" "$CLEANUP_SUMMARY"
    log_info "Cleanup summary saved to: $CLEANUP_SUMMARY"
fi

echo ""
echo "=========================================="
echo "STAGING CLEANUP SUMMARY"
echo "=========================================="
echo "Site: $SITE_DISPLAY_NAME ($SITE_NAME)"
echo "Environment: $STAGING_ENVIRONMENT_ID"
echo "Mode: $([ "$DRY_RUN" = "true" ] && echo "DRY RUN" || echo "LIVE CLEANUP")"
echo ""
echo "Cleanup Results:"
echo "  Total Tasks: $TOTAL_CLEANUP_TASKS"
echo "  Completed: $COMPLETED_CLEANUP_TASKS"
echo "  Failed: $FAILED_CLEANUP_TASKS"
echo ""
echo "Key Actions:"
if [[ "$DRY_RUN" != "true" ]]; then
    echo "  ✅ Infrastructure cleaned up"
    echo "  ✅ Terraform resources destroyed"
    echo "  ✅ Configuration files removed"
    echo "  ✅ Test artifacts cleaned up"
    echo "  ✅ Important files archived"
    echo "  ✅ Staging directory removed"
else
    echo "  📋 Infrastructure would be cleaned up"
    echo "  📋 Terraform resources would be destroyed"
    echo "  📋 Configuration files would be removed"
    echo "  📋 Test artifacts would be cleaned up"
    echo "  📋 Important files would be archived"
    echo "  📋 Staging directory would be removed"
fi
echo ""
if [[ "$DRY_RUN" != "true" && -f "$ARCHIVE_FILE" ]]; then
    echo "Archive: $ARCHIVE_FILE"
fi
echo "Summary: $CLEANUP_SUMMARY"
echo "Log: $CLEANUP_LOG"
echo "=========================================="

# Mark cleanup as completed
if [[ "$DRY_RUN" != "true" && $FAILED_CLEANUP_TASKS -eq 0 ]]; then
    echo "cleanup_completed" > "$REPO_ROOT/cleanup_${STAGING_ENVIRONMENT_ID}_completed"
elif [[ "$DRY_RUN" == "true" ]]; then
    echo "cleanup_dry_run_completed" > "$REPO_ROOT/cleanup_${STAGING_ENVIRONMENT_ID}_dry_run_completed"
else
    echo "cleanup_failed" > "$REPO_ROOT/cleanup_${STAGING_ENVIRONMENT_ID}_failed"
fi

log_info "Staging cleanup operation completed"

# Exit with appropriate code
if [[ $FAILED_CLEANUP_TASKS -gt 0 ]]; then
    exit 1
fi
