# BrewNix - Modular Network Infrastructure Management

BrewNix is a modular, GitOps-driven network infrastructure management system designed to replace monolithic deployment scripts with a clean, maintainable architecture.

## Architecture Overview

The system has been refactored from a single 2867-line monolithic script into a modular architecture with the following components:

### Core Modules (`scripts/core/`)
- **`init.sh`** - Environment initialization and prerequisite validation
- **`config.sh`** - Configuration management and YAML parsing
- **`logging.sh`** - Centralized logging with multiple output formats

### Feature Modules

#### Backup Module (`scripts/backup/`)
- Local and cloud backup operations
- Proxmox and OPNsense configuration backups
- Automated backup retention and cleanup

#### OPNsense Module (`scripts/opnsense/`) - **Phase 3 Implementation**
- Complete firewall management via REST API
- Rule and alias management
- Interface configuration
- System status monitoring

#### Monitoring Module (`scripts/monitoring/`)
- Health checks for all infrastructure components
- Automated alerting via email
- System resource monitoring
- Comprehensive reporting

#### GitOps Module (`scripts/gitops/`)
- Repository synchronization
- Configuration drift detection
- Automated webhook handling
- Push/pull operations

#### Deployment Module (`scripts/deployment/`)
- Network configuration deployment
- Device management
- Ansible playbook orchestration
- Validation and rollback capabilities

#### Utilities Module (`scripts/utilities/`)
- USB bootstrap creation
- Testing framework
- Configuration validation
- Dependency checking

## Quick Start

### Prerequisites
```bash
# Required tools
sudo apt-get install ansible git python3 curl jq

# Optional tools
sudo apt-get install docker docker-compose terraform pvesh
```

### Basic Usage
```bash
# Make script executable
chmod +x brewnix.sh

# Show help
./brewnix.sh --help

# Validate configuration
./brewnix.sh validate

# Check system health
./brewnix.sh monitoring check

# Backup current configuration
./brewnix.sh backup create my_backup
```

## Module Usage

### OPNsense Management (Phase 3)
```bash
# List firewall rules
./brewnix.sh opnsense rules list

# Create a new firewall rule
./brewnix.sh opnsense rules create lan wan pass "Allow HTTP" "source=192.168.1.0/24" "destination=any" "destination_port=80"

# Get system status
./brewnix.sh opnsense status

# Apply configuration changes
./brewnix.sh opnsense apply
```

### Backup Operations
```bash
# Create backup
./brewnix.sh backup create my_backup

# List available backups
./brewnix.sh backup list

# Restore from backup
./brewnix.sh backup restore /path/to/backup.tar.gz

# Backup Proxmox configuration
./brewnix.sh backup proxmox pve.example.com

# Clean up old backups
./brewnix.sh backup cleanup 30
```

### Monitoring
```bash
# Run health check
./brewnix.sh monitoring check

# Generate monitoring report
./brewnix.sh monitoring report

# Start monitoring daemon
./brewnix.sh monitoring start

# Stop monitoring daemon
./brewnix.sh monitoring stop
```

### GitOps Operations
```bash
# Sync repository
./brewnix.sh gitops sync

# Check for configuration drift
./brewnix.sh gitops drift

# Push local changes
./brewnix.sh gitops push "Configuration update"

# Pull and apply changes
./brewnix.sh gitops pull
```

### Deployment
```bash
# Deploy network configuration
./brewnix.sh deployment network site1

# Deploy devices
./brewnix.sh deployment devices site1

# Deploy complete site
./brewnix.sh deployment site site1

# Validate deployment
./brewnix.sh deployment validate site1
```

### Utilities
```bash
# Run tests
./brewnix.sh test run all

# Validate configuration
./brewnix.sh validate

# Check dependencies
./brewnix.sh deps

# Generate documentation
./brewnix.sh docs
```

## Configuration

### Main Configuration (`config.yml`)
```yaml
network:
  prefix: "10.0.0.0/8"
  dns_servers:
    - "8.8.8.8"
    - "1.1.1.1"

sites:
  site1:
    proxmox:
      hosts:
        - "pve01.example.com"
      api_key: "your-api-key"
    opnsense:
      hosts:
        - "fw01.example.com"
      api_key: "your-api-key"
      api_secret: "your-api-secret"

gitops:
  repo_url: "https://github.com/yourorg/brewnix-config"
  branch: "main"
  ssh_key: "/path/to/ssh/key"

monitoring:
  alert_email: "admin@example.com"
  interval: 300
```

### OPNsense Configuration
```yaml
opnsense:
  host: "fw01.example.com"
  api_key: "your-api-key"
  api_secret: "your-api-secret"
  api_url: "https://fw01.example.com/api"
```

## Environment Variables

- `VERBOSE=true` - Enable verbose output
- `DRY_RUN=true` - Enable dry-run mode
- `LOG_LEVEL=DEBUG|INFO|WARN|ERROR` - Set logging level
- `LOG_FILE=/path/to/log` - Custom log file location

## Development

### Adding New Modules
1. Create module directory under `scripts/`
2. Implement main function following the pattern: `module_main()`
3. Add initialization function: `init_module()`
4. Update `brewnix.sh` to source and route to the new module

### Module Structure
```bash
scripts/
├── core/
│   ├── init.sh
│   ├── config.sh
│   └── logging.sh
└── your_module/
    └── your_module.sh
```

### Coding Standards
- Use bash strict mode: `set -euo pipefail`
- Declare and assign variables separately to avoid masking return values
- Use proper error handling with `|| return 1`
- Follow the existing logging patterns
- Include comprehensive help text

## Migration from Monolithic Script

The old `deploy-gitops.sh` script has been replaced by this modular architecture. Key improvements:

1. **Separation of Concerns** - Each module handles a specific responsibility
2. **Maintainability** - Easier to modify and extend individual components
3. **Testability** - Modules can be tested independently
4. **Reusability** - Core functions are shared across modules
5. **Scalability** - New features can be added without affecting existing code

### Migration Steps
1. Update any existing automation to use the new command structure
2. Migrate custom configurations to the new format
3. Test each module independently before full deployment
4. Update documentation and training materials

## Troubleshooting

### Common Issues

1. **Module not found**
   ```bash
   # Ensure all modules are sourced in brewnix.sh
   ls -la scripts/
   ```

2. **Configuration errors**
   ```bash
   # Validate configuration
   ./brewnix.sh validate
   ```

3. **Permission issues**
   ```bash
   # Check script permissions
   chmod +x brewnix.sh
   chmod +x scripts/**/*.sh
   ```

4. **Dependency issues**
   ```bash
   # Check system dependencies
   ./brewnix.sh deps
   ```

### Logs and Debugging
```bash
# Enable verbose logging
VERBOSE=true ./brewnix.sh <module> <command>

# Check log files
tail -f build/brewnix.log

# Enable debug logging
LOG_LEVEL=DEBUG ./brewnix.sh <module> <command>
```

## Contributing

1. Follow the established coding standards
2. Add comprehensive tests for new features
3. Update documentation for any changes
4. Ensure backward compatibility where possible
5. Test across different environments

## License

This project is licensed under the terms specified in the LICENSE file.
