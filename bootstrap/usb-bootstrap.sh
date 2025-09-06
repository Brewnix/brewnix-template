#!/bin/bash
# USB Bootstrap Script for Brewnix GitOps
# This script sets up the initial environment for GitOps deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

log_info "Starting USB Bootstrap for Proxmox Firewall GitOps"

# Install required packages
log_info "Installing required packages..."
apt update
apt install -y \
    git \
    curl \
    wget \
    openssh-client \
    openssh-server \
    jq \
    git-crypt \
    age \
    ansible \
    python3-pip \
    python3-venv

# Install GitHub CLI
log_info "Installing GitHub CLI..."
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
apt update
apt install -y gh

# Setup SSH for GitHub
log_info "Setting up SSH for GitHub..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Generate SSH key if it doesn't exist
if [[ ! -f /root/.ssh/id_ed25519 ]]; then
    log_info "Generating SSH key..."
    ssh-keygen -t ed25519 -C "bootstrap@proxmox-firewall" -f /root/.ssh/id_ed25519 -N ""
fi

# Start SSH service
log_info "Starting SSH service..."
systemctl enable ssh
systemctl start ssh

# Display SSH public key for GitHub setup
log_info "SSH public key for GitHub (add this to your repository deploy keys):"
echo "----------------------------------------"
cat /root/.ssh/id_ed25519.pub
echo "----------------------------------------"
log_warn "Copy the above key and add it as a deploy key to your GitOps repository"

# Setup git
log_info "Configuring git..."
git config --global user.name "Proxmox Firewall Bootstrap"
git config --global user.email "bootstrap@proxmox-firewall.local"

# Create bootstrap directory structure
log_info "Creating bootstrap directory structure..."
mkdir -p /opt/proxmox-firewall-bootstrap
mkdir -p /opt/proxmox-firewall-bootstrap/logs
mkdir -p /opt/proxmox-firewall-bootstrap/state

# Copy bootstrap scripts
cp -r "$SCRIPT_DIR"/* /opt/proxmox-firewall-bootstrap/

# Setup environment
cat > /opt/proxmox-firewall-bootstrap/.env << EOF
# Bootstrap Environment Configuration
BOOTSTRAP_VERSION="1.0.0"
BOOTSTRAP_DATE="$(date)"
GITHUB_REPO="yourorg/your-firewall-deployment"
GITHUB_BRANCH="main"
PROXMOX_HOST="10.1.50.1"
NETWORK_PREFIX="10.1"
DOMAIN="firewall.local"
EOF

log_info "Bootstrap setup complete!"
log_info ""
log_info "Next steps:"
log_info "1. Add the SSH public key above to your GitHub repository deploy keys"
log_info "2. Run: ./github-connect.sh to connect to GitHub"
log_info "3. Run: ./initial-config.sh to configure the system"
log_info ""
log_warn "SSH service is running. You can now connect remotely if needed."
