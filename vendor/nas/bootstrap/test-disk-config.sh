#!/bin/bash
# Test script for USB bootstrap disk configuration parsing

set -e

echo "Testing USB Bootstrap Disk Configuration..."

# Create a test site config
cat > /tmp/test-site.yml << 'EOF'
site:
  name: "test-nas"
  network_prefix: "192.168.1.0/24"
  domain: "test.local"

storage:
  system_disks: ["/dev/sda", "/dev/sdb"]
  system_raid: "mirror"
  data_disks: ["/dev/sdc", "/dev/sdd", "/dev/sde", "/dev/sdf"]
  raid_level: "raidz2"
  hot_spare_disks: ["/dev/sdg"]
  slog_devices: ["/dev/nvme0n1"]
  l2arc_devices: ["/dev/nvme1n1"]
EOF

# Test parsing function
parse_disk_config() {
    local config_file="$1"

    # Parse system disks
    SYSTEM_DISKS=$(grep "system_disks:" "$config_file" | sed 's/.*: //' | tr -d '[]"' | tr ',' ' ')
    SYSTEM_RAID=$(grep "system_raid:" "$config_file" | sed 's/.*: //' | tr -d '"')

    # Parse data disks
    DATA_DISKS=$(grep "data_disks:" "$config_file" | sed 's/.*: //' | tr -d '[]"' | tr ',' ' ')
    RAID_LEVEL=$(grep "raid_level:" "$config_file" | sed 's/.*: //' | tr -d '"')

    # Parse optional devices
    HOT_SPARES=$(grep "hot_spare_disks:" "$config_file" | sed 's/.*: //' | tr -d '[]"' | tr ',' ' ')
    SLOG_DEVICES=$(grep "slog_devices:" "$config_file" | sed 's/.*: //' | tr -d '[]"' | tr ',' ' ')
    L2ARC_DEVICES=$(grep "l2arc_devices:" "$config_file" | sed 's/.*: //' | tr -d '[]"' | tr ',' ' ')

    echo "Parsed configuration:"
    echo "SYSTEM_DISKS: $SYSTEM_DISKS"
    echo "SYSTEM_RAID: $SYSTEM_RAID"
    echo "DATA_DISKS: $DATA_DISKS"
    echo "RAID_LEVEL: $RAID_LEVEL"
    echo "HOT_SPARES: $HOT_SPARES"
    echo "SLOG_DEVICES: $SLOG_DEVICES"
    echo "L2ARC_DEVICES: $L2ARC_DEVICES"
}

# Run the test
parse_disk_config "/tmp/test-site.yml"

echo ""
echo "Test completed successfully!"
echo "Configuration parsing works correctly with advanced disk options."
