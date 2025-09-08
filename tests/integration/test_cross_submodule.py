#!/usr/bin/env python3
"""
Integration Tests for Cross-Submodule Interactions
Tests interactions between vendor submodules and core components
"""

import os
import sys
import tempfile
import subprocess
import json
from pathlib import Path


class TestVendorSubmoduleIntegration:
    """Test integration between vendor submodules"""

    def test_vendor_submodules_exist(self):
        """Test that all expected vendor submodules exist"""
        project_root = Path(__file__).parent.parent.parent
        vendor_dir = project_root / "vendor"

        expected_submodules = ["proxmox-nas", "k3s-cluster", "development-server", "proxmox-firewall", "common", "scripts"]

        for submodule in expected_submodules:
            submodule_path = vendor_dir / submodule
            assert submodule_path.exists(), f"Vendor submodule {submodule} not found"
            assert submodule_path.is_dir(), f"{submodule} is not a directory"

    def test_vendor_submodule_structure(self):
        """Test that vendor submodules have expected structure"""
        project_root = Path(__file__).parent.parent.parent
        vendor_dir = project_root / "vendor"

        # Test that each vendor submodule has ansible directory
        for submodule_dir in vendor_dir.glob("*/"):
            if submodule_dir.is_dir() and submodule_dir.name not in ["common", "scripts"]:
                ansible_dir = submodule_dir / "ansible"
                if ansible_dir.exists():
                    # Check for site.yml
                    site_yml = ansible_dir / "site.yml"
                    assert site_yml.exists(), f"site.yml missing in {submodule_dir.name}"

                    # Check for ansible.cfg
                    ansible_cfg = ansible_dir / "ansible.cfg"
                    assert ansible_cfg.exists(), f"ansible.cfg missing in {submodule_dir.name}"


class TestCommonFrameworkIntegration:
    """Test integration with common framework components"""

    def test_common_ansible_roles_accessible(self):
        """Test that vendor submodules can access common Ansible roles"""
        project_root = Path(__file__).parent.parent.parent
        common_roles_dir = project_root / "vendor" / "common" / "ansible" / "roles"

        if common_roles_dir.exists():
            roles = list(common_roles_dir.glob("*/"))
            assert len(roles) > 0, "No common Ansible roles found"

            # Test that roles have proper structure
            for role_dir in roles:
                if role_dir.is_dir():
                    tasks_dir = role_dir / "tasks"
                    if tasks_dir.exists():
                        main_yml = tasks_dir / "main.yml"
                        if main_yml.exists():
                            # Quick syntax check
                            result = subprocess.run(
                                ["python3", "-c", f"import yaml; yaml.safe_load(open('{main_yml}'))"],
                                capture_output=True, text=True
                            )
                            assert result.returncode == 0, f"Invalid YAML in {main_yml}"

    def test_common_scripts_accessible(self):
        """Test that common scripts are accessible"""
        project_root = Path(__file__).parent.parent.parent
        common_scripts_dir = project_root / "vendor" / "scripts"

        if common_scripts_dir.exists():
            # Test core scripts
            core_scripts = ["config.sh", "init.sh", "logging.sh"]
            for script in core_scripts:
                script_path = common_scripts_dir / "core" / script
                assert script_path.exists(), f"Common script {script} not found"
                assert os.access(script_path, os.X_OK), f"Common script {script} not executable"


class TestScriptSymlinkIntegration:
    """Test integration of script symlinks"""

    def test_script_symlinks_work(self):
        """Test that script symlinks in main scripts/ directory work"""
        project_root = Path(__file__).parent.parent.parent
        scripts_dir = project_root / "scripts"

        # Test core symlink
        core_link = scripts_dir / "core"
        assert core_link.exists(), "core symlink not found"
        assert core_link.is_symlink(), "core is not a symlink"

        # Test that symlink points to correct location
        target = core_link.readlink()
        expected_target = Path("../vendor/scripts/core")
        assert target == expected_target, f"core symlink points to {target}, expected {expected_target}"

        # Test that symlink target exists
        target_path = core_link.parent / target
        assert target_path.exists(), f"Symlink target {target_path} does not exist"

    def test_symlink_functionality(self):
        """Test that symlinks actually work for file access"""
        project_root = Path(__file__).parent.parent.parent
        scripts_dir = project_root / "scripts"

        # Test accessing files through symlinks
        core_link = scripts_dir / "core"
        if core_link.exists() and core_link.is_symlink():
            # Try to list contents through symlink
            result = subprocess.run(["ls", str(core_link)],
                                  capture_output=True, text=True, cwd=scripts_dir)

            assert result.returncode == 0, f"Failed to access core through symlink: {result.stderr}"
            assert "config.sh" in result.stdout, "config.sh not accessible through symlink"


class TestConfigurationValidation:
    """Test configuration validation across submodules"""

    def test_site_configurations_valid(self):
        """Test that site configurations are valid YAML"""
        project_root = Path(__file__).parent.parent.parent
        sites_dir = project_root / "config" / "sites"

        if sites_dir.exists():
            for site_dir in sites_dir.glob("*/"):
                if site_dir.is_dir():
                    for config_file in site_dir.glob("*.yml"):
                        # Test YAML syntax
                        result = subprocess.run(
                            ["python3", "-c", f"import yaml; yaml.safe_load(open('{config_file}'))"],
                            capture_output=True, text=True
                        )
                        assert result.returncode == 0, f"Invalid YAML in {config_file}: {result.stderr}"

    def test_vendor_ansible_configs_valid(self):
        """Test that vendor Ansible configurations are valid"""
        project_root = Path(__file__).parent.parent.parent
        vendor_dir = project_root / "vendor"

        for submodule_dir in vendor_dir.glob("*/"):
            if submodule_dir.is_dir() and submodule_dir.name not in ["common", "scripts"]:
                ansible_cfg = submodule_dir / "ansible" / "ansible.cfg"
                if ansible_cfg.exists():
                    # Check that it references common roles
                    with open(ansible_cfg) as f:
                        content = f.read()
                        assert "common/ansible/roles" in content, \
                            f"{submodule_dir.name} ansible.cfg doesn't reference common roles"


def run_integration_tests():
    """Run all integration tests"""
    print("🔗 Testing Cross-Submodule Integration...")

    test_classes = [
        TestVendorSubmoduleIntegration,
        TestCommonFrameworkIntegration,
        TestScriptSymlinkIntegration,
        TestConfigurationValidation
    ]

    passed = 0
    failed = 0

    for test_class in test_classes:
        print(f"\n📋 Testing {test_class.__name__}:")

        # Create instance and run tests
        instance = test_class()

        for method_name in dir(instance):
            if method_name.startswith('test_'):
                try:
                    method = getattr(instance, method_name)
                    method()
                    print(f"  ✅ {method_name}")
                    passed += 1

                except Exception as e:
                    print(f"  ❌ {method_name}: {e}")
                    failed += 1

    print("\n📊 Integration Test Results:")
    print(f"  Passed: {passed}")
    print(f"  Failed: {failed}")
    print(f"  Total: {passed + failed}")

    if failed == 0:
        print("🎉 All integration tests passed!")
        return 0
    else:
        print("⚠️  Some integration tests failed")
        return 1


if __name__ == "__main__":
    sys.exit(run_integration_tests())
