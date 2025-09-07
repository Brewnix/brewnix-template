#!/bin/bash
# scripts/backup/backup.sh - Backup and restore functions

# Source core modules
source "${SCRIPT_DIR}/core/init.sh"
source "${SCRIPT_DIR}/core/config.sh"
source "${SCRIPT_DIR}/core/logging.sh"

# Backup configuration
BACKUP_ROOT="${BACKUP_ROOT:-${PROJECT_ROOT}/backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
BACKUP_COMPRESSION="${BACKUP_COMPRESSION:-gzip}"

# Initialize backup system
init_backup() {
    mkdir -p "$BACKUP_ROOT"
    log_info "Backup system initialized"
    log_debug "Backup root: $BACKUP_ROOT"
    log_debug "Retention: $BACKUP_RETENTION_DAYS days"
}

# Create timestamped backup
create_backup() {
    local name="$1"
    local source_dir="${2:-$PROJECT_ROOT}"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="${name}_${timestamp}"
    local backup_dir="${BACKUP_ROOT}/${backup_name}"

    log_section "Creating backup: $backup_name"

    # Create backup directory
    mkdir -p "$backup_dir"

    # Create backup using rsync
    log_command rsync -av --delete \
        --exclude='.git' \
        --exclude='node_modules' \
        --exclude='__pycache__' \
        --exclude='*.log' \
        --exclude='backups' \
        "$source_dir/" "$backup_dir/"

    if [[ $? -eq 0 ]]; then
        # Create compressed archive
        local archive_name="${backup_name}.tar.gz"
        local archive_path="${BACKUP_ROOT}/${archive_name}"

        log_info "Creating compressed archive: $archive_name"
        log_command tar -czf "$archive_path" -C "$BACKUP_ROOT" "$backup_name"

        if [[ $? -eq 0 ]]; then
            # Remove uncompressed backup
            rm -rf "$backup_dir"
            log_info "Backup created successfully: $archive_path"
            echo "$archive_path"
            return 0
        else
            log_error "Failed to create compressed archive"
            return 1
        fi
    else
        log_error "Failed to create backup"
        rm -rf "$backup_dir"
        return 1
    fi
}

# Restore from backup
restore_backup() {
    local backup_path="$1"
    local target_dir="${2:-$PROJECT_ROOT}"
    local temp_dir="${BUILD_DIR}/restore_temp"

    if [[ ! -f "$backup_path" ]]; then
        log_error "Backup file not found: $backup_path"
        return 1
    fi

    log_section "Restoring from backup: $(basename "$backup_path")"

    # Create temporary directory
    mkdir -p "$temp_dir"

    # Extract backup
    log_command tar -xzf "$backup_path" -C "$temp_dir"

    if [[ $? -eq 0 ]]; then
        # Get extracted directory name
        local extracted_dir
        extracted_dir=$(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)

        if [[ -z "$extracted_dir" ]]; then
            log_error "No directory found in backup archive"
            rm -rf "$temp_dir"
            return 1
        fi

        # Restore files
        log_command rsync -av --delete "$extracted_dir/" "$target_dir/"

        if [[ $? -eq 0 ]]; then
            log_info "Backup restored successfully to: $target_dir"
            rm -rf "$temp_dir"
            return 0
        else
            log_error "Failed to restore backup"
            rm -rf "$temp_dir"
            return 1
        fi
    else
        log_error "Failed to extract backup archive"
        rm -rf "$temp_dir"
        return 1
    fi
}

# List available backups
list_backups() {
    local pattern="${1:-*}"

    log_info "Available backups:"
    find "$BACKUP_ROOT" -name "${pattern}.tar.gz" -type f -printf "%T@ %p\n" | \
        sort -nr | \
        while read -r line; do
            local timestamp size filename
            timestamp=$(echo "$line" | cut -d' ' -f1)
            filename=$(echo "$line" | cut -d' ' -f2-)
            size=$(du -h "$filename" | cut -f1)

            printf "  %s (%s) - %s\n" \
                "$(basename "$filename" .tar.gz)" \
                "$size" \
                "$(date -d "@$timestamp" '+%Y-%m-%d %H:%M:%S')"
        done
}

# Clean old backups
cleanup_backups() {
    local days="${1:-$BACKUP_RETENTION_DAYS}"

    log_section "Cleaning up backups older than $days days"

    local count=0
    while IFS= read -r -d '' file; do
        log_command rm -f "$file"
        ((count++))
    done < <(find "$BACKUP_ROOT" -name "*.tar.gz" -type f -mtime +"$days" -print0)

    if [[ $count -gt 0 ]]; then
        log_info "Cleaned up $count old backup(s)"
    else
        log_info "No old backups to clean up"
    fi
}

# Backup Proxmox configuration
backup_proxmox() {
    local proxmox_host="${1:-$(get_config_value 'proxmox.host')}"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="proxmox_config_${timestamp}"
    local temp_dir="${BUILD_DIR}/proxmox_backup"

    if [[ -z "$proxmox_host" ]]; then
        log_error "Proxmox host not configured"
        return 1
    fi

    log_section "Backing up Proxmox configuration from: $proxmox_host"

    # Create temporary directory
    mkdir -p "$temp_dir"

    # Backup using Proxmox API or SSH
    if command -v pvesh &> /dev/null; then
        # Use local pvesh if available
        log_command pvesh get /cluster/resources > "${temp_dir}/resources.json"
        log_command pvesh get /cluster/config > "${temp_dir}/cluster_config.json"
        log_command pvesh get /nodes > "${temp_dir}/nodes.json"
    else
        # Use SSH to backup
        log_command scp -r "root@${proxmox_host}:/etc/pve" "${temp_dir}/"
    fi

    if [[ $? -eq 0 ]]; then
        # Create backup archive
        local archive_path="${BACKUP_ROOT}/${backup_name}.tar.gz"
        log_command tar -czf "$archive_path" -C "$temp_dir" .

        if [[ $? -eq 0 ]]; then
            log_info "Proxmox backup created: $archive_path"
            rm -rf "$temp_dir"
            echo "$archive_path"
            return 0
        fi
    fi

    log_error "Failed to backup Proxmox configuration"
    rm -rf "$temp_dir"
    return 1
}

# Backup OPNsense configuration
backup_opnsense() {
    local opnsense_host="${1:-$(get_config_value 'opnsense.host')}"
    local api_key="${2:-$(get_config_value 'opnsense.api_key')}"
    local api_secret="${3:-$(get_config_value 'opnsense.api_secret')}"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_name="opnsense_config_${timestamp}"

    if [[ -z "$opnsense_host" || -z "$api_key" || -z "$api_secret" ]]; then
        log_error "OPNsense configuration incomplete"
        return 1
    fi

    log_section "Backing up OPNsense configuration from: $opnsense_host"

    # Use OPNsense API to get configuration
    local config_data
    config_data=$(curl -s -k \
        -H "Authorization: Basic $(echo -n "${api_key}:${api_secret}" | base64)" \
        "https://${opnsense_host}/api/backup/backup/download")

    if [[ $? -eq 0 && -n "$config_data" ]]; then
        local backup_file="${BACKUP_ROOT}/${backup_name}.xml"
        echo "$config_data" > "$backup_file"

        log_info "OPNsense backup created: $backup_file"
        echo "$backup_file"
        return 0
    else
        log_error "Failed to backup OPNsense configuration"
        return 1
    fi
}

# Main backup function
backup_main() {
    local command="$1"
    shift

    case "$command" in
        create)
            create_backup "$@"
            ;;
        restore)
            restore_backup "$@"
            ;;
        list)
            list_backups "$@"
            ;;
        cleanup)
            cleanup_backups "$@"
            ;;
        proxmox)
            backup_proxmox "$@"
            ;;
        opnsense)
            backup_opnsense "$@"
            ;;
        *)
            log_error "Unknown backup command: $command"
            echo "Usage: $0 backup <create|restore|list|cleanup|proxmox|opnsense> [options]"
            return 1
            ;;
    esac
}

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_environment
    init_logging
    init_backup
    backup_main "$@"
fi
