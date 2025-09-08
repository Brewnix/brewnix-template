#!/usr/bin/env python3
"""
Performance Regression Tests
Tests for performance baselines and regression detection
"""

import os
import sys
import time
import tempfile
import subprocess
import json
from pathlib import Path
from typing import Dict, List, Any


class PerformanceTestRunner:
    """Runs performance tests and tracks baselines"""

    def __init__(self, project_root: Path):
        self.project_root = project_root
        self.baselines_file = project_root / "tests" / "performance" / "baselines.json"
        self.results_dir = project_root / "tests" / "performance" / "results"

        # Create directories
        self.results_dir.mkdir(parents=True, exist_ok=True)

        # Load existing baselines
        self.baselines = self._load_baselines()

    def _load_baselines(self) -> Dict[str, Any]:
        """Load performance baselines"""
        if self.baselines_file.exists():
            with open(self.baselines_file) as f:
                return json.load(f)
        return {}

    def _save_baselines(self):
        """Save performance baselines"""
        with open(self.baselines_file, 'w') as f:
            json.dump(self.baselines, f, indent=2)

    def run_script_performance_test(self, script_path: Path, test_name: str) -> Dict[str, Any]:
        """Run performance test for a script"""
        start_time = time.time()

        # Run the script with timeout
        try:
            result = subprocess.run(
                [str(script_path), "--help"] if script_path.suffix == ".sh" else [str(script_path), "--help"],
                capture_output=True,
                text=True,
                timeout=30,  # 30 second timeout
                cwd=self.project_root
            )
        except subprocess.TimeoutExpired:
            return {"error": "Script timed out", "duration": 30.0}

        end_time = time.time()
        duration = end_time - start_time

        return {
            "duration": duration,
            "returncode": result.returncode,
            "success": result.returncode == 0
        }

    def test_script_performance(self, script_path: Path, test_name: str) -> Dict[str, Any]:
        """Test script performance against baseline"""
        result = self.run_script_performance_test(script_path, test_name)

        if "error" in result:
            return result

        baseline_key = f"{test_name}_duration"
        current_duration = result["duration"]

        # Check against baseline
        if baseline_key in self.baselines:
            baseline_duration = self.baselines[baseline_key]
            regression_threshold = 2.0  # 2x slower is considered regression

            if current_duration > baseline_duration * regression_threshold:
                result["regression"] = True
                result["baseline_duration"] = baseline_duration
                result["regression_factor"] = current_duration / baseline_duration
            else:
                result["regression"] = False
        else:
            # First run, establish baseline
            self.baselines[baseline_key] = current_duration
            self._save_baselines()
            result["baseline_established"] = True

        return result


class TestScriptPerformance:
    """Test performance of core scripts"""

    def __init__(self):
        self.project_root = Path(__file__).parent.parent.parent
        self.performance_runner = PerformanceTestRunner(self.project_root)

    def test_core_script_performance(self):
        """Test performance of core scripts"""
        core_scripts = [
            ("config.sh", "vendor/scripts/core/config.sh"),
            ("init.sh", "vendor/scripts/core/init.sh"),
            ("logging.sh", "vendor/scripts/core/logging.sh")
        ]

        results = {}

        for script_name, script_rel_path in core_scripts:
            script_path = self.project_root / script_rel_path
            if script_path.exists():
                print(f"  Testing {script_name} performance...")
                result = self.performance_runner.test_script_performance(script_path, f"core_{script_name}")
                results[script_name] = result

                if "regression" in result and result["regression"]:
                    print(".2f")
                elif "baseline_established" in result:
                    print(".2f")
                else:
                    print(".2f")
        return results

    def test_utility_script_performance(self):
        """Test performance of utility scripts"""
        utility_scripts = [
            ("duplicate-core.sh", "vendor/scripts/utilities/duplicate-core.sh"),
            ("sync-core-modules.sh", "vendor/scripts/utilities/sync-core-modules.sh"),
            ("utilities.sh", "vendor/scripts/utilities/utilities.sh")
        ]

        results = {}

        for script_name, script_rel_path in utility_scripts:
            script_path = self.project_root / script_rel_path
            if script_path.exists():
                print(f"  Testing {script_name} performance...")
                result = self.performance_runner.test_script_performance(script_path, f"utility_{script_name}")
                results[script_name] = result

                if "regression" in result and result["regression"]:
                    print(".2f")
                elif "baseline_established" in result:
                    print(".2f")
                else:
                    print(".2f")
        return results


class TestBuildPerformance:
    """Test build and deployment performance"""

    def __init__(self):
        self.project_root = Path(__file__).parent.parent.parent
        self.performance_runner = PerformanceTestRunner(self.project_root)

    def test_build_script_performance(self):
        """Test performance of build scripts"""
        build_scripts = [
            ("build-release.sh", "scripts/build-release.sh"),
            ("ci-check.sh", "scripts/ci-check.sh")
        ]

        results = {}

        for script_name, script_rel_path in build_scripts:
            script_path = self.project_root / script_rel_path
            if script_path.exists():
                print(f"  Testing {script_name} performance...")
                result = self.performance_runner.test_script_performance(script_path, f"build_{script_name}")
                results[script_name] = result

                if "regression" in result and result["regression"]:
                    print(".2f")
                elif "baseline_established" in result:
                    print(".2f")
                else:
                    print(".2f")
        return results


def run_performance_tests():
    """Run all performance tests"""
    print("⚡ Running Performance Regression Tests...")

    # Test core scripts
    print("\n📋 Testing Core Script Performance:")
    core_tester = TestScriptPerformance()
    core_results = core_tester.test_core_script_performance()

    # Test utility scripts
    print("\n📋 Testing Utility Script Performance:")
    utility_results = core_tester.test_utility_script_performance()

    # Test build scripts
    print("\n📋 Testing Build Script Performance:")
    build_tester = TestBuildPerformance()
    build_results = build_tester.test_build_script_performance()

    # Analyze results
    total_tests = len(core_results) + len(utility_results) + len(build_results)
    regressions = 0
    baselines_established = 0

    all_results = {**core_results, **utility_results, **build_results}

    for script_name, result in all_results.items():
        if "regression" in result and result["regression"]:
            regressions += 1
        if "baseline_established" in result:
            baselines_established += 1

    print("\n📊 Performance Test Results:")
    print(f"  Total Scripts Tested: {total_tests}")
    print(f"  Performance Regressions: {regressions}")
    print(f"  Baselines Established: {baselines_established}")

    if regressions > 0:
        print("⚠️  Performance regressions detected!")
        return 1
    else:
        print("✅ No performance regressions detected!")
        return 0


if __name__ == "__main__":
    sys.exit(run_performance_tests())
