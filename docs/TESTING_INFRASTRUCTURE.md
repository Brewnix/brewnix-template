# BrewNix Testing Infrastructure

This document describes the comprehensive testing infrastructure implemented for BrewNix submodules, providing multi-branch CI/CD pipelines and local debugging capabilities.

## Overview

The testing infrastructure consists of three main components:

1. **Multi-Branch CI/CD Pipelines** - Automated testing across dev → test → production branches
2. **Local Debugging Scripts** - Duplicate CI/CD checks for pre-submission validation
3. **Testing Templates** - Reusable workflow templates for all BrewNix submodules

## CI/CD Pipeline Structure

### Development Branch (`dev`, `develop`, `development`)

**Workflow**: `templates/workflows/ci.yml`

- **Linting**: Shell script syntax checking, YAML validation, markdown linting
- **Security**: Vulnerability scanning, secrets detection, file permission checks
- **Sanity**: Required files validation, directory structure checks
- **Documentation**: Markdown validation, changelog verification
- **Dependencies**: External tool dependency analysis

### Test Branch (`test`, `testing`)

**Workflow**: `templates/workflows/test.yml`

- **Container Testing**: Docker build validation, container environment testing
- **Mock Deployment**: Configuration validation, deployment simulation
- **Integration Testing**: Core module integration, script dependency validation
- **Test Reporting**: Comprehensive test results with artifact uploads

### Production Branch (`main`, `production`, `release`)

**Workflow**: `templates/workflows/production.yml`

- **Release Validation**: Version tagging, changelog verification
- **Security Scan**: Production-ready security checks
- **Deployment Dry Run**: Production deployment simulation
- **Release Notes**: Automated release note generation
- **GitHub Release**: Automated release creation (when pushed to main)

## Local Debugging Scripts

### Comprehensive Testing (`scripts/local-test.sh`)

Duplicate all CI/CD checks for local development:

```bash
# Run comprehensive local testing
./scripts/local-test.sh
```

**Features**:

- All CI/CD validations (linting, security, sanity, docs, dependencies)
- Container testing and mock deployments
- Integration and performance testing
- Colored output with clear success/warning/error indicators
- Non-destructive testing (no actual deployments)

### Quick CI Check (`scripts/ci-check.sh`)

Fast validation before pushing to CI/CD:

```bash
# Quick validation check
./scripts/ci-check.sh
```

**Features**:

- Syntax validation for shell scripts and YAML
- Large file detection
- Git status and branch validation
- CI/CD pipeline target identification
- Fast execution for pre-commit checks

## Usage Guide

### For Developers

1. **Before starting work**:

   ```bash
   ./scripts/ci-check.sh  # Quick validation
   ```

2. **During development**:

   ```bash
   ./scripts/local-test.sh  # Comprehensive testing
   ```

3. **Before submitting PR**:

   ```bash
   ./scripts/local-test.sh  # Full validation
   git push origin feature/your-branch
   ```

### Branch Workflow

```bash
feature/your-feature
    ↓ (PR to dev)
dev branch
    ↓ (after testing)
test branch
    ↓ (after validation)
main/production
```

### Pipeline Triggers

- **Dev Branch**: Push/PR to `dev`, `develop`, `development`
- **Test Branch**: Push/PR to `test`, `testing`
- **Production**: Push/PR to `main`, `production`, `release`

## Testing Infrastructure Features

### Container Testing

- Dockerfile validation and build testing
- Container environment verification
- Basic test container creation if none exists

### Mock Deployments

- Configuration validation using `validate-config.sh`
- Deployment script testing
- Environment simulation without actual infrastructure

### Security Scanning

- Secrets detection in code
- File permission validation
- Security documentation checks

### Performance Monitoring

- Script execution time measurement
- Resource usage tracking
- Timeout handling for long-running tests

### Integration Testing

- Core module dependency validation
- Script integration verification
- Module loading tests

## Required Tools

### For Full Local Testing

- `shellcheck` - Shell script linting
- `yamllint` - YAML validation
- `markdownlint` - Markdown validation
- `docker` - Container testing
- `python3` - YAML parsing validation

### For Basic CI Checks

- `bash` - Shell script execution
- `git` - Repository operations
- `find` - File system operations

## Installation

### Local Testing Dependencies

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install shellcheck yamllint python3-pip docker.io

# Install markdownlint
npm install -g markdownlint-cli

# Or using pip for yamllint
pip3 install yamllint
```

### Making Scripts Executable

```bash
chmod +x scripts/local-test.sh
chmod +x scripts/ci-check.sh
```

## Customization

### Adding New Tests

Edit `scripts/local-test.sh` to add custom validation functions:

```bash
# Add custom test function
run_custom_checks() {
    log_info "Running custom checks..."
    # Your custom validation logic
    log_success "Custom checks completed"
}

# Call in main function
run_custom_checks
```

### Modifying CI/CD Pipelines

Edit the workflow templates in `templates/workflows/`:

- `ci.yml` - Development branch validations
- `test.yml` - Integration and deployment testing
- `production.yml` - Release and production validation

### Branch Configuration

Update branch names in workflow triggers as needed:

```yaml
on:
  push:
    branches: [ your-dev-branch, your-test-branch ]
  pull_request:
    branches: [ your-dev-branch, your-test-branch ]
```

## Troubleshooting

### Common Issues

1. **Permission Denied**

   ```bash
   chmod +x scripts/*.sh
   ```

2. **Missing Dependencies**

   ```bash
   ./scripts/ci-check.sh  # Will show what's missing
   ```

3. **YAML Syntax Errors**

   - Use online YAML validators
   - Check indentation (spaces, not tabs)
   - Validate with `yamllint`

4. **Docker Issues**

   - Ensure Docker daemon is running
   - Check user permissions for Docker
   - Use `docker build --dry-run` for syntax testing

### Debug Mode

Run scripts with verbose output:

```bash
bash -x scripts/local-test.sh
```

## Integration with BrewNix

This testing infrastructure is designed to work seamlessly with BrewNix submodules:

- **Submodule Structure**: Tests run from submodule root
- **Shared Scripts**: Common validation scripts in `scripts/core/`
- **Configuration**: Site-specific configs in `config/`
- **Documentation**: Module docs in `docs/`

## Contributing

When adding new tests or modifying the infrastructure:

1. Update this README with new features
2. Test locally using `./scripts/local-test.sh`
3. Ensure CI/CD pipelines still pass
4. Update branch naming if changed
5. Document any new dependencies

## Support

For issues with the testing infrastructure:

1. Check this README for common solutions
2. Run `./scripts/ci-check.sh` for quick diagnostics
3. Review CI/CD pipeline logs for detailed errors
4. Check file permissions and dependencies
