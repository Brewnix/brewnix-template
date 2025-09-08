#!/usr/bin/env python3
"""
Comprehensive Test Runner for Phase 5.1.1: Test Coverage Expansion
Runs all test types and generates coverage reports
"""

import os
import sys
import time
import subprocess
from pathlib import Path


class TestRunner:
    """Comprehensive test runner for all test types"""

    def __init__(self, project_root: Path):
        self.project_root = project_root
        self.tests_dir = project_root / "tests"
        self.start_time = time.time()

    def run_unit_tests(self) -> int:
        """Run all unit tests"""
        print("\n🧪 Running Unit Tests...")

        unit_tests = [
            "tests/unit/test_core_scripts.py",
            "tests/unit/test_utility_scripts.py",
            "tests/unit/test_monitoring_scripts.py",
            "tests/unit/test_deployment_scripts.py"
        ]

        total_passed = 0
        total_failed = 0

        for test_file in unit_tests:
            test_path = self.project_root / test_file
            if test_path.exists():
                print(f"  📋 Running {test_file}...")
                result = subprocess.run([sys.executable, str(test_path)],
                                      capture_output=True, text=True)

                if result.returncode == 0:
                    print(f"  ✅ {test_file} passed")
                    total_passed += 1
                else:
                    print(f"  ❌ {test_file} failed")
                    print(f"     {result.stderr}")
                    total_failed += 1
            else:
                print(f"  ⚠️  {test_file} not found")
                total_failed += 1

        print(f"\n  📊 Unit Tests: {total_passed} passed, {total_failed} failed")
        return 1 if total_failed > 0 else 0

    def run_integration_tests(self) -> int:
        """Run integration tests"""
        print("\n🔗 Running Integration Tests...")

        integration_tests = [
            "tests/integration/test_cross_submodule.py"
        ]

        total_passed = 0
        total_failed = 0

        for test_file in integration_tests:
            test_path = self.project_root / test_file
            if test_path.exists():
                print(f"  📋 Running {test_file}...")
                result = subprocess.run([sys.executable, str(test_path)],
                                      capture_output=True, text=True)

                if result.returncode == 0:
                    print(f"  ✅ {test_file} passed")
                    total_passed += 1
                else:
                    print(f"  ❌ {test_file} failed")
                    print(f"     {result.stderr}")
                    total_failed += 1
            else:
                print(f"  ⚠️  {test_file} not found")
                total_failed += 1

        print(f"\n  📊 Integration Tests: {total_passed} passed, {total_failed} failed")
        return 1 if total_failed > 0 else 0

    def run_performance_tests(self) -> int:
        """Run performance tests"""
        print("\n⚡ Running Performance Tests...")

        performance_tests = [
            "tests/performance/test_performance_regression.py"
        ]

        total_passed = 0
        total_failed = 0

        for test_file in performance_tests:
            test_path = self.project_root / test_file
            if test_path.exists():
                print(f"  📋 Running {test_file}...")
                result = subprocess.run([sys.executable, str(test_path)],
                                      capture_output=True, text=True)

                if result.returncode == 0:
                    print(f"  ✅ {test_file} passed")
                    total_passed += 1
                else:
                    print(f"  ❌ {test_file} failed")
                    print(f"     {result.stderr}")
                    total_failed += 1
            else:
                print(f"  ⚠️  {test_file} not found")
                total_failed += 1

        print(f"\n  📊 Performance Tests: {total_passed} passed, {total_failed} failed")
        return 1 if total_failed > 0 else 0

    def run_property_tests(self) -> int:
        """Run property-based tests"""
        print("\n🔬 Running Property-Based Tests...")

        property_tests = [
            "tests/property/test_property_based.py"
        ]

        total_passed = 0
        total_failed = 0

        for test_file in property_tests:
            test_path = self.project_root / test_file
            if test_path.exists():
                print(f"  📋 Running {test_file}...")
                result = subprocess.run([sys.executable, str(test_path)],
                                      capture_output=True, text=True)

                if result.returncode == 0:
                    print(f"  ✅ {test_file} passed")
                    total_passed += 1
                else:
                    print(f"  ❌ {test_file} failed")
                    print(f"     {result.stderr}")
                    total_failed += 1
            else:
                print(f"  ⚠️  {test_file} not found")
                total_failed += 1

        print(f"\n  📊 Property Tests: {total_passed} passed, {total_failed} failed")
        return 1 if total_failed > 0 else 0

    def run_coverage_analysis(self) -> int:
        """Run coverage analysis"""
        print("\n📊 Running Coverage Analysis...")

        coverage_script = self.tests_dir / "coverage_analyzer.py"
        if coverage_script.exists():
            result = subprocess.run([sys.executable, str(coverage_script)],
                                  capture_output=True, text=True)

            print(result.stdout)
            if result.stderr:
                print(f"Errors: {result.stderr}")

            return result.returncode
        else:
            print("  ⚠️  Coverage analyzer not found")
            return 1

    def generate_final_report(self, results: dict) -> None:
        """Generate final comprehensive report"""
        end_time = time.time()
        total_duration = end_time - self.start_time

        print("\n" + "="*60)
        print("🎯 PHASE 5.1.1: TEST COVERAGE EXPANSION - FINAL REPORT")
        print("="*60)

        print("\n📊 Test Results Summary:")
        print(f"  Unit Tests: {'✅ PASSED' if results['unit'] == 0 else '❌ FAILED'}")
        print(f"  Integration Tests: {'✅ PASSED' if results['integration'] == 0 else '❌ FAILED'}")
        print(f"  Performance Tests: {'✅ PASSED' if results['performance'] == 0 else '❌ FAILED'}")
        print(f"  Property Tests: {'✅ PASSED' if results['property'] == 0 else '❌ FAILED'}")
        print(f"  Coverage Analysis: {'✅ PASSED' if results['coverage'] == 0 else '❌ FAILED'}")

        overall_success = all(code == 0 for code in results.values())

        print("\n🏆 Overall Status:")
        if overall_success:
            print("  🎉 ALL TESTS PASSED! Test coverage expansion successful.")
            print("  📈 Ready to proceed to Phase 5.1.2: Code Quality Gates")
        else:
            print("  ⚠️  SOME TESTS FAILED. Review and fix issues before proceeding.")

        print(".2f")
        print("\n" + "="*60)

    def run_all_tests(self) -> int:
        """Run all test suites"""
        print("🚀 Starting Phase 5.1.1: Test Coverage Expansion")
        print("Testing all scripts and components...")

        results = {}

        # Run all test types
        results['unit'] = self.run_unit_tests()
        results['integration'] = self.run_integration_tests()
        results['performance'] = self.run_performance_tests()
        results['property'] = self.run_property_tests()
        results['coverage'] = self.run_coverage_analysis()

        # Generate final report
        self.generate_final_report(results)

        # Return overall success/failure
        return 1 if any(code != 0 for code in results.values()) else 0


def main():
    """Main test runner function"""
    project_root = Path(__file__).parent.parent

    runner = TestRunner(project_root)
    exit_code = runner.run_all_tests()

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
