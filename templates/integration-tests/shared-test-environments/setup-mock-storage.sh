#!/bin/bash

# BrewNix Mock Storage Environment Setup
# Phase 2.1.2 - Cross-Submodule Integration Testing
#
# This script sets up a mock storage environment for integration testing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
STORAGE_BASE_DIR="${SCRIPT_DIR}/mock-storage"
MOCK_ISCSI_TARGET="iqn.2025-01.com.brewnix:mock-target"
MOCK_SMB_SHARE="mock-share"

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[MOCK-STORAGE]${NC} $1"
}

log_error() {
    echo -e "${RED}[MOCK-STORAGE]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[MOCK-STORAGE]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[MOCK-STORAGE]${NC} $1"
}

# Check if running as root (required for some storage operations)
check_privileges() {
    if [ "$EUID" -ne 0 ]; then
        log_warning "Some storage operations may require root privileges"
        log_info "Consider running with sudo if you encounter permission issues"
    fi
}

# Check if required tools are available
check_dependencies() {
    local required_tools=("dd" "mkfs.ext4" "mount" "umount")
    local optional_tools=("nfs-kernel-server" "tgt" "samba")

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool not found: $tool"
            return 1
        fi
    done

    for tool in "${optional_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_warning "Optional tool not found: $tool"
        fi
    done

    log_success "Dependency check completed"
}

# Create mock storage directories and files
create_mock_storage() {
    log_info "Creating mock storage structure..."

    # Create base directory
    mkdir -p "$STORAGE_BASE_DIR"

    # Create volume directories
    local volumes=("test-vol-1:100G:ssd" "test-vol-2:500G:hdd" "test-vol-3:200G:nvme")

    for vol_spec in "${volumes[@]}"; do
        local name="${vol_spec%%:*}"
        local size_spec="${vol_spec#*:}"
        local size="${size_spec%%:*}"
        local type="${size_spec##*:}"

        local vol_dir="${STORAGE_BASE_DIR}/${name}"
        mkdir -p "$vol_dir"

        # Create mock volume file
        local vol_file="${vol_dir}/volume.img"
        if [ ! -f "$vol_file" ]; then
            log_info "Creating mock volume: $name (${size}, $type)"

            # Create a sparse file for the volume
            dd if=/dev/zero of="$vol_file" bs=1M count=1 seek=$(( ${size%G} * 1024 - 1 )) 2>/dev/null || true

            # Create filesystem on the volume
            mkfs.ext4 -F "$vol_file" >/dev/null 2>&1 || true

            log_success "Mock volume created: $vol_file"
        else
            log_info "Mock volume already exists: $vol_file"
        fi

        # Create volume metadata
        cat > "${vol_dir}/metadata.json" << EOF
{
  "name": "${name}",
  "size": "${size}",
  "type": "${type}",
  "path": "${vol_file}",
  "filesystem": "ext4",
  "created": "$(date -Iseconds)",
  "status": "available"
}
EOF
    done

    log_success "Mock storage structure created"
}

# Setup NFS export
setup_nfs_export() {
    log_info "Setting up NFS export..."

    if ! command -v exportfs &> /dev/null; then
        log_warning "NFS server not available, skipping NFS setup"
        return 0
    fi

    # Create exports file entry
    local exports_entry="${STORAGE_BASE_DIR} *(rw,sync,no_subtree_check,no_root_squash)"

    # Add to /etc/exports if not already present
    if ! grep -q "^${STORAGE_BASE_DIR}" /etc/exports 2>/dev/null; then
        echo "$exports_entry" >> /etc/exports
        log_info "Added NFS export: $exports_entry"
    else
        log_info "NFS export already configured"
    fi

    # Export the filesystem
    exportfs -ra

    # Start NFS service if available
    if command -v systemctl &> /dev/null; then
        systemctl restart nfs-kernel-server 2>/dev/null || true
    fi

    log_success "NFS export configured: $STORAGE_BASE_DIR"
}

# Setup iSCSI target
setup_iscsi_target() {
    log_info "Setting up iSCSI target..."

    if ! command -v tgtadm &> /dev/null; then
        log_warning "iSCSI target daemon not available, skipping iSCSI setup"
        return 0
    fi

    # Create iSCSI target configuration
    local target_config="/etc/tgt/conf.d/brewnix-mock.conf"

    cat > "$target_config" << EOF
<target ${MOCK_ISCSI_TARGET}>
    backing-store ${STORAGE_BASE_DIR}/test-vol-1/volume.img
    initiator-address ALL
    incominguser test-user test-password
</target>
EOF

    log_info "iSCSI target configuration created: $target_config"

    # Restart iSCSI target service
    if command -v systemctl &> /dev/null; then
        systemctl restart tgt 2>/dev/null || true
    fi

    log_success "iSCSI target configured: $MOCK_ISCSI_TARGET"
}

# Setup SMB/CIFS share
setup_smb_share() {
    log_info "Setting up SMB share..."

    if ! command -v smbpasswd &> /dev/null; then
        log_warning "Samba not available, skipping SMB setup"
        return 0
    fi

    # Create Samba configuration
    local smb_config="/etc/samba/smb.conf"

    # Backup existing config
    if [ -f "$smb_config" ] && [ ! -f "${smb_config}.brewnix-backup" ]; then
        cp "$smb_config" "${smb_config}.brewnix-backup"
    fi

    # Add share configuration
    cat >> "$smb_config" << EOF

[brewnix-mock-share]
   path = ${STORAGE_BASE_DIR}
   browseable = yes
   writable = yes
   guest ok = yes
   public = yes
   create mask = 0644
   directory mask = 0755
EOF

    log_info "SMB share configuration added to: $smb_config"

    # Restart Samba service
    if command -v systemctl &> /dev/null; then
        systemctl restart smbd 2>/dev/null || true
    fi

    log_success "SMB share configured: $MOCK_SMB_SHARE"
}

# Create storage configuration file
create_storage_config() {
    log_info "Creating storage configuration file..."

    local storage_config="${SCRIPT_DIR}/storage-config.json"

    cat > "$storage_config" << EOF
{
  "base_directory": "${STORAGE_BASE_DIR}",
  "volumes": [
    {
      "name": "test-vol-1",
      "path": "${STORAGE_BASE_DIR}/test-vol-1/volume.img",
      "size": "100G",
      "type": "ssd",
      "filesystem": "ext4",
      "status": "available"
    },
    {
      "name": "test-vol-2",
      "path": "${STORAGE_BASE_DIR}/test-vol-2/volume.img",
      "size": "500G",
      "type": "hdd",
      "filesystem": "ext4",
      "status": "available"
    },
    {
      "name": "test-vol-3",
      "path": "${STORAGE_BASE_DIR}/test-vol-3/volume.img",
      "size": "200G",
      "type": "nvme",
      "filesystem": "ext4",
      "status": "available"
    }
  ],
  "exports": {
    "nfs": {
      "enabled": true,
      "export_path": "${STORAGE_BASE_DIR}",
      "options": "*(rw,sync,no_subtree_check,no_root_squash)"
    },
    "iscsi": {
      "enabled": true,
      "target_iqn": "${MOCK_ISCSI_TARGET}",
      "lun": 1,
      "backing_store": "${STORAGE_BASE_DIR}/test-vol-1/volume.img"
    },
    "smb": {
      "enabled": true,
      "share_name": "brewnix-mock-share",
      "path": "${STORAGE_BASE_DIR}",
      "guest_access": true
    }
  },
  "created": "$(date -Iseconds)",
  "test_environment": true
}
EOF

    log_success "Storage configuration created: $storage_config"
}

# Verify storage setup
verify_setup() {
    log_info "Verifying storage setup..."

    local issues_found=0

    # Check base directory
    if [ ! -d "$STORAGE_BASE_DIR" ]; then
        log_error "Storage base directory not found: $STORAGE_BASE_DIR"
        ((issues_found++))
    else
        log_success "Storage base directory exists: $STORAGE_BASE_DIR"
    fi

    # Check volumes
    local volumes=("test-vol-1" "test-vol-2" "test-vol-3")
    for vol in "${volumes[@]}"; do
        local vol_file="${STORAGE_BASE_DIR}/${vol}/volume.img"
        if [ ! -f "$vol_file" ]; then
            log_error "Volume file not found: $vol_file"
            ((issues_found++))
        else
            log_success "Volume file exists: $vol_file"
        fi
    done

    # Check NFS export
    if command -v exportfs &> /dev/null; then
        if exportfs -v | grep -q "$STORAGE_BASE_DIR"; then
            log_success "NFS export is active"
        else
            log_warning "NFS export not found"
        fi
    fi

    # Check iSCSI target
    if command -v tgtadm &> /dev/null; then
        if tgtadm --lld iscsi --op show --mode target | grep -q "$MOCK_ISCSI_TARGET"; then
            log_success "iSCSI target is active"
        else
            log_warning "iSCSI target not found"
        fi
    fi

    if [ $issues_found -gt 0 ]; then
        log_error "Storage setup verification failed with $issues_found issues"
        return 1
    else
        log_success "Storage setup verification passed"
        return 0
    fi
}

# Cleanup function
cleanup_storage() {
    log_info "Cleaning up mock storage environment..."

    # Stop services
    if command -v systemctl &> /dev/null; then
        systemctl stop nfs-kernel-server 2>/dev/null || true
        systemctl stop tgt 2>/dev/null || true
        systemctl stop smbd 2>/dev/null || true
    fi

    # Remove NFS export
    if [ -f /etc/exports ]; then
        sed -i "\|^${STORAGE_BASE_DIR}|d" /etc/exports
        exportfs -ra 2>/dev/null || true
    fi

    # Remove iSCSI target config
    rm -f /etc/tgt/conf.d/brewnix-mock.conf
    tgt-admin --update ALL 2>/dev/null || true

    # Remove Samba configuration
    if [ -f /etc/samba/smb.conf ]; then
        sed -i '/^\[brewnix-mock-share\]/,/^$/d' /etc/samba/smb.conf
    fi

    # Remove storage files
    if [ -d "$STORAGE_BASE_DIR" ]; then
        rm -rf "$STORAGE_BASE_DIR"
        log_success "Mock storage directory removed: $STORAGE_BASE_DIR"
    fi

    log_success "Mock storage environment cleaned up"
}

# Main execution
main() {
    local action="${1:-setup}"

    case "$action" in
        "setup")
            log_info "Setting up mock storage environment for integration testing..."

            check_privileges
            check_dependencies
            create_mock_storage
            setup_nfs_export
            setup_iscsi_target
            setup_smb_share
            create_storage_config

            if verify_setup; then
                log_success "Mock storage environment setup completed successfully!"
                log_info "Storage Details:"
                log_info "  - Base Directory: $STORAGE_BASE_DIR"
                log_info "  - NFS Export: $STORAGE_BASE_DIR"
                log_info "  - iSCSI Target: $MOCK_ISCSI_TARGET"
                log_info "  - SMB Share: brewnix-mock-share"
            else
                log_error "Mock storage environment setup failed"
                exit 1
            fi
            ;;
        "cleanup")
            cleanup_storage
            ;;
        "verify")
            verify_setup
            ;;
        *)
            log_error "Usage: $0 {setup|cleanup|verify}"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
