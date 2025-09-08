#!/bin/bash
# scripts/utilities/duplicate-core.sh - Duplicate core infrastructure to submodules

# Source core modules from template
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE_DIR="${SCRIPT_DIR}/templates/submodule-core"
source "${TEMPLATE_DIR}/init.sh"
source "${TEMPLATE_DIR}/config.sh"
source "${TEMPLATE_DIR}/logging.sh"
DRY_RUN=false

# Initialize duplication
init_duplication() {
    log_info "Core duplication module initialized"

    if [[ ! -d "$TEMPLATE_DIR" ]]; then
        log_error "Template directory not found: $TEMPLATE_DIR"
        log_error "Please run Phase 1 first to create the duplication template"
        exit 1
    fi
}

# Validate target submodule
validate_submodule() {
    local submodule_path="$1"

    if [[ ! -d "$submodule_path" ]]; then
        log_error "Submodule directory not found: $submodule_path"
        return 1
    fi

    if [[ ! -d "${submodule_path}/.git" ]]; then
        log_warn "Target directory is not a Git repository: $submodule_path"
        log_warn "This may not be a proper submodule"
    fi

    # Check if already has core infrastructure
    if [[ -f "${submodule_path}/scripts/core/init.sh" ]]; then
        log_warn "Target submodule already has core infrastructure"
        log_warn "This will overwrite existing files"
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Duplication cancelled by user"
            return 1
        fi
    fi

    return 0
}

# Create directory structure
create_directories() {
    local submodule_path="$1"

    log_info "Creating directory structure in: $submodule_path"

    local dirs=(
        "scripts/core"
        "tests/core"
        "tests/integration"
        "logs"
        "tmp"
        "build"
        "test-results"
    )

    for dir in "${dirs[@]}"; do
        local full_path="${submodule_path}/${dir}"
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would create directory: $full_path"
        else
            if [[ ! -d "$full_path" ]]; then
                mkdir -p "$full_path"
                log_info "Created directory: $full_path"
            else
                log_info "Directory already exists: $full_path"
            fi
        fi
    done
}

# Copy core infrastructure files
copy_core_files() {
    local submodule_path="$1"

    log_info "Copying core infrastructure files"

    local files_to_copy=(
        "init.sh"
        "config.sh"
        "logging.sh"
    )

    for file in "${files_to_copy[@]}"; do
        local src="${TEMPLATE_DIR}/${file}"
        local dst="${submodule_path}/scripts/core/${file}"

        if [[ ! -f "$src" ]]; then
            log_error "Source file not found: $src"
            continue
        fi

        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would copy: $src -> $dst"
        else
            cp "$src" "$dst"
            chmod +x "$dst" 2>/dev/null || true
            log_info "Copied: scripts/core/$file"
        fi
    done

    # Copy other files to root
    local root_files=(
        "validate-config.sh"
        "dev-setup.sh"
        "local-test.sh"
        "README.md"
    )

    for file in "${root_files[@]}"; do
        local src="${TEMPLATE_DIR}/${file}"
        local dst="${submodule_path}/${file}"

        if [[ ! -f "$src" ]]; then
            log_error "Source file not found: $src"
            continue
        fi

        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would copy: $src -> $dst"
        else
            cp "$src" "$dst"
            chmod +x "$dst" 2>/dev/null || true
            log_info "Copied: $file"
        fi
    done
}

# Copy test files
copy_test_files() {
    local submodule_path="$1"

    log_info "Copying test files"

    # Copy core test files
    local core_tests=(
        "tests/core/test_config.sh"
        "tests/core/test_logging.sh"
    )

    for test_file in "${core_tests[@]}"; do
        local src="${TEMPLATE_DIR}/${test_file}"
        local dst="${submodule_path}/${test_file}"

        if [[ ! -f "$src" ]]; then
            log_error "Test file not found: $src"
            continue
        fi

        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would copy: $src -> $dst"
        else
            cp "$src" "$dst"
            chmod +x "$dst" 2>/dev/null || true
            log_info "Copied test: $test_file"
        fi
    done

    # Copy integration test files
    local integration_tests=(
        "tests/integration/test_deployment.sh"
    )

    for test_file in "${integration_tests[@]}"; do
        local src="${TEMPLATE_DIR}/${test_file}"
        local dst="${submodule_path}/${test_file}"

        if [[ ! -f "$src" ]]; then
            log_error "Integration test file not found: $src"
            continue
        fi

        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] Would copy: $src -> $dst"
        else
            cp "$src" "$dst"
            chmod +x "$dst" 2>/dev/null || true
            log_info "Copied integration test: $test_file"
        fi
    done
}

# Update file permissions
update_permissions() {
    local submodule_path="$1"

    log_info "Updating file permissions"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would update permissions for: $submodule_path"
        return 0
    fi

    # Make scripts executable
    find "$submodule_path" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true

    # Make sure core modules are executable
    local core_files=(
        "scripts/core/init.sh"
        "scripts/core/config.sh"
        "scripts/core/logging.sh"
    )

    for file in "${core_files[@]}"; do
        local full_path="${submodule_path}/${file}"
        if [[ -f "$full_path" ]]; then
            chmod +x "$full_path"
            log_info "Made executable: $file"
        fi
    done

    log_info "File permissions updated"
}

# Create .gitignore entries
create_gitignore_entries() {
    local submodule_path="$1"

    log_info "Checking .gitignore configuration"

    local gitignore="${submodule_path}/.gitignore"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would check .gitignore: $gitignore"
        return 0
    fi

    # Create .gitignore if it doesn't exist
    if [[ ! -f "$gitignore" ]]; then
        cat > "$gitignore" << 'EOF'
# BrewNix submodule .gitignore

# Logs
logs/
*.log

# Temporary files
tmp/
*.tmp
*.swp

# Build artifacts
build/
dist/

# Test results
test-results/
coverage/

# Environment files
.env
.env.local

# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# IDE files
.vscode/
.idea/
*.sublime-project
*.sublime-workspace

# Node modules (if any)
node_modules/
EOF
        log_info "Created .gitignore file"
    else
        log_info ".gitignore already exists"
    fi
}

# Verify duplication
verify_duplication() {
    local submodule_path="$1"

    log_info "Verifying duplication integrity"

    local required_files=(
        "scripts/core/init.sh"
        "scripts/core/config.sh"
        "scripts/core/logging.sh"
        "validate-config.sh"
        "dev-setup.sh"
        "local-test.sh"
        "tests/core/test_config.sh"
        "tests/core/test_logging.sh"
        "tests/integration/test_deployment.sh"
    )

    local missing_files=()

    for file in "${required_files[@]}"; do
        if [[ ! -f "${submodule_path}/${file}" ]]; then
            missing_files+=("$file")
        fi
    done

    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_error "Missing files after duplication:"
        for file in "${missing_files[@]}"; do
            log_error "  - $file"
        done
        return 1
    fi

    # Test that scripts are executable
    local non_executable=()
    for file in "${required_files[@]}"; do
        if [[ "${file}" == *.sh ]] && [[ ! -x "${submodule_path}/${file}" ]]; then
            non_executable+=("$file")
        fi
    done

    if [[ ${#non_executable[@]} -gt 0 ]]; then
        log_warn "Some scripts are not executable:"
        for file in "${non_executable[@]}"; do
            log_warn "  - $file"
        done
    fi

    log_info "✅ Duplication verification completed"
    return 0
}

# Generate duplication report
generate_report() {
    local submodule_path="$1"
    local start_time="$2"
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local report_file="${submodule_path}/duplication_report_${timestamp}.txt"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would generate report: $report_file"
        return 0
    fi

    cat > "$report_file" << EOF
BrewNix Core Duplication Report
Generated: $(date)
Duration: ${duration} seconds
=====================================

Target Submodule: $submodule_path
Template Used: $TEMPLATE_DIR

Duplicated Files:
- Core Infrastructure:
  - scripts/core/init.sh
  - scripts/core/config.sh
  - scripts/core/logging.sh

- Development Tools:
  - validate-config.sh
  - dev-setup.sh
  - local-test.sh
  - README.md

- Test Framework:
  - tests/core/test_config.sh
  - tests/core/test_logging.sh
  - tests/integration/test_deployment.sh

Next Steps:
1. Run './dev-setup.sh' to initialize the development environment
2. Run './validate-config.sh' to verify the setup
3. Run './local-test.sh' to execute tests
4. Customize configuration files as needed

For detailed documentation, see README.md
EOF

    log_info "Duplication report saved: $report_file"
}

# Main duplication function
duplicate_core() {
    local submodule_path="$1"
    local start_time
    start_time=$(date +%s)

    if [[ -z "$submodule_path" ]]; then
        log_error "Submodule path required"
        echo "Usage: $0 <submodule-path> [--dry-run]"
        return 1
    fi

    # Normalize path
    submodule_path="${submodule_path%/}"

    log_section "Starting core duplication to: $submodule_path"

    # Validate submodule
    if ! validate_submodule "$submodule_path"; then
        return 1
    fi

    # Create directory structure
    create_directories "$submodule_path"

    # Copy files
    copy_core_files "$submodule_path"
    copy_test_files "$submodule_path"

    # Update permissions
    update_permissions "$submodule_path"

    # Create .gitignore entries
    create_gitignore_entries "$submodule_path"

    # Verify duplication
    if ! verify_duplication "$submodule_path"; then
        log_error "Duplication verification failed"
        return 1
    fi

    # Generate report
    generate_report "$submodule_path" "$start_time"

    log_success "✅ Core duplication completed successfully!"
    log_info ""
    log_info "Next steps:"
    log_info "  cd $submodule_path"
    log_info "  ./dev-setup.sh"
    log_info "  ./validate-config.sh"
    log_info "  ./local-test.sh"

    return 0
}

# Main execution
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 <submodule-path> [OPTIONS]"
                echo ""
                echo "Duplicate BrewNix core infrastructure to a submodule"
                echo ""
                echo "Arguments:"
                echo "  submodule-path    Path to the target submodule"
                echo ""
                echo "Options:"
                echo "  --dry-run         Show what would be done without executing"
                echo "  -h, --help        Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0 vendor/proxmox-firewall"
                echo "  $0 vendor/proxmox-nas --dry-run"
                exit 0
                ;;
            *)
                if [[ -z "$TARGET_SUBMODULE" ]]; then
                    TARGET_SUBMODULE="$1"
                else
                    log_error "Unknown argument: $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$TARGET_SUBMODULE" ]]; then
        log_error "Submodule path required"
        echo "Usage: $0 <submodule-path> [--dry-run]"
        exit 1
    fi

    # Initialize
    init_duplication

    # Perform duplication
    if duplicate_core "$TARGET_SUBMODULE"; then
        log_success "Duplication completed successfully"
        exit 0
    else
        log_error "Duplication failed"
        exit 1
    fi
}

# Run duplication if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
