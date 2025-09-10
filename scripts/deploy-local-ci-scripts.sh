#!/bin/bash
set -euo pipefail

# BrewNix Local CI Testing Script Deployment
# Deploys local-ci-test.sh to all submodules for local development

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../templates/scripts"
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

    if [[ ! -f "templates/scripts/local-ci-test.sh" ]]; then
        log_error "Local CI test script not found at templates/scripts/local-ci-test.sh"
        exit 1
    fi
}

# Function to get list of submodules
get_submodules() {
    git submodule status | awk '{print $2}'
}

# Function to deploy local CI test script to submodule
deploy_local_ci_script() {
    local submodule="$1"
    local submodule_dir="$BREWNIX_ROOT/$submodule"
    local scripts_dir="$submodule_dir/scripts"
    local target_file="$scripts_dir/local-ci-test.sh"

    # Create scripts directory if it doesn't exist
    mkdir -p "$scripts_dir"

    # Copy local CI test script
    cp "$TEMPLATE_DIR/local-ci-test.sh" "$target_file"

    # Make it executable
    chmod +x "$target_file"

    log_success "Deployed local CI test script to $submodule"
}

# Function to validate deployment
validate_deployment() {
    local submodule="$1"
    local script_path="$BREWNIX_ROOT/$submodule/scripts/local-ci-test.sh"

    if [[ ! -f "$script_path" ]]; then
        log_error "Script file not found after deployment: $script_path"
        return 1
    fi

    if [[ ! -x "$script_path" ]]; then
        log_error "Script is not executable: $script_path"
        return 1
    fi

    # Basic validation - check if it's a bash script
    if ! head -1 "$script_path" | grep -q "#!/bin/bash"; then
        log_error "Script doesn't have proper shebang: $script_path"
        return 1
    fi

    log_success "Script validation passed for $submodule"
    return 0
}

# Function to show deployment summary
show_summary() {
    local submodules=("$@")

    echo
    echo "========================================"
    echo "LOCAL CI SCRIPT DEPLOYMENT SUMMARY"
    echo "========================================"
    echo

    echo "Local CI testing scripts deployed to:"
    for submodule in "${submodules[@]}"; do
        echo "  ✓ $submodule"
    done

    echo
    echo "Usage Instructions:"
    echo "1. Navigate to any submodule directory"
    echo "2. Run: ./scripts/local-ci-test.sh"
    echo "3. Get immediate feedback on code quality, security, and tests"
    echo "4. Fix issues before pushing to avoid CI failures"
    echo
    echo "Available Options:"
    echo "  ./scripts/local-ci-test.sh --help     # Show help"
    echo "  ./scripts/local-ci-test.sh --security # Run only security checks"
    echo "  ./scripts/local-ci-test.sh --quality  # Run only quality checks"
    echo "  ./scripts/local-ci-test.sh --test     # Run only tests"
    echo "  ./scripts/local-ci-test.sh --performance # Run only performance checks"
    echo
    echo "Benefits:"
    echo "  🚀 Faster feedback loop - no waiting for CI"
    echo "  💰 Reduced CI compute costs"
    echo "  🔧 Better developer experience"
    echo "  🐛 Catch issues before they reach CI"
    echo "  📊 Consistent local and CI environments"
}

# Main function
main() {
    log_info "Starting Local CI Testing Script Deployment"
    log_info "BrewNix Local Development Enhancement"

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
        echo "  $submodule"
    done

    echo
    read -p "Deploy local CI testing scripts to all submodules? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled"
        exit 0
    fi

    # Deploy to all submodules
    log_info "Deploying local CI testing scripts..."
    local deployed_submodules=()

    for submodule in "${submodules[@]}"; do
        log_info "Processing $submodule..."

        if deploy_local_ci_script "$submodule"; then
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
        log_success "Local CI testing script deployment completed successfully!"
    else
        log_error "No scripts were successfully deployed"
        exit 1
    fi
}

# Run main function
main "$@"
