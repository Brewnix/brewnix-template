# Brewnix - Generalized Infrastructure Management

Brewnix is a unified infrastructure management system that supports multiple server types and provides automated deployment, monitoring, and management capabilities for private SME networks.

## Supported Server Types

### 1. Proxmox NAS (`proxmox-nas`)

- **Purpose**: Network Attached Storage with virtualization
- **Features**: ZFS storage pools, VM/container hosting, NAS services
- **Use Cases**: Home labs, small business storage, development environments

### 2. Proxmox Firewall (`proxmox-firewall`)

- **Purpose**: Network security and firewall management
- **Features**: Advanced firewall rules, VPN server, network segmentation
- **Use Cases**: Enterprise network security, multi-site connectivity

### 3. K3s Cluster (`k3s-cluster`)

- **Purpose**: Lightweight Kubernetes for edge computing
- **Features**: Container orchestration, service mesh, ingress controllers
- **Use Cases**: Edge computing, IoT deployments, microservices

## 🧩 Quick Start

1. **Fork this repository** to your own GitHub account.
2. **Add the server model submodules:**

   ```bash
   git submodule add https://github.com/Brewnix/proxmox-firewall vendor/proxmox-firewall
   git submodule add https://github.com/Brewnix/proxmox-nas vendor/proxmox-nas
   git submodule add https://github.com/Brewnix/k3s-cluster vendor/k3s-cluster
   git submodule update --init --recursive
   ```

3. **Configure your site:**

   ```bash
   cp config/sites/site-example.yml config/sites/my-site.yml
   # Edit my-site.yml with your specific configuration
   ```

4. **Validate and build:**

   ```bash
   ./scripts/build-release.sh validate config/sites/my-site.yml
   ./scripts/build-release.sh build config/sites/my-site.yml
   ```

5. **Start the web UI:**

   ```bash
   cd web-ui && python app.py
   ```

## 📁 Directory Structure

```text
my-network-project/
├── config/                # Your site-specific configuration, secrets, inventory, etc.
│   └── sites/            # Site configurations for different deployments
├── vendor/
│   ├── proxmox-firewall/  # Firewall server model
│   ├── proxmox-nas/       # NAS server model
│   └── k3s-cluster/       # Kubernetes cluster model
├── bootstrap/             # Initial setup scripts for all server types
├── scripts/               # Management and build scripts
├── web-ui/               # Graphical management interface
├── docs/                  # Documentation
├── .env                   # Your environment variables
└── ...
```

## 🚀 Build and Release Workflow

### Basic Build

```bash
# Validate configuration
./scripts/build-release.sh validate config/sites/my-site.yml

# Build deployment artifacts
./scripts/build-release.sh build config/sites/my-site.yml

# Create release package
./scripts/build-release.sh release config/sites/my-site.yml v1.0.0
```

### Automated Deployment

```bash
# Build and deploy automatically
DEPLOY_SITE=true ./scripts/build-release.sh build config/sites/my-site.yml
```

### Bootstrap USB Creation

```bash
# Generate server-specific bootstrap USB
./scripts/build-release.sh bootstrap config/sites/my-site.yml
```

## 🖥️ Web UI Management

The web UI provides a graphical interface for managing all aspects of your infrastructure:

### Features

- **Dashboard**: Overview of all sites and their status
- **Site Management**: Create, edit, and monitor sites
- **Device Management**: Register and manage devices
- **Monitoring**: Real-time status and alerts
- **GitOps**: Version-controlled deployments

### Starting the Web UI

```bash
cd web-ui
python app.py
```

Access at: [http://localhost:8080]

## 📝 Configuration

### Site Configuration Structure

```yaml
site_name: "my-home-lab"
server_type: "proxmox-nas"  # proxmox-nas, proxmox-firewall, k3s-cluster
location: "Home Office"
admin_email: "admin@example.com"

network:
  vlan_id: 20
  ip_range: "192.168.1.0/24"
  management_ip: "192.168.1.100/24"
  gateway: "192.168.1.1"
  dns: "8.8.8.8 1.1.1.1"

# Server-type specific configuration
storage:  # For proxmox-nas
  data_disks: ["/dev/sdb", "/dev/sdc"]
  raid_level: "raidz1"

# Services to deploy
services:
  truenas: true
  nextcloud: true
  memos: true
```

### Device Management

```bash
# Register devices from site configuration
./scripts/manage-devices.sh register-from-config config/sites/my-site.yml

# List all registered devices
./scripts/manage-devices.sh list

# Update device information
./scripts/manage-devices.sh update desktop-01 --ip 192.168.1.101
```

## 🔄 GitOps Workflow

Enable automated deployments through Git:

```yaml
gitops:
  repo_url: "https://github.com/your-org/brewnix-deployment.git"
  branch: "main"
  auto_update: true
```

### Update Process

1. Push configuration changes to Git
2. CI/CD pipeline triggers automated build
3. Artifacts are generated and tested
4. Deployment is applied to target systems
5. Monitoring and alerting configured

## 📊 Monitoring and Alerting

Configure monitoring for your infrastructure:

```yaml
monitoring:
  email: "admin@example.com"
  prometheus: true
  grafana: false
```

## 🔒 Security

- All secrets/config stay in your repo
- The submodule is safe to update or replace at any time
- No risk of leaking secrets by updating the submodule
- Bootstrap process includes security hardening

## � Documentation

- See [Implementation Guide](docs/IMPLEMENTATION_GUIDE.md) for deployment details.
- See [State Management Guide](docs/STATE_MANAGEMENT.md) for backup and recovery.
- See vendor submodules for specific server model documentation.

## 🔧 Development

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

### Development Setup

```bash
# Clone the repository
git clone https://github.com/your-org/brewnix-template.git
cd brewnix-template

# Install dependencies
pip install -r requirements.txt

# Run tests
python -m pytest

# Start development web UI
cd web-ui && python app.py --debug
```

## 🐛 Troubleshooting

### Common Issues

1. **Bootstrap USB Creation Fails**
   - Check disk space and permissions
   - Verify ISO files are available
   - Ensure USB device is properly formatted

2. **Configuration Validation Errors**
   - Check YAML syntax with `yamllint`
   - Verify all required fields are present
   - Ensure server type is supported

3. **Deployment Failures**
   - Check network connectivity
   - Verify credentials and permissions
   - Review Ansible playbook logs

### Logs

```bash
# Bootstrap logs
tail -f /var/log/brewnix-bootstrap.log

# Ansible logs
tail -f /var/log/ansible.log

# Web UI logs
tail -f web-ui/app.log
```

---
MIT License
