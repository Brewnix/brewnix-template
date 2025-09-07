# Brewnix Template - Docker Test Framework Quick Start

## 🚀 Ready to Use!

The Docker test framework is now complete and ready for comprehensive testing of your Brewnix Template infrastructure deployments.

## 📋 What's Been Implemented

### ✅ Comprehensive Test Runner
- **File**: `run-comprehensive-tests.sh`
- **Features**: Unit, integration, and deployment testing with colorful output
- **Usage**: `./run-comprehensive-tests.sh [options]`

### ✅ Docker Test Infrastructure
- **Proxmox Mock API**: Realistic Proxmox VE API simulation
- **Test Runner Container**: Python-based integration testing with pytest
- **Network Simulation**: Container networking for topology testing
- **USB Device Mock**: Simulates USB image creation and validation

### ✅ GitHub Actions Integration
- **Development Workflow** (`.github/workflows/dev.yml`): 
  - Shell linting with ShellCheck
  - YAML validation with yamllint
  - Ansible linting with ansible-lint
  - Terraform validation with tfsec
  - Markdown linting with markdownlint
  - Security scanning with Bandit

- **Test Workflow** (`.github/workflows/test.yml`):
  - Deployment script testing
  - Ansible role validation
  - Container build verification
  - **NEW**: Comprehensive Docker test framework execution

## 🎯 Quick Test Commands

### Run All Tests
```bash
cd docker-test-framework
./run-comprehensive-tests.sh
```

### Fast Development Testing
```bash
./run-comprehensive-tests.sh --unit-only
```

### Integration Testing Only
```bash
./run-comprehensive-tests.sh --integration-only
```

### Deployment Validation Only
```bash
./run-comprehensive-tests.sh --deployment-only
```

### Verbose Output for Debugging
```bash
./run-comprehensive-tests.sh --verbose
```

## 📊 Test Results

Tests generate comprehensive reports in:
- **JSON Summary**: `reports/test-report-*.json`
- **JUnit XML**: `test-results/integration-test-results.xml`
- **HTML Report**: `test-results/integration-test-report.html`
- **Logs**: `logs/` directory

## 🐳 Docker Services

### Start Services Manually
```bash
docker-compose up -d
```

### View Service Status
```bash
docker-compose ps
```

### Check Logs
```bash
docker-compose logs proxmox-mock
docker-compose logs test-runner
```

### Access Mock Proxmox API
```bash
curl http://localhost:8006/api2/json/version
curl http://localhost:8006/health
```

## 🔍 What Gets Tested

### Unit Tests (30-60 seconds)
- ✅ Deployment script functionality
- ✅ YAML syntax validation for all configs
- ✅ Vendor type validation and error handling
- ✅ Ansible configuration verification
- ✅ Common framework role accessibility

### Integration Tests (60-120 seconds)
- ✅ Proxmox API mock connectivity
- ✅ Docker Compose configuration validation
- ✅ Network configuration testing
- ✅ Cross-vendor compatibility
- ✅ Service health checks

### Deployment Tests (120-300 seconds)
- ✅ Dry-run execution of all vendor deployments
- ✅ USB bootstrap script validation
- ✅ Container and VM build verification
- ✅ Network topology validation

## 🛠 Development Workflow

1. **Make changes** to your Brewnix Template code
2. **Run unit tests** for fast feedback: `./run-comprehensive-tests.sh --unit-only`
3. **Run integration tests** to validate interactions: `./run-comprehensive-tests.sh --integration-only`
4. **Run full suite** before committing: `./run-comprehensive-tests.sh`
5. **Push to GitHub** - CI/CD automatically runs all tests

## 🎉 Ready for Production!

Your Brewnix Template now has:

- ✅ **Multi-language linting** (Shell, YAML, Ansible, Terraform, Markdown)
- ✅ **Comprehensive testing** (Unit, Integration, Deployment)
- ✅ **Docker-based validation** (USB images, container builds, network topology)
- ✅ **CI/CD integration** (GitHub Actions workflows)
- ✅ **Cross-vendor compatibility** (NAS, K3S, Development, Security)
- ✅ **Production-ready reports** (JSON, XML, HTML, Logs)

## 🔗 Next Steps

1. **Test your first deployment**:
   ```bash
   ./run-comprehensive-tests.sh --deployment-only
   ```

2. **Customize test scenarios** by modifying:
   - `docker-test-framework/data/` - Test data
   - `docker-test-framework/test_integration.py` - Python tests
   - `docker-test-framework/run-comprehensive-tests.sh` - Shell tests

3. **Add new vendor types** by extending:
   - Mock data in `proxmox-mock/mock_data.py`
   - Test cases in `test_integration.py`
   - Validation logic in `run-comprehensive-tests.sh`

## 🆘 Need Help?

- **View documentation**: `docker-test-framework/README.md`
- **Check logs**: `docker-test-framework/logs/`
- **Run with verbose**: `--verbose` flag
- **Debug manually**: `docker-compose exec test-runner /bin/bash`

**The Brewnix Template is now production-ready with comprehensive testing! 🎊**
