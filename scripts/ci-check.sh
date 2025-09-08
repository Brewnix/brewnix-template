#!/bin/bash

# BrewNix CI Validation Script
# Quick validation before pushing to CI/CD pipeline

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

cd "$PROJECT_ROOT"

echo "🔍 BrewNix CI Validation Check"
echo "================================"

# Quick syntax checks
echo
echo "Checking shell scripts..."
find . -name "*.sh" -type f -exec bash -n {} \; 2>&1 | while read -r line; do
    if [[ $line == *": "* ]]; then
        log_error "Syntax error in $(echo "$line" | cut -d: -f1)"
    fi
done

if [ $? -eq 0 ]; then
    log_success "All shell scripts have valid syntax"
fi

# Check YAML files
echo
echo "Checking YAML files..."
if command -v python3 >/dev/null 2>&1; then
    find . \( -name "*.yml" -o -name "*.yaml" \) -not -path "./vendor/*" | while read -r file; do
        if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
            log_success "Valid YAML: $file"
        else
            log_error "Invalid YAML: $file"
        fi
    done
else
    log_warning "Python3 not available - skipping YAML validation"
fi

# Check for large files
echo
echo "Checking for large files..."
find . -type f -not -path "./.git/*" -not -path "./vendor/*" -size +50M | while read -r file; do
    log_warning "Large file detected: $file"
done

# Check git status
echo
echo "Checking git status..."
if git status --porcelain | grep -q .; then
    log_warning "Uncommitted changes detected"
    echo "Modified files:"
    git status --porcelain | head -10
else
    log_success "Working directory is clean"
fi

# Check branch
current_branch=$(git branch --show-current)
echo
echo "Current branch: $current_branch"

case $current_branch in
    main|master)
        log_warning "You're on $current_branch - consider using feature branches"
        ;;
    dev|develop|development)
        log_success "On development branch - ready for dev CI/CD"
        ;;
    test|testing)
        log_success "On test branch - ready for test CI/CD"
        ;;
    prod|production)
        log_success "On production branch - ready for production CI/CD"
        ;;
    *)
        if [[ $current_branch == feature/* ]] || [[ $current_branch == bugfix/* ]]; then
            log_success "On feature branch - ready for dev CI/CD after PR"
        else
            log_warning "Unconventional branch name: $current_branch"
        fi
        ;;
esac

echo
echo "🎯 CI/CD Pipeline Readiness"
echo "=========================="

# Determine target pipeline
if [[ $current_branch == dev* ]] || [[ $current_branch == feature/* ]] || [[ $current_branch == bugfix/* ]]; then
    echo "Target: Development Pipeline (linting, security, sanity checks)"
elif [[ $current_branch == test* ]]; then
    echo "Target: Test Pipeline (container, mock deployment, integration tests)"
elif [[ $current_branch == main ]] || [[ $current_branch == prod* ]]; then
    echo "Target: Production Pipeline (release validation, deployment dry-run)"
else
    echo "Target: Unknown - manual review required"
fi

echo
log_success "CI validation check completed!"
echo "💡 Tip: Run './scripts/local-test.sh' for comprehensive local testing"
