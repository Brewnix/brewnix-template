#!/usr/bin/env python3
"""
Unit Tests for Deployment Scripts
Tests for deployment.sh
"""

import os
import sys
import tempfile
import subprocess
from pathlib import Path


class TestDeploymentScript:
    """Test deployment.sh functionality"""

    def test_deployment_script_exists(self):
        """Test that deployment.sh exists and is executable"""
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "deployment" / "deployment.sh"
        assert script_path.exists(), "deployment.sh not found"
        assert os.access(script_path, os.X_OK), "deployment.sh is not executable"

    def test_deployment_script_syntax(self):
        """Test deployment.sh has valid bash syntax"""
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "deployment" / "deployment.sh"

        result = subprocess.run(["bash", "-n", str(script_path)],
                              capture_output=True, text=True)

        assert result.returncode == 0, f"Syntax error in deployment.sh: {result.stderr}"


def run_tests():
    """Run all deployment script tests"""
    print("🧪 Testing Deployment Scripts...")

    test_classes = [TestDeploymentScript]
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

    print("\n📊 Test Results:")
    print(f"  Passed: {passed}")
    print(f"  Failed: {failed}")
    print(f"  Total: {passed + failed}")

    if failed == 0:
        print("🎉 All deployment script tests passed!")
        return 0
    else:
        print("⚠️  Some tests failed")
        return 1


if __name__ == "__main__":
    sys.exit(run_tests())
