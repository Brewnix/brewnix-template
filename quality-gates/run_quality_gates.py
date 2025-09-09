#!/usr/bin/env python3
"""
BrewNix Code Quality Gates
Phase 5.1.2: Automated Code Quality Assurance
Comprehensive linting, complexity analysis, security scanning, and code review
"""

import os
import sys
import time
import subprocess
import json
from pathlib import Path
from typing import Dict, List, Any, Optional


class QualityGateManager:
    """Manages all code quality gate checks"""

    def __init__(self, project_root: Path):
        self.project_root = project_root
        self.quality_dir = project_root / "quality-gates"
        self.reports_dir = project_root / "quality-gates" / "reports"

        # Create directories
        self.reports_dir.mkdir(parents=True, exist_ok=True)

        # Quality gate thresholds
        self.thresholds = {
            "linting": {
                "max_errors": 0,
                "max_warnings": 10
            },
            "complexity": {
                "max_complexity": 10,
                "max_lines": 100
            },
            "security": {
                "max_critical": 0,
                "max_high": 0,
                "max_medium": 5
            },
            "coverage": {
                "min_coverage": 80.0
            }
        }

    def run_all_quality_gates(self) -> Dict[str, Any]:
        """Run all quality gate checks"""
        print("🔍 Running BrewNix Code Quality Gates...")

        results = {
            "timestamp": time.time(),
            "gates": {},
            "overall_status": "unknown",
            "summary": {}
        }

        # Run individual quality gates
        results["gates"]["linting"] = self.run_linting_checks()
        results["gates"]["complexity"] = self.run_complexity_analysis()
        results["gates"]["security"] = self.run_security_scanning()
        results["gates"]["review"] = self.run_code_review_checks()

        # Calculate overall status
        results["overall_status"] = self._calculate_overall_status(results["gates"])
        results["summary"] = self._generate_summary(results["gates"])

        # Save results
        self._save_results(results)

        return results

    def run_linting_checks(self) -> Dict[str, Any]:
        """Run comprehensive linting checks"""
        print("\n📏 Running Linting Checks...")

        result = {
            "status": "unknown",
            "languages": {},
            "total_errors": 0,
            "total_warnings": 0,
            "details": []
        }

        # Python linting
        if self._has_python_files():
            result["languages"]["python"] = self._run_python_linting()

        # Shell script linting
        if self._has_shell_files():
            result["languages"]["shell"] = self._run_shell_linting()

        # YAML linting
        if self._has_yaml_files():
            result["languages"]["yaml"] = self._run_yaml_linting()

        # Calculate totals
        for lang_result in result["languages"].values():
            result["total_errors"] += lang_result.get("errors", 0)
            result["total_warnings"] += lang_result.get("warnings", 0)

        # Determine status
        if result["total_errors"] > self.thresholds["linting"]["max_errors"]:
            result["status"] = "failed"
        elif result["total_warnings"] > self.thresholds["linting"]["max_warnings"]:
            result["status"] = "warning"
        else:
            result["status"] = "passed"

        return result

    def run_complexity_analysis(self) -> Dict[str, Any]:
        """Run code complexity analysis"""
        print("\n🧠 Running Complexity Analysis...")

        result = {
            "status": "unknown",
            "files_analyzed": 0,
            "complex_functions": [],
            "long_functions": [],
            "summary": {}
        }

        # Python complexity
        if self._has_python_files():
            python_result = self._run_python_complexity()
            result["files_analyzed"] += python_result.get("files_analyzed", 0)
            result["complex_functions"].extend(python_result.get("complex_functions", []))
            result["long_functions"].extend(python_result.get("long_functions", []))

        # Shell script complexity
        if self._has_shell_files():
            shell_result = self._run_shell_complexity()
            result["files_analyzed"] += shell_result.get("files_analyzed", 0)
            result["complex_functions"].extend(shell_result.get("complex_functions", []))
            result["long_functions"].extend(shell_result.get("long_functions", []))

        # Determine status
        max_complexity = max([f.get("complexity", 0) for f in result["complex_functions"]], default=0)
        max_lines = max([f.get("lines", 0) for f in result["long_functions"]], default=0)

        if max_complexity > self.thresholds["complexity"]["max_complexity"]:
            result["status"] = "failed"
        elif max_lines > self.thresholds["complexity"]["max_lines"]:
            result["status"] = "warning"
        else:
            result["status"] = "passed"

        result["summary"] = {
            "total_complex_functions": len(result["complex_functions"]),
            "total_long_functions": len(result["long_functions"]),
            "max_complexity": max_complexity,
            "max_lines": max_lines
        }

        return result

    def run_security_scanning(self) -> Dict[str, Any]:
        """Run security vulnerability scanning"""
        print("\n🔒 Running Security Scanning...")

        result = {
            "status": "unknown",
            "vulnerabilities": {
                "critical": [],
                "high": [],
                "medium": [],
                "low": [],
                "info": []
            },
            "summary": {}
        }

        # Try to use the dedicated security scanner
        try:
            security_script = self.quality_dir / "security" / "scan_security.py"
            if security_script.exists():
                cmd = [sys.executable, str(security_script)]
                process = subprocess.run(cmd, capture_output=True, text=True, cwd=self.project_root)

                if process.returncode == 0:
                    # Parse the security scan results
                    try:
                        import json
                        # The security scanner saves results to a file, let's read the latest one
                        security_reports = list((self.quality_dir / "security").glob("security-report-*.json"))
                        if security_reports:
                            latest_report = max(security_reports, key=lambda x: x.stat().st_mtime)
                            with open(latest_report) as f:
                                security_data = json.load(f)
                            result["vulnerabilities"] = security_data.get("vulnerabilities", result["vulnerabilities"])
                    except:
                        pass
                else:
                    print(f"⚠️ Security scanner failed: {process.stderr}")
                    # Fallback to basic security scan
                    security_result = self._run_security_scan()
                    result["vulnerabilities"] = security_result.get("vulnerabilities", result["vulnerabilities"])
            else:
                # Fallback to basic security scan
                security_result = self._run_security_scan()
                result["vulnerabilities"] = security_result.get("vulnerabilities", result["vulnerabilities"])

        except Exception as e:
            print(f"⚠️ Error running security scan: {e}")
            # Fallback to basic security scan
            security_result = self._run_security_scan()
            result["vulnerabilities"] = security_result.get("vulnerabilities", result["vulnerabilities"])

        # Calculate summary
        result["summary"] = {
            "critical_count": len(result["vulnerabilities"]["critical"]),
            "high_count": len(result["vulnerabilities"]["high"]),
            "medium_count": len(result["vulnerabilities"]["medium"]),
            "low_count": len(result["vulnerabilities"]["low"]),
            "info_count": len(result["vulnerabilities"]["info"])
        }

        # Determine status
        if result["summary"]["critical_count"] > self.thresholds["security"]["max_critical"]:
            result["status"] = "failed"
        elif result["summary"]["high_count"] > self.thresholds["security"]["max_high"]:
            result["status"] = "failed"
        elif result["summary"]["medium_count"] > self.thresholds["security"]["max_medium"]:
            result["status"] = "warning"
        else:
            result["status"] = "passed"

        return result

    def run_code_review_checks(self) -> Dict[str, Any]:
        """Run automated code review checks"""
        print("\n👁️ Running Code Review Checks...")

        result = {
            "status": "unknown",
            "checks": {},
            "recommendations": [],
            "score": 0
        }

        # Try to use the dedicated code review automation
        try:
            review_script = self.quality_dir / "review" / "automate_review.py"
            if review_script.exists():
                cmd = [sys.executable, str(review_script)]
                process = subprocess.run(cmd, capture_output=True, text=True, cwd=self.project_root)

                if process.returncode == 0:
                    # Parse the code review results
                    try:
                        import json
                        # The review automation saves results to a file, let's read the latest one
                        review_reports = list((self.quality_dir / "review").glob("review-report-*.json"))
                        if review_reports:
                            latest_report = max(review_reports, key=lambda x: x.stat().st_mtime)
                            with open(latest_report) as f:
                                review_data = json.load(f)
                            result["score"] = review_data.get("score", 0)
                            result["recommendations"] = review_data.get("recommendations", [])
                    except:
                        pass
                else:
                    print(f"⚠️ Code review automation failed: {process.stderr}")
                    # Fallback to basic code review checks
                    result["checks"]["documentation"] = self._check_documentation()
                    result["checks"]["naming"] = self._check_naming_conventions()
                    result["checks"]["structure"] = self._check_code_structure()
                    result["checks"]["best_practices"] = self._check_best_practices()
            else:
                # Fallback to basic code review checks
                result["checks"]["documentation"] = self._check_documentation()
                result["checks"]["naming"] = self._check_naming_conventions()
                result["checks"]["structure"] = self._check_code_structure()
                result["checks"]["best_practices"] = self._check_best_practices()

        except Exception as e:
            print(f"⚠️ Error running code review: {e}")
            # Fallback to basic code review checks
            result["checks"]["documentation"] = self._check_documentation()
            result["checks"]["naming"] = self._check_naming_conventions()
            result["checks"]["structure"] = self._check_code_structure()
            result["checks"]["best_practices"] = self._check_best_practices()

        # Calculate overall score if not already set
        if result["score"] == 0 and result["checks"]:
            passed_checks = sum(1 for check in result["checks"].values() if check.get("status") == "passed")
            total_checks = len(result["checks"])
            result["score"] = (passed_checks / total_checks) * 100 if total_checks > 0 else 0

        # Determine status
        if result["score"] >= 90:
            result["status"] = "passed"
        elif result["score"] >= 75:
            result["status"] = "warning"
        else:
            result["status"] = "failed"

        return result

    def _has_python_files(self) -> bool:
        """Check if project has Python files"""
        return len(list(self.project_root.glob("**/*.py"))) > 0

    def _has_shell_files(self) -> bool:
        """Check if project has shell files"""
        return len(list(self.project_root.glob("**/*.sh"))) > 0

    def _has_yaml_files(self) -> bool:
        """Check if project has YAML files"""
        return len(list(self.project_root.glob("**/*.yml"))) + len(list(self.project_root.glob("**/*.yaml"))) > 0

    def _run_python_linting(self) -> Dict[str, Any]:
        """Run Python linting"""
        result = {"errors": 0, "warnings": 0, "details": []}

        try:
            # Try flake8 first
            cmd = ["python3", "-m", "flake8", "--max-line-length=100", "--extend-ignore=E203,W503", str(self.project_root)]
            process = subprocess.run(cmd, capture_output=True, text=True, cwd=self.project_root)

            if process.returncode == 0:
                result["details"].append("✅ flake8: No issues found")
            else:
                lines = process.stdout.split('\n') + process.stderr.split('\n')
                for line in lines:
                    if line.strip():
                        if "error" in line.lower():
                            result["errors"] += 1
                        else:
                            result["warnings"] += 1
                        result["details"].append(line)

        except FileNotFoundError:
            result["details"].append("⚠️ flake8 not available, using basic syntax check")
            # Fallback to basic syntax check
            for py_file in self.project_root.glob("**/*.py"):
                try:
                    compile(py_file.read_text(), str(py_file), 'exec')
                except SyntaxError as e:
                    result["errors"] += 1
                    result["details"].append(f"❌ {py_file}: {e}")

        return result

    def _run_shell_linting(self) -> Dict[str, Any]:
        """Run shell script linting"""
        result = {"errors": 0, "warnings": 0, "details": []}

        try:
            # Try shellcheck
            cmd = ["shellcheck", "--severity=warning", str(self.project_root)]
            process = subprocess.run(cmd, capture_output=True, text=True, cwd=self.project_root)

            if process.returncode == 0:
                result["details"].append("✅ shellcheck: No issues found")
            else:
                lines = process.stdout.split('\n') + process.stderr.split('\n')
                for line in lines:
                    if line.strip():
                        if "error" in line.lower() or "critical" in line.lower():
                            result["errors"] += 1
                        else:
                            result["warnings"] += 1
                        result["details"].append(line)

        except FileNotFoundError:
            result["details"].append("⚠️ shellcheck not available, using basic syntax check")
            # Fallback to basic syntax check
            for sh_file in self.project_root.glob("**/*.sh"):
                try:
                    subprocess.run(["bash", "-n", str(sh_file)], check=True, capture_output=True)
                    result["details"].append(f"✅ {sh_file}: Syntax OK")
                except subprocess.CalledProcessError:
                    result["errors"] += 1
                    result["details"].append(f"❌ {sh_file}: Syntax error")

        return result

    def _run_yaml_linting(self) -> Dict[str, Any]:
        """Run YAML linting"""
        result = {"errors": 0, "warnings": 0, "details": []}

        try:
            import yaml
            for yaml_file in self.project_root.glob("**/*.yml"):
                try:
                    with open(yaml_file) as f:
                        yaml.safe_load(f)
                    result["details"].append(f"✅ {yaml_file}: Valid YAML")
                except yaml.YAMLError as e:
                    result["errors"] += 1
                    result["details"].append(f"❌ {yaml_file}: {e}")

            for yaml_file in self.project_root.glob("**/*.yaml"):
                try:
                    with open(yaml_file) as f:
                        yaml.safe_load(f)
                    result["details"].append(f"✅ {yaml_file}: Valid YAML")
                except yaml.YAMLError as e:
                    result["errors"] += 1
                    result["details"].append(f"❌ {yaml_file}: {e}")

        except ImportError:
            result["details"].append("⚠️ PyYAML not available for YAML validation")

        return result

    def _run_python_complexity(self) -> Dict[str, Any]:
        """Run Python complexity analysis"""
        result = {"files_analyzed": 0, "complex_functions": [], "long_functions": []}

        try:
            # Try radon for complexity analysis
            cmd = ["python3", "-m", "radon", "cc", "--min", "C", "--show-complexity", str(self.project_root)]
            process = subprocess.run(cmd, capture_output=True, text=True, cwd=self.project_root)

            if process.returncode == 0:
                lines = process.stdout.split('\n')
                for line in lines:
                    if line.strip():
                        # Parse complexity results
                        parts = line.split()
                        if len(parts) >= 3:
                            complexity = int(parts[-1])
                            function_name = ' '.join(parts[:-1])
                            if complexity > self.thresholds["complexity"]["max_complexity"]:
                                result["complex_functions"].append({
                                    "function": function_name,
                                    "complexity": complexity
                                })

        except (FileNotFoundError, subprocess.CalledProcessError):
            # Fallback: basic line count analysis
            for py_file in self.project_root.glob("**/*.py"):
                try:
                    content = py_file.read_text()
                    lines = len(content.split('\n'))
                    if lines > self.thresholds["complexity"]["max_lines"]:
                        result["long_functions"].append({
                            "file": str(py_file),
                            "lines": lines
                        })
                except:
                    pass

        result["files_analyzed"] = len(list(self.project_root.glob("**/*.py")))
        return result

    def _run_shell_complexity(self) -> Dict[str, Any]:
        """Run shell script complexity analysis"""
        result = {"files_analyzed": 0, "complex_functions": [], "long_functions": []}

        for sh_file in self.project_root.glob("**/*.sh"):
            try:
                content = sh_file.read_text()
                lines = len(content.split('\n'))

                if lines > self.thresholds["complexity"]["max_lines"]:
                    result["long_functions"].append({
                        "file": str(sh_file),
                        "lines": lines
                    })

                # Count functions (basic heuristic)
                functions = content.count("function ") + content.count("() {")
                if functions > 20:  # Arbitrary threshold
                    result["complex_functions"].append({
                        "file": str(sh_file),
                        "functions": functions
                    })

            except:
                pass

        result["files_analyzed"] = len(list(self.project_root.glob("**/*.sh")))
        return result

    def _run_security_scan(self) -> Dict[str, Any]:
        """Run security vulnerability scanning"""
        result = {"vulnerabilities": {"critical": [], "high": [], "medium": [], "low": [], "info": []}}

        try:
            # Try bandit for Python security
            cmd = ["python3", "-m", "bandit", "-r", str(self.project_root), "-f", "json"]
            process = subprocess.run(cmd, capture_output=True, text=True, cwd=self.project_root)

            if process.returncode == 0:
                try:
                    bandit_results = json.loads(process.stdout)
                    for issue in bandit_results.get("results", []):
                        severity = issue.get("issue_severity", "info").lower()
                        if severity in result["vulnerabilities"]:
                            result["vulnerabilities"][severity].append({
                                "file": issue.get("filename", ""),
                                "line": issue.get("line_number", 0),
                                "issue": issue.get("issue_text", ""),
                                "confidence": issue.get("issue_confidence", "")
                            })
                except json.JSONDecodeError:
                    pass

        except (FileNotFoundError, subprocess.CalledProcessError):
            result["vulnerabilities"]["info"].append({
                "file": "system",
                "issue": "bandit not available for Python security scanning"
            })

        # Basic shell script security checks
        for sh_file in self.project_root.glob("**/*.sh"):
            try:
                content = sh_file.read_text()
                issues = []

                # Check for dangerous patterns
                if "rm -rf /" in content:
                    issues.append("Dangerous: rm -rf /")
                if "chmod 777" in content:
                    issues.append("Dangerous: chmod 777")
                if "sudo" in content and "password" in content.lower():
                    issues.append("Potential password exposure")

                for issue in issues:
                    result["vulnerabilities"]["high"].append({
                        "file": str(sh_file),
                        "issue": issue
                    })

            except:
                pass

        return result

    def _check_documentation(self) -> Dict[str, Any]:
        """Check documentation quality"""
        result = {"status": "unknown", "score": 0, "issues": []}

        # Check for README files
        readme_files = list(self.project_root.glob("README*"))
        if not readme_files:
            result["issues"].append("Missing README file")
            result["score"] -= 20

        # Check for docstrings in Python files
        python_files = list(self.project_root.glob("**/*.py"))
        files_with_docstrings = 0

        for py_file in python_files:
            try:
                content = py_file.read_text()
                if '"""' in content or "'''" in content:
                    files_with_docstrings += 1
            except:
                pass

        if python_files:
            docstring_ratio = files_with_docstrings / len(python_files)
            if docstring_ratio < 0.5:
                result["issues"].append(f"Low docstring coverage: {docstring_ratio:.1%}")
                result["score"] -= 10

        result["score"] = max(0, min(100, 100 + result["score"]))
        result["status"] = "passed" if result["score"] >= 80 else "warning" if result["score"] >= 60 else "failed"

        return result

    def _check_naming_conventions(self) -> Dict[str, Any]:
        """Check naming conventions"""
        result = {"status": "unknown", "score": 0, "issues": []}

        # Check Python naming
        for py_file in self.project_root.glob("**/*.py"):
            try:
                content = py_file.read_text()
                lines = content.split('\n')

                for i, line in enumerate(lines, 1):
                    # Check for camelCase in Python (should be snake_case)
                    if "def " in line:
                        # Extract function name
                        parts = line.split("def ")[1].split("(")[0].strip()
                        if any(c.isupper() for c in parts[1:]):  # Skip first char
                            result["issues"].append(f"{py_file}:{i}: Function '{parts}' should use snake_case")
                            result["score"] -= 5

            except:
                pass

        result["score"] = max(0, min(100, 100 + result["score"]))
        result["status"] = "passed" if result["score"] >= 80 else "warning" if result["score"] >= 60 else "failed"

        return result

    def _check_code_structure(self) -> Dict[str, Any]:
        """Check code structure and organization"""
        result = {"status": "unknown", "score": 0, "issues": []}

        # Check for proper directory structure
        required_dirs = ["scripts", "vendor", "tests", "docs"]
        for req_dir in required_dirs:
            if not (self.project_root / req_dir).exists():
                result["issues"].append(f"Missing required directory: {req_dir}")
                result["score"] -= 10

        # Check for proper file organization
        python_files = list(self.project_root.glob("**/*.py"))
        if len(python_files) > 10:  # If we have many Python files
            # Check if they're organized in packages
            py_dirs = [f.parent for f in python_files if f.parent != self.project_root]
            if len(set(py_dirs)) < 3:  # Few directories for many files
                result["issues"].append("Python files may need better organization into packages")
                result["score"] -= 10

        result["score"] = max(0, min(100, 100 + result["score"]))
        result["status"] = "passed" if result["score"] >= 80 else "warning" if result["score"] >= 60 else "failed"

        return result

    def _check_best_practices(self) -> Dict[str, Any]:
        """Check adherence to best practices"""
        result = {"status": "unknown", "score": 0, "issues": []}

        # Check for hardcoded secrets
        secret_patterns = ["password", "secret", "key", "token"]
        for file in self.project_root.glob("**/*"):
            if file.is_file() and not file.name.endswith(('.pyc', '.pyo', '__pycache__')):
                try:
                    content = file.read_text().lower()
                    for pattern in secret_patterns:
                        if pattern in content and ("hardcoded" in content or "=" in content):
                            result["issues"].append(f"Potential hardcoded {pattern} in {file}")
                            result["score"] -= 15
                            break
                except:
                    pass

        # Check for TODO comments (should be tracked properly)
        todo_count = 0
        for file in self.project_root.glob("**/*"):
            if file.is_file():
                try:
                    content = file.read_text()
                    todo_count += content.upper().count("TODO")
                except:
                    pass

        if todo_count > 20:  # Too many TODOs
            result["issues"].append(f"High TODO count: {todo_count} items need attention")
            result["score"] -= 10

        result["score"] = max(0, min(100, 100 + result["score"]))
        result["status"] = "passed" if result["score"] >= 80 else "warning" if result["score"] >= 60 else "failed"

        return result

    def _calculate_overall_status(self, gate_results: Dict[str, Any]) -> str:
        """Calculate overall quality gate status"""
        statuses = [result.get("status", "unknown") for result in gate_results.values()]

        if "failed" in statuses:
            return "failed"
        elif "warning" in statuses:
            return "warning"
        elif all(status == "passed" for status in statuses):
            return "passed"
        else:
            return "unknown"

    def _generate_summary(self, gate_results: Dict[str, Any]) -> Dict[str, Any]:
        """Generate summary of all quality gate results"""
        summary = {
            "total_gates": len(gate_results),
            "passed_gates": 0,
            "warning_gates": 0,
            "failed_gates": 0,
            "critical_issues": []
        }

        for gate_name, result in gate_results.items():
            status = result.get("status", "unknown")
            if status == "passed":
                summary["passed_gates"] += 1
            elif status == "warning":
                summary["warning_gates"] += 1
            elif status == "failed":
                summary["failed_gates"] += 1

            # Collect critical issues
            if status == "failed":
                summary["critical_issues"].append(f"❌ {gate_name}: Failed quality checks")

        return summary

    def _save_results(self, results: Dict[str, Any]) -> None:
        """Save quality gate results to file"""
        timestamp = int(results["timestamp"])
        report_file = self.reports_dir / f"quality-gate-report-{timestamp}.json"

        with open(report_file, 'w') as f:
            json.dump(results, f, indent=2, default=str)

        print(f"\n📄 Quality gate report saved to: {report_file}")


def main():
    """Main quality gate runner function"""
    project_root = Path(__file__).parent.parent

    print("🚀 BrewNix Code Quality Gates - Phase 5.1.2")
    print("=" * 50)

    quality_manager = QualityGateManager(project_root)
    results = quality_manager.run_all_quality_gates()

    # Print final results
    print("\n" + "=" * 50)
    print("🎯 QUALITY GATE RESULTS")
    print("=" * 50)

    print(f"\n🏆 Overall Status: {results['overall_status'].upper()}")

    print("\n📊 Gate Results:")
    for gate_name, gate_result in results['gates'].items():
        status = gate_result.get('status', 'unknown')
        status_icon = "✅" if status == "passed" else "⚠️" if status == "warning" else "❌"
        print(f"  {status_icon} {gate_name.capitalize()}: {status.upper()}")

    summary = results['summary']
    print("\n📈 Summary:")
    print(f"  Total Gates: {summary['total_gates']}")
    print(f"  Passed: {summary['passed_gates']}")
    print(f"  Warnings: {summary['warning_gates']}")
    print(f"  Failed: {summary['failed_gates']}")

    if summary['critical_issues']:
        print("\n🚨 Critical Issues:")
        for issue in summary['critical_issues']:
            print(f"  {issue}")

    print("\n" + "=" * 50)

    # Exit with appropriate code
    if results['overall_status'] == 'passed':
        print("🎉 All quality gates passed!")
        sys.exit(0)
    elif results['overall_status'] == 'warning':
        print("⚠️ Quality gates passed with warnings")
        sys.exit(0)  # Allow progression with warnings
    else:
        print("❌ Quality gates failed - fix issues before proceeding")
        sys.exit(1)


if __name__ == "__main__":
    main()
