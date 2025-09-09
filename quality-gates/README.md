# BrewNix Code Quality Gates

## Phase 5.1.2: Automated Code Quality Assurance

This directory contains the comprehensive code quality assurance system for BrewNix, implementing automated linting, complexity analysis, security scanning, and code review validation.

## Overview

The quality gates system ensures that all code meets production-ready standards before deployment. It consists of four main components:

1. **Linting** - Code style and syntax validation
2. **Complexity Analysis** - Code complexity and maintainability checks
3. **Security Scanning** - Vulnerability detection and security best practices
4. **Code Review Automation** - Automated code review and best practices validation

## Directory Structure

```text
quality-gates/
├── run_quality_gates.py      # Main orchestrator script
├── linting/
│   └── generate_configs.py   # Linting configuration generator
├── complexity/
│   └── analyze_complexity.py # Multi-language complexity analyzer
├── security/
│   └── scan_security.py      # Security vulnerability scanner
├── review/
│   └── automate_review.py    # Automated code review tool
└── reports/                  # Generated quality reports
```

## Usage

### Running All Quality Gates

```bash
cd /path/to/brewnix-template
python3 quality-gates/run_quality_gates.py
```

### Running Individual Components

#### Security Scanning

```bash
python3 quality-gates/security/scan_security.py
```

#### Code Review Automation

```bash
python3 quality-gates/review/automate_review.py
```

#### Complexity Analysis

```bash
python3 quality-gates/complexity/analyze_complexity.py
```

#### Linting Configuration

```bash
python3 quality-gates/linting/generate_configs.py
```

## Quality Gate Thresholds

### Linting

- Max Errors: 0
- Max Warnings: 10

### Complexity

- Max Complexity Score: 10
- Max Function Lines: 100

### Security

- Max Critical Vulnerabilities: 0
- Max High Vulnerabilities: 0
- Max Medium Vulnerabilities: 5

### Code Review

- Min Quality Score: 75%

## Supported Languages

- **Python** - Full support for all quality gates
- **Shell Scripts** - Linting, complexity, and security scanning
- **YAML/JSON** - Configuration file validation
- **General Files** - Basic security and structure checks

## Quality Gate Results

### Status Levels

- **PASSED** ✅ - All checks passed, code is production-ready
- **WARNING** ⚠️ - Minor issues found, review recommended
- **FAILED** ❌ - Critical issues found, must be fixed before proceeding

### Report Generation

All quality gate runs generate detailed JSON reports in the `reports/` directory:

- `quality-gate-report-{timestamp}.json` - Complete quality gate results
- `security-report-{timestamp}.json` - Security scan details
- `review-report-{timestamp}.json` - Code review findings

## Integration with CI/CD

The quality gates are designed to integrate with CI/CD pipelines:

```bash
# In your CI/CD pipeline
python3 quality-gates/run_quality_gates.py
if [ $? -ne 0 ]; then
    echo "Quality gates failed - blocking deployment"
    exit 1
fi
```

## Dependencies

### Required Python Packages

- `flake8` - Python linting
- `bandit` - Python security scanning
- `radon` - Python complexity analysis
- `shellcheck` - Shell script linting
- `yamllint` - YAML validation

### Optional Dependencies

- `pylint` - Advanced Python linting
- `mypy` - Python type checking
- `black` - Python code formatting

## Usage

### Running All Quality Gates

```bash
cd /path/to/brewnix-template
python3 quality-gates/run_quality_gates.py
```

### Running Individual Components

#### Security Scanning
```bash
python3 quality-gates/security/scan_security.py
```

#### Code Review Automation
```bash
python3 quality-gates/review/automate_review.py
```

#### Complexity Analysis
```bash
python3 quality-gates/complexity/analyze_complexity.py
```

#### Linting Configuration
```bash
python3 quality-gates/linting/generate_configs.py
```

## Quality Gate Thresholds

The system uses configurable thresholds for determining pass/fail status:

### Linting
- Max Errors: 0
- Max Warnings: 10

### Complexity
- Max Complexity Score: 10
- Max Function Lines: 100

### Security
- Max Critical Vulnerabilities: 0
- Max High Vulnerabilities: 0
- Max Medium Vulnerabilities: 5

### Code Review
- Min Quality Score: 75%

## Supported Languages

- **Python** - Full support for all quality gates
- **Shell Scripts** - Linting, complexity, and security scanning
- **YAML/JSON** - Configuration file validation
- **General Files** - Basic security and structure checks

## Quality Gate Results

### Status Levels
- **PASSED** ✅ - All checks passed, code is production-ready
- **WARNING** ⚠️ - Minor issues found, review recommended
- **FAILED** ❌ - Critical issues found, must be fixed before proceeding

### Report Generation

All quality gate runs generate detailed JSON reports in the `reports/` directory:

- `quality-gate-report-{timestamp}.json` - Complete quality gate results
- `security-report-{timestamp}.json` - Security scan details
- `review-report-{timestamp}.json` - Code review findings

## Integration with CI/CD

The quality gates are designed to integrate with CI/CD pipelines:

```bash
# In your CI/CD pipeline
python3 quality-gates/run_quality_gates.py
if [ $? -ne 0 ]; then
    echo "Quality gates failed - blocking deployment"
    exit 1
fi
```

## Dependencies

### Required Python Packages
- `flake8` - Python linting
- `bandit` - Python security scanning
- `radon` - Python complexity analysis
- `shellcheck` - Shell script linting
- `yamllint` - YAML validation

### Optional Dependencies
- `pylint` - Advanced Python linting
- `mypy` - Python type checking
- `black` - Python code formatting

## Configuration

### Threshold Configuration

Edit the thresholds in `run_quality_gates.py`:

```python
self.thresholds = {
    "linting": {
        "max_errors": 0,
        "max_warnings": 10
    },
    "complexity": {
        "max_complexity": 10,
        "max_lines": 100
    },
    "security": {
        "max_critical": 0,
        "max_high": 0,
        "max_medium": 5
    }
}
```

### Linting Rules

The linting configuration generator creates language-specific config files:

- `.flake8` - Python linting rules
- `.shellcheckrc` - Shell script linting rules
- `.yamllint.yml` - YAML linting rules

## Best Practices

### For Developers

1. Run quality gates locally before committing
2. Address all FAILED issues immediately
3. Review WARNING issues and fix where possible
4. Keep code complexity below thresholds
5. Follow security best practices

### For CI/CD

1. Run quality gates on every push
2. Block merges on FAILED status
3. Allow WARNING status for urgent fixes
4. Archive quality reports for trend analysis

## Troubleshooting

### Common Issues

#### Missing Dependencies

```bash
pip install flake8 bandit radon yamllint
```

#### Permission Errors

```bash
chmod +x quality-gates/run_quality_gates.py
```

#### Path Issues

Ensure you're running from the project root directory.

### Debug Mode

Run with verbose output:

```bash
python3 -m quality-gates.run_quality_gates
```

## Contributing

When adding new quality checks:

1. Add the check to the appropriate module
2. Update the main orchestrator
3. Add tests for the new functionality
4. Update this documentation
5. Ensure the check integrates with the reporting system

## Future Enhancements

- Integration with SonarQube
- Custom rule engines
- Historical trend analysis
- IDE plugin integration
- Automated fix suggestions
