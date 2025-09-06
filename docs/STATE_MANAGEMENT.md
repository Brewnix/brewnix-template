# State Management Strategy for Brewnix GitOps

This document outlines the comprehensive state management strategy for the Brewnix GitOps implementation.

## Overview

State management in GitOps for infrastructure requires careful consideration of:

- Terraform state files
- Ansible facts and variables
- Secrets and credentials
- Configuration drift
- Backup and recovery
- Security implications

## Terraform State Management

### Local State Strategy

- **Storage**: Git-tracked in `sites/{site}/terraform/state/`
- **Benefits**: Full GitOps workflow, change tracking, rollback capability
- **Security**: Encrypt sensitive state with git-crypt

### State File Structure

```text
sites/{site}/terraform/state/
├── terraform.tfstate          # Current state
├── terraform.tfstate.backup   # Previous state
└── .gitkeep                   # Ensure directory exists in git
```

### State Backup Strategy

- **Automatic**: Daily backups via cron job
- **Manual**: Via `scripts/backup-state.sh`
- **Remote**: GitHub releases for off-site backup
- **Retention**: 30 days local, indefinite in releases

### State Recovery Process

1. Identify target state version (commit SHA or release tag)
2. Checkout repository at that version
3. Extract state files from backup
4. Re-initialize Terraform with recovered state
5. Verify infrastructure matches state

## Secrets Management

### git-crypt Integration

```bash
# Initialize git-crypt
git-crypt init

# Add encryption for secrets
echo "secrets/" > .gitattributes
git-crypt add-gpg-user your-gpg-key-id

# Encrypt existing secrets
git add .
git commit -m "Encrypt secrets"
```

### Alternative: Age Encryption

```bash
# Generate age key
age-keygen -o key.txt

# Encrypt secrets
tar -cz secrets/ | age -r age1... > secrets.tar.gz.age

# Decrypt during deployment
age -d -i key.txt secrets.tar.gz.age | tar -xz
```

### Secrets Storage Strategy

1. **Repository**: Encrypted with git-crypt in `sites/{site}/secrets/`
2. **Environment**: GitHub Secrets for CI/CD
3. **Runtime**: Ansible Vault for sensitive variables
4. **External**: HashiCorp Vault for production secrets

### Secrets File Structure

```text
sites/{site}/secrets/
├── api_keys/           # API tokens and keys
│   ├── proxmox_api_key.enc
│   └── tailscale_auth_key.enc
├── certificates/       # SSL certificates
│   ├── wildcard.home.local.crt.enc
│   └── wildcard.home.local.key.enc
├── credentials/        # Service credentials
│   ├── omada_password.enc
│   └── nas_credentials.enc
└── .gitattributes      # git-crypt configuration
```

## Configuration Management

### Site Configuration

- **Format**: Shell environment files (`site.conf`)
- **Validation**: Automated via GitHub Actions
- **Versioning**: Full git history for changes
- **Templating**: Jinja2 for dynamic configuration

### Environment-Specific Configuration

```bash
# Base configuration
SITE_NAME="production-site"
NETWORK_PREFIX="10.1"

# Environment overrides
if [[ "$ENVIRONMENT" == "staging" ]]; then
    NETWORK_PREFIX="10.101"
    SITE_NAME="staging-site"
fi
```

### Configuration Drift Detection

- **Ansible**: `--check` mode for dry-run validation
- **Terraform**: `plan` command for change detection
- **Monitoring**: Automated drift detection via cron

## Backup and Recovery

### Automated Backup Process

```bash
# Daily backup cron job
0 2 * * * /opt/proxmox-firewall/scripts/backup-state.sh all-sites

# Backup contents:
# - Terraform state files
# - Ansible facts
# - Site configurations
# - Git repository state
```

### Backup Storage Strategy

1. **Local**: `/var/backup/proxmox-firewall/` (30 days retention)
2. **Git**: State files committed to repository
3. **Remote**: GitHub releases for long-term storage
4. **Off-site**: Optional S3/Backblaze B2 integration

### Recovery Scenarios

#### Complete System Recovery

1. Bootstrap new system with USB
2. Connect to GitHub repository
3. Restore latest backup from releases
4. Re-deploy configuration
5. Verify system state

#### Partial State Recovery

1. Identify affected components
2. Restore specific state files
3. Run targeted deployment
4. Validate partial recovery

#### Configuration Rollback

1. Identify target commit/version
2. Checkout repository at that point
3. Deploy with rollback flag
4. Monitor for issues

## Security Considerations

### Access Control

- **SSH Keys**: Deploy keys per site/environment
- **Git Permissions**: Branch protection rules
- **API Tokens**: Least privilege principle
- **Audit Logging**: All state changes logged

### Encryption Strategy

- **At Rest**: git-crypt for repository files
- **In Transit**: SSH for all connections
- **Runtime**: Ansible Vault for variables
- **Backup**: Age encryption for archives

### Compliance Requirements

- **PCI DSS**: Tokenization for payment data
- **HIPAA**: PHI encryption requirements
- **GDPR**: Data residency considerations
- **SOX**: Audit trail requirements

## Implementation Details

### GitOps Workflow Integration

```yaml
# .github/workflows/deploy.yml
- name: Backup state
  run: ./scripts/backup-state.sh ${{ github.event.inputs.site }}

- name: Deploy
  run: ./scripts/deploy-site.sh ${{ github.event.inputs.site }}

- name: Verify deployment
  run: ./scripts/verify-deployment.sh ${{ github.event.inputs.site }}
```

### Monitoring and Alerting

- **State Changes**: Git commit notifications
- **Backup Status**: Automated verification
- **Drift Detection**: Scheduled checks
- **Security Events**: Real-time alerting

### Performance Optimization

- **State Size**: Minimize Terraform state files
- **Backup Frequency**: Balance between safety and storage
- **Compression**: Use gzip for backup archives
- **Caching**: Leverage Terraform/Ansible caching

## Best Practices

### State Management

1. Never manually edit Terraform state files
2. Always backup state before major changes
3. Use consistent naming conventions
4. Document state file locations

### Security

1. Rotate encryption keys regularly
2. Use separate keys per environment
3. Implement least privilege access
4. Regular security audits

### Operations

1. Test backup restoration regularly
2. Document recovery procedures
3. Automate as much as possible
4. Monitor for configuration drift

## Troubleshooting

### Common Issues

- **State Lock**: `terraform force-unlock` (use carefully)
- **Decryption Failures**: Verify git-crypt keys
- **Backup Corruption**: Restore from GitHub releases
- **Configuration Drift**: Run drift detection manually

### Debugging Commands

```bash
# Check state status
terraform state list
terraform state show <resource>

# Verify git-crypt
git-crypt status

# Check backup integrity
tar -tzf backup.tar.gz

# Validate configuration
ansible-playbook --check site-playbook.yml
```
