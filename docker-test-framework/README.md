# Brewnix Template - Docker Test Framework

## Overview

This Docker-based test framework provides comprehensive testing for the Brewnix Template universal infrastructure deployment system. It validates deployment scripts, configuration files, USB image creation, and container builds across all vendor types.

## Architecture

The test framework consists of several containerized services:

- **Proxmox Mock**: Simulates Proxmox VE API for testing deployment scripts
- **Test Runner**: Executes Python-based integration tests using pytest
- **Network Simulator**: Provides network topology simulation for testing
- **Config Validator**: Validates YAML configurations and Ansible playbooks
- **USB Mock**: Simulates USB device creation and validation
- **Log Collector**: Aggregates logs from all test services

## Quick Start

### Prerequisites

- Docker and Docker Compose
- At least 4GB available RAM
- 10GB available disk space

### Running Tests

1. **Full Test Suite** (recommended for CI/CD):
```bash
./run-comprehensive-tests.sh
```

2. **Unit Tests Only** (fast validation):
```bash
./run-comprehensive-tests.sh --unit-only
```

3. **Integration Tests Only**:
```bash
./run-comprehensive-tests.sh --integration-only
```

4. **Deployment Tests Only**:
```bash
./run-comprehensive-tests.sh --deployment-only
```

### Using Docker Compose Directly

```bash
# Start all test services
docker-compose up -d

# Run integration tests
docker-compose exec test-runner python3 test_integration.py

# View logs
docker-compose logs

# Cleanup
docker-compose down
```

## Test Categories

### Unit Tests
- Deployment script functionality validation
- YAML syntax checking for all configuration files
- Vendor type validation and error handling
- Ansible configuration verification
- Common framework role accessibility

### Integration Tests
- Proxmox API mock service connectivity
- Docker Compose configuration validation
- Network configuration testing
- Cross-vendor compatibility verification
- Service health checks and dependency validation

### Deployment Tests
- Dry-run execution of all vendor deployments
- USB bootstrap script validation
- Container and VM build verification
- Network topology validation
- Security configuration testing

## Configuration

### Environment Variables

- `TEST_VERBOSE`: Enable verbose output (default: false)
- `PROXMOX_API_URL`: Proxmox mock API URL (default: http://proxmox-mock:8006)
- `TEST_MODE`: Test execution mode (default: comprehensive)
- `CLEANUP_AFTER`: Cleanup containers after tests (default: true)

### Test Options

```bash
# Command line options for run-comprehensive-tests.sh
--unit-only         # Run only unit tests
--integration-only  # Run only integration tests
--deployment-only   # Run only deployment tests
--no-cleanup        # Don't cleanup Docker containers after tests
--parallel          # Run tests in parallel where possible
-v, --verbose       # Verbose output
-h, --help          # Show help
```

## Test Results

### Output Locations

- **Test Results**: `./test-results/` directory
- **Logs**: `./logs/` directory
- **Reports**: `./reports/` directory
- **JUnit XML**: `./test-results/integration-test-results.xml`
- **HTML Report**: `./test-results/integration-test-report.html`

### JSON Summary Report

Each test run generates a JSON summary:

```json
{
  "timestamp": "2024-01-01T12:00:00Z",
  "overall_success": true,
  "test_results": {
    "unit_tests": {
      "enabled": true,
      "result": "✓ PASSED (45s)"
    },
    "integration_tests": {
      "enabled": true,
      "result": "✓ PASSED (120s)"
    },
    "deployment_tests": {
      "enabled": true,
      "result": "✓ PASSED (180s)"
    }
  },
  "configuration": {
    "verbose": false,
    "parallel": false,
    "cleanup": true
  }
}
```

## Mock Services

### Proxmox Mock API

The Proxmox mock service provides realistic API responses for testing:

- **Endpoints**: `/api2/json/*` - Standard Proxmox API endpoints
- **Health Check**: `/health` - Service health status
- **Data**: Dynamic mock data for nodes, VMs, containers, storage

### Test Data

Mock data includes:
- 3 cluster nodes (pve1, pve2, pve3)
- Random VM and container distributions
- Realistic resource usage metrics
- Network configurations matching test scenarios

## Integration with CI/CD

### GitHub Actions Integration

The test framework integrates with the project's GitHub Actions workflows:

```yaml
# In .github/workflows/test.yml
- name: Run Comprehensive Tests
  run: |
    cd docker-test-framework
    ./run-comprehensive-tests.sh --verbose
```

### Exit Codes

- `0`: All tests passed
- `1`: One or more tests failed
- `2`: Prerequisites not met
- `3`: Configuration error

## Development

### Adding New Tests

1. **Unit Tests**: Add test functions to `run-comprehensive-tests.sh`
2. **Integration Tests**: Add test classes to `test_integration.py`
3. **Mock Data**: Extend `proxmox-mock/mock_data.py`

### Mock Service Development

```bash
# Rebuild mock services
docker-compose build proxmox-mock

# Test mock service directly
curl http://localhost:8006/api2/json/version
```

### Test Data Customization

Modify `./data/` directory contents to customize test scenarios:
- Site configurations
- Network topologies
- Expected deployment outcomes

## Troubleshooting

### Common Issues

1. **Port Conflicts**: Ensure ports 8006, 5432, 3001 are available
2. **Docker Permissions**: User must be in `docker` group
3. **Memory Issues**: Increase Docker memory allocation to 4GB+
4. **Network Issues**: Check Docker bridge networking

### Debug Mode

```bash
# Enable debug logging
DEBUG=true ./run-comprehensive-tests.sh --verbose

# Check container logs
docker-compose logs proxmox-mock
docker-compose logs test-runner
```

### Manual Testing

```bash
# Connect to test runner for manual testing
docker-compose exec test-runner /bin/bash

# Run specific test modules
python3 -m pytest test_integration.py::TestProxmoxIntegration -v
```

## Performance

### Execution Times

- **Unit Tests**: ~30-60 seconds
- **Integration Tests**: ~60-120 seconds  
- **Deployment Tests**: ~120-300 seconds
- **Full Suite**: ~5-8 minutes

### Optimization

- Use `--unit-only` for fast validation during development
- Use `--parallel` for faster execution on multi-core systems
- Cache Docker images to reduce startup time

## Security

### Test Isolation

- All tests run in isolated Docker containers
- No access to host file system except mounted volumes
- Network isolation between test services
- Automatic cleanup of test artifacts

### Sensitive Data

- No production credentials required
- Mock services use fake authentication
- All test data is synthetic and safe for CI/CD

## Contributing

### Test Framework Updates

1. Update mock services for new vendor types
2. Add integration tests for new features
3. Extend deployment validation for new configurations
4. Update documentation for new test categories

### Code Quality

- All shell scripts must pass ShellCheck
- Python code follows PEP8 standards
- Docker images use security best practices
- Test coverage reports generated automatically
