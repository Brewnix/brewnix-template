#!/bin/bash
# scripts/monitoring/monitoring.sh - Health monitoring and alerting

# Source core modules
source "${SCRIPT_DIR}/core/init.sh"
source "${SCRIPT_DIR}/core/config.sh"
source "${SCRIPT_DIR}/core/logging.sh"

# Monitoring configuration
MONITORING_INTERVAL="${MONITORING_INTERVAL:-300}"  # 5 minutes
ALERT_EMAIL="${ALERT_EMAIL:-$(get_config_value 'monitoring.alert_email')}"
HEALTH_CHECK_FILE="${BUILD_DIR}/health_status.json"

# Initialize monitoring
init_monitoring() {
    mkdir -p "$(dirname "$HEALTH_CHECK_FILE")"
    log_info "Monitoring system initialized"
    log_debug "Interval: $MONITORING_INTERVAL seconds"
    log_debug "Alert email: $ALERT_EMAIL"
}

# Health check functions
check_service_health() {
    local service="$1"
    local host="${2:-localhost}"
    local port="$3"

    case "$service" in
        proxmox)
            # Check Proxmox API
            if curl -s --max-time 10 "https://${host}:8006/api2/json/cluster/resources" > /dev/null 2>&1; then
                echo "healthy"
            else
                echo "unhealthy"
            fi
            ;;
        opnsense)
            # Check OPNsense web interface
            if curl -s --max-time 10 -k "https://${host}" > /dev/null 2>&1; then
                echo "healthy"
            else
                echo "unhealthy"
            fi
            ;;
        port)
            # Check specific port
            if timeout 5 bash -c "</dev/tcp/${host}/${port}" 2>/dev/null; then
                echo "healthy"
            else
                echo "unhealthy"
            fi
            ;;
        *)
            log_error "Unknown service type: $service"
            echo "unknown"
            ;;
    esac
}

# Check system resources
check_system_resources() {
    local output_file="${BUILD_DIR}/system_stats.json"

    # Get system information
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')

    local mem_usage
    mem_usage=$(free | grep Mem | awk '{printf "%.2f", $3/$2 * 100.0}')

    local disk_usage
    disk_usage=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')

    # Create JSON output
    cat > "$output_file" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "cpu_usage_percent": $cpu_usage,
    "memory_usage_percent": $mem_usage,
    "disk_usage_percent": $disk_usage,
    "load_average": "$(uptime | awk -F'load average:' '{ print $2 }' | sed 's/^ *//')"
}
EOF

    log_debug "System stats updated: CPU=${cpu_usage}%, MEM=${mem_usage}%, DISK=${disk_usage}%"
    echo "$output_file"
}

# Check network connectivity
check_network_connectivity() {
    local targets=("8.8.8.8" "1.1.1.1" "208.67.222.222")  # Google, Cloudflare, OpenDNS
    local healthy_count=0

    for target in "${targets[@]}"; do
        if ping -c 1 -W 2 "$target" > /dev/null 2>&1; then
            ((healthy_count++))
        fi
    done

    if [[ $healthy_count -ge 2 ]]; then
        echo "healthy"
    else
        echo "unhealthy"
    fi
}

# Run comprehensive health check
run_health_check() {
    local timestamp
    timestamp=$(date -Iseconds)
    local health_status="healthy"
    local issues=()

    log_info "Running comprehensive health check..."

    # Check system resources
    local system_stats
    system_stats=$(check_system_resources)

    # Parse system stats for alerts
    if command -v jq &> /dev/null && [[ -f "$system_stats" ]]; then
        local cpu_usage mem_usage disk_usage
        cpu_usage=$(jq -r '.cpu_usage_percent' "$system_stats" 2>/dev/null)
        mem_usage=$(jq -r '.memory_usage_percent' "$system_stats" 2>/dev/null)
        disk_usage=$(jq -r '.disk_usage_percent' "$system_stats" 2>/dev/null)

        if (( $(echo "$cpu_usage > 90" | bc -l 2>/dev/null || echo "0") )); then
            issues+=("High CPU usage: ${cpu_usage}%")
            health_status="warning"
        fi

        if (( $(echo "$mem_usage > 90" | bc -l 2>/dev/null || echo "0") )); then
            issues+=("High memory usage: ${mem_usage}%")
            health_status="warning"
        fi

        if (( $(echo "$disk_usage > 90" | bc -l 2>/dev/null || echo "0") )); then
            issues+=("High disk usage: ${disk_usage}%")
            health_status="critical"
        fi
    fi

    # Check network connectivity
    local network_status
    network_status=$(check_network_connectivity)
    if [[ "$network_status" != "healthy" ]]; then
        issues+=("Network connectivity issues")
        health_status="critical"
    fi

    # Check configured services
    local sites
    sites=$(list_sites)
    for site in $sites; do
        local proxmox_host opnsense_host
        proxmox_host=$(get_config_value "sites.${site}.proxmox.host")
        opnsense_host=$(get_config_value "sites.${site}.opnsense.host")

        if [[ -n "$proxmox_host" ]]; then
            local proxmox_status
            proxmox_status=$(check_service_health "proxmox" "$proxmox_host")
            if [[ "$proxmox_status" != "healthy" ]]; then
                issues+=("Proxmox (${site}): unhealthy")
                health_status="critical"
            fi
        fi

        if [[ -n "$opnsense_host" ]]; then
            local opnsense_status
            opnsense_status=$(check_service_health "opnsense" "$opnsense_host")
            if [[ "$opnsense_status" != "healthy" ]]; then
                issues+=("OPNsense (${site}): unhealthy")
                health_status="critical"
            fi
        fi
    done

    # Create health status file
    cat > "$HEALTH_CHECK_FILE" << EOF
{
    "timestamp": "$timestamp",
    "status": "$health_status",
    "issues": $(printf '%s\n' "${issues[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]"),
    "system_stats": $(cat "$system_stats" 2>/dev/null || echo "{}")
}
EOF

    log_info "Health check completed - Status: $health_status"

    if [[ ${#issues[@]} -gt 0 ]]; then
        log_warn "Issues found:"
        for issue in "${issues[@]}"; do
            log_warn "  - $issue"
        done

        # Send alert if configured
        if [[ -n "$ALERT_EMAIL" && "$health_status" != "healthy" ]]; then
            send_alert_email "$health_status" "${issues[@]}"
        fi
    fi

    echo "$health_status"
}

# Send alert email
send_alert_email() {
    local status="$1"
    shift
    local issues=("$@")

    if ! command -v mail &> /dev/null; then
        log_warn "Mail command not available, skipping email alert"
        return 1
    fi

    local subject="BrewNix Alert: $status"
    local body
    body="Health check detected issues:

Status: $status
Time: $(date)
Issues:
$(printf '  - %s\n' "${issues[@]}")

System Information:
$(cat "$HEALTH_CHECK_FILE" 2>/dev/null || echo "No detailed information available")

Please check the system logs for more details."

    echo "$body" | mail -s "$subject" "$ALERT_EMAIL"

    if [[ $? -eq 0 ]]; then
        log_info "Alert email sent to: $ALERT_EMAIL"
    else
        log_error "Failed to send alert email"
    fi
}

# Generate monitoring report
generate_report() {
    local date_stamp
    date_stamp=$(date +%Y%m%d)
    local report_file="${BUILD_DIR}/monitoring_report_${date_stamp}.txt"

    log_info "Generating monitoring report: $report_file"

    {
        echo "BrewNix Monitoring Report"
        echo "Generated: $(date)"
        echo "=========================="
        echo ""

        if [[ -f "$HEALTH_CHECK_FILE" ]]; then
            echo "Current Health Status:"
            echo "----------------------"
            jq -r '.status' "$HEALTH_CHECK_FILE" 2>/dev/null || echo "Unknown"
            echo ""

            echo "Issues:"
            echo "-------"
            jq -r '.issues[]' "$HEALTH_CHECK_FILE" 2>/dev/null || echo "None"
            echo ""

            echo "System Statistics:"
            echo "------------------"
            jq -r '.system_stats | to_entries[] | "\(.key): \(.value)"' "$HEALTH_CHECK_FILE" 2>/dev/null || echo "No stats available"
            echo ""
        fi

        echo "Recent Log Entries:"
        echo "-------------------"
        if [[ -f "$LOG_FILE" ]]; then
            tail -20 "$LOG_FILE"
        else
            echo "No log file available"
        fi

    } > "$report_file"

    log_info "Report generated: $report_file"
    echo "$report_file"
}

# Start monitoring daemon
start_monitoring_daemon() {
    local pid_file="${BUILD_DIR}/monitoring.pid"

    if [[ -f "$pid_file" ]]; then
        local existing_pid
        existing_pid=$(cat "$pid_file")
        if kill -0 "$existing_pid" 2>/dev/null; then
            log_warn "Monitoring daemon already running (PID: $existing_pid)"
            return 1
        else
            rm -f "$pid_file"
        fi
    fi

    log_info "Starting monitoring daemon..."

    # Start daemon in background
    (
        while true; do
            run_health_check > /dev/null 2>&1
            sleep "$MONITORING_INTERVAL"
        done
    ) &

    local daemon_pid=$!
    echo "$daemon_pid" > "$pid_file"

    log_info "Monitoring daemon started (PID: $daemon_pid)"
}

# Stop monitoring daemon
stop_monitoring_daemon() {
    local pid_file="${BUILD_DIR}/monitoring.pid"

    if [[ ! -f "$pid_file" ]]; then
        log_warn "No monitoring daemon PID file found"
        return 1
    fi

    local daemon_pid
    daemon_pid=$(cat "$pid_file")

    if kill "$daemon_pid" 2>/dev/null; then
        log_info "Monitoring daemon stopped (PID: $daemon_pid)"
        rm -f "$pid_file"
    else
        log_error "Failed to stop monitoring daemon"
        return 1
    fi
}

# Main monitoring function
monitoring_main() {
    local command="$1"
    shift

    case "$command" in
        check)
            run_health_check
            ;;
        report)
            generate_report
            ;;
        start)
            start_monitoring_daemon
            ;;
        stop)
            stop_monitoring_daemon
            ;;
        status)
            if [[ -f "${BUILD_DIR}/monitoring.pid" ]]; then
                local pid
                pid=$(cat "${BUILD_DIR}/monitoring.pid")
                if kill -0 "$pid" 2>/dev/null; then
                    echo "Monitoring daemon is running (PID: $pid)"
                else
                    echo "Monitoring daemon is not running (stale PID file)"
                fi
            else
                echo "Monitoring daemon is not running"
            fi
            ;;
        *)
            log_error "Unknown monitoring command: $command"
            echo "Usage: $0 monitoring <check|report|start|stop|status>"
            return 1
            ;;
    esac
}

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_environment
    init_logging
    init_monitoring
    monitoring_main "$@"
fi
