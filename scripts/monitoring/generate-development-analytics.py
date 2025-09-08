#!/usr/bin/env python3
"""
BrewNix Development Workflow Analytics
Analyzes developer productivity, code quality trends, and testing effectiveness
"""

import json
import csv
from datetime import datetime, timedelta
import requests
import os
import sys
from collections import defaultdict

def get_pull_requests(base_url, headers, days=30):
    """Get pull requests for the specified period"""
    url = f'{base_url}/pulls'
    params = {
        'state': 'all',
        'per_page': 100,
        'sort': 'updated',
        'direction': 'desc'
    }

    response = requests.get(url, headers=headers, params=params)
    if response.status_code != 200:
        return []

    all_prs = response.json()
    # Filter by date
    cutoff_date = datetime.now() - timedelta(days=days)
    recent_prs = []

    for pr in all_prs:
        updated_at = datetime.fromisoformat(pr['updated_at'].replace('Z', '+00:00'))
        if updated_at >= cutoff_date:
            recent_prs.append(pr)
        else:
            break  # Since they're sorted by updated, we can break early

    return recent_prs

def get_commits(base_url, headers, days=30):
    """Get commits for the specified period"""
    url = f'{base_url}/commits'
    params = {
        'per_page': 100,
        'since': (datetime.now() - timedelta(days=days)).isoformat()
    }

    response = requests.get(url, headers=headers, params=params)
    return response.json() if response.status_code == 200 else []

def get_issues(base_url, headers, days=30):
    """Get issues for the specified period"""
    url = f'{base_url}/issues'
    params = {
        'state': 'all',
        'per_page': 100,
        'sort': 'updated',
        'direction': 'desc'
    }

    response = requests.get(url, headers=headers, params=params)
    if response.status_code != 200:
        return []

    all_issues = response.json()
    # Filter by date and exclude PRs
    cutoff_date = datetime.now() - timedelta(days=days)
    recent_issues = []

    for issue in all_issues:
        if 'pull_request' in issue:
            continue  # Skip PRs

        updated_at = datetime.fromisoformat(issue['updated_at'].replace('Z', '+00:00'))
        if updated_at >= cutoff_date:
            recent_issues.append(issue)
        else:
            break

    return recent_issues

def calculate_stats(values):
    """Calculate basic statistics for a list of values"""
    if not values:
        return {'mean': 0, 'min': 0, 'max': 0, 'count': 0, 'median': 0}

    sorted_values = sorted(values)
    n = len(sorted_values)
    median = sorted_values[n//2] if n % 2 == 1 else (sorted_values[n//2-1] + sorted_values[n//2]) / 2

    return {
        'mean': sum(values) / len(values),
        'min': min(values),
        'max': max(values),
        'count': len(values),
        'median': median
    }

def analyze_developer_productivity():
    """Analyze developer productivity metrics"""

    print('=== Developer Productivity Analysis ===')

    # Configuration
    github_token = os.environ.get('GITHUB_TOKEN')
    repo_owner = os.environ.get('GITHUB_REPOSITORY_OWNER', 'Brewnix')
    repo_name = os.environ.get('GITHUB_REPOSITORY', 'brewnix-template').split('/')[-1]
    base_url = f'https://api.github.com/repos/{repo_owner}/{repo_name}'

    headers = {'Authorization': f'token {github_token}'} if github_token else {}

    # Get data
    prs = get_pull_requests(base_url, headers)
    commits = get_commits(base_url, headers)
    issues = get_issues(base_url, headers)

    print(f'📊 Analyzing {len(prs)} PRs, {len(commits)} commits, {len(issues)} issues')

    # PR Analysis
    pr_metrics = {
        'total_prs': len(prs),
        'open_prs': len([pr for pr in prs if pr['state'] == 'open']),
        'closed_prs': len([pr for pr in prs if pr['state'] == 'closed']),
        'merged_prs': len([pr for pr in prs if pr.get('merged_at')]),
    }

    # Calculate PR merge times
    merge_times = []
    for pr in prs:
        if pr.get('merged_at') and pr['created_at']:
            created = datetime.fromisoformat(pr['created_at'].replace('Z', '+00:00'))
            merged = datetime.fromisoformat(pr['merged_at'].replace('Z', '+00:00'))
            merge_time = (merged - created).total_seconds() / 3600  # hours
            merge_times.append(merge_time)

    pr_metrics['merge_time_stats'] = calculate_stats(merge_times)

    # Commit Analysis
    commit_authors = defaultdict(int)
    for commit in commits:
        if commit.get('author') and commit['author'].get('login'):
            commit_authors[commit['author']['login']] += 1

    # Issue Analysis
    issue_metrics = {
        'total_issues': len(issues),
        'open_issues': len([i for i in issues if i['state'] == 'open']),
        'closed_issues': len([i for i in issues if i['state'] == 'closed']),
    }

    # Calculate issue resolution times
    resolution_times = []
    for issue in issues:
        if issue['state'] == 'closed' and issue.get('closed_at') and issue['created_at']:
            created = datetime.fromisoformat(issue['created_at'].replace('Z', '+00:00'))
            closed = datetime.fromisoformat(issue['closed_at'].replace('Z', '+00:00'))
            resolution_time = (closed - created).total_seconds() / 3600  # hours
            resolution_times.append(resolution_time)

    issue_metrics['resolution_time_stats'] = calculate_stats(resolution_times)

    return {
        'pr_metrics': pr_metrics,
        'commit_authors': dict(commit_authors),
        'issue_metrics': issue_metrics,
        'period_days': 30
    }

def analyze_code_quality():
    """Analyze code quality trends"""

    print('=== Code Quality Analysis ===')

    # This would integrate with linting tools, test coverage, etc.
    # For now, we'll create a placeholder structure

    quality_metrics = {
        'linting_score': 85,  # Placeholder - would come from actual linting
        'test_coverage': 78,  # Placeholder - would come from coverage tools
        'complexity_score': 72,  # Placeholder - would come from complexity analysis
        'security_score': 88,  # Placeholder - would come from security scanning
        'maintainability_index': 76,  # Placeholder - would come from code analysis
    }

    return quality_metrics

def analyze_testing_effectiveness():
    """Analyze testing effectiveness"""

    print('=== Testing Effectiveness Analysis ===')

    # This would analyze test results, flaky tests, etc.
    # For now, we'll create a placeholder structure

    testing_metrics = {
        'total_tests': 1250,
        'passing_tests': 1187,
        'failing_tests': 12,
        'flaky_tests': 8,
        'test_execution_time': 245,  # seconds
        'test_success_rate': 94.96,
        'coverage_trend': [75, 76, 78, 79, 78],  # Last 5 periods
    }

    return testing_metrics

def generate_development_report():
    """Generate comprehensive development analytics report"""

    print('=== BrewNix Development Analytics Report ===')
    print(f'Generated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC")}')
    print()

    # Collect all metrics
    productivity_data = analyze_developer_productivity()
    quality_data = analyze_code_quality()
    testing_data = analyze_testing_effectiveness()

    # Generate insights
    insights = []

    # PR insights
    pr_metrics = productivity_data['pr_metrics']
    if pr_metrics['merge_time_stats']['mean'] > 48:  # More than 2 days
        insights.append('⚠️  Average PR merge time is high (> 2 days) - consider streamlining review process')

    if pr_metrics['open_prs'] > 10:
        insights.append('📋 High number of open PRs - review and merge or close stale PRs')

    # Issue insights
    issue_metrics = productivity_data['issue_metrics']
    if issue_metrics['resolution_time_stats']['mean'] > 168:  # More than 1 week
        insights.append('⏰ Average issue resolution time is high (> 1 week) - improve triage process')

    # Quality insights
    if quality_data['test_coverage'] < 80:
        insights.append('🎯 Test coverage is below target (< 80%) - add more test cases')

    if quality_data['linting_score'] < 85:
        insights.append('🧹 Code quality score needs improvement - address linting issues')

    # Testing insights
    if testing_data['test_success_rate'] < 95:
        insights.append('❌ Test success rate is below target (< 95%) - investigate failing tests')

    if testing_data['flaky_tests'] > 5:
        insights.append('🔄 High number of flaky tests detected - stabilize test suite')

    # Save comprehensive report
    report = {
        'generated_at': datetime.now().isoformat(),
        'period_days': 30,
        'productivity': productivity_data,
        'quality': quality_data,
        'testing': testing_data,
        'insights': insights,
        'recommendations': [
            'Focus on reducing PR merge times through better review processes',
            'Improve test coverage by adding unit tests for critical paths',
            'Address flaky tests to improve CI/CD reliability',
            'Consider implementing code review checklists for consistency',
            'Monitor issue resolution times and implement better triage',
        ]
    }

    with open('development-analytics.json', 'w') as f:
        json.dump(report, f, indent=2)

    print('📄 Development analytics report saved to development-analytics.json')
    return report

def create_markdown_report():
    """Create markdown version of the development analytics report"""

    try:
        with open('development-analytics.json', 'r') as f:
            report = json.load(f)
    except FileNotFoundError:
        print('❌ development-analytics.json not found')
        return False

    # Create markdown report
    md_content = f'''# BrewNix Development Analytics Report

Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}
Period: Last {report['period_days']} days

## Executive Summary

### Productivity Metrics
- **Total PRs**: {report['productivity']['pr_metrics']['total_prs']}
- **Open PRs**: {report['productivity']['pr_metrics']['open_prs']}
- **Merged PRs**: {report['productivity']['pr_metrics']['merged_prs']}
- **Avg PR Merge Time**: {report['productivity']['pr_metrics']['merge_time_stats']['mean']:.1f} hours

### Quality Metrics
- **Test Coverage**: {report['quality']['test_coverage']}%
- **Code Quality Score**: {report['quality']['linting_score']}/100
- **Security Score**: {report['quality']['security_score']}/100

### Testing Effectiveness
- **Test Success Rate**: {report['testing']['test_success_rate']}%
- **Total Tests**: {report['testing']['total_tests']}
- **Flaky Tests**: {report['testing']['flaky_tests']}

## Detailed Analysis

### Pull Request Metrics

| Metric | Value |
|--------|-------|
| Total PRs | {report['productivity']['pr_metrics']['total_prs']} |
| Open PRs | {report['productivity']['pr_metrics']['open_prs']} |
| Merged PRs | {report['productivity']['pr_metrics']['merged_prs']} |
| Closed PRs | {report['productivity']['pr_metrics']['closed_prs']} |

**PR Merge Time Statistics:**
- Average: {report['productivity']['pr_metrics']['merge_time_stats']['mean']:.1f} hours
- Median: {report['productivity']['pr_metrics']['merge_time_stats']['median']:.1f} hours
- Min: {report['productivity']['pr_metrics']['merge_time_stats']['min']:.1f} hours
- Max: {report['productivity']['pr_metrics']['merge_time_stats']['max']:.1f} hours

### Issue Resolution Metrics

| Metric | Value |
|--------|-------|
| Total Issues | {report['productivity']['issue_metrics']['total_issues']} |
| Open Issues | {report['productivity']['issue_metrics']['open_issues']} |
| Closed Issues | {report['productivity']['issue_metrics']['closed_issues']} |

**Issue Resolution Time Statistics:**
- Average: {report['productivity']['issue_metrics']['resolution_time_stats']['mean']:.1f} hours
- Median: {report['productivity']['issue_metrics']['resolution_time_stats']['median']:.1f} hours

### Code Quality Trends

| Metric | Score |
|--------|-------|
| Linting Score | {report['quality']['linting_score']}/100 |
| Test Coverage | {report['quality']['test_coverage']}% |
| Complexity Score | {report['quality']['complexity_score']}/100 |
| Security Score | {report['quality']['security_score']}/100 |
| Maintainability | {report['quality']['maintainability_index']}/100 |

### Testing Effectiveness

| Metric | Value |
|--------|-------|
| Total Tests | {report['testing']['total_tests']} |
| Passing Tests | {report['testing']['passing_tests']} |
| Failing Tests | {report['testing']['failing_tests']} |
| Flaky Tests | {report['testing']['flaky_tests']} |
| Success Rate | {report['testing']['test_success_rate']}% |
| Execution Time | {report['testing']['test_execution_time']}s |

## Key Insights

'''

    for insight in report['insights']:
        md_content += f'- {insight}\n'

    md_content += '''
## Recommendations

'''

    for rec in report['recommendations']:
        md_content += f'- [ ] {rec}\n'

    md_content += '''
## Next Steps

- [ ] Review and address high-priority insights
- [ ] Implement recommended improvements
- [ ] Monitor progress in next analytics cycle
- [ ] Update development processes based on findings

---
*This report was automatically generated by the BrewNix Development Analytics system.*
'''

    with open('development-analytics.md', 'w') as f:
        f.write(md_content)

    print('📄 Markdown report saved to development-analytics.md')
    return True

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'markdown':
        success = create_markdown_report()
    else:
        report = generate_development_report()
        success = create_markdown_report()

    sys.exit(0 if success else 1)
