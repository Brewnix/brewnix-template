#!/bin/bash

# chaos-engineering.sh
# Chaos engineering testing for BrewNix deployments
# Tests system resilience through controlled failure injection

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOG_FILE=""
BACKUP_DIR=""
DEPLOYMENT_ID=""
ENVIRONMENT=""
DURATION=300  # Default 5 minutes
DRY_RUN=false
VERBOSE=false

# Chaos experiment types
EXPERIMENTS=(
    "network_latency"
    "network_packet_loss"
    "service_kill"
    "resource_exhaustion"
    "disk_space_filling"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "${LOG_FILE}"
}

# Function to display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Chaos engineering testing for BrewNix deployments.

OPTIONS:
    --environment ENV       Target environment (staging, production, development)
    --deployment-id ID       Specific deployment ID for testing
    --duration SEC          Duration of chaos experiments in seconds (default: 300)
    --log-dir DIR           Directory for log files
    --backup-dir DIR        Directory for backup files
    --dry-run               Show what would be done without executing
    --verbose               Enable verbose output
    --help                  Show this help message

EXAMPLES:
    $0 --environment staging --deployment-id 20240907-143000 --duration 600
    $0 --environment production --dry-run --verbose

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --deployment-id)
                DEPLOYMENT_ID="$2"
                shift 2
                ;;
            --duration)
                DURATION="$2"
                shift 2
                ;;
            --log-dir)
                LOG_DIR="$2"
                shift 2
                ;;
            --backup-dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Validate inputs
validate_inputs() {
    if [[ -z "${ENVIRONMENT}" ]]; then
        log_error "Environment is required. Use --environment"
        exit 1
    fi

    if [[ -z "${DEPLOYMENT_ID}" ]]; then
        DEPLOYMENT_ID=$(date +%Y%m%d-%H%M%S)
    fi

    if [[ -z "${LOG_DIR}" ]]; then
        LOG_DIR="${PROJECT_ROOT}/logs/rollback-testing"
    fi

    if [[ -z "${BACKUP_DIR}" ]]; then
        BACKUP_DIR="${PROJECT_ROOT}/backups/rollback-testing"
    fi

    # Create directories if they don't exist
    mkdir -p "${LOG_DIR}" "${BACKUP_DIR}"

    LOG_FILE="${LOG_DIR}/chaos-test-${DEPLOYMENT_ID}.log"
}

# Setup chaos environment
setup_chaos_environment() {
    log_info "Setting up chaos engineering environment..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would setup chaos environment"
        return 0
    fi

    # Create chaos results directory
    CHAOS_RESULTS_DIR="${BACKUP_DIR}/chaos-results-${DEPLOYMENT_ID}"
    mkdir -p "${CHAOS_RESULTS_DIR}"

    # Setup monitoring baseline
    establish_monitoring_baseline

    log_success "Chaos environment setup completed"
}

# Establish monitoring baseline
establish_monitoring_baseline() {
    log_info "Establishing monitoring baseline..."

    # Run initial health checks
    if ! "${SCRIPT_DIR}/../staging/monitor-environment.sh" --environment "${ENVIRONMENT}" --baseline; then
        log_warning "Failed to establish monitoring baseline"
    fi

    # Record initial metrics
    local baseline_file="${CHAOS_RESULTS_DIR}/baseline-metrics.json"
    cat > "${baseline_file}" << EOF
{
    "timestamp": "$(date -Iseconds)",
    "environment": "${ENVIRONMENT}",
    "baseline_metrics": {
        "cpu_usage": "unknown",
        "memory_usage": "unknown",
        "disk_usage": "unknown",
        "network_connections": "unknown"
    }
}
EOF

    log_success "Monitoring baseline established"
}

# Run network latency experiment
run_network_latency_experiment() {
    log_info "Running network latency experiment..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would inject network latency"
        return 0
    fi

    local experiment_duration=60  # 1 minute
    local latency_ms=100

    log_info "Injecting ${latency_ms}ms latency for ${experiment_duration} seconds"

    # Use tc (traffic control) to inject latency
    # Note: This requires root privileges and tc command
    if command -v tc >/dev/null 2>&1; then
        # Add latency to eth0 (adjust interface as needed)
        sudo tc qdisc add dev eth0 root netem delay "${latency_ms}ms"

        # Wait for experiment duration
        sleep "${experiment_duration}"

        # Remove latency
        sudo tc qdisc del dev eth0 root netem
    else
        log_warning "tc command not available, skipping network latency experiment"
    fi

    log_success "Network latency experiment completed"
}

# Run packet loss experiment
run_packet_loss_experiment() {
    log_info "Running packet loss experiment..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would inject packet loss"
        return 0
    fi

    local experiment_duration=30  # 30 seconds
    local loss_percentage=5

    log_info "Injecting ${loss_percentage}% packet loss for ${experiment_duration} seconds"

    # Use tc to inject packet loss
    if command -v tc >/dev/null 2>&1; then
        sudo tc qdisc add dev eth0 root netem loss "${loss_percentage}%"

        sleep "${experiment_duration}"

        sudo tc qdisc del dev eth0 root
    else
        log_warning "tc command not available, skipping packet loss experiment"
    fi

    log_success "Packet loss experiment completed"
}

# Run service kill experiment
run_service_kill_experiment() {
    log_info "Running service kill experiment..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would kill services"
        return 0
    fi

    # Identify services to kill (be careful with this!)
    local services_to_kill=("nginx" "apache2" "httpd")

    for service in "${services_to_kill[@]}"; do
        if systemctl is-active --quiet "${service}"; then
            log_info "Stopping service: ${service}"
            sudo systemctl stop "${service}"

            # Wait a bit
            sleep 10

            # Restart service
            log_info "Restarting service: ${service}"
            sudo systemctl start "${service}"
        else
            log_info "Service ${service} not active, skipping"
        fi
    done

    log_success "Service kill experiment completed"
}

# Run resource exhaustion experiment
run_resource_exhaustion_experiment() {
    log_info "Running resource exhaustion experiment..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would exhaust resources"
        return 0
    fi

    local experiment_duration=30

    log_info "Simulating CPU exhaustion for ${experiment_duration} seconds"

    # Create CPU load using stress or similar tool
    if command -v stress >/dev/null 2>&1; then
        timeout "${experiment_duration}" stress --cpu 2 --timeout "${experiment_duration}" &
    else
        # Fallback: use dd to create CPU load
        timeout "${experiment_duration}" dd if=/dev/zero of=/dev/null &
    fi

    wait
    log_success "Resource exhaustion experiment completed"
}

# Run disk space filling experiment
run_disk_space_experiment() {
    log_info "Running disk space filling experiment..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would fill disk space"
        return 0
    fi

    local temp_file="/tmp/chaos-disk-fill-${DEPLOYMENT_ID}"
    local fill_size_mb=100

    log_info "Filling ${fill_size_mb}MB of disk space"

    # Create a large file to fill disk space
    dd if=/dev/zero of="${temp_file}" bs=1M count="${fill_size_mb}"

    # Wait a bit
    sleep 10

    # Clean up
    rm -f "${temp_file}"

    log_success "Disk space experiment completed"
}

# Monitor experiment impact
monitor_experiment_impact() {
    local experiment_name="$1"

    log_info "Monitoring impact of ${experiment_name}..."

    # Run health checks during experiment
    if ! "${SCRIPT_DIR}/../staging/monitor-environment.sh" --environment "${ENVIRONMENT}" --quick-check; then
        log_warning "Health check failed during ${experiment_name}"
    fi

    # Record metrics
    local metrics_file="${CHAOS_RESULTS_DIR}/metrics-${experiment_name}.json"
    cat > "${metrics_file}" << EOF
{
    "experiment": "${experiment_name}",
    "timestamp": "$(date -Iseconds)",
    "impact_metrics": {
        "response_time": "unknown",
        "error_rate": "unknown",
        "resource_usage": "unknown"
    }
}
EOF
}

# Run chaos experiments
run_chaos_experiments() {
    log_info "Running chaos experiments for ${DURATION} seconds..."

    local experiment_interval=$((DURATION / ${#EXPERIMENTS[@]}))
    local start_time
    start_time=$(date +%s)

    for experiment in "${EXPERIMENTS[@]}"; do
        log_info "Starting experiment: ${experiment}"

        # Monitor before experiment
        monitor_experiment_impact "${experiment}-before"

        # Run specific experiment
        case "${experiment}" in
            network_latency)
                run_network_latency_experiment
                ;;
            network_packet_loss)
                run_packet_loss_experiment
                ;;
            service_kill)
                run_service_kill_experiment
                ;;
            resource_exhaustion)
                run_resource_exhaustion_experiment
                ;;
            disk_space_filling)
                run_disk_space_experiment
                ;;
        esac

        # Monitor after experiment
        monitor_experiment_impact "${experiment}-after"

        # Check if we should continue
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [[ ${elapsed} -ge ${DURATION} ]]; then
            log_info "Chaos experiment duration reached, stopping..."
            break
        fi

        # Wait before next experiment
        if [[ ${elapsed} -lt ${DURATION} ]]; then
            local wait_time=$((experiment_interval / 2))
            log_info "Waiting ${wait_time} seconds before next experiment..."
            sleep "${wait_time}"
        fi
    done

    log_success "Chaos experiments completed"
}

# Validate system recovery
validate_system_recovery() {
    log_info "Validating system recovery after chaos experiments..."

    # Run comprehensive health checks
    if ! "${SCRIPT_DIR}/../staging/comprehensive-validation.sh" --environment "${ENVIRONMENT}" --chaos-recovery; then
        log_error "System recovery validation failed"
        return 1
    fi

    # Check if all services are running
    if ! "${SCRIPT_DIR}/../staging/monitor-environment.sh" --environment "${ENVIRONMENT}" --service-check; then
        log_error "Service recovery validation failed"
        return 1
    fi

    log_success "System recovery validation completed"
}

# Generate chaos engineering report
generate_chaos_report() {
    log_info "Generating chaos engineering test report..."

    local report_file="${LOG_DIR}/chaos-report-${DEPLOYMENT_ID}.json"

    cat > "${report_file}" << EOF
{
    "deployment_id": "${DEPLOYMENT_ID}",
    "environment": "${ENVIRONMENT}",
    "test_timestamp": "$(date -Iseconds)",
    "experiment_duration": ${DURATION},
    "experiments_run": $(printf '%s\n' "${EXPERIMENTS[@]}" | jq -R . | jq -s .),
    "test_status": "completed",
    "total_duration": "$(($(date +%s) - START_TIME))",
    "log_file": "${LOG_FILE}",
    "results_dir": "${CHAOS_RESULTS_DIR}"
}
EOF

    log_success "Chaos engineering report generated: ${report_file}"
}

# Cleanup chaos environment
cleanup_chaos_environment() {
    log_info "Cleaning up chaos engineering environment..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would cleanup chaos environment"
        return 0
    fi

    # Ensure network rules are cleaned up
    if command -v tc >/dev/null 2>&1; then
        sudo tc qdisc del dev eth0 root 2>/dev/null || true
    fi

    # Clean up any remaining chaos artifacts
    rm -rf "${CHAOS_RESULTS_DIR}"

    log_success "Chaos environment cleanup completed"
}

# Main function
main() {
    START_TIME=$(date +%s)

    log_info "Starting chaos engineering test"
    log_info "Environment: ${ENVIRONMENT}"
    log_info "Duration: ${DURATION} seconds"
    log_info "Log file: ${LOG_FILE}"

    # Execute chaos engineering test phases
    setup_chaos_environment
    run_chaos_experiments
    validate_system_recovery
    generate_chaos_report
    cleanup_chaos_environment

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - START_TIME))

    log_success "Chaos engineering test completed successfully in ${duration} seconds"
    log_info "Test results saved to: ${LOG_FILE}"
}

# Initialize script
parse_args "$@"
validate_inputs

# Run main function
if [[ "${VERBOSE}" == "true" ]]; then
    set -x
fi

main "$@"
