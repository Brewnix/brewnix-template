#!/bin/bash

# BrewNix Mock Network Environment Setup
# Phase 2.1.2 - Cross-Submodule Integration Testing
#
# This script sets up a mock network environment for integration testing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
BRIDGE_NAME="brewnix-br0"
VLAN_BASE=10
SUBNET_PREFIX="10.0"

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[MOCK-NETWORK]${NC} $1"
}

log_error() {
    echo -e "${RED}[MOCK-NETWORK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[MOCK-NETWORK]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[MOCK-NETWORK]${NC} $1"
}

# Check if running as root (required for network setup)
check_privileges() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root for network setup"
        log_info "Usage: sudo $0"
        exit 1
    fi
}

# Check if required tools are available
check_dependencies() {
    local required_tools=("ip" "brctl" "iptables" "dhcpd")

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_warning "Required tool not found: $tool"
            case $tool in
                "brctl")
                    log_info "Installing bridge-utils..."
                    apt-get update && apt-get install -y bridge-utils
                    ;;
                "dhcpd")
                    log_info "Installing isc-dhcp-server..."
                    apt-get update && apt-get install -y isc-dhcp-server
                    ;;
            esac
        fi
    done

    log_success "All required tools are available"
}

# Create network bridge
create_bridge() {
    log_info "Creating network bridge: $BRIDGE_NAME"

    # Remove existing bridge if it exists
    if ip link show "$BRIDGE_NAME" &> /dev/null; then
        log_warning "Removing existing bridge: $BRIDGE_NAME"
        ip link set "$BRIDGE_NAME" down
        brctl delbr "$BRIDGE_NAME"
    fi

    # Create new bridge
    brctl addbr "$BRIDGE_NAME"
    ip link set "$BRIDGE_NAME" up

    # Configure bridge IP
    ip addr add "${SUBNET_PREFIX}.${VLAN_BASE}.1/24" dev "$BRIDGE_NAME"

    log_success "Network bridge created: $BRIDGE_NAME"
}

# Create VLAN interfaces
create_vlans() {
    log_info "Creating VLAN interfaces..."

    local vlans=("management:10" "storage:20" "compute:30")

    for vlan_spec in "${vlans[@]}"; do
        local name="${vlan_spec%%:*}"
        local id="${vlan_spec##*:}"

        local vlan_interface="${BRIDGE_NAME}.${id}"

        log_info "Creating VLAN interface: $vlan_interface ($name)"

        # Create VLAN interface
        ip link add link "$BRIDGE_NAME" name "$vlan_interface" type vlan id "$id"
        ip link set "$vlan_interface" up

        # Configure VLAN IP
        ip addr add "${SUBNET_PREFIX}.${id}.1/24" dev "$vlan_interface"

        log_success "VLAN interface created: $vlan_interface"
    done
}

# Setup DHCP server configuration
setup_dhcp() {
    log_info "Setting up DHCP server configuration..."

    local dhcp_config="/etc/dhcp/dhcpd.conf"
    local dhcp_backup
    dhcp_backup="${dhcp_config}.backup.$(date +%Y%m%d_%H%M%S)"

    # Backup existing configuration
    if [ -f "$dhcp_config" ]; then
        cp "$dhcp_config" "$dhcp_backup"
        log_info "Backed up existing DHCP config to: $dhcp_backup"
    fi

    # Create new DHCP configuration
    cat > "$dhcp_config" << EOF
# BrewNix Integration Test DHCP Configuration
# Generated on $(date)

# Global options
option domain-name "brewnix.test";
option domain-name-servers 8.8.8.8, 8.8.4.4;
default-lease-time 600;
max-lease-time 7200;
ddns-update-style none;

# Management network
subnet ${SUBNET_PREFIX}.10.0 netmask 255.255.255.0 {
  range ${SUBNET_PREFIX}.10.100 ${SUBNET_PREFIX}.10.200;
  option routers ${SUBNET_PREFIX}.10.1;
  option broadcast-address ${SUBNET_PREFIX}.10.255;
}

# Storage network
subnet ${SUBNET_PREFIX}.20.0 netmask 255.255.255.0 {
  range ${SUBNET_PREFIX}.20.100 ${SUBNET_PREFIX}.20.200;
  option routers ${SUBNET_PREFIX}.20.1;
  option broadcast-address ${SUBNET_PREFIX}.20.255;
}

# Compute network
subnet ${SUBNET_PREFIX}.30.0 netmask 255.255.255.0 {
  range ${SUBNET_PREFIX}.30.100 ${SUBNET_PREFIX}.30.200;
  option routers ${SUBNET_PREFIX}.30.1;
  option broadcast-address ${SUBNET_PREFIX}.30.255;
}
EOF

    log_success "DHCP configuration created: $dhcp_config"
}

# Configure iptables rules
setup_iptables() {
    log_info "Setting up iptables rules for test network..."

    # Allow forwarding
    iptables -P FORWARD ACCEPT

    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward

    # NAT rules for internet access
    iptables -t nat -A POSTROUTING -o "$(ip route show default | awk '/default/ {print $5}')" -j MASQUERADE

    # Allow DHCP traffic
    iptables -A INPUT -p udp --dport 67:68 --sport 67:68 -j ACCEPT

    # Allow DNS traffic
    iptables -A INPUT -p udp --dport 53 -j ACCEPT
    iptables -A INPUT -p tcp --dport 53 -j ACCEPT

    log_success "Iptables rules configured"
}

# Create network configuration file for tests
create_network_config() {
    log_info "Creating network configuration file for tests..."

    local network_config="${SCRIPT_DIR}/network-config.json"

    cat > "$network_config" << EOF
{
  "bridge": {
    "name": "${BRIDGE_NAME}",
    "ip": "${SUBNET_PREFIX}.${VLAN_BASE}.1",
    "subnet": "${SUBNET_PREFIX}.${VLAN_BASE}.0/24"
  },
  "vlans": [
    {
      "name": "management",
      "id": 10,
      "interface": "${BRIDGE_NAME}.10",
      "subnet": "${SUBNET_PREFIX}.10.0/24",
      "gateway": "${SUBNET_PREFIX}.10.1",
      "dhcp_range": "${SUBNET_PREFIX}.10.100-${SUBNET_PREFIX}.10.200"
    },
    {
      "name": "storage",
      "id": 20,
      "interface": "${BRIDGE_NAME}.20",
      "subnet": "${SUBNET_PREFIX}.20.0/24",
      "gateway": "${SUBNET_PREFIX}.20.1",
      "dhcp_range": "${SUBNET_PREFIX}.20.100-${SUBNET_PREFIX}.20.200"
    },
    {
      "name": "compute",
      "id": 30,
      "interface": "${BRIDGE_NAME}.30",
      "subnet": "${SUBNET_PREFIX}.30.0/24",
      "gateway": "${SUBNET_PREFIX}.30.1",
      "dhcp_range": "${SUBNET_PREFIX}.30.100-${SUBNET_PREFIX}.30.200"
    }
  ],
  "dhcp": {
    "config_file": "/etc/dhcp/dhcpd.conf",
    "lease_time": 600,
    "max_lease_time": 7200
  },
  "dns": {
    "servers": ["8.8.8.8", "8.8.4.4"],
    "domain": "brewnix.test"
  }
}
EOF

    log_success "Network configuration created: $network_config"
}

# Start DHCP service
start_dhcp_service() {
    log_info "Starting DHCP service..."

    # Stop any existing DHCP service
    systemctl stop isc-dhcp-server 2>/dev/null || true

    # Start DHCP service
    systemctl start isc-dhcp-server

    # Enable DHCP service to start on boot
    systemctl enable isc-dhcp-server

    log_success "DHCP service started and enabled"
}

# Verify network setup
verify_setup() {
    log_info "Verifying network setup..."

    local issues_found=0

    # Check bridge
    if ! ip link show "$BRIDGE_NAME" &> /dev/null; then
        log_error "Bridge $BRIDGE_NAME not found"
        ((issues_found++))
    else
        log_success "Bridge $BRIDGE_NAME is up"
    fi

    # Check VLANs
    local vlans=("10" "20" "30")
    for vlan_id in "${vlans[@]}"; do
        local vlan_interface="${BRIDGE_NAME}.${vlan_id}"
        if ! ip link show "$vlan_interface" &> /dev/null; then
            log_error "VLAN interface $vlan_interface not found"
            ((issues_found++))
        else
            log_success "VLAN interface $vlan_interface is up"
        fi
    done

    # Check DHCP service
    if ! systemctl is-active --quiet isc-dhcp-server; then
        log_error "DHCP service is not running"
        ((issues_found++))
    else
        log_success "DHCP service is running"
    fi

    if [ $issues_found -gt 0 ]; then
        log_error "Network setup verification failed with $issues_found issues"
        return 1
    else
        log_success "Network setup verification passed"
        return 0
    fi
}

# Cleanup function (for test teardown)
cleanup_network() {
    log_info "Cleaning up test network environment..."

    # Stop DHCP service
    systemctl stop isc-dhcp-server 2>/dev/null || true
    systemctl disable isc-dhcp-server 2>/dev/null || true

    # Remove VLAN interfaces
    local vlans=("10" "20" "30")
    for vlan_id in "${vlans[@]}"; do
        local vlan_interface="${BRIDGE_NAME}.${vlan_id}"
        ip link delete "$vlan_interface" 2>/dev/null || true
    done

    # Remove bridge
    ip link set "$BRIDGE_NAME" down 2>/dev/null || true
    brctl delbr "$BRIDGE_NAME" 2>/dev/null || true

    log_success "Test network environment cleaned up"
}

# Main execution
main() {
    local action="${1:-setup}"

    case "$action" in
        "setup")
            log_info "Setting up mock network environment for integration testing..."

            check_privileges
            check_dependencies
            create_bridge
            create_vlans
            setup_dhcp
            setup_iptables
            create_network_config
            start_dhcp_service

            if verify_setup; then
                log_success "Mock network environment setup completed successfully!"
                log_info "Network Details:"
                log_info "  - Bridge: $BRIDGE_NAME"
                log_info "  - Management VLAN: ${BRIDGE_NAME}.10 (${SUBNET_PREFIX}.10.0/24)"
                log_info "  - Storage VLAN: ${BRIDGE_NAME}.20 (${SUBNET_PREFIX}.20.0/24)"
                log_info "  - Compute VLAN: ${BRIDGE_NAME}.30 (${SUBNET_PREFIX}.30.0/24)"
                log_info "  - DHCP: Running"
            else
                log_error "Mock network environment setup failed"
                exit 1
            fi
            ;;
        "cleanup")
            cleanup_network
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
