#!/bin/bash
# Proxmox NAS USB Bootstrap Script
# Automated GitOps onboarding for NAS systems

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

# Load site configuration from USB
load_site_config() {
    log_step "Loading site configuration..."

    # Look for site config on USB drives
    for usb_dev in /media/*; do
        if [[ -f "$usb_dev/site-config.yml" ]]; then
            SITE_CONFIG="$usb_dev/site-config.yml"
            log_info "Found site configuration: $SITE_CONFIG"
            break
        fi
    done

    if [[ -z "$SITE_CONFIG" ]]; then
        log_error "No site configuration found on USB drives"
        exit 1
    fi

    # Parse basic config
    SITE_NAME=$(grep "site_name:" "$SITE_CONFIG" | cut -d'"' -f2)
    NETWORK_PREFIX=$(grep "network_prefix:" "$SITE_CONFIG" | cut -d'"' -f2)
    DOMAIN=$(grep "domain:" "$SITE_CONFIG" | cut -d'"' -f2)

    log_info "Site: $SITE_NAME, Network: $NETWORK_PREFIX, Domain: $DOMAIN"
}

# Configure system hostname and network
configure_system() {
    log_step "Configuring system identity..."

    # Set hostname
    hostnamectl set-hostname "proxmox-nas-$SITE_NAME"
    echo "127.0.0.1 proxmox-nas-$SITE_NAME" >> /etc/hosts

    # Configure network (DHCP for now, will be refined later)
    log_info "Network will be configured via DHCP initially"
}

# Setup ZFS storage pools
setup_zfs_storage() {
    log_step "Setting up ZFS storage pools..."

    # Detect available disks
    log_info "Detecting available disks..."
    lsblk -d -o NAME,SIZE,TYPE | grep -E "(sd|nvme|hd)"

    # Parse storage config from site config
    SYSTEM_DISKS=$(grep "system_disks:" "$SITE_CONFIG" | sed 's/.*://' | tr -d '[]"' | tr ',' ' ')
    DATA_DISKS=$(grep "data_disks:" "$SITE_CONFIG" | sed 's/.*://' | tr -d '[]"' | tr ',' ' ')
    RAID_LEVEL=$(grep "raid_level:" "$SITE_CONFIG" | cut -d'"' -f2)
    SYSTEM_RAID=$(grep "system_raid:" "$SITE_CONFIG" | cut -d'"' -f2)
    SLOG_DEVICES=$(grep "slog_devices:" "$SITE_CONFIG" | sed 's/.*://' | tr -d '[]"' | tr ',' ' ')
    L2ARC_DEVICES=$(grep "l2arc_devices:" "$SITE_CONFIG" | sed 's/.*://' | tr -d '[]"' | tr ',' ' ')
    HOT_SPARES=$(grep "hot_spare_disks:" "$SITE_CONFIG" | sed 's/.*://' | tr -d '[]"' | tr ',' ' ')

    log_info "System disks: $SYSTEM_DISKS"
    log_info "Data disks: $DATA_DISKS"
    log_info "RAID level: $RAID_LEVEL"
    log_info "System RAID: $SYSTEM_RAID"
    log_info "SLOG devices: $SLOG_DEVICES"
    log_info "L2ARC devices: $L2ARC_DEVICES"
    log_info "Hot spares: $HOT_SPARES"

    # Create system pool (for OS, VMs, containers)
    if [[ -n "$SYSTEM_DISKS" ]]; then
        if [[ "$SYSTEM_RAID" == "mirror" && $(echo "$SYSTEM_DISKS" | wc -w) -gt 1 ]]; then
            log_info "Creating system Linux RAID mirror..."
            eval "mdadm --create /dev/md0 --level=1 --raid-devices=$(echo "$SYSTEM_DISKS" | wc -w) $SYSTEM_DISKS"
            sleep 5  # Wait for RAID sync
            log_info "Creating system ZFS pool on RAID..."
            zpool create -f system /dev/md0
        else
            log_info "Creating system ZFS pool..."
            zpool create -f system "$SYSTEM_DISKS"
        fi
        zfs create system/root
        zfs create system/vm-storage
        zfs create system/container-storage
    fi

    # Create data pool (for NAS storage)
    if [[ -n "$DATA_DISKS" ]]; then
        log_info "Creating data ZFS pool..."
        case $RAID_LEVEL in
            "raidz1")
                zpool create -f data raidz1 "$DATA_DISKS"
                ;;
            "raidz2")
                zpool create -f data raidz2 "$DATA_DISKS"
                ;;
            "raidz3")
                zpool create -f data raidz3 "$DATA_DISKS"
                ;;
            "mirror")
                zpool create -f data mirror "$DATA_DISKS"
                ;;
            *)
                zpool create -f data "$DATA_DISKS"
                ;;
        esac

        # Add hot spares if configured
        if [[ -n "$HOT_SPARES" ]]; then
            log_info "Adding hot spares to data pool..."
            zpool add data spare "$HOT_SPARES"
        fi

        # Add SLOG if configured
        if [[ -n "$SLOG_DEVICES" ]]; then
            log_info "Adding SLOG device to data pool..."
            zpool add data log "$SLOG_DEVICES"
        fi

        # Add L2ARC if configured
        if [[ -n "$L2ARC_DEVICES" ]]; then
            log_info "Adding L2ARC device to data pool..."
            zpool add data cache "$L2ARC_DEVICES"
        fi

        # Create datasets
        zfs create data/nas-data
        zfs create data/vm-storage
        zfs create data/container-storage
        zfs create data/backup
    fi

    # Set proper permissions and properties
    zfs set compression=lz4 data
    zfs set atime=off data
    zfs set xattr=sa data
    zfs set acltype=posixacl data
}

# Configure Proxmox (already installed via ISO)
configure_proxmox() {
    log_step "Configuring Proxmox..."

    # Proxmox is already installed, just ensure it's properly configured
    # Update package lists and install any additional packages needed
    apt update && apt upgrade -y

    # Install additional packages for NAS functionality
    apt install -y proxmox-backup-client proxmox-backup-server zfsutils-linux git curl wget

    # Enable ZFS support in Proxmox
    modprobe zfs
    echo "zfs" >> /etc/modules

    log_info "Proxmox configured successfully"
}

# Setup GitOps authentication
setup_gitops_auth() {
    log_step "Setting up GitOps authentication..."

    # Generate SSH key for GitHub
    ssh-keygen -t ed25519 -C "proxmox-nas-$SITE_NAME@github" -f /root/.ssh/id_ed25519 -N ""

    # Look for GitHub token on USB
    GITHUB_TOKEN=""
    for usb_dev in /media/*; do
        if [[ -f "$usb_dev/github-token.txt" ]]; then
            GITHUB_TOKEN=$(cat "$usb_dev/github-token.txt")
            log_info "Found GitHub token on USB"
            break
        fi
    done

    if [[ -z "$GITHUB_TOKEN" ]]; then
        log_warn "No GitHub token found - manual setup required"
        echo "SSH Public Key for GitHub:"
        cat /root/.ssh/id_ed25519.pub
        echo ""
        echo "Add this key to your GitHub repository deploy keys"
        echo "Then run: git clone git@github.com:your-org/your-repo.git /opt/brewnix"
        return
    fi

    # Auto-setup GitHub access
    log_info "Setting up automated GitHub access..."

    # Add GitHub to known hosts
    ssh-keyscan -H github.com >> /root/.ssh/known_hosts

    # Test connection
    if ssh -T git@github.com -o StrictHostKeyChecking=no; then
        log_info "GitHub SSH access configured"
    else
        log_error "GitHub SSH setup failed"
    fi
}

# Clone and setup repository
setup_repository() {
    log_step "Setting up repository..."

    # Parse repo URL from site config
    REPO_URL=$(grep "repo_url:" "$SITE_CONFIG" | cut -d'"' -f2)

    if [[ -n "$REPO_URL" ]]; then
        log_info "Cloning repository: $REPO_URL"
        git clone "$REPO_URL" /opt/brewnix
        cd /opt/brewnix
        git submodule update --init --recursive
    else
        log_warn "No repository URL specified - manual setup required"
    fi
}

# Configure monitoring and logging
setup_monitoring() {
    log_step "Setting up monitoring..."

    # Install basic monitoring tools
    apt install -y htop iotop ncdu zfsutils-linux

    # Setup log rotation for ZFS
    cat > /etc/logrotate.d/zfs << EOF
/var/log/zfs/*.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
EOF

    # Create monitoring script
    cat > /usr/local/bin/monitor-nas.sh << 'EOF'
#!/bin/bash
echo "=== Proxmox NAS Status ==="
echo "Date: $(date)"
echo ""
echo "=== ZFS Pools ==="
zpool status -v
echo ""
echo "=== ZFS Datasets ==="
zfs list
echo ""
echo "=== Disk Usage ==="
df -h | grep -E "(Filesystem|/)"
echo ""
echo "=== Memory Usage ==="
free -h
EOF

    chmod +x /usr/local/bin/monitor-nas.sh

    # Add to cron for regular monitoring
    echo "*/15 * * * * root /usr/local/bin/monitor-nas.sh >> /var/log/nas-monitor.log 2>&1" > /etc/cron.d/nas-monitoring
}

# Final setup and reboot
finalize_setup() {
    log_step "Finalizing setup..."

    # Update GRUB for ZFS
    update-grub

    # Setup auto-mount for ZFS pools
    zpool set cachefile=/etc/zfs/zpool.cache system
    zpool set cachefile=/etc/zfs/zpool.cache data

    # Create status file
    cat > /var/log/nas-bootstrap.log << EOF
Proxmox NAS Bootstrap Complete
==============================
Site: $SITE_NAME
Network: $NETWORK_PREFIX
Domain: $DOMAIN
Timestamp: $(date)
System Pool: $(zpool list system -H -o health 2>/dev/null || echo "Not created")
Data Pool: $(zpool list data -H -o health 2>/dev/null || echo "Not created")
EOF

    log_info "Bootstrap complete! System will reboot in 10 seconds..."
    log_info "After reboot, check /var/log/nas-bootstrap.log for status"
    sleep 10
    reboot
}

# Main execution
main() {
    log_info "Starting Proxmox NAS USB Bootstrap..."

    load_site_config
    configure_system
    setup_zfs_storage
    configure_proxmox
    setup_gitops_auth
    setup_repository
    setup_monitoring
    finalize_setup
}

# Run main function
main "$@"
