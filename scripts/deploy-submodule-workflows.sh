#!/bin/bash
set -euo pipefail

# BrewNix Submodule Workflow Standardization Script
# Phase 5.3.4: Submodule Workflow Improvements

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../templates/workflows"
BREWNIX_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if we're in the right directory
check_environment() {
    if [[ ! -f ".gitmodules" ]]; then
        log_error "Not in brewnix-template root directory. Please run from the template root."
        exit 1
    fi

    if [[ ! -f "templates/workflows/submodule-ci-standardized.yml" ]]; then
        log_error "Standardized workflow template not found at templates/workflows/submodule-ci-standardized.yml"
        exit 1
    fi
}

# Function to get list of submodules
get_submodules() {
    git submodule status | awk '{print $2}'
}

# Function to check submodule workflow status
check_submodule_workflow() {
    local submodule="$1"
    local workflow_path="$BREWNIX_ROOT/$submodule/.github/workflows/ci.yml"

    if [[ ! -f "$workflow_path" ]]; then
        echo "missing"
        return
    fi

    # Check if it's the basic template (has only 3 jobs: test)
    local job_count
    job_count=$(grep -c "^jobs:" "$workflow_path")
    local test_job_count
    test_job_count=$(grep -c "jobs:" "$workflow_path" -A 10 | grep -c "test:")

    if [[ $job_count -eq 1 && $test_job_count -eq 1 ]]; then
        echo "basic"
    else
        echo "custom"
    fi
}

# Function to backup existing workflow
backup_workflow() {
    local submodule="$1"
    local workflow_path="$BREWNIX_ROOT/$submodule/.github/workflows/ci.yml"
    local backup_path
    backup_path="$workflow_path.backup.$(date +%Y%m%d_%H%M%S)"

    if [[ -f "$workflow_path" ]]; then
        cp "$workflow_path" "$backup_path"
        log_info "Backed up existing workflow: $backup_path"
    fi
}

# Function to deploy standardized workflow to submodule
deploy_workflow() {
    local submodule="$1"
    local submodule_dir="$BREWNIX_ROOT/$submodule"
    local workflow_dir="$submodule_dir/.github/workflows"
    local template_file="$TEMPLATE_DIR/submodule-ci-standardized.yml"
    local target_file="$workflow_dir/ci.yml"

    # Create workflow directory if it doesn't exist
    mkdir -p "$workflow_dir"

    # Backup existing workflow
    backup_workflow "$submodule"

    # Copy standardized workflow
    cp "$template_file" "$target_file"

    log_success "Deployed standardized workflow to $submodule"
}

# Function to validate deployment
validate_deployment() {
    local submodule="$1"
    local workflow_path="$BREWNIX_ROOT/$submodule/.github/workflows/ci.yml"

    if [[ ! -f "$workflow_path" ]]; then
        log_error "Workflow file not found after deployment: $workflow_path"
        return 1
    fi

    # Basic YAML validation
    if python3 -c "import yaml; yaml.safe_load(open('$workflow_path'))" 2>/dev/null; then
        log_success "Workflow YAML is valid for $submodule"
        return 0
    else
        log_error "Invalid YAML in workflow for $submodule"
        return 1
    fi
}

# Function to show deployment summary
show_summary() {
    local submodules=("$@")

    echo
    echo "========================================"
    echo "PHASE 5.3.4 DEPLOYMENT SUMMARY"
    echo "========================================"
    echo

    echo "Standardized workflows deployed to:"
    for submodule in "${submodules[@]}"; do
        echo "  ✓ $submodule"
    done

    echo
    echo "Next Steps:"
    echo "1. Review the new workflows in each submodule"
    echo "2. Test the workflows by pushing changes to submodules"
    echo "3. Monitor CI/CD pipeline performance"
    echo "4. Address any security or quality issues found"
    echo
    echo "Workflow Features Added:"
    echo "  🔒 Security scanning with Trivy"
    echo "  🔍 Code quality gates (linting, complexity)"
    echo "  🧪 Comprehensive test suite"
    echo "  ⚡ Performance benchmarking"
    echo "  📊 Detailed status reporting"
    echo "  🚨 Automated failure notifications"
}

# Main function
main() {
    log_info "Starting Phase 5.3.4: Submodule Workflow Improvements"
    log_info "BrewNix Submodule Workflow Standardization"

    # Check environment
    check_environment

    # Get submodules
    log_info "Discovering submodules..."
    local submodules
    mapfile -t submodules < <(get_submodules)

    if [[ ${#submodules[@]} -eq 0 ]]; then
        log_error "No submodules found"
        exit 1
    fi

    log_info "Found ${#submodules[@]} submodules:"
    for submodule in "${submodules[@]}"; do
        workflow_status=$(check_submodule_workflow "$submodule")
        case $workflow_status in
            "missing")
                echo "  $submodule: ${RED}No workflow${NC}"
                ;;
            "basic")
                echo "  $submodule: ${YELLOW}Basic workflow${NC}"
                ;;
            "custom")
                echo "  $submodule: ${BLUE}Custom workflow${NC}"
                ;;
        esac
    done

    echo
    read -p "Deploy standardized workflows to all submodules? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled"
        exit 0
    fi

    # Deploy to all submodules
    log_info "Deploying standardized workflows..."
    deployed_submodules=()

    for submodule in "${submodules[@]}"; do
        log_info "Processing $submodule..."

        if deploy_workflow "$submodule"; then
            if validate_deployment "$submodule"; then
                deployed_submodules+=("$submodule")
            else
                log_warning "Validation failed for $submodule"
            fi
        else
            log_error "Failed to deploy to $submodule"
        fi
    done

    # Show summary
    if [[ ${#deployed_submodules[@]} -gt 0 ]]; then
        show_summary "${deployed_submodules[@]}"
        log_success "Phase 5.3.4 deployment completed successfully!"
    else
        log_error "No workflows were successfully deployed"
        exit 1
    fi
}

# Run main function
main "$@"
