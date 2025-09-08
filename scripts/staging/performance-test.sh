#!/bin/bash
# scripts/staging/performance-test.sh - Performance testing for staging environments

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

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
STAGING_ENVIRONMENT_ID=""
TEST_DURATION="300"  # 5 minutes default
CONCURRENT_USERS="10"  # 10 users default
TEST_TYPE="load"  # load, stress, spike

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: $0 <staging_environment_id> [options]"
            echo "Options:"
            echo "  --duration <seconds>    Test duration in seconds (default: 300)"
            echo "  --users <count>         Number of concurrent users (default: 10)"
            echo "  --type <type>           Test type: load, stress, spike (default: load)"
            exit 0
            ;;
        --duration)
            TEST_DURATION="$2"
            shift 2
            ;;
        --users)
            CONCURRENT_USERS="$2"
            shift 2
            ;;
        --type)
            TEST_TYPE="$2"
            shift 2
            ;;
        -*)
            log_error "Unknown option: $1"
            exit 1
            ;;
        *)
            if [[ -z "$STAGING_ENVIRONMENT_ID" ]]; then
                STAGING_ENVIRONMENT_ID="$1"
            else
                log_error "Too many arguments"
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$STAGING_ENVIRONMENT_ID" ]]; then
    log_error "Staging environment ID is required"
    echo "Usage: $0 <staging_environment_id> [options]"
    exit 1
fi

STAGING_DIR="$REPO_ROOT/staging/$STAGING_ENVIRONMENT_ID"
PERFORMANCE_LOG="$STAGING_DIR/logs/performance_test_$(date +%Y%m%d_%H%M%S).log"
PERFORMANCE_RESULTS="$STAGING_DIR/performance_test_results.json"

# Create performance test log
exec > >(tee -a "$PERFORMANCE_LOG") 2>&1

log_info "Starting performance test for $STAGING_ENVIRONMENT_ID"
log_info "Test type: $TEST_TYPE, Duration: ${TEST_DURATION}s, Users: $CONCURRENT_USERS"

# Check if staging environment exists
if [[ ! -d "$STAGING_DIR" ]]; then
    log_error "Staging environment not found: $STAGING_DIR"
    exit 1
fi

# Load staging metadata
if [[ ! -f "$STAGING_DIR/metadata.json" ]]; then
    log_error "Staging metadata not found: $STAGING_DIR/metadata.json"
    exit 1
fi

# Parse metadata
SITE_NAME=$(python3 -c "import json; print(json.load(open('$STAGING_DIR/metadata.json'))['site_name'])")
SITE_DISPLAY_NAME=$(python3 -c "import json; print(json.load(open('$STAGING_DIR/metadata.json'))['site_display_name'])")
ANSIBLE_INVENTORY=$(python3 -c "import json; print(json.load(open('$STAGING_DIR/metadata.json'))['ansible_inventory'])")

log_info "Running performance test for $SITE_DISPLAY_NAME"

# Initialize performance test results
cat > "$PERFORMANCE_RESULTS" << EOF
{
  "test_type": "performance_$TEST_TYPE",
  "site_name": "$SITE_NAME",
  "site_display_name": "$SITE_DISPLAY_NAME",
  "staging_environment_id": "$STAGING_ENVIRONMENT_ID",
  "test_start": "$(date -Iseconds)",
  "test_configuration": {
    "duration_seconds": $TEST_DURATION,
    "concurrent_users": $CONCURRENT_USERS,
    "test_type": "$TEST_TYPE"
  },
  "test_results": {}
}
EOF

# Step 1: Pre-test system monitoring
log_step "Step 1: Pre-test system monitoring"

log_info "Collecting baseline system metrics..."
BASELINE_METRICS="$STAGING_DIR/baseline_metrics.json"

ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags system_metrics \
    --extra-vars "output_file=$BASELINE_METRICS" \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/collect_system_metrics.yml"

log_info "Baseline metrics collected: $BASELINE_METRICS"

# Step 2: Load test execution
log_step "Step 2: Load test execution"

log_info "Starting $TEST_TYPE test with $CONCURRENT_USERS users for ${TEST_DURATION}s..."

# Create load test script
LOAD_TEST_SCRIPT="$STAGING_DIR/load_test.py"

# Get application endpoints from metadata
APP_ENDPOINTS=$(python3 -c "
import json
metadata = json.load(open('$STAGING_DIR/metadata.json'))
if 'application_endpoints' in metadata:
    endpoints = metadata['application_endpoints']
    print(' '.join([f'\"{ep}\"' for ep in endpoints]))
else:
    print('\"http://localhost:8080\"')
")

cat > "$LOAD_TEST_SCRIPT" << EOF
#!/usr/bin/env python3
import requests
import time
import threading
import json
import sys
from datetime import datetime
import statistics

# Test configuration
DURATION = $TEST_DURATION
USERS = $CONCURRENT_USERS
ENDPOINTS = [$APP_ENDPOINTS]

results = {
    'response_times': [],
    'status_codes': {},
    'errors': [],
    'requests_per_second': [],
    'total_requests': 0
}

def make_request(session, endpoint):
    start_time = time.time()
    try:
        response = session.get(endpoint, timeout=10)
        response_time = time.time() - start_time
        
        results['response_times'].append(response_time)
        results['status_codes'][str(response.status_code)] = results['status_codes'].get(str(response.status_code), 0) + 1
        results['total_requests'] += 1
        
        return response_time, response.status_code
    except Exception as e:
        results['errors'].append(str(e))
        return None, None

def user_simulation(user_id):
    session = requests.Session()
    start_time = time.time()
    request_count = 0
    
    while time.time() - start_time < DURATION:
        for endpoint in ENDPOINTS:
            make_request(session, endpoint)
            request_count += 1
            time.sleep(0.1)  # Small delay between requests
        
        # Calculate requests per second for this user
        elapsed = time.time() - start_time
        if elapsed > 0:
            rps = request_count / elapsed
            results['requests_per_second'].append(rps)

# Run the test
threads = []
for i in range(USERS):
    t = threading.Thread(target=user_simulation, args=(i,))
    threads.append(t)
    t.start()

# Wait for all threads to complete
for t in threads:
    t.join()

# Calculate statistics
if results['response_times']:
    results['statistics'] = {
        'avg_response_time': statistics.mean(results['response_times']),
        'median_response_time': statistics.median(results['response_times']),
        'min_response_time': min(results['response_times']),
        'max_response_time': max(results['response_times']),
        '95th_percentile': statistics.quantiles(results['response_times'], n=20)[18] if len(results['response_times']) >= 20 else max(results['response_times']),
        '99th_percentile': statistics.quantiles(results['response_times'], n=100)[98] if len(results['response_times']) >= 100 else max(results['response_times'])
    }
else:
    results['statistics'] = {'error': 'No successful requests'}

if results['requests_per_second']:
    results['avg_requests_per_second'] = statistics.mean(results['requests_per_second'])
else:
    results['avg_requests_per_second'] = 0

# Save results
with open('$PERFORMANCE_RESULTS', 'r') as f:
    data = json.load(f)

data['test_results'] = results
data['test_end'] = datetime.now().isoformat()

with open('$PERFORMANCE_RESULTS', 'w') as f:
    json.dump(data, f, indent=2, default=str)

print(f"Load test completed. Results saved to $PERFORMANCE_RESULTS")
EOF

chmod +x "$LOAD_TEST_SCRIPT"

# Run the load test
python3 "$LOAD_TEST_SCRIPT"

log_info "Load test completed. Results saved to: $PERFORMANCE_RESULTS"

# Step 3: Post-test system monitoring
log_step "Step 3: Post-test system monitoring"

log_info "Collecting post-test system metrics..."
POST_TEST_METRICS="$STAGING_DIR/post_test_metrics.json"

ansible-playbook \
    --inventory "$ANSIBLE_INVENTORY" \
    --limit "$SITE_NAME" \
    --tags system_metrics \
    --extra-vars "output_file=$POST_TEST_METRICS" \
    "$REPO_ROOT/vendor/proxmox-firewall/tests/collect_system_metrics.yml"

log_info "Post-test metrics collected: $POST_TEST_METRICS"

# Step 4: Analyze results
log_step "Step 4: Analyze results"

log_info "Analyzing performance test results..."

# Load test results
TEST_RESULTS=$(cat "$PERFORMANCE_RESULTS")

# Extract key metrics
TOTAL_REQUESTS=$(echo "$TEST_RESULTS" | python3 -c "import json, sys; print(json.load(sys.stdin)['test_results']['total_requests'])")
AVG_RESPONSE_TIME=$(echo "$TEST_RESULTS" | python3 -c "import json, sys; data=json.load(sys.stdin); print(f\"{data['test_results']['statistics']['avg_response_time']:.3f}\")" 2>/dev/null || echo "N/A")
P95_RESPONSE_TIME=$(echo "$TEST_RESULTS" | python3 -c "import json, sys; data=json.load(sys.stdin); print(f\"{data['test_results']['statistics']['95th_percentile']:.3f}\")" 2>/dev/null || echo "N/A")
AVG_RPS=$(echo "$TEST_RESULTS" | python3 -c "import json, sys; data=json.load(sys.stdin); print(f\"{data['test_results']['avg_requests_per_second']:.2f}\")" 2>/dev/null || echo "N/A")
ERROR_COUNT=$(echo "$TEST_RESULTS" | python3 -c "import json, sys; print(len(json.load(sys.stdin)['test_results']['errors']))")

# Performance thresholds (configurable)
MAX_RESPONSE_TIME=2.0  # seconds
MAX_ERROR_RATE=0.05    # 5%
MIN_RPS=10            # requests per second

# Calculate error rate
if [[ "$TOTAL_REQUESTS" -gt 0 ]]; then
    ERROR_RATE=$(echo "scale=4; $ERROR_COUNT / $TOTAL_REQUESTS" | bc)
else
    ERROR_RATE=0
fi

# Evaluate performance
PERFORMANCE_PASSED=true
ISSUES=()

# Check response time
if [[ "$AVG_RESPONSE_TIME" != "N/A" && $(echo "$AVG_RESPONSE_TIME > $MAX_RESPONSE_TIME" | bc -l) -eq 1 ]]; then
    PERFORMANCE_PASSED=false
    ISSUES+=("Average response time (${AVG_RESPONSE_TIME}s) exceeds threshold (${MAX_RESPONSE_TIME}s)")
fi

# Check error rate
if [[ $(echo "$ERROR_RATE > $MAX_ERROR_RATE" | bc -l) -eq 1 ]]; then
    PERFORMANCE_PASSED=false
    ISSUES+=("Error rate (${ERROR_RATE}) exceeds threshold (${MAX_ERROR_RATE})")
fi

# Check requests per second
if [[ "$AVG_RPS" != "N/A" && $(echo "$AVG_RPS < $MIN_RPS" | bc -l) -eq 1 ]]; then
    PERFORMANCE_PASSED=false
    ISSUES+=("Average RPS (${AVG_RPS}) below minimum threshold (${MIN_RPS})")
fi

# Step 5: Generate performance report
log_step "Step 5: Generate performance report"

PERFORMANCE_REPORT="$STAGING_DIR/performance_test_report.json"

cat > "$PERFORMANCE_REPORT" << EOF
{
  "performance_report": {
    "site_name": "$SITE_NAME",
    "site_display_name": "$SITE_DISPLAY_NAME",
    "staging_environment_id": "$STAGING_ENVIRONMENT_ID",
    "test_timestamp": "$(date -Iseconds)",
    "test_type": "$TEST_TYPE",
    "test_configuration": {
      "duration_seconds": $TEST_DURATION,
      "concurrent_users": $CONCURRENT_USERS
    },
    "key_metrics": {
      "total_requests": $TOTAL_REQUESTS,
      "average_response_time_seconds": "$AVG_RESPONSE_TIME",
      "95th_percentile_response_time_seconds": "$P95_RESPONSE_TIME",
      "average_requests_per_second": "$AVG_RPS",
      "error_count": $ERROR_COUNT,
      "error_rate": $ERROR_RATE
    },
    "performance_evaluation": {
      "passed": $PERFORMANCE_PASSED,
      "issues": $(printf '%s\n' "${ISSUES[@]}" | jq -R . | jq -s .)
    },
    "thresholds": {
      "max_response_time_seconds": $MAX_RESPONSE_TIME,
      "max_error_rate": $MAX_ERROR_RATE,
      "min_requests_per_second": $MIN_RPS
    },
    "recommendations": [
      $(if [ "$PERFORMANCE_PASSED" = "true" ]; then
          echo '"Performance test passed - system meets requirements"'
      else
          echo '"Performance test failed - address identified issues before production deployment"'
      fi)
    ]
  },
  "baseline_metrics": "$BASELINE_METRICS",
  "post_test_metrics": "$POST_TEST_METRICS",
  "detailed_results": "$PERFORMANCE_RESULTS",
  "test_log": "$PERFORMANCE_LOG"
}
EOF

log_info "Performance test report generated: $PERFORMANCE_REPORT"

# Display results
echo ""
echo "=========================================="
echo "PERFORMANCE TEST RESULTS"
echo "=========================================="
echo "Site: $SITE_DISPLAY_NAME ($SITE_NAME)"
echo "Environment: $STAGING_ENVIRONMENT_ID"
echo "Test Type: $TEST_TYPE"
echo "Duration: ${TEST_DURATION}s"
echo "Concurrent Users: $CONCURRENT_USERS"
echo ""
echo "Key Metrics:"
echo "  Total Requests: $TOTAL_REQUESTS"
echo "  Avg Response Time: ${AVG_RESPONSE_TIME}s"
echo "  95th Percentile: ${P95_RESPONSE_TIME}s"
echo "  Avg RPS: ${AVG_RPS}"
echo "  Errors: $ERROR_COUNT (${ERROR_RATE} rate)"
echo ""
echo "Performance Status: $([ "$PERFORMANCE_PASSED" = "true" ] && echo "✅ PASSED" || echo "❌ FAILED")"
echo ""
if [[ ${#ISSUES[@]} -gt 0 ]]; then
    echo "Issues Found:"
    for issue in "${ISSUES[@]}"; do
        echo "  - $issue"
    done
    echo ""
fi
echo "Report: $PERFORMANCE_REPORT"
echo "Results: $PERFORMANCE_RESULTS"
echo "Log: $PERFORMANCE_LOG"
echo "=========================================="

# Mark performance test as completed
if [[ "$PERFORMANCE_PASSED" == "true" ]]; then
    echo "performance_test_passed" > "$STAGING_DIR/performance_test_passed"
else
    echo "performance_test_failed" > "$STAGING_DIR/performance_test_failed"
fi

# Exit with appropriate code
if [[ "$PERFORMANCE_PASSED" != "true" ]]; then
    exit 1
fi
