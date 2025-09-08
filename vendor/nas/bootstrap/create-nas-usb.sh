#!/bin/bash
# Create Proxmox NAS USB Bootstrap Script
# Generates bootable USB with automated GitOps setup

set -e

#SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#REPO_ROOT="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Parse arguments
SITE_CONFIG=""
USB_DEVICE=""
GITHUB_TOKEN=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --site-config)
            SITE_CONFIG="$2"
            shift 2
            ;;
        --usb-device)
            USB_DEVICE="$2"
            shift 2
            ;;
        --github-token)
            GITHUB_TOKEN="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 --site-config <config.yml> --usb-device <device> [--github-token <token>]"
            echo ""
            echo "Arguments:"
            echo "  --site-config: Path to site configuration YAML file"
            echo "  --usb-device:  USB device (e.g., /dev/sdb)"
            echo "  --github-token: GitHub personal access token (optional)"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate arguments
if [[ -z "$SITE_CONFIG" ]]; then
    log_error "Site configuration file is required (--site-config)"
    exit 1
fi

if [[ -z "$USB_DEVICE" ]]; then
    log_error "USB device is required (--usb-device)"
    exit 1
fi

if [[ ! -f "$SITE_CONFIG" ]]; then
    log_error "Site configuration file not found: $SITE_CONFIG"
    exit 1
fi

if [[ ! -b "$USB_DEVICE" ]]; then
    log_error "USB device not found or not a block device: $USB_DEVICE"
    exit 1
fi

log_info "Creating Proxmox NAS USB for site config: $SITE_CONFIG"
log_info "Target USB device: $USB_DEVICE"

# Confirm destructive operation
echo ""
echo "WARNING: This will completely erase $USB_DEVICE"
echo "Site config: $SITE_CONFIG"
echo "GitHub token: $(if [[ -n "$GITHUB_TOKEN" ]]; then echo "Provided"; else echo "Not provided"; fi)"
echo ""
read -r -p "Are you sure you want to continue? (yes/no): " confirm

if [[ "$confirm" != "yes" ]]; then
    log_info "Operation cancelled"
    exit 0
fi

# Create temporary directory for USB contents
TEMP_DIR=$(mktemp -d)
log_info "Using temporary directory: $TEMP_DIR"

# Copy bootstrap files
log_step "Copying bootstrap files..."
cp "$SCRIPT_DIR/usb-bootstrap.sh" "$TEMP_DIR/"
chmod +x "$TEMP_DIR/usb-bootstrap.sh"

# Copy bootstrap files
log_step "Copying bootstrap files..."
cp "$SCRIPT_DIR/usb-bootstrap.sh" "$TEMP_DIR/"
chmod +x "$TEMP_DIR/usb-bootstrap.sh"

# Copy site configuration
log_step "Copying site configuration..."
cp "$SITE_CONFIG" "$TEMP_DIR/site-config.yml"

# Copy GitHub token if provided
if [[ -n "$GITHUB_TOKEN" ]]; then
    log_step "Setting up GitHub token..."
    echo "$GITHUB_TOKEN" > "$TEMP_DIR/github-token.txt"
    chmod 600 "$TEMP_DIR/github-token.txt"
fi

# Copy GitHub token if provided
if [[ -n "$GITHUB_TOKEN" ]]; then
    log_step "Setting up GitHub token..."
    echo "$GITHUB_TOKEN" > "$TEMP_DIR/github-token.txt"
    chmod 600 "$TEMP_DIR/github-token.txt"
fi

# Create autoinstall configuration for Proxmox (Debian-based)
log_step "Creating Proxmox autoinstall configuration..."
cat > "$TEMP_DIR/user-data" << 'EOF'
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: proxmox-nas-bootstrap
    username: root
    password: "proxmox"  # Change this!
  ssh:
    install-server: true
    allow-pw: true
  packages:
    - zfsutils-linux
    - openssh-server
    - curl
    - wget
    - git
  late-commands:
    - curtin in-target --target=/target -- chmod +x /bootstrap.sh
    - curtin in-target --target=/target -- /bootstrap.sh
EOF

cat > "$TEMP_DIR/meta-data" << 'EOF'
instance-id: proxmox-nas-bootstrap
local-hostname: proxmox-nas-bootstrap
EOF

# Format USB drive
log_step "Formatting USB drive..."
umount "${USB_DEVICE}"* 2>/dev/null || true

# Create partition table
parted -s "$USB_DEVICE" mklabel msdos

# Create boot partition (EFI)
parted -s "$USB_DEVICE" mkpart primary fat32 1MiB 512MiB
parted -s "$USB_DEVICE" set 1 boot on

# Create data partition
parted -s "$USB_DEVICE" mkpart primary ext4 512MiB 100%

# Format partitions
mkfs.vfat -F 32 "${USB_DEVICE}1"
mkfs.ext4 "${USB_DEVICE}2"

# Mount partitions
BOOT_MOUNT=$(mktemp -d)
DATA_MOUNT=$(mktemp -d)
mount "${USB_DEVICE}1" "$BOOT_MOUNT"
mount "${USB_DEVICE}2" "$DATA_MOUNT"

# Download Proxmox ISO and extract boot files
log_step "Setting up Proxmox boot environment..."
PROXMOX_ISO_URL="https://enterprise.proxmox.com/iso/proxmox-ve_9.0-1.iso"
PROXMOX_ISO="$TEMP_DIR/proxmox.iso"

log_info "Downloading Proxmox ISO..."
wget -q --show-progress "$PROXMOX_ISO_URL" -O "$PROXMOX_ISO"

log_info "Extracting boot files..."
xorriso -osirrox on -indev "$PROXMOX_ISO" -extract / "$BOOT_MOUNT/" 2>/dev/null || true

# Copy bootstrap files to data partition
log_step "Copying bootstrap files to USB..."
mkdir -p "$DATA_MOUNT/bootstrap"
cp "$TEMP_DIR"/* "$DATA_MOUNT/"

# Create post-install script for Proxmox
log_step "Creating post-install script..."
cat > "$DATA_MOUNT/post-install.sh" << 'EOF'
#!/bin/bash
# Post-install script for Proxmox NAS
# This runs after Proxmox installation is complete

set -e

echo "Starting Proxmox NAS post-install setup..."

# Mount the data partition (where our bootstrap files are)
mount /dev/sdb2 /mnt 2>/dev/null || true

if [[ -f /mnt/bootstrap/usb-bootstrap.sh ]]; then
    echo "Found bootstrap script, executing..."
    cp /mnt/bootstrap/* /root/
    chmod +x /root/usb-bootstrap.sh
    /root/usb-bootstrap.sh
else
    echo "Bootstrap script not found. Manual setup required."
    echo "Run the following commands manually:"
    echo "1. cp /mnt/bootstrap/* /root/"
    echo "2. chmod +x /root/usb-bootstrap.sh"
    echo "3. /root/usb-bootstrap.sh"
fi
EOF

chmod +x "$DATA_MOUNT/post-install.sh"

# Create README for USB
cat > "$DATA_MOUNT/README.txt" << EOF
Proxmox NAS USB Bootstrap
=========================

This USB drive contains the automated setup for a Proxmox NAS system.

Installation Instructions:
1. Insert this USB drive into the target system
2. Boot from USB (you may need to change boot order in BIOS)
3. Install Proxmox using the standard Proxmox installer
4. After installation completes, run the post-install script:
   sudo /mnt/post-install.sh
   (assuming USB is mounted at /mnt)

The post-install script will:
- Configure disks and ZFS pools
- Set up GitOps authentication
- Register with your GitHub repository

Site Configuration:
$(cat "$SITE_CONFIG")

GitHub Token: $(if [[ -n "$GITHUB_TOKEN" ]]; then echo "Provided"; else echo "Not provided - manual setup required"; fi)

Logs will be available at /var/log/nas-bootstrap.log after setup.

For support, check the repository documentation.
EOF

# Cleanup
log_step "Cleaning up..."
umount "$BOOT_MOUNT"
umount "$DATA_MOUNT"
rm -rf "$TEMP_DIR" "$BOOT_MOUNT" "$DATA_MOUNT"

log_info "USB creation complete!"
log_info "Boot the target system from $USB_DEVICE to start automated setup"
log_info "Monitor progress at /var/log/nas-bootstrap.log on the target system"
