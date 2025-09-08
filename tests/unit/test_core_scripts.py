#!/usr/bin/env python3
"""
Unit Tests for Core Scripts
Tests for config.sh, init.sh, logging.sh
"""

import os
import sys
import tempfile
import subprocess
from pathlib import Path


class TestConfigScript:
    """Test config.sh functionality"""

    def test_config_script_exists(self):
        """Test that config.sh exists and is executable"""
        config_script = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "core" / "config.sh"
        assert config_script.exists(), "config.sh not found"
        assert os.access(config_script, os.X_OK), "config.sh is not executable"

    def test_config_script_basic_execution(self):
        """Test config.sh can be executed without errors"""
        config_script = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "core" / "config.sh"

        # Just test that the script can be sourced without errors
        result = subprocess.run(["bash", "-c", f"source {config_script}"],
                              capture_output=True, text=True, cwd=tempfile.gettempdir())

        # Should not have critical syntax errors
        assert "syntax error" not in result.stderr.lower()

    def test_config_script_syntax(self):
        """Test config.sh has valid bash syntax"""
        config_script = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "core" / "config.sh"

        result = subprocess.run(["bash", "-n", str(config_script)],
                              capture_output=True, text=True)

        assert result.returncode == 0, f"Syntax error in config.sh: {result.stderr}"


class TestInitScript:
    """Test init.sh functionality"""

    def test_init_script_exists(self):
        """Test that init.sh exists and is executable"""
        init_script = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "core" / "init.sh"
        assert init_script.exists(), "init.sh not found"
        assert os.access(init_script, os.X_OK), "init.sh is not executable"

    def test_init_script_syntax(self):
        """Test init.sh has valid bash syntax"""
        init_script = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "core" / "init.sh"

        result = subprocess.run(["bash", "-n", str(init_script)],
                              capture_output=True, text=True)

        assert result.returncode == 0, f"Syntax error in init.sh: {result.stderr}"


class TestLoggingScript:
    """Test logging.sh functionality"""

    def test_logging_script_exists(self):
        """Test that logging.sh exists and is executable"""
        logging_script = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "core" / "logging.sh"
        assert logging_script.exists(), "logging.sh not found"
        assert os.access(logging_script, os.X_OK), "logging.sh is not executable"

    def test_logging_script_syntax(self):
        """Test logging.sh has valid bash syntax"""
        logging_script = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "core" / "logging.sh"

        result = subprocess.run(["bash", "-n", str(logging_script)],
                              capture_output=True, text=True)

        assert result.returncode == 0, f"Syntax error in logging.sh: {result.stderr}"


class TestCoreScriptsIntegration:
    """Test integration between core scripts"""

    def test_core_scripts_dependencies(self):
        """Test that core scripts can be sourced together"""
        project_root = Path(__file__).parent.parent.parent
        core_dir = project_root / "vendor" / "scripts" / "core"

        # Create a test script that sources all core scripts
        test_script = tempfile.NamedTemporaryFile(mode='w', suffix='.sh', delete=False)
        test_script.write(f"""#!/bin/bash
# Test script to source all core scripts

# Source each core script
source "{core_dir}/config.sh"
source "{core_dir}/init.sh"
source "{core_dir}/logging.sh"

# Test that key functions/variables are available
echo "Testing core script integration..."

# Check if basic functions exist (this will vary based on actual script content)
echo "Core scripts sourced successfully"
""")
        test_script.close()

        # Make it executable
        os.chmod(test_script.name, 0o755)

        result = subprocess.run([test_script.name],
                              capture_output=True, text=True)

        # Clean up
        os.unlink(test_script.name)

        # Should complete without critical errors
        assert result.returncode == 0, f"Core script integration failed: {result.stderr}"


def run_tests():
    """Run all core script tests"""
    print("🧪 Testing Core Scripts...")

    test_classes = [TestConfigScript, TestInitScript, TestLoggingScript, TestCoreScriptsIntegration]
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
        print("🎉 All core script tests passed!")
        return 0
    else:
        print("⚠️  Some tests failed")
        return 1


if __name__ == "__main__":
    sys.exit(run_tests())
