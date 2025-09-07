#!/usr/bin/env python3
"""
Brewnix Template Integration Test Suite
Comprehensive testing for universal deployment framework
"""

import os
import sys
import json
import time
import logging
import subprocess
import requests
import yaml
from pathlib import Path
from typing import Dict, List, Any, Optional
import pytest


class TestConfiguration:
    """Test configuration and utilities"""
    
    def __init__(self):
        self.workspace_root = Path("/workspace")
        self.test_data_dir = Path("/test-data")
        self.results_dir = Path("/results")
        self.proxmox_api_url = os.getenv("PROXMOX_API_URL", "http://proxmox-mock:8006")
        
        # Ensure directories exist
        self.results_dir.mkdir(exist_ok=True)
        
        # Setup logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.StreamHandler(),
                logging.FileHandler(self.results_dir / "integration_tests.log")
            ]
        )
        self.logger = logging.getLogger(__name__)


class ProxmoxMockClient:
    """Client for Proxmox mock API"""
    
    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip('/')
        self.session = requests.Session()
        
    def health_check(self) -> bool:
        """Check if Proxmox mock is healthy"""
        try:
            response = self.session.get(f"{self.base_url}/api2/json/version", timeout=5)
            return response.status_code == 200
        except Exception:
            return False
    
    def get_nodes(self) -> List[Dict]:
        """Get list of nodes"""
        try:
            response = self.session.get(f"{self.base_url}/api2/json/nodes")
            response.raise_for_status()
            return response.json().get("data", [])
        except Exception as e:
            return []
    
    def get_storage(self, node: str) -> List[Dict]:
        """Get storage information for a node"""
        try:
            response = self.session.get(f"{self.base_url}/api2/json/nodes/{node}/storage")
            response.raise_for_status()
            return response.json().get("data", [])
        except Exception as e:
            return []


class TestProxmoxIntegration:
    """Test Proxmox integration and mock services"""
    
    @pytest.fixture(autouse=True)
    def setup(self):
        self.config = TestConfiguration()
        self.proxmox = ProxmoxMockClient(self.config.proxmox_api_url)
        
    def test_proxmox_mock_health(self):
        """Test that Proxmox mock service is healthy"""
        assert self.proxmox.health_check(), "Proxmox mock service is not responding"
        
    def test_proxmox_api_endpoints(self):
        """Test essential Proxmox API endpoints"""
        # Test nodes endpoint
        nodes = self.proxmox.get_nodes()
        assert len(nodes) > 0, "No nodes returned from API"
        
        # Test storage endpoint for first node
        if nodes:
            node_name = nodes[0]["node"]
            storage = self.proxmox.get_storage(node_name)
            # Storage list can be empty in mock, just test endpoint responds
            assert isinstance(storage, list), "Storage endpoint should return a list"


class TestVendorConfigurations:
    """Test vendor-specific configurations and deployments"""
    
    @pytest.fixture(autouse=True)
    def setup(self):
        self.config = TestConfiguration()
        self.vendors_dir = self.config.workspace_root / "vendor"
        
    def test_vendor_directories_exist(self):
        """Test that all expected vendor directories exist"""
        expected_vendors = ["nas", "k3s-cluster", "development", "security"]
        
        for vendor in expected_vendors:
            vendor_dir = self.vendors_dir / vendor
            assert vendor_dir.exists(), f"Vendor directory {vendor} does not exist"
            
    def test_vendor_ansible_configs(self):
        """Test vendor Ansible configurations"""
        for vendor_dir in self.vendors_dir.glob("*/"):
            if vendor_dir.is_dir():
                ansible_dir = vendor_dir / "ansible"
                if ansible_dir.exists():
                    # Check ansible.cfg
                    ansible_cfg = ansible_dir / "ansible.cfg"
                    assert ansible_cfg.exists(), f"ansible.cfg missing in {vendor_dir.name}"
                    
                    # Check roles path configuration
                    with open(ansible_cfg) as f:
                        content = f.read()
                        assert "common/ansible/roles" in content, \
                            f"Common roles path not configured in {vendor_dir.name}"
                            
    def test_vendor_site_playbooks(self):
        """Test vendor site.yml playbooks exist and are valid"""
        for vendor_dir in self.vendors_dir.glob("*/"):
            if vendor_dir.is_dir():
                ansible_dir = vendor_dir / "ansible"
                if ansible_dir.exists():
                    site_yml = ansible_dir / "site.yml"
                    if site_yml.exists():
                        # Test YAML syntax
                        with open(site_yml) as f:
                            try:
                                yaml.safe_load(f)
                            except yaml.YAMLError as e:
                                pytest.fail(f"Invalid YAML in {vendor_dir.name}/ansible/site.yml: {e}")


class TestSiteConfigurations:
    """Test site configuration files"""
    
    @pytest.fixture(autouse=True)
    def setup(self):
        self.config = TestConfiguration()
        self.sites_dir = self.config.workspace_root / "config" / "sites"
        
    def test_site_configs_valid_yaml(self):
        """Test that all site configuration files are valid YAML"""
        if not self.sites_dir.exists():
            pytest.skip("No sites directory found")
            
        for site_dir in self.sites_dir.glob("*/"):
            if site_dir.is_dir():
                for yaml_file in site_dir.glob("*.yml"):
                    with open(yaml_file) as f:
                        try:
                            config = yaml.safe_load(f)
                            assert config is not None, f"Empty configuration in {yaml_file}"
                        except yaml.YAMLError as e:
                            pytest.fail(f"Invalid YAML in {yaml_file}: {e}")
                            
    def test_site_configs_required_fields(self):
        """Test that site configurations have required fields"""
        if not self.sites_dir.exists():
            pytest.skip("No sites directory found")
            
        required_fields = ["network", "deployment"]
        
        for site_dir in self.sites_dir.glob("*/"):
            if site_dir.is_dir():
                for yaml_file in site_dir.glob("*.yml"):
                    with open(yaml_file) as f:
                        config = yaml.safe_load(f)
                        
                    for field in required_fields:
                        assert field in config, \
                            f"Required field '{field}' missing in {yaml_file}"


class TestDeploymentScripts:
    """Test deployment scripts and functionality"""
    
    @pytest.fixture(autouse=True)
    def setup(self):
        self.config = TestConfiguration()
        self.scripts_dir = self.config.workspace_root / "scripts"
        
    def test_deploy_script_exists(self):
        """Test that deployment script exists and is executable"""
        deploy_script = self.scripts_dir / "deploy-vendor.sh"
        assert deploy_script.exists(), "deploy-vendor.sh script not found"
        assert os.access(deploy_script, os.X_OK), "deploy-vendor.sh is not executable"
        
    def test_deploy_script_help(self):
        """Test deployment script help functionality"""
        deploy_script = self.scripts_dir / "deploy-vendor.sh"
        
        result = subprocess.run([str(deploy_script), "--help"], 
                              capture_output=True, text=True)
        assert result.returncode == 0, "Deploy script help failed"
        assert "Usage:" in result.stdout, "Help output missing usage information"
        
    def test_deploy_script_vendor_validation(self):
        """Test deployment script vendor type validation"""
        deploy_script = self.scripts_dir / "deploy-vendor.sh"
        
        # Test invalid vendor
        result = subprocess.run([str(deploy_script), "invalid-vendor", "test.yml"], 
                              capture_output=True, text=True)
        assert result.returncode != 0, "Invalid vendor should fail"
        assert "Invalid vendor type" in result.stderr or "Invalid vendor type" in result.stdout, \
            "Should show invalid vendor error"


class TestBootstrapScripts:
    """Test bootstrap and USB creation scripts"""
    
    @pytest.fixture(autouse=True)
    def setup(self):
        self.config = TestConfiguration()
        self.bootstrap_dir = self.config.workspace_root / "bootstrap"
        
    def test_bootstrap_scripts_exist(self):
        """Test that bootstrap scripts exist"""
        expected_scripts = ["usb-bootstrap.sh", "initial-config.sh"]
        
        for script_name in expected_scripts:
            script_path = self.bootstrap_dir / script_name
            assert script_path.exists(), f"Bootstrap script {script_name} not found"
            
    def test_bootstrap_scripts_syntax(self):
        """Test bootstrap scripts have valid bash syntax"""
        for script_path in self.bootstrap_dir.glob("*.sh"):
            result = subprocess.run(["bash", "-n", str(script_path)], 
                                  capture_output=True, text=True)
            assert result.returncode == 0, \
                f"Syntax error in {script_path.name}: {result.stderr}"


class TestUSBImageCreation:
    """Test USB image creation and validation"""
    
    @pytest.fixture(autouse=True)
    def setup(self):
        self.config = TestConfiguration()
        self.usb_images_dir = Path("/images")
        self.usb_images_dir.mkdir(exist_ok=True)
        
    def test_usb_creation_simulation(self):
        """Test USB image creation simulation"""
        # This would be a more complex test in a real environment
        # For now, just test that we can create a test image file
        test_image = self.usb_images_dir / "test-image.img"
        
        # Create a minimal test image (1MB)
        result = subprocess.run([
            "dd", "if=/dev/zero", f"of={test_image}", "bs=1M", "count=1"
        ], capture_output=True, text=True)
        
        assert result.returncode == 0, f"Failed to create test image: {result.stderr}"
        assert test_image.exists(), "Test image file was not created"
        
        # Cleanup
        test_image.unlink()


class TestNetworkConfiguration:
    """Test network configuration and validation"""
    
    @pytest.fixture(autouse=True)
    def setup(self):
        self.config = TestConfiguration()
        
    def test_network_prefix_validation(self):
        """Test network prefix format validation"""
        # This would test the network prefix format from the docs
        valid_prefixes = [
            "192.168.1.0/24",
            "10.0.0.0/8", 
            "172.16.0.0/12"
        ]
        
        invalid_prefixes = [
            "192.168.1.0/40",  # Invalid CIDR
            "256.1.1.0/24",    # Invalid IP
            "192.168.1/24"     # Missing octet
        ]
        
        # Import network validation if it exists
        try:
            import ipaddress
            
            for prefix in valid_prefixes:
                try:
                    ipaddress.ip_network(prefix, strict=False)
                except ValueError:
                    pytest.fail(f"Valid prefix {prefix} failed validation")
                    
            for prefix in invalid_prefixes:
                try:
                    ipaddress.ip_network(prefix, strict=False)
                    pytest.fail(f"Invalid prefix {prefix} passed validation")
                except ValueError:
                    pass  # Expected
                    
        except ImportError:
            pytest.skip("ipaddress module not available")


class TestCommonFramework:
    """Test common framework components"""
    
    @pytest.fixture(autouse=True)
    def setup(self):
        self.config = TestConfiguration()
        self.common_dir = self.config.workspace_root / "common"
        
    def test_common_ansible_roles(self):
        """Test common Ansible roles structure"""
        if not self.common_dir.exists():
            pytest.skip("Common directory not found")
            
        ansible_roles_dir = self.common_dir / "ansible" / "roles"
        if ansible_roles_dir.exists():
            # Check that roles directory has some content
            roles = list(ansible_roles_dir.glob("*/"))
            assert len(roles) > 0, "No common roles found"
            
            # Check that each role has proper structure
            for role_dir in roles:
                if role_dir.is_dir():
                    # Check for main.yml in tasks
                    tasks_main = role_dir / "tasks" / "main.yml"
                    if tasks_main.exists():
                        with open(tasks_main) as f:
                            try:
                                yaml.safe_load(f)
                            except yaml.YAMLError as e:
                                pytest.fail(f"Invalid YAML in {tasks_main}: {e}")


def run_integration_tests():
    """Run all integration tests"""
    config = TestConfiguration()
    
    # Run pytest with custom configuration
    pytest_args = [
        "-v",  # Verbose output
        "--tb=short",  # Short traceback format
        "--junit-xml=/results/integration-test-results.xml",
        "--html=/results/integration-test-report.html",
        "--self-contained-html",
        __file__
    ]
    
    config.logger.info("Starting integration tests...")
    exit_code = pytest.main(pytest_args)
    
    # Generate summary report
    summary = {
        "timestamp": time.time(),
        "exit_code": exit_code,
        "success": exit_code == 0,
        "test_file": __file__
    }
    
    with open("/results/integration-summary.json", "w") as f:
        json.dump(summary, f, indent=2)
        
    config.logger.info(f"Integration tests completed with exit code: {exit_code}")
    return exit_code


if __name__ == "__main__":
    sys.exit(run_integration_tests())
