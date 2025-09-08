#!/usr/bin/env python3
"""
BrewNix Pipeline Performance Report Generator
Generates comprehensive reports on CI/CD pipeline performance
"""

import json
import csv
from datetime import datetime, timedelta
import requests
import os
import sys

def get_workflow_runs(base_url, workflow_id, headers, days=7):
    """Get workflow runs for the specified period"""
    url = f'{base_url}/actions/workflows/{workflow_id}/runs'
    params = {
        'per_page': 100,
        'created': f'>{datetime.now() - timedelta(days=days):%Y-%m-%d}T00:00:00Z'
    }

    response = requests.get(url, headers=headers, params=params)
    return response.json()['workflow_runs'] if response.status_code == 200 else []

def calculate_stats(values):
    """Calculate basic statistics for a list of values"""
    if not values:
        return {'mean': 0, 'min': 0, 'max': 0, 'count': 0}

    return {
        'mean': sum(values) / len(values),
        'min': min(values),
        'max': max(values),
        'count': len(values)
    }

def generate_report():
    """Generate comprehensive pipeline performance report"""

    print('=== BrewNix Pipeline Performance Report ===')
    print(f'Generated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC")}')
    print()

    # Configuration
    github_token = os.environ.get('GITHUB_TOKEN')
    repo_owner = os.environ.get('GITHUB_REPOSITORY_OWNER', 'Brewnix')
    repo_name = os.environ.get('GITHUB_REPOSITORY', 'brewnix-template').split('/')[-1]
    base_url = f'https://api.github.com/repos/{repo_owner}/{repo_name}'

    headers = {'Authorization': f'token {github_token}'} if github_token else {}

    # Get all workflows
    workflows_url = f'{base_url}/actions/workflows'
    workflows_response = requests.get(workflows_url, headers=headers)

    if workflows_response.status_code != 200:
        print('❌ Failed to fetch workflows')
        return False

    workflows = workflows_response.json()['workflows']
    report_data = []

    for workflow in workflows:
        if workflow['state'] != 'active':
            continue

        print(f'📊 Analyzing workflow: {workflow["name"]}')

        runs = get_workflow_runs(base_url, workflow['id'], headers)

        if not runs:
            print(f'  ℹ️  No runs found for {workflow["name"]}')
            continue

        # Calculate metrics
        total_runs = len(runs)
        successful_runs = len([r for r in runs if r['conclusion'] == 'success'])
        failed_runs = len([r for r in runs if r['conclusion'] == 'failure'])
        success_rate = (successful_runs / total_runs * 100) if total_runs > 0 else 0

        # Calculate average duration
        durations = []
        for run in runs:
            if run['status'] == 'completed':
                created = datetime.fromisoformat(run['created_at'].replace('Z', '+00:00'))
                updated = datetime.fromisoformat(run['updated_at'].replace('Z', '+00:00'))
                duration = (updated - created).total_seconds()
                durations.append(duration)

        avg_duration = sum(durations) / len(durations) if durations else 0

        report_data.append({
            'workflow': workflow['name'],
            'total_runs': total_runs,
            'successful_runs': successful_runs,
            'failed_runs': failed_runs,
            'success_rate': round(success_rate, 2),
            'avg_duration': round(avg_duration, 2)
        })

        print(f'  ✅ Success Rate: {success_rate:.1f}%')
        print(f'  ⏱️  Avg Duration: {avg_duration:.1f}s')
        print(f'  📈 Total Runs: {total_runs}')
        print()

    # Generate summary
    if report_data:
        success_rates = [w['success_rate'] for w in report_data]
        durations = [w['avg_duration'] for w in report_data]

        success_stats = calculate_stats(success_rates)
        duration_stats = calculate_stats(durations)

        print('=== Summary Statistics ===')
        print(f'Total Workflows: {len(report_data)}')
        print(f'Overall Success Rate: {success_stats["mean"]:.1f}%')
        print(f'Average Duration: {duration_stats["mean"]:.1f}s')
        print()

        # Identify problematic workflows
        problematic = [w for w in report_data if w['success_rate'] < 80]
        if problematic:
            print('⚠️  Workflows with < 80% success rate:')
            for workflow in problematic:
                print(f'  - {workflow["workflow"]}: {workflow["success_rate"]}% success rate')
            print()

        # Identify slow workflows (top 25% slowest)
        if durations:
            sorted_durations = sorted(durations)
            threshold_index = int(len(sorted_durations) * 0.75)
            slow_threshold = sorted_durations[threshold_index] * 1.5

            slow_workflows = [w for w in report_data if w['avg_duration'] > slow_threshold]
            if slow_workflows:
                print('🐌 Slow workflows (> 1.5x Q3 duration):')
                for workflow in slow_workflows:
                    print(f'  - {workflow["workflow"]}: {workflow["avg_duration"]}s average')
                print()

    # Save JSON report
    report = {
        'generated_at': datetime.now().isoformat(),
        'period_days': 7,
        'workflows': report_data,
        'summary': {
            'total_workflows': len(report_data),
            'overall_success_rate': success_stats['mean'] if report_data else 0,
            'average_duration': duration_stats['mean'] if report_data else 0
        }
    }

    with open('pipeline-report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print('📄 JSON report saved to pipeline-report.json')
    return True

def create_markdown_report():
    """Create markdown version of the report"""

    try:
        with open('pipeline-report.json', 'r') as f:
            report = json.load(f)
    except FileNotFoundError:
        print('❌ pipeline-report.json not found')
        return False

    # Create markdown report
    md_content = f'''# BrewNix Pipeline Performance Report

Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}
Period: Last 7 days

## Executive Summary

- **Total Workflows**: {report['summary']['total_workflows']}
- **Overall Success Rate**: {report['summary']['overall_success_rate']:.1f}%
- **Average Duration**: {report['summary']['average_duration']:.1f}s

## Workflow Details

| Workflow | Success Rate | Avg Duration | Total Runs |
|----------|-------------|--------------|------------|
'''

    for workflow in report['workflows']:
        md_content += f'| {workflow["workflow"]} | {workflow["success_rate"]}% | {workflow["avg_duration"]}s | {workflow["total_runs"]} |\n'

    md_content += '''
## Recommendations

'''

    # Add recommendations based on data
    if report['workflows']:
        success_rates = [w['success_rate'] for w in report['workflows']]
        durations = [w['avg_duration'] for w in report['workflows']]

        if success_rates and min(success_rates) < 80:
            md_content += '- ⚠️  Review workflows with low success rates (< 80%)\n'

        if durations and max(durations) > 600:  # 10 minutes
            md_content += '- 🐌 Optimize slow workflows (> 10 minutes average)\n'

        if report['summary']['overall_success_rate'] < 90:
            md_content += '- 📈 Focus on improving overall pipeline reliability\n'

    md_content += '''
## Next Steps

- [ ] Review failed workflow runs for root causes
- [ ] Optimize slow-performing workflows
- [ ] Update monitoring thresholds based on trends
- [ ] Implement additional alerting rules if needed

---
*This report was automatically generated by the BrewNix Pipeline Monitoring system.*
'''

    with open('pipeline-report.md', 'w') as f:
        f.write(md_content)

    print('📄 Markdown report saved to pipeline-report.md')
    return True

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'markdown':
        success = create_markdown_report()
    else:
        success = generate_report()

    sys.exit(0 if success else 1)
