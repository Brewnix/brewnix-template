# Brewnix Template

**Universal Proxmox Infrastructure Framework with Vendor-Specific Deployments**

A comprehensive, modular infrastructure-as-code framework for deploying specialized server environments on Proxmox VE. Features a universal service management framework with vendor-specific implementations for different use cases.

## 🏗️ Architecture

### Universal Framework (`common/`)
Shared components used across all vendor implementations:
- **Service Management**: Universal VM deployment and configuration
- **Proxmox Host Setup**: Base system configuration, repositories, networking

### Vendor-Specific Implementations (`vendor/`)

#### 🗄️ **NAS Storage** (`vendor/proxmox-nas/`)
Network-attached storage and media services
- **Services**: TrueNAS Scale, Proxmox Backup Server, Jellyfin, Samba
- **Features**: ZFS storage, file sharing, media streaming, backup management

#### ☸️ **K3S Cluster** (`vendor/k3s-cluster/`)  
Kubernetes cluster deployment and management
- **Services**: K3S masters/workers, Longhorn storage, Rancher, Harbor registry
- **Features**: Multi-node clusters, distributed storage, container orchestration

#### 💻 **Development Server** (`vendor/development-server/`)
Complete development environment
- **Services**: VS Code Server, Jupyter Lab, GitLab CE, PostgreSQL, MySQL
- **Features**: Web IDEs, database systems, Git repositories, development tools

#### 🔒 **Security & Firewall** (`vendor/security-firewall/`)
Network security and firewall infrastructure  
- **Services**: OPNsense, Suricata IDS, Ntopng, Pi-hole, Step CA
- **Features**: Firewall management, intrusion detection, DNS filtering, PKI

## 🚀 Quick Start

### Prerequisites
- Proxmox VE 7.0+ host
- Ubuntu 20.04+ or similar Linux distribution  
- 8GB+ RAM, 50GB+ storage minimum
- Network access for downloading images

### 1. Clone and Initialize

```bash
git clone https://github.com/your-username/brewnix-template.git
cd brewnix-template
git submodule update --init --recursive
```

### 2. Choose Your Deployment Type

#### Deploy NAS Storage

```bash
./brewnix.sh deployment site proxmox-nas config/sites/nas-example/nas-site.yml
```

#### Deploy K3S Cluster

```bash
./brewnix.sh deployment site k3s-cluster config/sites/k3s-example/k3s-site.yml
```

#### Deploy Development Environment

```bash
./brewnix.sh deployment site development-server config/sites/development-example/dev-site.yml
```

#### Deploy Security Infrastructure

```bash
./brewnix.sh deployment site proxmox-firewall config/sites/security-example/security-site.yml
```

### 3. Configuration Validation

```bash
# Validate configuration without deployment
./brewnix.sh deployment validate config/sites/k3s-example/k3s-site.yml

# Dry run to see what would be deployed
./brewnix.sh deployment site proxmox-nas config/sites/nas-example/nas-site.yml --dry-run
```

## 📁 Project Structure

```
brewnix-template/
├── common/                     # Universal framework
│   └── ansible/
│       └── roles/
│           ├── service_management/    # Universal service deployment
│           └── proxmox_host_setup/    # Base Proxmox setup
├── vendor/                     # Vendor-specific implementations
│   ├── proxmox-nas/           # NAS storage deployment
│   ├── k3s-cluster/           # Kubernetes cluster
│   ├── development-server/    # Development environment  
│   ├── security-firewall/     # Security infrastructure
│   └── proxmox-firewall/      # Advanced firewall (submodule)
├── config/                    # Site configurations
│   └── sites/
│       ├── nas-example/
│       ├── k3s-example/
│       ├── development-example/
│       └── security-example/
├── scripts/                   # Deployment and utility scripts
└── docs/                     # Documentation
```

## ⚙️ Configuration

### Site Configuration Structure
Each vendor type uses standardized site configuration:

```yaml
# Site identification
site_name: "my-infrastructure"
site_type: "k3s-cluster"  # nas | k3s-cluster | development | security
deployment_environment: "production"

# Network configuration
network:
  vlan_id: 100
  ip_range: "192.168.100.0/24"
  management_ip: "192.168.100.10"
  gateway: "192.168.100.1"

# Proxmox configuration  
proxmox_api_host: "{{ network.management_ip }}"
proxmox_api_password: "{{ vault_proxmox_password }}"

# Vendor-specific configuration...
```

### Service Definitions
Services are defined per vendor in `services/` directories:

```yaml
# Example: K3S cluster services
k3s_master:
  enabled: true
  count: 3
  vm_config: { vcpus: 4, memory: 8192, disk: 100 }

k3s_worker:
  enabled: true
  count: 5
  vm_config: { vcpus: 4, memory: 8192, disk: 100 }
```

## 🔧 Advanced Usage

### Deployment Options

```bash
# Deploy specific components only
./brewnix.sh deployment site proxmox-nas config/sites/nas-site.yml --tags storage,backup

# Skip certain components
./brewnix.sh deployment site k3s-cluster config/sites/k3s-site.yml --skip-tags monitoring

# Verbose output for troubleshooting
./brewnix.sh deployment site development-server config/sites/dev-site.yml --verbose
```

### Multi-Vendor Deployments

Deploy multiple vendor types on the same Proxmox host:

```bash
# Deploy NAS first for shared storage
./brewnix.sh deployment site proxmox-nas config/sites/nas-site.yml

# Deploy K3S cluster that can use NAS storage
./brewnix.sh deployment site k3s-cluster config/sites/k3s-site.yml

# Deploy security infrastructure to protect everything
./brewnix.sh deployment site proxmox-firewall config/sites/security-site.yml
```

## 🔒 Security Features

- **Community Repository Integration**: No-subscription Proxmox repos
- **Subscription Nag Suppression**: Clean Proxmox web interface
- **Firewall Integration**: Advanced firewall with device templates
- **Certificate Management**: Built-in PKI with Step CA
- **Network Segmentation**: VLAN and security zone support

## 📚 Documentation

- [Implementation Guide](docs/IMPLEMENTATION_GUIDE.md) - Detailed setup instructions
- [Architecture Refactoring](docs/ARCHITECTURE_REFACTORING.md) - Framework design details
- [State Management](docs/STATE_MANAGEMENT.md) - Configuration management

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built on the excellent [proxmox-firewall](vendor/proxmox-firewall/) foundation
- Inspired by Infrastructure as Code best practices
- Community-driven development and testing
