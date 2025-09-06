# Brewnix Template

This repository is a **starter template** for private configuration management against releases of various server models deployed on baremetal servers for private SME networks.

## 🧩 How to Use

1. **Fork this repository** to your own GitHub account.
2. **Add the server model submodules:**
   ```bash
   git submodule add https://github.com/FyberLabs/proxmox-firewall vendor/proxmox-firewall
   git submodule add https://github.com/FyberLabs/proxmox-nas vendor/proxmox-nas
   git submodule add https://github.com/FyberLabs/proxmox-k3b vendor/proxmox-k3b
   git submodule update --init --recursive
   ```
3. **Store all your configuration, secrets, and inventory in the `config/` directory.**
4. **Run all automation/scripts from the submodule, passing in your config as needed.**
5. **Update the submodule** to get new features and fixes:
   ```bash
   cd vendor/proxmox-firewall
   git fetch origin
   git checkout <latest-release-tag>
   cd ../..
   git add vendor/proxmox-firewall
   git commit -m "Update proxmox-firewall submodule to <latest-release-tag>"
   ```

## 📁 Directory Structure

```
my-network-project/
├── config/                # Your site-specific configuration, secrets, inventory, etc.
├── vendor/
│   ├── proxmox-firewall/  # Firewall server model
│   ├── proxmox-nas/       # NAS server model
│   └── proxmox-k3b/       # Kubernetes cluster model
├── bootstrap/             # Initial setup scripts
├── scripts/               # Management scripts
├── docs/                  # Documentation
├── .env                   # Your environment variables
└── ...
```

- **Never store secrets or config in the submodule.**
- **Pin the submodule** to a specific release/tag for stability.
- **Update regularly** to get security and feature updates.

## 🔒 Security
- All secrets/config stay in your repo
- The submodule is safe to update or replace at any time
- No risk of leaking secrets by updating the submodule

## 📝 Documentation
- See [Implementation Guide](docs/IMPLEMENTATION_GUIDE.md) for deployment details.
- See [State Management Guide](docs/STATE_MANAGEMENT.md) for backup and recovery.
- See vendor submodules for specific server model documentation.

---
MIT License
