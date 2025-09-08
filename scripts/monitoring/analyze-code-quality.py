#!/usr/bin/env python3
"""
BrewNix Code Quality Analysis
Analyzes code quality trends and generates quality metrics
"""

import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

def run_command(cmd, cwd=None):
    """Run a command and return the result"""
    try:
        result = subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True)
        return result.returncode, result.stdout, result.stderr
    except Exception as e:
        return 1, "", str(e)

def analyze_python_quality():
    """Analyze Python code quality"""
    metrics = {}

    # Check for Python files
    python_files = []
    for root, dirs, files in os.walk('.'):
        for file in files:
            if file.endswith('.py'):
                python_files.append(os.path.join(root, file))

    if not python_files:
        return {'python_files': 0, 'error': 'No Python files found'}

    metrics['python_files'] = len(python_files)

    # Run pylint if available
    returncode, stdout, stderr = run_command('python3 -m pylint --output-format=json ' + ' '.join(python_files[:5]))  # Limit to first 5 files
    if returncode == 0 and stdout:
        try:
            pylint_results = json.loads(stdout)
            metrics['pylint_score'] = sum(item.get('score', 0) for item in pylint_results) / len(pylint_results) if pylint_results else 0
            metrics['pylint_issues'] = len([item for item in pylint_results if item.get('type') == 'error'])
        except:
            metrics['pylint_score'] = 0
            metrics['pylint_issues'] = 0
    else:
        metrics['pylint_score'] = 0
        metrics['pylint_issues'] = 0

    # Run flake8 if available
    returncode, stdout, stderr = run_command('python3 -m flake8 --max-line-length=100 --extend-ignore=E203,W503 ' + ' '.join(python_files[:5]))
    metrics['flake8_issues'] = len(stdout.split('\n')) if stdout else 0

    # Run radon for complexity
    returncode, stdout, stderr = run_command('python3 -m radon cc --average ' + ' '.join(python_files[:5]))
    if returncode == 0 and stdout:
        try:
            # Parse radon output (average complexity)
            lines = stdout.split('\n')
            for line in lines:
                if 'Average complexity:' in line:
                    metrics['average_complexity'] = float(line.split(':')[1].strip())
                    break
        except:
            metrics['average_complexity'] = 0
    else:
        metrics['average_complexity'] = 0

    return metrics

def analyze_javascript_quality():
    """Analyze JavaScript/TypeScript code quality"""
    metrics = {}

    # Check for JS/TS files
    js_files = []
    ts_files = []
    for root, dirs, files in os.walk('.'):
        for file in files:
            if file.endswith('.js') or file.endswith('.jsx'):
                js_files.append(os.path.join(root, file))
            elif file.endswith('.ts') or file.endswith('.tsx'):
                ts_files.append(os.path.join(root, file))

    metrics['javascript_files'] = len(js_files)
    metrics['typescript_files'] = len(ts_files)

    # Run eslint if available
    all_js_files = js_files + ts_files
    if all_js_files:
        returncode, stdout, stderr = run_command('npx eslint --format=json ' + ' '.join(all_js_files[:5]))
        if returncode == 0 and stdout:
            try:
                eslint_results = json.loads(stdout)
                total_issues = 0
                error_count = 0
                warning_count = 0
                for file_result in eslint_results:
                    if 'messages' in file_result:
                        for message in file_result['messages']:
                            total_issues += 1
                            if message.get('severity') == 2:
                                error_count += 1
                            elif message.get('severity') == 1:
                                warning_count += 1
                metrics['eslint_total_issues'] = total_issues
                metrics['eslint_errors'] = error_count
                metrics['eslint_warnings'] = warning_count
            except:
                metrics['eslint_total_issues'] = 0
                metrics['eslint_errors'] = 0
                metrics['eslint_warnings'] = 0
        else:
            metrics['eslint_total_issues'] = 0
            metrics['eslint_errors'] = 0
            metrics['eslint_warnings'] = 0

    return metrics

def analyze_shell_quality():
    """Analyze shell script quality"""
    metrics = {}

    # Check for shell files
    shell_files = []
    for root, dirs, files in os.walk('.'):
        for file in files:
            if file.endswith('.sh') or file.endswith('.bash'):
                shell_files.append(os.path.join(root, file))

    metrics['shell_files'] = len(shell_files)

    # Run shellcheck if available
    if shell_files:
        returncode, stdout, stderr = run_command('shellcheck --format=json ' + ' '.join(shell_files[:5]))
        if returncode == 0 and stdout:
            try:
                shellcheck_results = json.loads(stdout)
                total_issues = 0
                error_count = 0
                warning_count = 0
                for file_result in shellcheck_results:
                    if 'comments' in file_result:
                        for comment in file_result['comments']:
                            total_issues += 1
                            if comment.get('level') == 'error':
                                error_count += 1
                            elif comment.get('level') == 'warning':
                                warning_count += 1
                metrics['shellcheck_total_issues'] = total_issues
                metrics['shellcheck_errors'] = error_count
                metrics['shellcheck_warnings'] = warning_count
            except:
                metrics['shellcheck_total_issues'] = 0
                metrics['shellcheck_errors'] = 0
                metrics['shellcheck_warnings'] = 0
        else:
            metrics['shellcheck_total_issues'] = 0
            metrics['shellcheck_errors'] = 0
            metrics['shellcheck_warnings'] = 0

    return metrics

def calculate_overall_quality_score(python_metrics, js_metrics, shell_metrics):
    """Calculate overall code quality score"""
    scores = []

    # Python score (weighted by file count)
    if python_metrics.get('python_files', 0) > 0:
        python_score = 100
        if python_metrics.get('pylint_score'):
            python_score = min(100, python_metrics['pylint_score'] * 10)
        python_score -= python_metrics.get('flake8_issues', 0) * 2
        python_score -= python_metrics.get('pylint_issues', 0) * 5
        python_score = max(0, python_score)
        scores.append((python_score, python_metrics['python_files']))

    # JavaScript/TypeScript score
    if js_metrics.get('javascript_files', 0) > 0 or js_metrics.get('typescript_files', 0) > 0:
        js_score = 100
        js_score -= js_metrics.get('eslint_errors', 0) * 10
        js_score -= js_metrics.get('eslint_warnings', 0) * 2
        js_score = max(0, js_score)
        total_js_files = js_metrics.get('javascript_files', 0) + js_metrics.get('typescript_files', 0)
        scores.append((js_score, total_js_files))

    # Shell script score
    if shell_metrics.get('shell_files', 0) > 0:
        shell_score = 100
        shell_score -= shell_metrics.get('shellcheck_errors', 0) * 10
        shell_score -= shell_metrics.get('shellcheck_warnings', 0) * 2
        shell_score = max(0, shell_score)
        scores.append((shell_score, shell_metrics['shell_files']))

    # Calculate weighted average
    if scores:
        total_score = 0
        total_files = 0
        for score, files in scores:
            total_score += score * files
            total_files += files
        return total_score / total_files if total_files > 0 else 0

    return 0

def generate_quality_report():
    """Generate comprehensive code quality report"""

    print('=== Code Quality Analysis ===')
    print(f'Generated: {datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC")}')
    print()

    # Analyze different languages
    python_metrics = analyze_python_quality()
    js_metrics = analyze_javascript_quality()
    shell_metrics = analyze_shell_quality()

    # Calculate overall score
    overall_score = calculate_overall_quality_score(python_metrics, js_metrics, shell_metrics)

    # Generate insights
    insights = []

    if overall_score < 70:
        insights.append('❌ Overall code quality is poor - immediate attention required')
    elif overall_score < 80:
        insights.append('⚠️  Code quality needs improvement')
    else:
        insights.append('✅ Code quality is good')

    # Language-specific insights
    if python_metrics.get('python_files', 0) > 0:
        if python_metrics.get('pylint_score', 0) < 7:
            insights.append('🐍 Python code quality needs improvement (Pylint score < 7)')
        if python_metrics.get('flake8_issues', 0) > 10:
            insights.append('🐍 High number of Python style issues detected')

    if js_metrics.get('eslint_errors', 0) > 5:
        insights.append('🟨 High number of JavaScript/TypeScript errors detected')

    if shell_metrics.get('shellcheck_errors', 0) > 3:
        insights.append('🐚 Shell script errors detected - fix immediately')

    # Create comprehensive report
    report = {
        'generated_at': datetime.now().isoformat(),
        'overall_quality_score': round(overall_score, 2),
        'python_metrics': python_metrics,
        'javascript_metrics': js_metrics,
        'shell_metrics': shell_metrics,
        'insights': insights,
        'recommendations': [
            'Run automated code quality checks in CI/CD pipeline',
            'Set up pre-commit hooks for code quality validation',
            'Establish code review checklists for quality standards',
            'Implement regular code quality training sessions',
            'Consider using automated code refactoring tools',
        ]
    }

    with open('code-quality-report.json', 'w') as f:
        json.dump(report, f, indent=2)

    print(f'📊 Overall Quality Score: {overall_score:.1f}/100')
    print(f'📄 Report saved to code-quality-report.json')

    return report

def create_quality_markdown_report():
    """Create markdown version of the quality report"""

    try:
        with open('code-quality-report.json', 'r') as f:
            report = json.load(f)
    except FileNotFoundError:
        print('❌ code-quality-report.json not found')
        return False

    # Create markdown report
    md_content = f'''# BrewNix Code Quality Report

Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}

## Executive Summary

**Overall Quality Score: {report['overall_quality_score']}/100**

## Language Breakdown

### Python Code Quality

| Metric | Value |
|--------|-------|
| Python Files | {report['python_metrics'].get('python_files', 0)} |
| Pylint Score | {report['python_metrics'].get('pylint_score', 0):.1f}/10 |
| Pylint Issues | {report['python_metrics'].get('pylint_issues', 0)} |
| Flake8 Issues | {report['python_metrics'].get('flake8_issues', 0)} |
| Average Complexity | {report['python_metrics'].get('average_complexity', 0):.1f} |

### JavaScript/TypeScript Code Quality

| Metric | Value |
|--------|-------|
| JavaScript Files | {report['javascript_metrics'].get('javascript_files', 0)} |
| TypeScript Files | {report['javascript_metrics'].get('typescript_files', 0)} |
| ESLint Total Issues | {report['javascript_metrics'].get('eslint_total_issues', 0)} |
| ESLint Errors | {report['javascript_metrics'].get('eslint_errors', 0)} |
| ESLint Warnings | {report['javascript_metrics'].get('eslint_warnings', 0)} |

### Shell Script Quality

| Metric | Value |
|--------|-------|
| Shell Files | {report['shell_metrics'].get('shell_files', 0)} |
| ShellCheck Total Issues | {report['shell_metrics'].get('shellcheck_total_issues', 0)} |
| ShellCheck Errors | {report['shell_metrics'].get('shellcheck_errors', 0)} |
| ShellCheck Warnings | {report['shell_metrics'].get('shellcheck_warnings', 0)} |

## Quality Insights

'''

    for insight in report['insights']:
        md_content += f'- {insight}\n'

    md_content += '''
## Recommendations

'''

    for rec in report['recommendations']:
        md_content += f'- [ ] {rec}\n'

    md_content += '''
## Quality Score Interpretation

- **90-100**: Excellent code quality
- **80-89**: Good code quality
- **70-79**: Acceptable code quality
- **60-69**: Needs improvement
- **Below 60**: Critical attention required

## Next Steps

- [ ] Review and address high-priority quality issues
- [ ] Implement automated quality gates in CI/CD
- [ ] Set up regular quality monitoring
- [ ] Train team on quality best practices

---
*This report was automatically generated by the BrewNix Code Quality Analysis system.*
'''

    with open('code-quality-report.md', 'w') as f:
        f.write(md_content)

    print('📄 Markdown report saved to code-quality-report.md')
    return True

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'markdown':
        success = create_quality_markdown_report()
    else:
        report = generate_quality_report()
        success = create_quality_markdown_report()

    sys.exit(0 if success else 1)
