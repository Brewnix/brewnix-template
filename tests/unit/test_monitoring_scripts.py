#!/usr/bin/env python3
"""
Unit Tests for Monitoring Scripts
Tests for analyze-code-quality.py, generate-development-analytics.py, monitoring.sh
"""

import os
import sys
import tempfile
import subprocess
from pathlib import Path


class TestAnalyzeCodeQualityScript:
    """Test analyze-code-quality.py functionality"""

    def test_analyze_code_quality_script_exists(self):
        """Test that analyze-code-quality.py exists and is executable"""
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "monitoring" / "analyze-code-quality.py"
        assert script_path.exists(), "analyze-code-quality.py not found"
        assert os.access(script_path, os.X_OK), "analyze-code-quality.py is not executable"

    def test_analyze_code_quality_script_syntax(self):
        """Test analyze-code-quality.py has valid Python syntax"""
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "monitoring" / "analyze-code-quality.py"

        result = subprocess.run(["python3", "-m", "py_compile", str(script_path)],
                              capture_output=True, text=True)

        assert result.returncode == 0, f"Syntax error in analyze-code-quality.py: {result.stderr}"


class TestGenerateDevelopmentAnalyticsScript:
    """Test generate-development-analytics.py functionality"""

    def test_generate_development_analytics_script_exists(self):
        """Test that generate-development-analytics.py exists and is executable"""
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "monitoring" / "generate-development-analytics.py"
        assert script_path.exists(), "generate-development-analytics.py not found"
        assert os.access(script_path, os.X_OK), "generate-development-analytics.py is not executable"

    def test_generate_development_analytics_script_syntax(self):
        """Test generate-development-analytics.py has valid Python syntax"""
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "monitoring" / "generate-development-analytics.py"

        result = subprocess.run(["python3", "-m", "py_compile", str(script_path)],
                              capture_output=True, text=True)

        assert result.returncode == 0, f"Syntax error in generate-development-analytics.py: {result.stderr}"


class TestMonitoringScript:
    """Test monitoring.sh functionality"""

    def test_monitoring_script_exists(self):
        """Test that monitoring.sh exists and is executable"""
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "monitoring" / "monitoring.sh"
        assert script_path.exists(), "monitoring.sh not found"
        assert os.access(script_path, os.X_OK), "monitoring.sh is not executable"

    def test_monitoring_script_syntax(self):
        """Test monitoring.sh has valid bash syntax"""
        script_path = Path(__file__).parent.parent.parent / "vendor" / "scripts" / "monitoring" / "monitoring.sh"

        result = subprocess.run(["bash", "-n", str(script_path)],
                              capture_output=True, text=True)

        assert result.returncode == 0, f"Syntax error in monitoring.sh: {result.stderr}"


def run_tests():
    """Run all monitoring script tests"""
    print("🧪 Testing Monitoring Scripts...")

    test_classes = [TestAnalyzeCodeQualityScript, TestGenerateDevelopmentAnalyticsScript, TestMonitoringScript]
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
        print("🎉 All monitoring script tests passed!")
        return 0
    else:
        print("⚠️  Some tests failed")
        return 1


if __name__ == "__main__":
    sys.exit(run_tests())
