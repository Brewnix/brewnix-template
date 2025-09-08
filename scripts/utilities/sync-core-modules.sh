#!/bin/bash

# BrewNix Core Module Synchronization Script
# Phase 3.1.1 - Core Module Sync Process
#
# This script synchronizes core modules between brewnix-template and submodule instances
# ensuring consistency, integrity, and version compatibility across the ecosystem

set -euo pipefail

# Source core modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Configuration
TEMPLATE_CORE_DIR="${PROJECT_ROOT}/scripts/core"
SUBMODULE_CORE_DIR="${PROJECT_ROOT}/templates/submodule-core"
SYNC_LOG_FILE="${PROJECT_ROOT}/build/sync-core-modules.log"
SYNC_REPORT_FILE="${PROJECT_ROOT}/build/sync-core-modules-report.md"

# Core modules to sync
CORE_MODULES=("config.sh" "logging.sh" "init.sh" "dev-setup.sh" "local-test.sh" "validate-config.sh")

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Statistics
SYNCED_MODULES=0
SKIPPED_MODULES=0
FAILED_MODULES=0
TOTAL_MODULES=0

# Logging functions
log_info() {
    echo -e "${BLUE}[SYNC]${NC} $1" | tee -a "$SYNC_LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$SYNC_LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$SYNC_LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$SYNC_LOG_FILE"
}

# Initialize sync environment
init_sync_environment() {
    log_info "Initializing core module synchronization environment..."

    # Create build directory if it doesn't exist
    mkdir -p "${PROJECT_ROOT}/build"

    # Initialize log file
    echo "=== BrewNix Core Module Sync - $(date) ===" > "$SYNC_LOG_FILE"
    echo "Project Root: $PROJECT_ROOT" >> "$SYNC_LOG_FILE"
    echo "Template Core Dir: $TEMPLATE_CORE_DIR" >> "$SYNC_LOG_FILE"
    echo "Submodule Core Dir: $SUBMODULE_CORE_DIR" >> "$SYNC_LOG_FILE"
    echo "" >> "$SYNC_LOG_FILE"

    # Reset statistics
    SYNCED_MODULES=0
    SKIPPED_MODULES=0
    FAILED_MODULES=0
    TOTAL_MODULES=0

    log_success "Sync environment initialized"
}

# Validate core module integrity
validate_module_integrity() {
    local module_name="$1"
    local source_file="$2"
    local target_file="$3"

    log_info "Validating integrity of $module_name..."

    # Check if source file exists
    if [[ ! -f "$source_file" ]]; then
        log_error "Source file missing: $source_file"
        return 1
    fi

    # Check if target file exists
    if [[ ! -f "$target_file" ]]; then
        log_warning "Target file missing: $target_file"
        return 1
    fi

    # Validate bash syntax
    if ! bash -n "$source_file" 2>/dev/null; then
        log_error "Source file has syntax errors: $source_file"
        return 1
    fi

    if ! bash -n "$target_file" 2>/dev/null; then
        log_error "Target file has syntax errors: $target_file"
        return 1
    fi

    # Check file permissions
    local source_perms
    local target_perms
    source_perms=$(stat -c '%a' "$source_file")
    target_perms=$(stat -c '%a' "$target_file")

    if [[ "$source_perms" != "$target_perms" ]]; then
        log_warning "Permission mismatch for $module_name: source=${source_perms}, target=${target_perms}"
    fi

    log_success "Integrity validation passed for $module_name"
    return 0
}

# Compare module versions/content
compare_modules() {
    local module_name="$1"
    local source_file="$2"
    local target_file="$3"

    log_info "Comparing $module_name versions..."

    # Get file modification times
    local source_mtime
    local target_mtime
    source_mtime=$(stat -c '%Y' "$source_file")
    target_mtime=$(stat -c '%Y' "$target_file")

    # Compare modification times
    if [[ "$source_mtime" -gt "$target_mtime" ]]; then
        log_info "$module_name: Source is newer than target"
        return 1  # Source is newer
    elif [[ "$source_mtime" -lt "$target_mtime" ]]; then
        log_warning "$module_name: Target is newer than source (possible local modifications)"
        return 2  # Target is newer
    else
        # Compare file contents
        if ! diff -q "$source_file" "$target_file" >/dev/null 2>&1; then
            log_info "$module_name: Content differs despite same modification time"
            return 1  # Content differs
        else
            log_info "$module_name: Files are identical"
            return 0  # Files are identical
        fi
    fi
}

# Sync individual module
sync_module() {
    local module_name="$1"
    local source_file="$2"
    local target_file="$3"

    ((TOTAL_MODULES++))

    log_info "Processing $module_name..."

    # Validate integrity first
    if ! validate_module_integrity "$module_name" "$source_file" "$target_file"; then
        log_error "Integrity validation failed for $module_name"
        ((FAILED_MODULES++))
        return 1
    fi

    # Compare modules
    local compare_exit_code
    compare_modules "$module_name" "$source_file" "$target_file"
    compare_exit_code=$?

    case $compare_exit_code in
        0)
            # Files are identical
            log_success "$module_name is already synchronized"
            ((SKIPPED_MODULES++))
            ;;
        1)
            # Source is newer or content differs
            log_info "Synchronizing $module_name from source to target..."

            # Create backup of target file
            local backup_file
            backup_file="${target_file}.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$target_file" "$backup_file"
            log_info "Created backup: $backup_file"

            # Copy source to target
            if cp "$source_file" "$target_file"; then
                log_success "Successfully synchronized $module_name"
                ((SYNCED_MODULES++))
            else
                log_error "Failed to synchronize $module_name"
                ((FAILED_MODULES++))
                return 1
            fi
            ;;
        2)
            # Target is newer (possible local modifications)
            log_warning "$module_name has local modifications in target"
            log_warning "Manual review required for $module_name"

            # Ask user what to do (in interactive mode)
            if [[ -t 0 ]]; then
                echo -n "Do you want to overwrite target with source? (y/N): "
                read -r response
                if [[ "$response" =~ ^[Yy]$ ]]; then
                    local backup_file
                    backup_file="${target_file}.backup.$(date +%Y%m%d_%H%M%S)"
                    cp "$target_file" "$backup_file"
                    log_info "Created backup: $backup_file"

                    if cp "$source_file" "$target_file"; then
                        log_success "Force synchronized $module_name"
                        ((SYNCED_MODULES++))
                    else
                        log_error "Failed to force synchronize $module_name"
                        ((FAILED_MODULES++))
                        return 1
                    fi
                else
                    log_info "Skipped synchronization of $module_name"
                    ((SKIPPED_MODULES++))
                fi
            else
                log_warning "Non-interactive mode: skipping $module_name with local modifications"
                ((SKIPPED_MODULES++))
            fi
            ;;
    esac

    return 0
}

# Sync all core modules
sync_all_modules() {
    log_info "Starting synchronization of all core modules..."

    for module in "${CORE_MODULES[@]}"; do
        # Determine source and target files
        local source_file=""
        local target_file=""

        # Check if module exists in template core
        if [[ -f "${TEMPLATE_CORE_DIR}/${module}" ]]; then
            source_file="${TEMPLATE_CORE_DIR}/${module}"
            target_file="${SUBMODULE_CORE_DIR}/${module}"
        elif [[ -f "${SUBMODULE_CORE_DIR}/${module}" ]]; then
            # Module only exists in submodule core, use it as source
            source_file="${SUBMODULE_CORE_DIR}/${module}"
            target_file="${TEMPLATE_CORE_DIR}/${module}"
            log_warning "Module $module only exists in submodule core, using as source"
        else
            log_warning "Module $module not found in either location, skipping"
            continue
        fi

        # Sync the module
        if ! sync_module "$module" "$source_file" "$target_file"; then
            log_error "Failed to sync module: $module"
        fi
    done

    log_success "Core module synchronization completed"
}

# Generate sync report
generate_sync_report() {
    log_info "Generating synchronization report..."

    cat > "$SYNC_REPORT_FILE" << EOF
# BrewNix Core Module Synchronization Report

Generated: $(date)
Project: $PROJECT_ROOT

## Synchronization Summary

- **Total Modules Processed**: $TOTAL_MODULES
- **Modules Synchronized**: $SYNCED_MODULES
- **Modules Skipped**: $SKIPPED_MODULES
- **Modules Failed**: $FAILED_MODULES

## Success Rate

$(calculate_success_rate)%

## Module Details

EOF

    # Add details for each module
    for module in "${CORE_MODULES[@]}"; do
        echo "### $module" >> "$SYNC_REPORT_FILE"

        if [[ -f "${TEMPLATE_CORE_DIR}/${module}" ]]; then
            echo "- **Template Location**: ${TEMPLATE_CORE_DIR}/${module}" >> "$SYNC_REPORT_FILE"
            echo "- **Template Modified**: $(stat -c '%y' "${TEMPLATE_CORE_DIR}/${module}" 2>/dev/null || echo 'N/A')" >> "$SYNC_REPORT_FILE"
        fi

        if [[ -f "${SUBMODULE_CORE_DIR}/${module}" ]]; then
            echo "- **Submodule Location**: ${SUBMODULE_CORE_DIR}/${module}" >> "$SYNC_REPORT_FILE"
            echo "- **Submodule Modified**: $(stat -c '%y' "${SUBMODULE_CORE_DIR}/${module}" 2>/dev/null || echo 'N/A')" >> "$SYNC_REPORT_FILE"
        fi

        echo "" >> "$SYNC_REPORT_FILE"
    done

    # Add recommendations
    cat >> "$SYNC_REPORT_FILE" << EOF
## Recommendations

EOF

    if [[ $FAILED_MODULES -gt 0 ]]; then
        cat >> "$SYNC_REPORT_FILE" << EOF
- **Review Failed Modules**: $FAILED_MODULES modules failed synchronization
- **Check Error Logs**: Review ${SYNC_LOG_FILE} for detailed error information
- **Manual Intervention**: Some modules may require manual review and merging

EOF
    fi

    if [[ $SYNCED_MODULES -gt 0 ]]; then
        cat >> "$SYNC_REPORT_FILE" << EOF
- **Test Changes**: Verify that synchronized modules work correctly
- **Update Documentation**: Ensure any module changes are documented
- **Notify Team**: Inform team members of significant module updates

EOF
    fi

    if [[ $TOTAL_MODULES -eq $SKIPPED_MODULES ]]; then
        cat >> "$SYNC_REPORT_FILE" << EOF
- **All Modules Current**: No synchronization was necessary
- **Regular Maintenance**: Continue regular sync checks to maintain consistency

EOF
    fi

    log_success "Synchronization report generated: $SYNC_REPORT_FILE"
}

# Calculate success rate
calculate_success_rate() {
    if [[ $TOTAL_MODULES -eq 0 ]]; then
        echo "0"
        return
    fi

    local success_count=$((SYNCED_MODULES + SKIPPED_MODULES))
    local success_rate=$(( (success_count * 100) / TOTAL_MODULES ))
    echo "$success_rate"
}

# Validate sync results
validate_sync_results() {
    log_info "Validating synchronization results..."

    local validation_errors=0

    # Check that all target files exist and are executable
    for module in "${CORE_MODULES[@]}"; do
        local target_file="${SUBMODULE_CORE_DIR}/${module}"

        if [[ -f "$target_file" ]]; then
            # Check if file is executable (for scripts)
            if [[ "$module" == *.sh ]] && [[ ! -x "$target_file" ]]; then
                log_warning "Module $module is not executable, fixing permissions"
                chmod +x "$target_file"
            fi

            # Validate syntax again
            if ! bash -n "$target_file" 2>/dev/null; then
                log_error "Post-sync validation failed for $module: syntax errors"
                ((validation_errors++))
            fi
        fi
    done

    if [[ $validation_errors -gt 0 ]]; then
        log_error "Post-sync validation found $validation_errors errors"
        return 1
    else
        log_success "Post-sync validation passed"
        return 0
    fi
}

# Main execution function
main() {
    local exit_code=0

    # Initialize environment first
    init_sync_environment

    log_info "Starting BrewNix Core Module Synchronization"
    log_info "Date: $(date)"
    log_info "Project Root: $PROJECT_ROOT"

    # Sync all modules
    sync_all_modules

    # Validate results
    if ! validate_sync_results; then
        log_error "Synchronization validation failed"
        exit_code=1
    fi

    # Generate report
    generate_sync_report

    # Calculate final statistics
    local success_rate
    success_rate=$(calculate_success_rate)

    log_info "Synchronization completed"
    log_info "Final Statistics:"
    log_info "  - Total modules: $TOTAL_MODULES"
    log_info "  - Synchronized: $SYNCED_MODULES"
    log_info "  - Skipped: $SKIPPED_MODULES"
    log_info "  - Failed: $FAILED_MODULES"
    log_info "  - Success rate: ${success_rate}%"

    if [[ $exit_code -eq 0 ]]; then
        log_success "✅ Core module synchronization completed successfully"
    else
        log_error "❌ Core module synchronization completed with errors"
    fi

    log_info "Detailed log: $SYNC_LOG_FILE"
    log_info "Report: $SYNC_REPORT_FILE"

    return $exit_code
}

# Execute main function
main "$@"
