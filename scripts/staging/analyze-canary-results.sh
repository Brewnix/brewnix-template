#!/bin/bash
# scripts/staging/analyze-canary-results.sh - Analyze canary deployment results

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

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: $0 <staging_environment_id>"
            echo "Analyze canary deployment results"
            exit 0
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
    echo "Usage: $0 <staging_environment_id>"
    exit 1
fi

STAGING_DIR="$REPO_ROOT/staging/$STAGING_ENVIRONMENT_ID"
ANALYSIS_LOG="$STAGING_DIR/logs/canary_analysis_$(date +%Y%m%d_%H%M%S).log"

# Create analysis log
exec > >(tee -a "$ANALYSIS_LOG") 2>&1

log_info "Starting canary results analysis for $STAGING_ENVIRONMENT_ID"

# Check if staging environment exists
if [[ ! -d "$STAGING_DIR" ]]; then
    log_error "Staging environment not found: $STAGING_DIR"
    exit 1
fi

# Check if canary monitoring data exists
if [[ ! -f "$STAGING_DIR/canary_monitor_data.json" ]]; then
    log_error "Canary monitoring data not found: $STAGING_DIR/canary_monitor_data.json"
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

log_info "Analyzing canary results for $SITE_DISPLAY_NAME"

# Load canary monitoring data
CANARY_DATA=$(cat "$STAGING_DIR/canary_monitor_data.json")

# Extract key metrics
TOTAL_CHECKS=$(echo "$CANARY_DATA" | python3 -c "import json, sys; print(json.load(sys.stdin)['total_checks'])")
HEALTHY_CHECKS=$(echo "$CANARY_DATA" | python3 -c "import json, sys; print(json.load(sys.stdin)['healthy_checks'])")
WARNING_CHECKS=$(echo "$CANARY_DATA" | python3 -c "import json, sys; print(json.load(sys.stdin)['warning_checks'])")
UNHEALTHY_CHECKS=$(echo "$CANARY_DATA" | python3 -c "import json, sys; print(json.load(sys.stdin)['unhealthy_checks'])")
OVERALL_SUCCESS_RATE=$(echo "$CANARY_DATA" | python3 -c "import json, sys; print(json.load(sys.stdin)['overall_success_rate'])")
AVG_RESPONSE_TIME=$(echo "$CANARY_DATA" | python3 -c "import json, sys; print(json.load(sys.stdin)['average_response_time'])")
AVG_ERROR_RATE=$(echo "$CANARY_DATA" | python3 -c "import json, sys; print(json.load(sys.stdin)['average_error_rate'])")
CANARY_PERCENTAGE=$(echo "$CANARY_DATA" | python3 -c "import json, sys; print(json.load(sys.stdin)['canary_percentage'])")

log_step "Analyzing canary performance metrics"

echo "=========================================="
echo "CANARY ANALYSIS METRICS"
echo "=========================================="
echo "Site: $SITE_DISPLAY_NAME ($SITE_NAME)"
echo "Canary Traffic: ${CANARY_PERCENTAGE}%"
echo "Total Monitoring Checks: $TOTAL_CHECKS"
echo "Healthy Checks: $HEALTHY_CHECKS"
echo "Warning Checks: $WARNING_CHECKS"
echo "Unhealthy Checks: $UNHEALTHY_CHECKS"
echo "Overall Success Rate: ${OVERALL_SUCCESS_RATE}%"
echo "Average Response Time: ${AVG_RESPONSE_TIME}ms"
echo "Average Error Rate: ${AVG_ERROR_RATE}%"
echo "=========================================="

# Analyze performance trends
log_info "Analyzing performance trends..."

# Calculate trend analysis
python3 -c "
import json
import sys

data = json.load(open('$STAGING_DIR/canary_monitor_data.json'))
metrics = data['metrics']

if len(metrics) > 1:
    # Response time trend
    response_times = [m['response_time_avg'] for m in metrics if m['response_time_avg'] > 0]
    if len(response_times) > 1:
        first_avg = sum(response_times[:len(response_times)//2]) / len(response_times[:len(response_times)//2])
        second_avg = sum(response_times[len(response_times)//2:]) / len(response_times[len(response_times)//2:])
        if second_avg > first_avg * 1.1:
            print('RESPONSE_TIME_TREND=worsening')
        elif second_avg < first_avg * 0.9:
            print('RESPONSE_TIME_TREND=improving')
        else:
            print('RESPONSE_TIME_TREND=stable')
    else:
        print('RESPONSE_TIME_TREND=unknown')
    
    # Error rate trend
    error_rates = [m['error_rate'] for m in metrics if m['error_rate'] > 0]
    if len(error_rates) > 1:
        first_avg = sum(error_rates[:len(error_rates)//2]) / len(error_rates[:len(error_rates)//2])
        second_avg = sum(error_rates[len(error_rates)//2:]) / len(error_rates[len(error_rates)//2:])
        if second_avg > first_avg * 1.2:
            print('ERROR_RATE_TREND=worsening')
        elif second_avg < first_avg * 0.8:
            print('ERROR_RATE_TREND=improving')
        else:
            print('ERROR_RATE_TREND=stable')
    else:
        print('ERROR_RATE_TREND=unknown')
    
    # Success rate trend
    success_rates = [m['success_rate'] for m in metrics]
    if len(success_rates) > 1:
        first_avg = sum(success_rates[:len(success_rates)//2]) / len(success_rates[:len(success_rates)//2])
        second_avg = sum(success_rates[len(success_rates)//2:]) / len(success_rates[len(success_rates)//2:])
        if second_avg > first_avg + 2:
            print('SUCCESS_RATE_TREND=improving')
        elif second_avg < first_avg - 2:
            print('SUCCESS_RATE_TREND=worsening')
        else:
            print('SUCCESS_RATE_TREND=stable')
    else:
        print('SUCCESS_RATE_TREND=unknown')
else:
    print('RESPONSE_TIME_TREND=insufficient_data')
    print('ERROR_RATE_TREND=insufficient_data')
    print('SUCCESS_RATE_TREND=insufficient_data')
" > "$STAGING_DIR/trend_analysis.txt"

# Load trend analysis
if [[ -f "$STAGING_DIR/trend_analysis.txt" ]]; then
    RESPONSE_TIME_TREND=$(grep "RESPONSE_TIME_TREND" "$STAGING_DIR/trend_analysis.txt" | cut -d'=' -f2)
    ERROR_RATE_TREND=$(grep "ERROR_RATE_TREND" "$STAGING_DIR/trend_analysis.txt" | cut -d'=' -f2)
    SUCCESS_RATE_TREND=$(grep "SUCCESS_RATE_TREND" "$STAGING_DIR/trend_analysis.txt" | cut -d'=' -f2)
else
    RESPONSE_TIME_TREND="unknown"
    ERROR_RATE_TREND="unknown"
    SUCCESS_RATE_TREND="unknown"
fi

log_info "Performance Trends:"
log_info "  Response Time: $RESPONSE_TIME_TREND"
log_info "  Error Rate: $ERROR_RATE_TREND"
log_info "  Success Rate: $SUCCESS_RATE_TREND"

# Determine canary analysis result
log_step "Determining canary analysis result"

CANARY_RESULT="unknown"
CANARY_CONFIDENCE="low"
RECOMMENDATIONS=()

# Primary criteria: Success rate
if [ $OVERALL_SUCCESS_RATE -ge 95 ] && [ $UNHEALTHY_CHECKS -eq 0 ]; then
    CANARY_RESULT="excellent"
    CANARY_CONFIDENCE="high"
    RECOMMENDATIONS+=("Canary deployment is performing excellently")
    RECOMMENDATIONS+=("Safe to proceed with full traffic switch")
    RECOMMENDATIONS+=("Consider automating this canary percentage for future deployments")
elif [ $OVERALL_SUCCESS_RATE -ge 90 ] && [ $UNHEALTHY_CHECKS -le 1 ]; then
    CANARY_RESULT="good"
    CANARY_CONFIDENCE="high"
    RECOMMENDATIONS+=("Canary deployment is performing well")
    RECOMMENDATIONS+=("Safe to proceed with gradual traffic increase")
    RECOMMENDATIONS+=("Monitor closely during full rollout")
elif [ $OVERALL_SUCCESS_RATE -ge 80 ] && [ $UNHEALTHY_CHECKS -le 2 ]; then
    CANARY_RESULT="acceptable"
    CANARY_CONFIDENCE="medium"
    RECOMMENDATIONS+=("Canary deployment shows acceptable performance")
    RECOMMENDATIONS+=("Proceed with caution and close monitoring")
    RECOMMENDATIONS+=("Consider reducing traffic increase rate")
elif [ $OVERALL_SUCCESS_RATE -ge 70 ]; then
    CANARY_RESULT="concerning"
    CANARY_CONFIDENCE="medium"
    RECOMMENDATIONS+=("Canary deployment has concerning performance")
    RECOMMENDATIONS+=("Do not increase traffic beyond current level")
    RECOMMENDATIONS+=("Investigate issues before proceeding")
else
    CANARY_RESULT="poor"
    CANARY_CONFIDENCE="high"
    RECOMMENDATIONS+=("Canary deployment performance is poor")
    RECOMMENDATIONS+=("Do not proceed with rollout")
    RECOMMENDATIONS+=("Consider rolling back canary deployment")
fi

# Factor in trends
if [[ "$RESPONSE_TIME_TREND" == "worsening" ]]; then
    RECOMMENDATIONS+=("Response time is trending worse - investigate performance issues")
    if [[ "$CANARY_CONFIDENCE" == "high" ]]; then
        CANARY_CONFIDENCE="medium"
    fi
elif [[ "$RESPONSE_TIME_TREND" == "improving" ]]; then
    RECOMMENDATIONS+=("Response time is improving - positive trend")
fi

if [[ "$ERROR_RATE_TREND" == "worsening" ]]; then
    RECOMMENDATIONS+=("Error rate is trending worse - investigate stability issues")
    if [[ "$CANARY_CONFIDENCE" != "low" ]]; then
        CANARY_CONFIDENCE="low"
    fi
elif [[ "$ERROR_RATE_TREND" == "improving" ]]; then
    RECOMMENDATIONS+=("Error rate is improving - positive trend")
fi

# Factor in absolute performance metrics
if [ "$AVG_RESPONSE_TIME" -gt 1000 ]; then
    RECOMMENDATIONS+=("High average response time (${AVG_RESPONSE_TIME}ms) - optimize performance")
    if [[ "$CANARY_RESULT" == "excellent" ]]; then
        CANARY_RESULT="good"
    fi
fi

if [ "$AVG_ERROR_RATE" -gt 5 ]; then
    RECOMMENDATIONS+=("High error rate (${AVG_ERROR_RATE}%) - investigate errors")
    if [[ "$CANARY_RESULT" != "poor" ]]; then
        CANARY_RESULT="concerning"
    fi
fi

log_info "Canary Analysis Result: $CANARY_RESULT (Confidence: $CANARY_CONFIDENCE)"

# Create canary analysis report
CANARY_ANALYSIS_REPORT="$STAGING_DIR/canary_analysis_results.json"

cat > "$CANARY_ANALYSIS_REPORT" << EOF
{
  "analysis_type": "canary_deployment_analysis",
  "site_name": "$SITE_NAME",
  "site_display_name": "$SITE_DISPLAY_NAME",
  "staging_environment_id": "$STAGING_ENVIRONMENT_ID",
  "canary_percentage": $CANARY_PERCENTAGE,
  "analysis_timestamp": "$(date -Iseconds)",
  "performance_metrics": {
    "total_checks": $TOTAL_CHECKS,
    "healthy_checks": $HEALTHY_CHECKS,
    "warning_checks": $WARNING_CHECKS,
    "unhealthy_checks": $UNHEALTHY_CHECKS,
    "overall_success_rate": $OVERALL_SUCCESS_RATE,
    "average_response_time": $AVG_RESPONSE_TIME,
    "average_error_rate": $AVG_ERROR_RATE
  },
  "performance_trends": {
    "response_time_trend": "$RESPONSE_TIME_TREND",
    "error_rate_trend": "$ERROR_RATE_TREND",
    "success_rate_trend": "$SUCCESS_RATE_TREND"
  },
  "analysis_result": {
    "canary_result": "$CANARY_RESULT",
    "confidence_level": "$CANARY_CONFIDENCE",
    "recommendations": $(printf '%s\n' "${RECOMMENDATIONS[@]}" | jq -R . | jq -s .)
  },
  "analysis_log": "$ANALYSIS_LOG"
}
EOF

log_info "Canary analysis report saved to: $CANARY_ANALYSIS_REPORT"

echo ""
echo "=========================================="
echo "CANARY ANALYSIS SUMMARY"
echo "=========================================="
echo "Site: $SITE_DISPLAY_NAME ($SITE_NAME)"
echo "Environment: $STAGING_ENVIRONMENT_ID"
echo "Canary Traffic: ${CANARY_PERCENTAGE}%"
echo "Result: $CANARY_RESULT"
echo "Confidence: $CANARY_CONFIDENCE"
echo ""
echo "Key Metrics:"
echo "  Success Rate: ${OVERALL_SUCCESS_RATE}%"
echo "  Avg Response Time: ${AVG_RESPONSE_TIME}ms"
echo "  Avg Error Rate: ${AVG_ERROR_RATE}%"
echo ""
echo "Trends:"
echo "  Response Time: $RESPONSE_TIME_TREND"
echo "  Error Rate: $ERROR_RATE_TREND"
echo "  Success Rate: $SUCCESS_RATE_TREND"
echo ""
echo "Recommendations:"
for rec in "${RECOMMENDATIONS[@]}"; do
    echo "  • $rec"
done
echo ""
echo "Report: $CANARY_ANALYSIS_REPORT"
echo "Log: $ANALYSIS_LOG"
echo "=========================================="

# Mark analysis as completed
echo "canary_analysis_completed" > "$STAGING_DIR/canary_analysis_completed"
