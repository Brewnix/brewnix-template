# Brewnix GitOps Implementation Guide

This guide provides a comprehensive roadmap for implementing GitOps for your Brewnix infrastructure across multiple server models, including the new duplication strategy for maintaining core module consistency.

## Table of Contents

1. [Repository Setup](#repository-setup)
2. [Bootstrap Process](#bootstrap-process)
3. [Duplication Strategy](#duplication-strategy)
4. [Site Configuration](#site-configuration)
5. [Deployment Workflow](#deployment-workflow)
6. [State Management](#state-management)
7. [Security Implementation](#security-implementation)
8. [Monitoring and Maintenance](#monitoring-and-maintenance)

## Repository Setup

### 1. Create Template Repository

```bash
# Clone this template
git clone https://github.com/yourorg/brewnix-template.git your-network-deployment
cd your-firewall-deployment

# Initialize submodules
git submodule update --init --recursive

# Setup git-crypt for secrets
git-crypt init
git-crypt add-gpg-user YOUR_GPG_KEY_ID
```

### 2. Repository Structure

```text
your-network-deployment/
├── sites/                          # Site-specific configurations
│   ├── production/                 # Production site
│   └── staging/                    # Staging site
├── bootstrap/                      # Initial setup scripts
├── scripts/                        # Management scripts
│   ├── core/                       # Core infrastructure modules
│   │   ├── init.sh                 # Initialization functions
│   │   ├── config.sh               # Configuration management
│   │   └── logging.sh              # Logging framework
│   └── utilities/                  # Utility scripts
│       └── duplicate-core.sh       # Core duplication script
├── templates/                      # Template infrastructure
│   ├── submodule-core/             # Core module templates
│   └── workflows/                  # CI/CD workflow templates
├── vendor/                         # Server model submodules
│   ├── proxmox-firewall/
│   ├── proxmox-nas/
│   └── k3s-cluster/
├── .github/workflows/             # GitHub Actions
├── docs/                          # Documentation
└── config/                        # Global configuration
```

## Bootstrap Process

### Phase 1: USB Bootstrap

1. **Create Bootstrap USB**:

   ```bash
   # On development machine
   ./bootstrap/create-bootstrap-usb.sh
   ```

2. **Boot Target System**:
   - Boot from USB drive
   - Run: `./bootstrap/usb-bootstrap.sh`

3. **Initial Setup**:

   ```bash
   # On target system
   ./bootstrap/initial-config.sh
   ```

### Phase 2: GitHub Connectivity

1. **Add SSH Key to GitHub**:
   - Copy SSH public key displayed during bootstrap
   - Add as deploy key to your repository

2. **Connect to Repository**:

   ```bash
   # On target system
   ./bootstrap/github-connect.sh
   ```

3. **Verify Connection**:

   ```bash
   cd /opt/brewnix-deployment
   git status
   ```

## Duplication Strategy

### Overview

The Brewnix duplication strategy ensures consistent core infrastructure across all submodules while allowing for independent development and deployment. This strategy includes:

- **Core Module Synchronization**: Automated sync of init.sh, config.sh, and logging.sh
- **CI/CD Workflow Templates**: Standardized testing and deployment pipelines
- **Synchronization Tools**: Scripts for maintaining core module updates
- **Path Resolution**: Context-aware logging and configuration management

### Core Module Architecture

#### Core Modules

- **init.sh**: Common initialization functions and environment setup
- **config.sh**: Configuration management and validation
- **logging.sh**: Centralized logging framework with path resolution

#### Synchronization Process

```bash
# Duplicate core infrastructure to all submodules
./scripts/utilities/duplicate-core.sh vendor/proxmox-firewall
./scripts/utilities/duplicate-core.sh vendor/proxmox-nas
./scripts/utilities/duplicate-core.sh vendor/k3s-cluster

# Sync core modules from template (run from submodule)
cd vendor/proxmox-firewall
./tools/update-core.sh
```

#### CI/CD Workflow Templates

The duplication strategy includes standardized CI/CD workflows:

- **ci.yml**: Basic continuous integration with linting and validation
- **test.yml**: Comprehensive test execution with coverage reporting
- **validate.yml**: Configuration validation and security checks

### Maintenance Workflow

1. **Update Core Modules**: Modify core modules in `scripts/core/`
2. **Test Changes**: Run tests in template environment
3. **Sync to Submodules**: Use duplication script to propagate changes
4. **Verify Deployment**: Run validation in each submodule
5. **Update Documentation**: Reflect changes in submodule-specific docs

## Site Configuration

### 1. Create Site Structure

```bash
# Copy template site
cp -r sites/site1 sites/production

# Edit site configuration
vim sites/production/config/site.conf
```

### 2. Configure Site Variables

```bash
# sites/production/config/site.conf
SITE_NAME="production"
SITE_DISPLAY_NAME="Production Network"
NETWORK_PREFIX="10.1"
DOMAIN="home.local"
PROXMOX_HOST="10.1.50.1"
```

### 3. Setup Secrets

```bash
# Create secrets directory
mkdir -p sites/production/secrets

# Add encrypted secrets
echo "your-secret-value" > sites/production/secrets/api_key.txt

# Commit encrypted secrets
git add .
git commit -m "Add production secrets"
```

### 4. Configure Terraform

```bash
# sites/production/terraform/main.tf (symlink to submodule)
ln -s ../../../vendor/proxmox-firewall/terraform/main.tf .

# sites/production/config/terraform.tfvars
proxmox_host = "10.1.50.1"
site_name = "production"
network_prefix = "10.1"
```

## Deployment Workflow

### Manual Deployment

```bash
# Deploy single site
./scripts/deploy-site.sh production

# Deploy with options
./scripts/deploy-site.sh production --staging --dry-run

# Deploy all sites
./scripts/deploy-all-sites.sh
```

### Automated Deployment via GitHub Actions

#### Setup GitHub Secrets

```text
STAGING_SSH_PRIVATE_KEY     # SSH key for staging
PRODUCTION_SSH_PRIVATE_KEY  # SSH key for production
STAGING_PROXMOX_HOST        # Staging Proxmox IP
PRODUCTION_PROXMOX_HOST     # Production Proxmox IP
SLACK_WEBHOOK_URL           # For notifications
```

#### Deployment Triggers

- **Push to main**: Production deployment
- **Push to staging**: Staging deployment
- **Pull Request**: Validation only
- **Manual**: Via GitHub Actions dispatch

#### Deployment Process

1. **Validation**: Lint, test, plan
2. **Backup**: State backup before changes
3. **Deploy**: Apply infrastructure changes
4. **Verify**: Post-deployment tests
5. **Notify**: Success/failure notifications

## State Management

### Terraform State Strategy

- **Local**: Git-tracked in repository
- **Backup**: Daily automated backups
- **Recovery**: From git history or releases

### Backup Process

```bash
# Manual backup
./scripts/backup-state.sh production

# Automated backup (runs daily)
# Configured in /etc/cron.d/brewnix-backups
```

### State Recovery

```bash
# From git history
git checkout <commit-sha>
terraform init
terraform apply

# From backup
./scripts/restore-state.sh production <backup-file>
```

## Security Implementation

### SSH Key Management

```bash
# Generate site-specific keys
ssh-keygen -t ed25519 -C "production@brewnix" \
    -f sites/production/ssh/deploy_key

# Add to Proxmox host
ssh-copy-id -i sites/production/ssh/deploy_key.pub root@10.1.50.1
```

### Secrets Encryption

```bash
# Using git-crypt
echo "secrets/" >> .gitattributes
git-crypt status
git-crypt add-gpg-user user@domain.com

# Using age
age-keygen -o sites/production/secrets/key.txt
echo "secret-value" | age -r $(cat sites/production/secrets/key.txt | grep public | cut -d' ' -f4) > secret.enc
```

### Access Control

- **GitHub**: Branch protection, required reviews
- **SSH**: Key-based authentication only
- **API**: Token-based with minimal permissions
- **Monitoring**: Audit all access and changes

## Monitoring and Maintenance

### Automated Monitoring

```bash
# System health checks
*/5 * * * * root /opt/brewnix/scripts/health-check.sh

# Configuration drift detection
0 */6 * * * root /opt/brewnix/scripts/drift-check.sh

# Backup verification
0 3 * * * root /opt/brewnix/scripts/verify-backups.sh
```

### Log Management

```bash
# Centralized logging
/var/log/brewnix/
├── deployment.log          # Deployment logs
├── ansible.log            # Ansible execution logs
├── terraform.log          # Terraform logs
└── health.log             # System health logs
```

### Update Process

```bash
# Update main codebase
git submodule update --remote vendor/proxmox-firewall

# Test updates on staging
./scripts/deploy-site.sh staging

# Deploy to production
./scripts/deploy-site.sh production
```

## Troubleshooting

### Common Issues

#### Bootstrap Problems

```bash
# Check USB creation
lsblk  # Verify USB device
df -h /mnt/boot  # Check mount

# Verify network
ping 8.8.8.8
curl -I https://github.com
```

#### GitHub Connection Issues

```bash
# Test SSH
ssh -T git@github.com

# Check deploy key
cat ~/.ssh/id_ed25519.pub

# Verify repository access
git ls-remote origin
```

#### Deployment Failures

```bash
# Check logs
tail -f /var/log/brewnix/deployment.log

# Ansible connectivity
ansible -m ping production

# Terraform state
cd sites/production/terraform
terraform state list
```

### Recovery Procedures

#### System Recovery Fixes

1. Bootstrap with USB
2. Connect to GitHub
3. Restore from latest backup
4. Re-deploy configuration

#### State Recovery Fixes

1. Identify backup point
2. Restore state files
3. Re-initialize Terraform
4. Apply configuration

## Best Practices

### Development Workflow

1. **Branch**: Create feature branches
2. **Test**: Deploy to staging first
3. **Review**: Pull request for changes
4. **Deploy**: Automated production deployment

### Security Practices

1. **Rotate Keys**: Regularly rotate SSH keys
2. **Audit Logs**: Monitor all access
3. **Backup**: Regular state backups
4. **Updates**: Keep systems updated

### Operational Excellence

1. **Documentation**: Keep configs documented
2. **Automation**: Automate everything possible
3. **Monitoring**: Monitor system health
4. **Testing**: Test changes before production

## Migration from Existing Setup

### Phase 1: Assessment

- Inventory current infrastructure
- Document existing configurations
- Identify manual processes to automate

### Phase 2: Preparation

- Setup GitOps repository structure
- Migrate configurations to new format
- Test bootstrap process

### Phase 3: Migration

- Deploy GitOps on staging environment
- Migrate one site at a time
- Validate functionality after each migration

### Phase 4: Optimization

- Implement automated monitoring
- Setup backup procedures
- Train team on GitOps processes

## Support and Resources

### Documentation

- [State Management Guide](./STATE_MANAGEMENT.md)
- [Security Guidelines](./SECURITY.md)
- [Troubleshooting Guide](./TROUBLESHOOTING.md)
- [Duplication Analysis](./TASK3_DUPLICATION_ANALYSIS.md)

### Tools and Scripts

- `scripts/core/` - Core infrastructure modules
- `scripts/utilities/duplicate-core.sh` - Core duplication script
- `templates/submodule-core/` - Core module templates
- `templates/workflows/` - CI/CD workflow templates
- `bootstrap/` - Initial setup scripts
- `.github/workflows/` - CI/CD pipelines

### Community Resources

- [Proxmox Documentation](https://pve.proxmox.com/wiki/Main_Page)
- [Terraform Documentation](https://www.terraform.io/docs)
- [Ansible Documentation](https://docs.ansible.com)

---

This implementation provides a complete GitOps solution for managing Proxmox Firewall infrastructure with automated deployments, comprehensive state management, robust security practices, and a sophisticated duplication strategy for maintaining core module consistency across multiple server models.
