# BrewNix Integration Test Framework

## Overview

This integration test framework implements Phase 2.1.2 Cross-Submodule Integration Testing as specified in the BrewNix TODO.md. It provides comprehensive testing capabilities for validating inter-submodule dependencies, shared environments, contract testing, and end-to-end deployment scenarios.

## Framework Structure

```
templates/integration-tests/
├── run-integration-tests.sh          # Main orchestration script
├── config/
│   └── integration-test-config.yml   # Test configuration
├── shared-test-environments/
│   ├── setup-mock-proxmox.sh         # Docker-based Proxmox mock
│   ├── setup-mock-network.sh         # Network bridge/VLAN setup
│   └── setup-mock-storage.sh         # Mock storage (NFS/iSCSI/SMB)
├── cross-submodule-tests/
│   └── test-core-module-sync.sh      # Core module dependency tests
├── contract-tests/
│   └── test-api-contracts.sh         # API contract validation
├── e2e-deployment-tests/
│   └── test-full-deployment.sh       # End-to-end deployment tests
└── performance-regression-test.sh    # Performance regression testing
```

## Test Categories

### 1. Cross-Submodule Tests
- **Purpose**: Validate dependencies and synchronization between BrewNix submodules
- **Coverage**: Core module loading, function contracts, dependency validation
- **Location**: `cross-submodule-tests/`

### 2. Contract Tests
- **Purpose**: Ensure API contracts between submodules remain stable
- **Coverage**: Function signatures, variable contracts, exit codes, compatibility
- **Location**: `contract-tests/`

### 3. End-to-End Deployment Tests
- **Purpose**: Validate complete deployment workflows from start to finish
- **Coverage**: Configuration validation, deployment simulation, rollback procedures, monitoring
- **Location**: `e2e-deployment-tests/`

### 4. Performance Regression Tests
- **Purpose**: Detect performance degradation in core operations
- **Coverage**: Module load times, configuration validation, initialization, deployment simulation
- **Location**: `performance-regression-test.sh`

## Shared Test Environments

### Mock Proxmox Environment
- **Purpose**: Simulate Proxmox VE API for testing infrastructure interactions
- **Technology**: Docker container with Python mock server
- **Setup**: `shared-test-environments/setup-mock-proxmox.sh`

### Mock Network Environment
- **Purpose**: Create isolated network environments for testing
- **Features**: Bridge creation, VLAN setup, DHCP configuration
- **Setup**: `shared-test-environments/setup-mock-network.sh`

### Mock Storage Environment
- **Purpose**: Simulate storage services for testing
- **Protocols**: NFS, iSCSI, SMB exports
- **Setup**: `shared-test-environments/setup-mock-storage.sh`

## Usage

### Running All Integration Tests

```bash
cd templates/integration-tests
./run-integration-tests.sh
```

### Running Specific Test Categories

```bash
# Run only cross-submodule tests
./run-integration-tests.sh --category cross-submodule

# Run only contract tests
./run-integration-tests.sh --category contract

# Run only E2E deployment tests
./run-integration-tests.sh --category e2e

# Run only performance tests
./run-integration-tests.sh --category performance
```

### Running Individual Tests

```bash
# Run specific test script
./cross-submodule-tests/test-core-module-sync.sh
./contract-tests/test-api-contracts.sh
./e2e-deployment-tests/test-full-deployment.sh
./performance-regression-test.sh
```

### Setting Up Test Environments

```bash
# Setup all mock environments
./shared-test-environments/setup-mock-proxmox.sh
./shared-test-environments/setup-mock-network.sh
./shared-test-environments/setup-mock-storage.sh

# Clean up environments
./shared-test-environments/cleanup-mock-services.sh
```

## Configuration

Test behavior is controlled by `config/integration-test-config.yml`:

```yaml
# Test execution settings
test_execution:
  timeout_seconds: 300
  parallel_execution: false
  fail_fast: false

# Test categories
test_categories:
  cross_submodule: true
  contract: true
  e2e_deployment: true
  performance: true

# Environment settings
environments:
  mock_proxmox: true
  mock_network: true
  mock_storage: true

# Performance thresholds
performance_thresholds:
  max_core_module_load_time: 2.0
  max_config_validation_time: 5.0
  max_init_time: 10.0
  max_deployment_simulation_time: 30.0

# Reporting settings
reporting:
  output_format: markdown
  include_timestamps: true
  save_results: true
```

## Test Results and Reporting

### Output Formats
- **Console**: Real-time colored output with test progress
- **Markdown**: Detailed test reports with execution times and results
- **JSON**: Structured results for CI/CD integration

### Result Files
- `integration-test-results.md`: Comprehensive test report
- `performance-baseline.json`: Performance baseline data
- `performance-results.json`: Current performance measurements

### Exit Codes
- `0`: All tests passed
- `1`: One or more tests failed
- `2`: Test execution error

## Performance Baseline Management

### Creating Initial Baseline

```bash
# Run performance tests to establish baseline
./performance-regression-test.sh

# Copy results to baseline file
cp performance-results.json performance-baseline.json
```

### Updating Baseline

```bash
# After confirming performance improvements are acceptable
cp performance-results.json performance-baseline.json
```

## Prerequisites

### System Requirements
- Bash 4.0+
- Docker (for mock Proxmox environment)
- jq (for JSON processing)
- bc (for floating-point calculations)
- Network tools: ip, brctl, iptables
- Storage tools: nfs-kernel-server, open-iscsi, samba (optional)

### BrewNix Dependencies
- Core modules: `scripts/core/config.sh`, `scripts/core/logging.sh`, `scripts/core/init.sh`
- Deployment scripts: `scripts/deployment/deployment.sh`
- Configuration files: `config/site-example.yml`

## Troubleshooting

### Common Issues

1. **Permission Denied**
   ```bash
   # Make scripts executable
   chmod +x *.sh */*.sh
   ```

2. **Docker Not Available**
   ```bash
   # Install Docker or disable mock Proxmox tests
   sudo apt-get install docker.io
   ```

3. **Network Setup Fails**
   ```bash
   # Run with sudo for network operations
   sudo ./shared-test-environments/setup-mock-network.sh
   ```

4. **Missing Dependencies**
   ```bash
   # Install required packages
   sudo apt-get install jq bc bridge-utils iptables
   ```

### Debug Mode

Enable verbose logging by setting the environment variable:

```bash
export BREWNIX_DEBUG=true
./run-integration-tests.sh
```

## Integration with CI/CD

The framework is designed to integrate with BrewNix CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Run Integration Tests
  run: |
    cd templates/integration-tests
    ./run-integration-tests.sh

- name: Upload Test Results
  uses: actions/upload-artifact@v2
  with:
    name: integration-test-results
    path: templates/integration-tests/integration-test-results.md
```

## Contributing

When adding new tests:

1. Follow the existing naming convention: `test-*.sh`
2. Include proper error handling and logging
3. Add configuration options to `integration-test-config.yml`
4. Update this README with test documentation
5. Ensure tests are executable and follow Bash best practices

## Phase 2.1.2 Completion Criteria

This framework fulfills the following Phase 2.1.2 requirements:

- ✅ **Cross-submodule dependency testing**: Validates core module synchronization
- ✅ **Shared test environments**: Mock Proxmox, network, and storage environments
- ✅ **Contract testing**: API contract validation between submodules
- ✅ **End-to-end deployment testing**: Complete deployment workflow validation
- ✅ **Performance regression testing**: Automated performance monitoring
- ✅ **Comprehensive reporting**: Detailed test results and performance metrics
- ✅ **CI/CD integration**: Framework designed for automated testing pipelines
