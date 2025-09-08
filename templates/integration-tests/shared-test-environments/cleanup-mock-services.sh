#!/bin/bash

# BrewNix Shared Test Environments Cleanup
# Phase 2.1.2 - Cross-Submodule Integration Testing
#
# This script cleans up all shared test environments

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[CLEANUP]${NC} $1"
}

log_error() {
    echo -e "${RED}[CLEANUP]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[CLEANUP]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[CLEANUP]${NC} $1"
}

# Cleanup mock Proxmox environment
cleanup_mock_proxmox() {
    log_info "Cleaning up mock Proxmox environment..."

    local container_name="brewnix-mock-proxmox"

    # Stop and remove container
    if docker ps -a --format 'table {{.Names}}' | grep -q "^${container_name}$"; then
        docker stop "$container_name" >/dev/null 2>&1 || true
        docker rm "$container_name" >/dev/null 2>&1 || true
        log_success "Mock Proxmox container removed: $container_name"
    else
        log_info "Mock Proxmox container not found"
    fi

    # Remove Docker image
    local image_name="brewnix/mock-proxmox:latest"
    if docker images --format 'table {{.Repository}}:{{.Tag}}' | grep -q "^${image_name}$"; then
        docker rmi "$image_name" >/dev/null 2>&1 || true
        log_success "Mock Proxmox image removed: $image_name"
    fi

    # Remove mock data directory
    local mock_data_dir="${SCRIPT_DIR}/mock-data"
    if [ -d "$mock_data_dir" ]; then
        rm -rf "$mock_data_dir"
        log_success "Mock data directory removed: $mock_data_dir"
    fi
}

# Cleanup mock network environment
cleanup_mock_network() {
    log_info "Cleaning up mock network environment..."

    local bridge_name="brewnix-br0"

    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        # Stop DHCP service
        systemctl stop isc-dhcp-server 2>/dev/null || true
        systemctl disable isc-dhcp-server 2>/dev/null || true

        # Remove VLAN interfaces
        local vlans=("10" "20" "30")
        for vlan_id in "${vlans[@]}"; do
            local vlan_interface="${bridge_name}.${vlan_id}"
            ip link delete "$vlan_interface" 2>/dev/null || true
        done

        # Remove bridge
        ip link set "$bridge_name" down 2>/dev/null || true
        brctl delbr "$bridge_name" 2>/dev/null || true

        log_success "Mock network environment cleaned up"
    else
        log_warning "Not running as root - skipping network cleanup"
        log_info "Run with sudo to clean up network environment"
    fi

    # Remove network configuration file
    local network_config="${SCRIPT_DIR}/network-config.json"
    if [ -f "$network_config" ]; then
        rm -f "$network_config"
        log_success "Network configuration file removed: $network_config"
    fi
}

# Cleanup mock storage environment
cleanup_mock_storage() {
    log_info "Cleaning up mock storage environment..."

    local storage_base_dir="${SCRIPT_DIR}/mock-storage"

    # Check if running as root for service cleanup
    if [ "$EUID" -eq 0 ]; then
        # Stop services
        systemctl stop nfs-kernel-server 2>/dev/null || true
        systemctl stop tgt 2>/dev/null || true
        systemctl stop smbd 2>/dev/null || true

        # Remove NFS export
        if [ -f /etc/exports ]; then
            sed -i "\|^${storage_base_dir}|d" /etc/exports
            exportfs -ra 2>/dev/null || true
        fi

        # Remove iSCSI target config
        rm -f /etc/tgt/conf.d/brewnix-mock.conf
        tgt-admin --update ALL 2>/dev/null || true

        # Remove Samba configuration
        if [ -f /etc/samba/smb.conf ]; then
            sed -i '/^\[brewnix-mock-share\]/,/^$/d' /etc/samba/smb.conf
        fi

        log_success "Storage services cleaned up"
    else
        log_warning "Not running as root - skipping service cleanup"
        log_info "Run with sudo to clean up storage services"
    fi

    # Remove storage files
    if [ -d "$storage_base_dir" ]; then
        rm -rf "$storage_base_dir"
        log_success "Mock storage directory removed: $storage_base_dir"
    fi

    # Remove storage configuration file
    local storage_config="${SCRIPT_DIR}/storage-config.json"
    if [ -f "$storage_config" ]; then
        rm -f "$storage_config"
        log_success "Storage configuration file removed: $storage_config"
    fi
}

# Cleanup test result files
cleanup_test_results() {
    log_info "Cleaning up test result files..."

    local project_root
    project_root="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
    local test_results_dir="${project_root}/build/integration-test-results"

    if [ -d "$test_results_dir" ]; then
        rm -rf "$test_results_dir"
        log_success "Test results directory removed: $test_results_dir"
    fi
}

# Cleanup Docker resources
cleanup_docker_resources() {
    log_info "Cleaning up Docker resources..."

    # Remove dangling images
    docker image prune -f >/dev/null 2>&1 || true

    # Remove unused volumes
    docker volume prune -f >/dev/null 2>&1 || true

    # Remove unused networks
    docker network prune -f >/dev/null 2>&1 || true

    log_success "Docker resources cleaned up"
}

# Main cleanup function
main() {
    log_info "Starting cleanup of shared test environments..."

    # Cleanup in reverse order of setup
    cleanup_mock_proxmox
    cleanup_mock_network
    cleanup_mock_storage
    cleanup_test_results
    cleanup_docker_resources

    log_success "Cleanup of shared test environments completed!"
    log_info "All mock environments and test artifacts have been removed"
}

# Execute main function
main "$@"
