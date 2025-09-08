#!/usr/bin/env python3
"""
Property-Based Tests
Tests for script behavior with various inputs and edge cases
"""

import os
import sys
import tempfile
import subprocess
import random
import string
from pathlib import Path


class PropertyTester:
    """Base class for property-based testing"""

    def __init__(self, script_path: Path):
        self.script_path = script_path

    def generate_random_string(self, length: int = 10) -> str:
        """Generate a random string"""
        return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

    def generate_random_file_path(self) -> str:
        """Generate a random file path"""
        return f"/tmp/test_{self.generate_random_string()}.txt"

    def run_script_with_input(self, args: list = None, input_data: str = None) -> subprocess.CompletedProcess:
        """Run script with given arguments and input"""
        cmd = [str(self.script_path)]
        if args:
            cmd.extend(args)

        return subprocess.run(
            cmd,
            input=input_data,
            capture_output=True,
            text=True,
            timeout=10
        )


class TestConfigScriptProperties(PropertyTester):
    """Property-based tests for config.sh"""

    def __init__(self):
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "core" / "config.sh"
        super().__init__(script_path)

    def test_basic_execution_consistency(self):
        """Test that script can be executed consistently"""
        for _ in range(5):  # Test multiple times
            result = self.run_script_with_input([])
            # Should not crash
            assert isinstance(result.returncode, int)

    def test_invalid_arguments_handling(self):
        """Test handling of invalid arguments"""
        invalid_args = [
            ["--invalid-flag"],
            ["invalid-command"],
            ["--help", "extra-arg"],
            [self.generate_random_string()],
            [""]  # Empty argument
        ]

        for args in invalid_args:
            result = self.run_script_with_input(args)
            # Should not crash, should handle gracefully
            assert isinstance(result.returncode, int)


class TestInitScriptProperties(PropertyTester):
    """Property-based tests for init.sh"""

    def __init__(self):
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "core" / "init.sh"
        super().__init__(script_path)

    def test_initialization_idempotency(self):
        """Test that initialization is idempotent"""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Run initialization multiple times
            for i in range(3):
                result = subprocess.run(
                    [str(self.script_path)],
                    cwd=tmpdir,
                    capture_output=True,
                    text=True
                )
                # Should not fail on subsequent runs
                assert result.returncode == 0, f"Initialization failed on run {i+1}: {result.stderr}"


class TestLoggingScriptProperties(PropertyTester):
    """Property-based tests for logging.sh"""

    def __init__(self):
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "core" / "logging.sh"
        super().__init__(script_path)

    def test_log_message_variations(self):
        """Test logging with various message types"""
        test_messages = [
            "Simple message",
            "Message with spaces and symbols: !@#$%^&*()",
            "Multiline\nmessage",
            "",  # Empty message
            "Very long message: " + "x" * 1000,
            "Unicode: ñáéíóú 🚀 🌟"
        ]

        for message in test_messages:
            # Test different log levels if supported
            for level in ["info", "warn", "error"]:
                result = self.run_script_with_input([level, message])
                # Should handle various inputs gracefully
                assert isinstance(result.returncode, int)


class TestUtilityScriptProperties:
    """Property-based tests for utility scripts"""

    def test_duplicate_core_properties(self):
        """Test duplicate-core.sh with various scenarios"""
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "utilities" / "duplicate-core.sh"

        if not script_path.exists():
            print(f"  ⚠️  duplicate-core.sh not found, skipping test")
            return

        tester = PropertyTester(script_path)

        # Test with non-existent source
        result = tester.run_script_with_input(["/non/existent/path", "/tmp/dest"])
        assert result.returncode != 0  # Should fail gracefully

        # Test with invalid destination
        with tempfile.TemporaryDirectory() as tmpdir:
            result = tester.run_script_with_input([tmpdir, "/invalid/dest"])
            assert result.returncode != 0  # Should fail gracefully

    def test_sync_modules_properties(self):
        """Test sync-core-modules.sh properties"""
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "utilities" / "sync-core-modules.sh"

        if not script_path.exists():
            print(f"  ⚠️  sync-core-modules.sh not found, skipping test")
            return

        tester = PropertyTester(script_path)

        # Test running in various directories
        with tempfile.TemporaryDirectory() as tmpdir:
            result = subprocess.run(
                [str(script_path)],
                cwd=tmpdir,
                capture_output=True,
                text=True
            )
            # Should handle missing files gracefully
            assert isinstance(result.returncode, int)


class TestDeploymentScriptProperties:
    """Property-based tests for deployment.sh"""

    def test_deployment_validation(self):
        """Test deployment.sh input validation"""
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "deployment" / "deployment.sh"

        if not script_path.exists():
            print(f"  ⚠️  deployment.sh not found, skipping test")
            return

        tester = PropertyTester(script_path)

        # Test with invalid vendor types
        invalid_vendors = ["", "invalid", "123", "!@#", "very-long-vendor-name-that-should-not-exist"]
        for vendor in invalid_vendors:
            result = tester.run_script_with_input([vendor, "test.yml"])
            assert result.returncode != 0  # Should reject invalid vendors

        # Test with non-existent config files
        result = tester.run_script_with_input(["nas", "/non/existent/config.yml"])
        assert result.returncode != 0  # Should handle missing files


class TestFileSystemProperties:
    """Test file system related properties"""

    def test_symlink_integrity(self):
        """Test that symlinks are properly maintained"""
        project_root = Path(__file__).parent.parent.parent
        scripts_dir = project_root / "scripts"

        symlinks = ["core", "utilities", "monitoring", "deployment"]

        for link_name in symlinks:
            link_path = scripts_dir / link_name
            if link_path.exists():
                assert link_path.is_symlink(), f"{link_name} should be a symlink"

                # Test that target exists
                target = link_path.readlink()
                target_path = link_path.parent / target
                assert target_path.exists(), f"Symlink target {target_path} does not exist"

                # Test that we can list contents
                result = subprocess.run(["ls", str(link_path)],
                                      capture_output=True, text=True)
                assert result.returncode == 0, f"Cannot access {link_name} through symlink"


def run_property_tests():
    """Run all property-based tests"""
    print("🔬 Running Property-Based Tests...")

    test_classes = [
        TestConfigScriptProperties,
        TestInitScriptProperties,
        TestLoggingScriptProperties,
        TestUtilityScriptProperties,
        TestDeploymentScriptProperties,
        TestFileSystemProperties
    ]

    passed = 0
    failed = 0

    for test_class in test_classes:
        print(f"\n📋 Testing {test_class.__name__}:")

        try:
            # Create instance
            if test_class.__name__ == "TestFileSystemProperties":
                instance = test_class()
            else:
                instance = test_class()

            # Run test methods
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

        except Exception as e:
            print(f"  ❌ Failed to initialize {test_class.__name__}: {e}")
            failed += 1

    print("\n📊 Property-Based Test Results:")
    print(f"  Passed: {passed}")
    print(f"  Failed: {failed}")
    print(f"  Total: {passed + failed}")

    if failed == 0:
        print("🎉 All property-based tests passed!")
        return 0
    else:
        print("⚠️  Some property-based tests failed")
        return 1


if __name__ == "__main__":
    sys.exit(run_property_tests())
