#!/bin/bash
# Brewnix Device Registration Manager
# Manages device registration and configuration

set -e

#SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/opt/brewnix/config"
DEVICE_DIR="$CONFIG_DIR/devices"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

usage() {
    cat << EOF
Brewnix Device Registration Manager

USAGE:
    $0 COMMAND [OPTIONS]

COMMANDS:
    register     Register a new device
    list         List all registered devices
    update       Update device information
    remove       Remove a device registration
    export       Export device data to CSV
    import       Import devices from CSV

OPTIONS:
    --device-id ID       Device identifier
    --device-type TYPE   Device type (desktop, laptop, server, etc.)
    --site-name NAME     Site name where device is located
    --ip-address IP      Device IP address
    --mac-address MAC    Device MAC address
    --serial SN          Device serial number
    --file FILE          CSV file for import/export
    --help               Show this help

EXAMPLES:
    $0 register --device-id desktop-01 --device-type desktop --site-name home-lab
    $0 list
    $0 export --file devices.csv
    $0 import --file devices.csv

EOF
}

# Create directories if they don't exist
setup_directories() {
    mkdir -p "$DEVICE_DIR"
}

# Register a new device
register_device() {
    local device_id=""
    local device_type=""
    local site_name=""
    local ip_address=""
    local mac_address=""
    local serial_number=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --device-id)
                device_id="$2"
                shift 2
                ;;
            --device-type)
                device_type="$2"
                shift 2
                ;;
            --site-name)
                site_name="$2"
                shift 2
                ;;
            --ip-address)
                ip_address="$2"
                shift 2
                ;;
            --mac-address)
                mac_address="$2"
                shift 2
                ;;
            --serial)
                serial_number="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Validate required fields
    if [[ -z "$device_id" || -z "$device_type" || -z "$site_name" ]]; then
        error "Device ID, type, and site name are required"
        exit 1
    fi

    # Check if device already exists
    if [[ -f "$DEVICE_DIR/${device_id}.yml" ]]; then
        error "Device $device_id is already registered"
        exit 1
    fi

    # Validate device type
    local valid_types=("desktop" "laptop" "smartphone" "server" "network_switch" "wifi_access_point" "smart_tv" "iot_hub" "camera" "smart_doorbell" "smart_fan" "smart_light" "smart_switch" "game_console" "nas" "nvr" "roku" "ecobee" "yolink_hub" "custom")
    local type_valid=false
    for valid_type in "${valid_types[@]}"; do
        if [[ "$device_type" == "$valid_type" ]]; then
            type_valid=true
            break
        fi
    done

    if [[ "$type_valid" == false ]]; then
        error "Invalid device type: $device_type"
        info "Valid types: ${valid_types[*]}"
        exit 1
    fi

    # Create device configuration
    cat > "$DEVICE_DIR/${device_id}.yml" << EOF
device_id: "$device_id"
device_type: "$device_type"
site_name: "$site_name"
ip_address: "$ip_address"
mac_address: "$mac_address"
serial_number: "$serial_number"
registered_at: "$(date -Iseconds)"
status: "registered"
EOF

    log "Device $device_id registered successfully"
    info "Configuration saved to: $DEVICE_DIR/${device_id}.yml"
}

# List all registered devices
list_devices() {
    local format="${1:-table}"

    if [[ ! -d "$DEVICE_DIR" ]]; then
        info "No devices registered yet"
        return
    fi

    local devices=()
    while IFS= read -r -d '' file; do
        devices+=("$file")
    done < <(find "$DEVICE_DIR" -name "*.yml" -print0)

    if [[ ${#devices[@]} -eq 0 ]]; then
        info "No devices registered yet"
        return
    fi

    case "$format" in
        table)
            printf "%-20s %-15s %-15s %-15s %-20s %-15s\n" "Device ID" "Type" "Site" "IP Address" "MAC Address" "Status"
            printf "%-20s %-15s %-15s %-15s %-20s %-15s\n" "---------" "----" "----" "----------" "-----------" "------"
            for device_file in "${devices[@]}"; do
                local device_id device_type site_name ip_address mac_address status

                device_id=$(grep -E '^device_id:' "$device_file" | sed 's/.*: //' | tr -d '"')
                device_type=$(grep -E '^device_type:' "$device_file" | sed 's/.*: //' | tr -d '"')
                site_name=$(grep -E '^site_name:' "$device_file" | sed 's/.*: //' | tr -d '"')
                ip_address=$(grep -E '^ip_address:' "$device_file" | sed 's/.*: //' | tr -d '"')
                mac_address=$(grep -E '^mac_address:' "$device_file" | sed 's/.*: //' | tr -d '"')
                status=$(grep -E '^status:' "$device_file" | sed 's/.*: //' | tr -d '"')

                printf "%-20s %-15s %-15s %-15s %-20s %-15s\n" \
                    "${device_id:0:20}" \
                    "${device_type:0:15}" \
                    "${site_name:0:15}" \
                    "${ip_address:0:15}" \
                    "${mac_address:0:20}" \
                    "${status:0:15}"
            done
            ;;
        json)
            echo "["
            local first=true
            for device_file in "${devices[@]}"; do
                if [[ "$first" == false ]]; then
                    echo ","
                fi
                python3 -c "
import yaml
import json
import sys
with open('$device_file', 'r') as f:
    data = yaml.safe_load(f)
    print(json.dumps(data, indent=None))
" 2>/dev/null || echo "{}"
                first=false
            done
            echo "]"
            ;;
        *)
            error "Unknown format: $format"
            exit 1
            ;;
    esac
}

# Update device information
update_device() {
    local device_id=""
    local field=""
    local value=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --device-id)
                device_id="$2"
                shift 2
                ;;
            --field)
                field="$2"
                shift 2
                ;;
            --value)
                value="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    if [[ -z "$device_id" || -z "$field" ]]; then
        error "Device ID and field are required"
        exit 1
    fi

    local device_file="$DEVICE_DIR/${device_id}.yml"
    if [[ ! -f "$device_file" ]]; then
        error "Device $device_id not found"
        exit 1
    fi

    # Update the field in the YAML file
    if command -v python3 &> /dev/null; then
        python3 -c "
import yaml
import sys
with open('$device_file', 'r') as f:
    data = yaml.safe_load(f)
data['$field'] = '$value'
data['updated_at'] = '$(date -Iseconds)'
with open('$device_file', 'w') as f:
    yaml.dump(data, f, default_flow_style=False)
"
    else
        # Fallback: use sed for simple updates
        sed -i "s/^$field:.*/$field: \"$value\"/" "$device_file"
        echo "updated_at: \"$(date -Iseconds)\"" >> "$device_file"
    fi

    log "Device $device_id updated: $field = $value"
}

# Remove device registration
remove_device() {
    local device_id="$1"

    if [[ -z "$device_id" ]]; then
        error "Device ID is required"
        exit 1
    fi

    local device_file="$DEVICE_DIR/${device_id}.yml"
    if [[ ! -f "$device_file" ]]; then
        error "Device $device_id not found"
        exit 1
    fi

    rm "$device_file"
    log "Device $device_id removed successfully"
}

# Export devices to CSV
export_devices() {
    local csv_file="${1:-devices.csv}"

    if [[ ! -d "$DEVICE_DIR" ]]; then
        error "No devices to export"
        return
    fi

    # Create CSV header
    echo "device_id,device_type,site_name,ip_address,mac_address,serial_number,status,registered_at" > "$csv_file"

    # Export each device
    for device_file in "$DEVICE_DIR"/*.yml; do
        if [[ -f "$device_file" ]]; then
            local device_id device_type site_name ip_address mac_address serial_number status registered_at

            device_id=$(grep -E '^device_id:' "$device_file" | sed 's/.*: //' | tr -d '"')
            device_type=$(grep -E '^device_type:' "$device_file" | sed 's/.*: //' | tr -d '"')
            site_name=$(grep -E '^site_name:' "$device_file" | sed 's/.*: //' | tr -d '"')
            ip_address=$(grep -E '^ip_address:' "$device_file" | sed 's/.*: //' | tr -d '"')
            mac_address=$(grep -E '^mac_address:' "$device_file" | sed 's/.*: //' | tr -d '"')
            serial_number=$(grep -E '^serial_number:' "$device_file" | sed 's/.*: //' | tr -d '"')
            status=$(grep -E '^status:' "$device_file" | sed 's/.*: //' | tr -d '"')
            registered_at=$(grep -E '^registered_at:' "$device_file" | sed 's/.*: //' | tr -d '"')

            echo "$device_id,$device_type,$site_name,$ip_address,$mac_address,$serial_number,$status,$registered_at" >> "$csv_file"
        fi
    done

    log "Devices exported to $csv_file"
}

# Import devices from CSV
import_devices() {
    local csv_file="$1"

    if [[ ! -f "$csv_file" ]]; then
        error "CSV file not found: $csv_file"
        exit 1
    fi

    local count=0
    # Skip header line
    while IFS=',' read -r device_id device_type site_name ip_address mac_address serial_number status registered_at; do
        if [[ "$device_id" != "device_id" && -n "$device_id" ]]; then
            # Create device configuration
            cat > "$DEVICE_DIR/${device_id}.yml" << EOF
device_id: "$device_id"
device_type: "$device_type"
site_name: "$site_name"
ip_address: "$ip_address"
mac_address: "$mac_address"
serial_number: "$serial_number"
status: "$status"
registered_at: "$registered_at"
imported_at: "$(date -Iseconds)"
EOF
            ((count++))
        fi
    done < "$csv_file"

    log "$count devices imported successfully"
}

# Main command processing
setup_directories

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
    register)
        register_device "$@"
        ;;
    list)
        list_devices "$@"
        ;;
    update)
        update_device "$@"
        ;;
    remove)
        remove_device "$@"
        ;;
    export)
        export_devices "$@"
        ;;
    import)
        import_devices "$@"
        ;;
    --help|-h)
        usage
        ;;
    *)
        error "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac
