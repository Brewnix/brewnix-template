#!/bin/bash
# scripts/staging/generate-validation-report.sh - Generate comprehensive validation report

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
OUTPUT_FORMAT="json"  # json, html, pdf

while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            echo "Usage: $0 <staging_environment_id> [options]"
            echo "Options:"
            echo "  --format <format>    Output format: json, html, pdf (default: json)"
            exit 0
            ;;
        --format)
            OUTPUT_FORMAT="$2"
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
REPORT_LOG="$STAGING_DIR/logs/generate_validation_report_$(date +%Y%m%d_%H%M%S).log"

# Create report generation log
exec > >(tee -a "$REPORT_LOG") 2>&1

log_info "Starting validation report generation for $STAGING_ENVIRONMENT_ID"

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

log_info "Generating validation report for $SITE_DISPLAY_NAME"

# Collect all validation results
log_step "Collecting validation results"

VALIDATION_FILES=()
VALIDATION_SUMMARIES=()

# Find all validation result files
if [[ -f "$STAGING_DIR/comprehensive_validation_results.json" ]]; then
    VALIDATION_FILES+=("$STAGING_DIR/comprehensive_validation_results.json")
fi

if [[ -f "$STAGING_DIR/performance_test_results.json" ]]; then
    VALIDATION_FILES+=("$STAGING_DIR/performance_test_results.json")
fi

if [[ -f "$STAGING_DIR/security_validation_results.json" ]]; then
    VALIDATION_FILES+=("$STAGING_DIR/security_validation_results.json")
fi

# Find all validation summary files
if [[ -f "$STAGING_DIR/comprehensive_validation_summary.json" ]]; then
    VALIDATION_SUMMARIES+=("$STAGING_DIR/comprehensive_validation_summary.json")
fi

if [[ -f "$STAGING_DIR/performance_test_report.json" ]]; then
    VALIDATION_SUMMARIES+=("$STAGING_DIR/performance_test_report.json")
fi

if [[ -f "$STAGING_DIR/security_validation_summary.json" ]]; then
    VALIDATION_SUMMARIES+=("$STAGING_DIR/security_validation_summary.json")
fi

if [[ ${#VALIDATION_FILES[@]} -eq 0 ]]; then
    log_warn "No validation result files found"
fi

if [[ ${#VALIDATION_SUMMARIES[@]} -eq 0 ]]; then
    log_warn "No validation summary files found"
fi

# Generate comprehensive report
log_step "Generating comprehensive report"

COMPREHENSIVE_REPORT="$STAGING_DIR/comprehensive_validation_report.json"

# Initialize report structure
cat > "$COMPREHENSIVE_REPORT" << EOF
{
  "comprehensive_validation_report": {
    "report_metadata": {
      "site_name": "$SITE_NAME",
      "site_display_name": "$SITE_DISPLAY_NAME",
      "staging_environment_id": "$STAGING_ENVIRONMENT_ID",
      "report_generated": "$(date -Iseconds)",
      "report_format": "$OUTPUT_FORMAT"
    },
    "validation_summary": {},
    "validation_details": {},
    "recommendations": [],
    "production_readiness": {}
  }
}
EOF

# Aggregate validation results
python3 -c "
import json
import os
from datetime import datetime

report = json.load(open('$COMPREHENSIVE_REPORT'))

# Initialize counters
total_validations = 0
passed_validations = 0
failed_validations = 0
warning_validations = 0

all_recommendations = []
validation_details = {}

# Process validation summaries
validation_summaries = [
$(for summary_file in "${VALIDATION_SUMMARIES[@]}"; do
    echo "    '$summary_file',"
done)
]

for summary_file in validation_summaries:
    if os.path.exists(summary_file):
        try:
            with open(summary_file, 'r') as f:
                summary_data = json.load(f)
            
            # Extract validation type from filename
            filename = os.path.basename(summary_file)
            if 'comprehensive' in filename:
                validation_type = 'comprehensive'
            elif 'performance' in filename:
                validation_type = 'performance'
            elif 'security' in filename:
                validation_type = 'security'
            else:
                validation_type = 'unknown'
            
            validation_details[validation_type] = summary_data
            
            # Count results
            if 'overall_status' in summary_data.get(validation_type + '_validation_summary', {}):
                status = summary_data[validation_type + '_validation_summary']['overall_status']
            elif 'overall_status' in summary_data:
                status = summary_data['overall_status']
            else:
                status = 'unknown'
            
            total_validations += 1
            if status == 'passed':
                passed_validations += 1
            elif status == 'failed':
                failed_validations += 1
            else:
                warning_validations += 1
            
            # Collect recommendations
            if 'recommendations' in summary_data.get(validation_type + '_validation_summary', {}):
                all_recommendations.extend(summary_data[validation_type + '_validation_summary']['recommendations'])
            elif 'recommendations' in summary_data:
                all_recommendations.extend(summary_data['recommendations'])
                
        except Exception as e:
            print(f'Error processing {summary_file}: {e}', file=sys.stderr)

# Calculate overall metrics
overall_success_rate = (passed_validations / total_validations * 100) if total_validations > 0 else 0

# Determine production readiness
if overall_success_rate >= 95:
    production_readiness = 'ready'
    readiness_message = 'Environment is ready for production deployment'
elif overall_success_rate >= 85:
    production_readiness = 'conditional'
    readiness_message = 'Environment is conditionally ready - minor issues to address'
elif overall_success_rate >= 75:
    production_readiness = 'needs_attention'
    readiness_message = 'Environment needs attention - address critical issues before production'
else:
    production_readiness = 'not_ready'
    readiness_message = 'Environment is not ready for production - critical issues must be resolved'

# Update report
report['comprehensive_validation_report']['validation_summary'] = {
    'total_validations': total_validations,
    'passed_validations': passed_validations,
    'failed_validations': failed_validations,
    'warning_validations': warning_validations,
    'overall_success_rate': round(overall_success_rate, 2)
}

report['comprehensive_validation_report']['validation_details'] = validation_details
report['comprehensive_validation_report']['recommendations'] = list(set(all_recommendations))
report['comprehensive_validation_report']['production_readiness'] = {
    'status': production_readiness,
    'message': readiness_message,
    'success_rate': round(overall_success_rate, 2)
}

# Save comprehensive report
with open('$COMPREHENSIVE_REPORT', 'w') as f:
    json.dump(report, f, indent=2)

print(f'Comprehensive report generated: $COMPREHENSIVE_REPORT')
"

log_info "Comprehensive validation report generated: $COMPREHENSIVE_REPORT"

# Generate HTML report if requested
if [[ "$OUTPUT_FORMAT" == "html" ]]; then
    log_step "Generating HTML report"

    HTML_REPORT="$STAGING_DIR/comprehensive_validation_report.html"

    python3 -c "
import json
from datetime import datetime

# Load the comprehensive report
with open('$COMPREHENSIVE_REPORT', 'r') as f:
    report_data = json.load(f)

report = report_data['comprehensive_validation_report']
metadata = report['report_metadata']
summary = report['validation_summary']
readiness = report['production_readiness']

# Generate recommendations HTML
recommendations_html = ''
for rec in report['recommendations']:
    recommendations_html += f'<div class=\"recommendation-item\">{rec}</div>\n            '

# Generate HTML
html_content = f'''
<!DOCTYPE html>
<html lang=\"en\">
<head>
    <meta charset=\"UTF-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
    <title>Staging Validation Report - {metadata['site_display_name']}</title>
    <style>
        body {{
            font-family: Arial, sans-serif;
            line-height: 1.6;
            margin: 40px;
            background-color: #f5f5f5;
        }}
        .container {{
            max-width: 1200px;
            margin: 0 auto;
            background-color: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }}
        .header {{
            text-align: center;
            border-bottom: 2px solid #333;
            padding-bottom: 20px;
            margin-bottom: 30px;
        }}
        .summary {{
            background-color: #f8f9fa;
            padding: 20px;
            border-radius: 5px;
            margin-bottom: 30px;
        }}
        .status-badge {{
            display: inline-block;
            padding: 5px 15px;
            border-radius: 20px;
            font-weight: bold;
            text-transform: uppercase;
            font-size: 0.9em;
        }}
        .status-ready {{ background-color: #d4edda; color: #155724; }}
        .status-conditional {{ background-color: #fff3cd; color: #856404; }}
        .status-attention {{ background-color: #f8d7da; color: #721c24; }}
        .status-not-ready {{ background-color: #f8d7da; color: #721c24; }}
        .metrics {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }}
        .metric-card {{
            background-color: #f8f9fa;
            padding: 20px;
            border-radius: 5px;
            text-align: center;
        }}
        .metric-value {{
            font-size: 2em;
            font-weight: bold;
            color: #007bff;
        }}
        .recommendations {{
            background-color: #f8f9fa;
            padding: 20px;
            border-radius: 5px;
            margin-bottom: 30px;
        }}
        .recommendation-item {{
            background-color: white;
            margin: 10px 0;
            padding: 10px;
            border-left: 4px solid #007bff;
            border-radius: 3px;
        }}
        .footer {{
            text-align: center;
            color: #666;
            font-size: 0.9em;
            border-top: 1px solid #ddd;
            padding-top: 20px;
            margin-top: 40px;
        }}
    </style>
</head>
<body>
    <div class=\"container\">
        <div class=\"header\">
            <h1>Staging Validation Report</h1>
            <h2>{metadata['site_display_name']} ({metadata['site_name']})</h2>
            <p>Environment: {metadata['staging_environment_id']}</p>
            <p>Report Generated: {metadata['report_generated']}</p>
        </div>

        <div class=\"summary\">
            <h3>Overall Status</h3>
            <span class=\"status-badge status-{readiness['status']}\">{readiness['status'].upper()}</span>
            <p><strong>{readiness['message']}</strong></p>
            <p>Overall Success Rate: {readiness['success_rate']}%</p>
        </div>

        <div class=\"metrics\">
            <div class=\"metric-card\">
                <div class=\"metric-value\">{summary['total_validations']}</div>
                <div>Total Validations</div>
            </div>
            <div class=\"metric-card\">
                <div class=\"metric-value\">{summary['passed_validations']}</div>
                <div>Passed</div>
            </div>
            <div class=\"metric-card\">
                <div class=\"metric-value\">{summary['failed_validations']}</div>
                <div>Failed</div>
            </div>
            <div class=\"metric-card\">
                <div class=\"metric-value\">{summary['warning_validations']}</div>
                <div>Warnings</div>
            </div>
        </div>

        <div class=\"recommendations\">
            <h3>Recommendations</h3>
            {recommendations_html}
        </div>

        <div class=\"footer\">
            <p>This report was automatically generated by BrewNix staging validation system.</p>
            <p>For questions or concerns, please contact the DevOps team.</p>
        </div>
    </div>
</body>
</html>
'''

with open('$HTML_REPORT', 'w') as f:
    f.write(html_content)

print(f'HTML report generated: $HTML_REPORT')
"

    log_info "HTML validation report generated: $HTML_REPORT"
fi

# Display report summary
echo ""
echo "=========================================="
echo "COMPREHENSIVE VALIDATION REPORT"
echo "=========================================="
echo "Site: $SITE_DISPLAY_NAME ($SITE_NAME)"
echo "Environment: $STAGING_ENVIRONMENT_ID"
echo "Report Generated: $(date -Iseconds)"
echo ""

# Load and display summary
if [[ -f "$COMPREHENSIVE_REPORT" ]]; then
    SUMMARY_DATA=$(cat "$COMPREHENSIVE_REPORT")
    
    TOTAL_VALS=$(echo "$SUMMARY_DATA" | python3 -c "import json, sys; print(json.load(sys.stdin)['comprehensive_validation_report']['validation_summary']['total_validations'])")
    PASSED_VALS=$(echo "$SUMMARY_DATA" | python3 -c "import json, sys; print(json.load(sys.stdin)['comprehensive_validation_report']['validation_summary']['passed_validations'])")
    FAILED_VALS=$(echo "$SUMMARY_DATA" | python3 -c "import json, sys; print(json.load(sys.stdin)['comprehensive_validation_report']['validation_summary']['failed_validations'])")
    WARNING_VALS=$(echo "$SUMMARY_DATA" | python3 -c "import json, sys; print(json.load(sys.stdin)['comprehensive_validation_report']['validation_summary']['warning_validations'])")
    SUCCESS_RATE=$(echo "$SUMMARY_DATA" | python3 -c "import json, sys; print(json.load(sys.stdin)['comprehensive_validation_report']['validation_summary']['overall_success_rate'])")
    
    PRODUCTION_STATUS=$(echo "$SUMMARY_DATA" | python3 -c "import json, sys; print(json.load(sys.stdin)['comprehensive_validation_report']['production_readiness']['status'])")
    PRODUCTION_MESSAGE=$(echo "$SUMMARY_DATA" | python3 -c "import json, sys; print(json.load(sys.stdin)['comprehensive_validation_report']['production_readiness']['message'])")
    
    echo "Validation Summary:"
    echo "  Total Validations: $TOTAL_VALS"
    echo "  Passed: $PASSED_VALS"
    echo "  Failed: $FAILED_VALS"
    echo "  Warnings: $WARNING_VALS"
    echo "  Success Rate: ${SUCCESS_RATE}%"
    echo ""
    echo "Production Readiness:"
    echo "  Status: $(echo "$PRODUCTION_STATUS" | tr '[:lower:]' '[:upper:]')"
    echo "  Message: $PRODUCTION_MESSAGE"
    echo ""
    
    echo "Generated Files:"
    echo "  JSON Report: $COMPREHENSIVE_REPORT"
    if [[ "$OUTPUT_FORMAT" == "html" && -f "$HTML_REPORT" ]]; then
        echo "  HTML Report: $HTML_REPORT"
    fi
    echo "  Report Log: $REPORT_LOG"
else
    log_error "Failed to generate comprehensive report"
    exit 1
fi

echo "=========================================="

log_info "Validation report generation completed successfully"
