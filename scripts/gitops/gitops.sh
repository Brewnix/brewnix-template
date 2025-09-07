#!/bin/bash
# scripts/gitops/gitops.sh - GitOps repository management

# Source core modules
source "${SCRIPT_DIR}/core/init.sh"
source "${SCRIPT_DIR}/core/config.sh"
source "${SCRIPT_DIR}/core/logging.sh"

# GitOps configuration
GITOPS_REPO_URL="${GITOPS_REPO_URL:-$(get_config_value 'gitops.repo_url')}"
GITOPS_BRANCH="${GITOPS_BRANCH:-$(get_config_value 'gitops.branch' || echo 'main')}"
GITOPS_LOCAL_PATH="${GITOPS_LOCAL_PATH:-${BUILD_DIR}/gitops}"
GITOPS_SYNC_INTERVAL="${GITOPS_SYNC_INTERVAL:-300}"  # 5 minutes
GITOPS_SSH_KEY="${GITOPS_SSH_KEY:-$(get_config_value 'gitops.ssh_key')}"

# Initialize GitOps
init_gitops() {
    if [[ -z "$GITOPS_REPO_URL" ]]; then
        log_error "GitOps repository URL not configured"
        return 1
    fi

    mkdir -p "$GITOPS_LOCAL_PATH"
    log_info "GitOps system initialized"
    log_debug "Repository: $GITOPS_REPO_URL"
    log_debug "Branch: $GITOPS_BRANCH"
    log_debug "Local path: $GITOPS_LOCAL_PATH"
}

# Clone or update repository
sync_repository() {
    local force="${1:-false}"

    log_info "Syncing GitOps repository..."

    if [[ ! -d "${GITOPS_LOCAL_PATH}/.git" ]]; then
        # Clone repository
        log_debug "Cloning repository: $GITOPS_REPO_URL"

        if [[ -n "$GITOPS_SSH_KEY" ]]; then
            # Use SSH key for authentication
            export GIT_SSH_COMMAND="ssh -i $GITOPS_SSH_KEY -o StrictHostKeyChecking=no"
        fi

        if git clone --branch "$GITOPS_BRANCH" "$GITOPS_REPO_URL" "$GITOPS_LOCAL_PATH" 2>/dev/null; then
            log_info "Repository cloned successfully"
        else
            log_error "Failed to clone repository"
            return 1
        fi
    else
        # Update existing repository
        log_debug "Updating repository"

        cd "$GITOPS_LOCAL_PATH" || return 1

        if [[ "$force" == "true" ]]; then
            git reset --hard HEAD
            git clean -fd
        fi

        if git pull origin "$GITOPS_BRANCH" 2>/dev/null; then
            log_info "Repository updated successfully"
        else
            log_error "Failed to update repository"
            return 1
        fi
    fi

    # Get latest commit info
    cd "$GITOPS_LOCAL_PATH" || return 1
    local latest_commit
    latest_commit=$(git log -1 --oneline 2>/dev/null || echo "unknown")

    log_info "Repository sync completed - Latest: $latest_commit"
    return 0
}

# Check for configuration drift
check_drift() {
    log_info "Checking for configuration drift..."

    if [[ ! -d "$GITOPS_LOCAL_PATH" ]]; then
        log_error "GitOps repository not synced"
        return 1
    fi

    local drift_detected=false
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local drift_report="${BUILD_DIR}/drift_report_${timestamp}.txt"

    {
        echo "Configuration Drift Report"
        echo "Generated: $(date)"
        echo "=========================="
        echo ""
    } > "$drift_report"

    # Compare configurations
    local config_files=("config.yml" "sites" "devices")

    for config_file in "${config_files[@]}"; do
        local git_file="${GITOPS_LOCAL_PATH}/${config_file}"
        local local_file="${PROJECT_ROOT}/${config_file}"

        if [[ -f "$git_file" && -f "$local_file" ]]; then
            if ! diff -q "$git_file" "$local_file" >/dev/null 2>&1; then
                drift_detected=true
                {
                    echo "DRIFT DETECTED: $config_file"
                    echo "Differences:"
                    diff -u "$git_file" "$local_file" | sed 's/^/  /'
                    echo ""
                } >> "$drift_report"
            else
                echo "OK: $config_file" >> "$drift_report"
            fi
        elif [[ -f "$git_file" && ! -f "$local_file" ]]; then
            drift_detected=true
            echo "MISSING LOCALLY: $config_file" >> "$drift_report"
        elif [[ ! -f "$git_file" && -f "$local_file" ]]; then
            drift_detected=true
            echo "MISSING IN GIT: $config_file" >> "$drift_report"
        fi
    done

    if [[ "$drift_detected" == "true" ]]; then
        log_warn "Configuration drift detected"
        log_info "Drift report: $drift_report"

        # Send alert if configured
        if [[ -n "$ALERT_EMAIL" ]]; then
            echo "Configuration drift detected. See attached report." | \
                mail -s "BrewNix: Configuration Drift Detected" \
                     -A "$drift_report" "$ALERT_EMAIL"
        fi

        echo "$drift_report"
        return 1
    else
        log_info "No configuration drift detected"
        rm -f "$drift_report"
        return 0
    fi
}

# Push local changes to repository
push_changes() {
    local commit_message="${1:-Auto-commit: Configuration update}"

    if [[ ! -d "$GITOPS_LOCAL_PATH" ]]; then
        log_error "GitOps repository not available"
        return 1
    fi

    log_info "Pushing changes to GitOps repository..."

    cd "$GITOPS_LOCAL_PATH" || return 1

    # Copy current configuration to git repo
    cp "${PROJECT_ROOT}/config.yml" . 2>/dev/null || true
    cp -r "${PROJECT_ROOT}/sites" . 2>/dev/null || true
    cp -r "${PROJECT_ROOT}/devices" . 2>/dev/null || true

    # Check for changes
    if git diff --quiet && git diff --staged --quiet; then
        log_info "No changes to push"
        return 0
    fi

    # Add and commit changes
    git add .

    if git commit -m "$commit_message" 2>/dev/null; then
        if git push origin "$GITOPS_BRANCH" 2>/dev/null; then
            log_info "Changes pushed successfully"
            return 0
        else
            log_error "Failed to push changes"
            return 1
        fi
    else
        log_info "No changes to commit"
        return 0
    fi
}

# Pull and apply configuration changes
pull_and_apply() {
    log_info "Pulling and applying configuration changes..."

    # Sync repository
    if ! sync_repository; then
        log_error "Failed to sync repository"
        return 1
    fi

    # Check for drift
    if check_drift >/dev/null 2>&1; then
        log_info "Configuration is up to date"
        return 0
    fi

    # Apply changes from repository
    log_warn "Applying configuration changes from repository..."

    # Backup current configuration
    local backup_file
    backup_file=$(create_backup "pre_gitops_apply")

    # Copy configuration from repository
    cp "${GITOPS_LOCAL_PATH}/config.yml" "${PROJECT_ROOT}/" 2>/dev/null || true
    cp -r "${GITOPS_LOCAL_PATH}/sites" "${PROJECT_ROOT}/" 2>/dev/null || true
    cp -r "${GITOPS_LOCAL_PATH}/devices" "${PROJECT_ROOT}/" 2>/dev/null || true

    log_info "Configuration changes applied"
    log_info "Backup created: $backup_file"

    # Reload configuration
    load_config

    return 0
}

# Setup webhook handler
setup_webhook_handler() {
    local webhook_port="${1:-8080}"
    local webhook_script="${BUILD_DIR}/webhook_handler.sh"

    log_info "Setting up webhook handler on port $webhook_port"

    # Create webhook handler script
    cat > "$webhook_script" << 'EOF'
#!/bin/bash
# Webhook handler for GitOps automation

WEBHOOK_LOG="/tmp/webhook.log"

echo "$(date): Webhook received" >> "$WEBHOOK_LOG"

# Process webhook payload (simplified - in production, validate signature)
if [[ "$REQUEST_METHOD" == "POST" ]]; then
    # Read payload
    read -r payload
    
    # Check if it's a push event to our branch
    if echo "$payload" | grep -q '"ref":.*refs/heads/'"${GITOPS_BRANCH}"'"'; then
        echo "$(date): Push to ${GITOPS_BRANCH} detected, triggering sync" >> "$WEBHOOK_LOG"
        
        # Trigger configuration sync
        nohup /bin/bash -c "cd '${SCRIPT_DIR}/gitops' && source gitops.sh && pull_and_apply" >> "$WEBHOOK_LOG" 2>&1 &
    fi
fi

# Send response
echo "HTTP/1.1 200 OK"
echo "Content-Type: text/plain"
echo ""
echo "Webhook processed"
EOF

    chmod +x "$webhook_script"

    # Start simple HTTP server
    if command -v nc &> /dev/null; then
        log_info "Starting webhook listener on port $webhook_port"
        (
            while true; do
                nc -l -p "$webhook_port" -e "$webhook_script"
            done
        ) &
        local listener_pid=$!
        echo "$listener_pid" > "${BUILD_DIR}/webhook_listener.pid"
        log_info "Webhook listener started (PID: $listener_pid)"
    else
        log_error "netcat not available for webhook handling"
        return 1
    fi
}

# Start GitOps daemon
start_gitops_daemon() {
    local pid_file="${BUILD_DIR}/gitops.pid"

    if [[ -f "$pid_file" ]]; then
        local existing_pid
        existing_pid=$(cat "$pid_file")
        if kill -0 "$existing_pid" 2>/dev/null; then
            log_warn "GitOps daemon already running (PID: $existing_pid)"
            return 1
        else
            rm -f "$pid_file"
        fi
    fi

    log_info "Starting GitOps daemon..."

    # Start daemon in background
    (
        while true; do
            sync_repository > /dev/null 2>&1
            check_drift > /dev/null 2>&1
            sleep "$GITOPS_SYNC_INTERVAL"
        done
    ) &

    local daemon_pid=$!
    echo "$daemon_pid" > "$pid_file"

    log_info "GitOps daemon started (PID: $daemon_pid)"
}

# Stop GitOps daemon
stop_gitops_daemon() {
    local pid_file="${BUILD_DIR}/gitops.pid"

    if [[ ! -f "$pid_file" ]]; then
        log_warn "No GitOps daemon PID file found"
        return 1
    fi

    local daemon_pid
    daemon_pid=$(cat "$pid_file")

    if kill "$daemon_pid" 2>/dev/null; then
        log_info "GitOps daemon stopped (PID: $daemon_pid)"
        rm -f "$pid_file"
    else
        log_error "Failed to stop GitOps daemon"
        return 1
    fi
}

# Main GitOps function
gitops_main() {
    local command="$1"
    shift

    case "$command" in
        sync)
            sync_repository "$@"
            ;;
        push)
            push_changes "$@"
            ;;
        pull)
            pull_and_apply
            ;;
        drift)
            check_drift
            ;;
        webhook)
            setup_webhook_handler "$@"
            ;;
        start)
            start_gitops_daemon
            ;;
        stop)
            stop_gitops_daemon
            ;;
        status)
            if [[ -f "${BUILD_DIR}/gitops.pid" ]]; then
                local pid
                pid=$(cat "${BUILD_DIR}/gitops.pid")
                if kill -0 "$pid" 2>/dev/null; then
                    echo "GitOps daemon is running (PID: $pid)"
                else
                    echo "GitOps daemon is not running (stale PID file)"
                fi
            else
                echo "GitOps daemon is not running"
            fi
            ;;
        *)
            log_error "Unknown GitOps command: $command"
            echo "Usage: $0 gitops <sync|push|pull|drift|webhook|start|stop|status> [options]"
            return 1
            ;;
    esac
}

# If script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_environment
    init_logging
    init_gitops
    gitops_main "$@"
fi
