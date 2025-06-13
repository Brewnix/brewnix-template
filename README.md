# Proxmox Firewall Template

This repository is a **starter template** for private configuration management against a release of [proxmox-firewall](https://github.com/FyberLabs/proxmox-firewall).

## 🧩 How to Use

1. **Fork this repository** to your own GitHub account.
2. **Add the proxmox-firewall repo as a submodule:**
   ```bash
   git submodule add https://github.com/FyberLabs/proxmox-firewall vendor/proxmox-firewall
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
my-firewall-project/
├── config/                # Your site-specific configuration, secrets, inventory, etc.
├── vendor/
│   └── proxmox-firewall/  # This repo as a submodule
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
- See [proxmox-firewall docs](https://github.com/FyberLabs/proxmox-firewall/tree/main/docs) for full usage and integration details.
- See [Submodule Strategy](https://github.com/FyberLabs/proxmox-firewall/blob/main/docs/SUBMODULE_STRATEGY.md) for best practices.

---
MIT License
