# Proxmox Firewall - Site Template Repository

This repository serves as a template for deploying Proxmox-based firewalls using GitOps principles. It uses the [proxmox-firewall](https://github.com/yourorg/proxmox-firewall) repository as a git submodule.

## Repository Structure

```
├── sites/                          # Site-specific configurations
│   ├── site1/                      # First site configuration
│   │   ├── config/                 # Site-specific config files
│   │   ├── terraform/              # Terraform state (git-tracked)
│   │   ├── ansible/                # Ansible inventory/vars
│   │   └── secrets/                # Encrypted secrets (git-crypt)
│   └── site2/                      # Second site configuration
├── bootstrap/                      # Bootstrap scripts and configs
│   ├── usb-bootstrap.sh           # USB bootstrap script
│   ├── github-connect.sh          # GitHub connectivity setup
│   └── initial-config.sh          # Initial system configuration
├── scripts/                        # Site management scripts
│   ├── deploy-site.sh             # Deploy specific site
│   ├── update-site.sh             # Update specific site
│   └── backup-state.sh            # Backup terraform state
├── .github/workflows/             # GitHub Actions
│   ├── deploy.yml                 # Main deployment workflow
│   ├── validate.yml               # Configuration validation
│   └── backup.yml                 # State backup workflow
├── proxmox-firewall/              # Git submodule (main codebase)
├── .gitmodules                    # Git submodule configuration
└── ansible.cfg                    # Ansible configuration
```

## Quick Start

### 1. Create Your Site Repository

```bash
# Clone this template
git clone https://github.com/yourorg/proxmox-firewall-template.git my-firewall-deployment
cd my-firewall-deployment

# Initialize submodules
git submodule update --init --recursive

# Create your first site
cp -r sites/site1 sites/my-site
# Edit sites/my-site/config/site.conf with your settings
```

### 2. Configure Your Site

Edit `sites/my-site/config/site.conf`:

```bash
SITE_NAME="my-site"
SITE_DISPLAY_NAME="My Home Network"
NETWORK_PREFIX="10.1"
DOMAIN="myhome.local"
PROXMOX_HOST="10.1.50.1"
```

### 3. Bootstrap Your System

1. **Create Bootstrap USB**:
   ```bash
   ./bootstrap/create-bootstrap-usb.sh
   ```

2. **Boot from USB** and run:
   ```bash
   ./bootstrap/initial-config.sh
   ```

3. **Connect to GitHub**:
   ```bash
   ./bootstrap/github-connect.sh
   ```

### 4. Deploy

```bash
# Deploy your site
./scripts/deploy-site.sh my-site

# Or deploy all sites
./scripts/deploy-all-sites.sh
```

## State Management Strategy

### Terraform State
- **Local**: Stored in `sites/{site}/terraform/` (git-tracked)
- **Backup**: Automatic backups to GitHub releases
- **Recovery**: Can restore from git history or releases

### Secrets Management
- **git-crypt**: Encrypts sensitive files before commit
- **Age encryption**: Alternative modern encryption
- **External**: HashiCorp Vault or AWS Secrets Manager

### Configuration Management
- **Site-specific**: `sites/{site}/config/`
- **Shared templates**: `proxmox-firewall/` submodule
- **Version pinning**: Tag-based submodule references

## GitOps Workflow

### Automated Deployments
- Push to `main` → Automatic deployment to staging
- Tag releases → Production deployments
- Pull requests → Validation and testing

### Update Process
1. Update submodule: `git submodule update --remote`
2. Test changes in staging site
3. Deploy to production sites
4. Monitor and rollback if needed

### Bootstrap Process

The bootstrap USB contains:
- Minimal Linux environment
- SSH keys for GitHub access
- Initial configuration scripts
- Network setup utilities

## Security Considerations

### Secrets
- Never commit plaintext secrets
- Use `git-crypt` or `age` for encryption
- Rotate keys regularly
- Store master keys offline

### Access Control
- SSH key-based authentication
- GitHub deploy keys per site
- Separate credentials per environment

### Network Security
- Bootstrap systems isolated from production
- VPN required for remote access
- Firewall rules applied immediately

## Backup and Recovery

### Automated Backups
- Terraform state → GitHub releases
- VM backups → NAS/S3
- Configuration → Git history

### Recovery Process
1. Bootstrap new system
2. Restore from GitHub
3. Apply latest configuration
4. Test connectivity

## Multi-Site Management

### Site Organization
- Each site in separate directory
- Shared configuration via templates
- Independent deployments

### Cross-Site Connectivity
- Tailscale for secure inter-site communication
- Shared secrets for VPN configuration
- Centralized monitoring

## Troubleshooting

### Common Issues
- **Submodule issues**: `git submodule update --init --recursive`
- **State conflicts**: Check `.terraform.lock.hcl`
- **Permission errors**: Verify SSH keys and deploy tokens

### Debugging
- Check GitHub Actions logs
- Review Ansible playbooks output
- Verify network connectivity

## Contributing

1. Fork this template
2. Create feature branch
3. Test changes on staging site
4. Submit pull request
5. Deploy via GitOps workflow
