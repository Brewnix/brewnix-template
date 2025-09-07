#!/bin/bash
# Test USB Bootstrap Creation (Dry Run)
# This simulates the USB bootstrap creation without requiring actual USB device

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"
SITE_CONFIG="$1"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Simulate USB bootstrap creation
log_info "=== USB Bootstrap Creation Test (Dry Run) ==="
log_info "Site configuration: $SITE_CONFIG"

# Create bootstrap directory
bootstrap_dir="${BUILD_DIR}/usb-bootstrap"
mkdir -p "$bootstrap_dir"
log_info "Created bootstrap directory: $bootstrap_dir"

# Copy site configuration
cp "$SITE_CONFIG" "$bootstrap_dir/site-config.yml"
log_success "Copied site configuration to bootstrap directory"

# Copy SSH keys if available
if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
    cp "$HOME/.ssh/id_ed25519.pub" "$bootstrap_dir/authorized_keys"
    log_success "Copied SSH public key"
else
    log_warning "No SSH public key found at $HOME/.ssh/id_ed25519.pub"
    echo "# Placeholder for SSH keys" > "$bootstrap_dir/authorized_keys"
fi

# Create bootstrap script
cat > "$bootstrap_dir/bootstrap.sh" << 'EOF'
#!/bin/bash
# USB Bootstrap Script for Proxmox Firewall (Network-Aware GitOps)
set -euo pipefail

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1"
}

log_info "=== Starting Network-Aware Proxmox Firewall USB Bootstrap ==="

# Display embedded configuration summary
log_info "Embedded configuration summary:"
if [[ -f "site-config.yml" ]]; then
    echo "Site: $(grep '^site_name:' site-config.yml | cut -d'"' -f2 || echo 'unknown')"
    echo "Network Prefix: $(grep '^network_prefix:' site-config.yml | cut -d'"' -f2 || echo 'unknown')"
    echo "VLANs: $(grep -c 'vlan_id:' site-config.yml || echo '0')"
    echo "Devices: $(grep -A 100 '^devices:' site-config.yml | grep -c 'type:' || echo '0')"
fi

# Copy configuration to system
log_info "Setting up system configuration..."
mkdir -p /opt/brewnix-firewall
cp site-config.yml /opt/brewnix-firewall/

# Setup SSH access
if [[ -f "authorized_keys" ]]; then
    mkdir -p /root/.ssh
    cp authorized_keys /root/.ssh/
    chmod 600 /root/.ssh/authorized_keys
    log_success "SSH access configured"
fi

# Install dependencies
log_info "Installing dependencies..."
apt-get update > /dev/null 2>&1
apt-get install -y git ansible python3-pip curl > /dev/null 2>&1

# Clone firewall repository
log_info "Cloning GitOps repository..."
cd /opt/brewnix-firewall
git clone https://github.com/Brewnix/brewnix-template.git repo > /dev/null 2>&1
cd repo

# Setup environment variables
export TAILSCALE_AUTH_KEY="auto-generated-or-from-config"
export GRAFANA_ADMIN_PASSWORD="auto-generated-or-from-config"

# Run network-aware GitOps deployment
log_info "Running network-aware GitOps deployment..."
./vendor/proxmox-firewall/gitops/deploy-gitops.sh --operation deploy /opt/brewnix-firewall/site-config.yml

log_success "=== Network-Aware USB Bootstrap Completed Successfully ==="
log_info "GitOps deployment active with drift detection enabled"
log_info "USB device can be safely removed"
EOF

chmod +x "$bootstrap_dir/bootstrap.sh"
log_success "Created executable bootstrap script"

# Create network configuration summary
cat > "$bootstrap_dir/network-summary.txt" << EOF
Network-Aware USB Bootstrap Summary
===================================
Generated: $(date)
Site Configuration: $(basename "$SITE_CONFIG")

Network Information:
$(grep '^site_name:\|^network_prefix:\|^domain:' "$SITE_CONFIG" || echo "Basic config fields not found")

VLAN Configuration:
$(grep -A 20 '^vlans:' "$SITE_CONFIG" | grep 'name:\|vlan_id:\|subnet:' || echo "VLAN config not found")

Device Configuration:
$(grep -A 50 '^devices:' "$SITE_CONFIG" | grep 'type:\|ip_address:\|vlan_id:' || echo "Device config not found")

GitOps Configuration:
$(grep -A 10 '^gitops:' "$SITE_CONFIG" | grep 'enabled:\|repository_url:\|drift_detection:' || echo "GitOps config not found")

USB Bootstrap Features:
- Zero-touch deployment
- Network-aware configuration
- Embedded VLAN and device settings
- GitOps drift detection
- SSH key deployment
- Automated dependency installation
EOF

log_success "Created network configuration summary"

# Create file manifest
echo "USB Bootstrap Contents:" > "$bootstrap_dir/MANIFEST.txt"
echo "======================" >> "$bootstrap_dir/MANIFEST.txt"
ls -la "$bootstrap_dir" >> "$bootstrap_dir/MANIFEST.txt"

log_info "Bootstrap directory contents:"
ls -la "$bootstrap_dir"

log_success "=== USB Bootstrap Preparation Complete ==="
log_info "To create actual USB device:"
log_info "1. Insert USB device (e.g., /dev/sdb)"
log_info "2. Run: sudo mkfs.ext4 -F /dev/sdb"
log_info "3. Mount: sudo mount /dev/sdb /mnt"
log_info "4. Copy: sudo cp -r $bootstrap_dir/* /mnt/"
log_info "5. Unmount: sudo umount /mnt"
log_info ""
log_info "Bootstrap directory ready at: $bootstrap_dir"
