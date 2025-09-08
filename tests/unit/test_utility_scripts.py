#!/usr/bin/env python3
"""
Unit Tests for Utility Scripts
Tests for duplicate-core.sh, sync-core-modules.sh, utilities.sh
"""

import os
import sys
import tempfile
import subprocess
from pathlib import Path


class TestDuplicateCoreScript:
    """Test duplicate-core.sh functionality"""

    def test_duplicate_core_script_exists(self):
        """Test that duplicate-core.sh exists and is executable"""
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "utilities" / "duplicate-core.sh"
        assert script_path.exists(), "duplicate-core.sh not found"
        assert os.access(script_path, os.X_OK), "duplicate-core.sh is not executable"

    def test_duplicate_core_script_syntax(self):
        """Test duplicate-core.sh has valid bash syntax"""
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "utilities" / "duplicate-core.sh"

        result = subprocess.run(["bash", "-n", str(script_path)],
                              capture_output=True, text=True)

        assert result.returncode == 0, f"Syntax error in duplicate-core.sh: {result.stderr}"

    def test_duplicate_core_script_syntax(self):
        """Test duplicate-core.sh has valid bash syntax"""
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "utilities" / "duplicate-core.sh"

        result = subprocess.run(["bash", "-n", str(script_path)],
                              capture_output=True, text=True)

        assert result.returncode == 0, f"Syntax error in duplicate-core.sh: {result.stderr}"


class TestSyncCoreModulesScript:
    """Test sync-core-modules.sh functionality"""

    def test_sync_core_modules_script_exists(self):
        """Test that sync-core-modules.sh exists and is executable"""
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "utilities" / "sync-core-modules.sh"
        assert script_path.exists(), "sync-core-modules.sh not found"
        assert os.access(script_path, os.X_OK), "sync-core-modules.sh is not executable"

    def test_sync_core_modules_script_syntax(self):
        """Test sync-core-modules.sh has valid bash syntax"""
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "utilities" / "sync-core-modules.sh"

        result = subprocess.run(["bash", "-n", str(script_path)],
                              capture_output=True, text=True)

        assert result.returncode == 0, f"Syntax error in sync-core-modules.sh: {result.stderr}"


class TestUtilitiesScript:
    """Test utilities.sh functionality"""

    def test_utilities_script_exists(self):
        """Test that utilities.sh exists and is executable"""
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "utilities" / "utilities.sh"
        assert script_path.exists(), "utilities.sh not found"
        assert os.access(script_path, os.X_OK), "utilities.sh is not executable"

    def test_utilities_script_syntax(self):
        """Test utilities.sh has valid bash syntax"""
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "utilities" / "utilities.sh"

        result = subprocess.run(["bash", "-n", str(script_path)],
                              capture_output=True, text=True)

        assert result.returncode == 0, f"Syntax error in utilities.sh: {result.stderr}"


def run_tests():
    """Run all utility script tests"""
    print("🧪 Testing Utility Scripts...")

    test_classes = [TestDuplicateCoreScript, TestSyncCoreModulesScript, TestUtilitiesScript]
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
                    # Create a temporary directory if needed
                    if 'temp_dir' in method.__code__.co_varnames:
                        with tempfile.TemporaryDirectory() as tmpdir:
                            temp_dir_path = Path(tmpdir)
                            method(temp_dir_path)
                    else:
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
        print("🎉 All utility script tests passed!")
        return 0
    else:
        print("⚠️  Some tests failed")
        return 1


if __name__ == "__main__":
    sys.exit(run_tests())
