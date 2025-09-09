#!/usr/bin/env python3
"""
BrewNix Security Scanner
Comprehensive security vulnerability scanning for multiple languages
"""

import os
import re
import subprocess
from pathlib import Path
from typing import Dict, List, Any, Optional


class SecurityScanner:
    """Scans for security vulnerabilities in code"""

    def __init__(self, project_root: Path):
        self.project_root = project_root
        self.vulnerabilities = {
            "critical": [],
            "high": [],
            "medium": [],
            "low": [],
            "info": []
        }

    def scan_all_files(self) -> Dict[str, Any]:
        """Scan all files for security vulnerabilities"""
        print("🔒 Scanning for Security Vulnerabilities...")

        results = {
            "vulnerabilities": self.vulnerabilities.copy(),
            "summary": {},
            "languages": {},
            "recommendations": []
        }

        # Scan Python files
        python_results = self.scan_python_files()
        if python_results:
            results["languages"]["python"] = python_results

        # Scan shell scripts
        shell_results = self.scan_shell_scripts()
        if shell_results:
            results["languages"]["shell"] = shell_results

        # Scan configuration files
        config_results = self.scan_config_files()
        if config_results:
            results["languages"]["config"] = config_results

        # Scan for general security issues
        general_results = self.scan_general_security()
        if general_results:
            results["languages"]["general"] = general_results

        # Calculate summary
        results["summary"] = self._calculate_summary()
        results["recommendations"] = self._generate_recommendations()

        return results

    def scan_python_files(self) -> Optional[Dict[str, Any]]:
        """Scan Python files for security vulnerabilities"""
        python_files = list(self.project_root.glob("**/*.py"))
        if not python_files:
            return None

        results = {
            "files_scanned": len(python_files),
            "vulnerabilities": []
        }

        for py_file in python_files:
            try:
                file_vulns = self._scan_python_file(py_file)
                results["vulnerabilities"].extend(file_vulns)
            except Exception as e:
                print(f"⚠️ Error scanning {py_file}: {e}")

        return results

    def _scan_python_file(self, file_path: Path) -> List[Dict[str, Any]]:
        """Scan a single Python file"""
        vulnerabilities = []

        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()

            lines = content.split('\n')

            for i, line in enumerate(lines, 1):
                line_clean = line.strip()

                # Check for dangerous patterns
                vuln = self._check_python_vulnerability(line_clean, i, str(file_path))
                if vuln:
                    vulnerabilities.append(vuln)

        except Exception as e:
            vulnerabilities.append({
                "file": str(file_path),
                "line": 0,
                "severity": "info",
                "issue": f"Could not scan file: {e}",
                "recommendation": "Check file permissions and encoding"
            })

        return vulnerabilities

    def _check_python_vulnerability(self, line: str, line_num: int, file_path: str) -> Optional[Dict[str, Any]]:
        """Check a line for Python security vulnerabilities"""

        # Dangerous function calls
        dangerous_functions = {
            "eval(": {"severity": "critical", "issue": "Use of eval() function", "recommendation": "Avoid eval() - use ast.literal_eval() for safe evaluation"},
            "exec(": {"severity": "critical", "issue": "Use of exec() function", "recommendation": "Avoid exec() - find alternative implementation"},
            "os.system(": {"severity": "high", "issue": "Use of os.system()", "recommendation": "Use subprocess.run() instead"},
            "subprocess.call(": {"severity": "medium", "issue": "Use of subprocess.call()", "recommendation": "Use subprocess.run() for better security"},
            "pickle.load(": {"severity": "high", "issue": "Use of pickle.load()", "recommendation": "Avoid pickle for untrusted data - use json instead"},
            "yaml.load(": {"severity": "high", "issue": "Unsafe YAML loading", "recommendation": "Use yaml.safe_load() instead"},
            "input(": {"severity": "medium", "issue": "Use of input() in Python 2 style", "recommendation": "Use proper input validation"}
        }

        for pattern, vuln_info in dangerous_functions.items():
            if pattern in line:
                return {
                    "file": file_path,
                    "line": line_num,
                    "severity": vuln_info["severity"],
                    "issue": vuln_info["issue"],
                    "code": line,
                    "recommendation": vuln_info["recommendation"]
                }

        # Hardcoded secrets
        secret_patterns = [
            r'password\s*=\s*["\'][^"\']*["\']',
            r'secret\s*=\s*["\'][^"\']*["\']',
            r'key\s*=\s*["\'][^"\']*["\']',
            r'token\s*=\s*["\'][^"\']*["\']'
        ]

        for pattern in secret_patterns:
            if re.search(pattern, line, re.IGNORECASE):
                return {
                    "file": file_path,
                    "line": line_num,
                    "severity": "high",
                    "issue": "Potential hardcoded secret",
                    "code": line,
                    "recommendation": "Move secrets to environment variables or secure config files"
                }

        # SQL injection patterns
        sql_patterns = [
            r'execute\s*\(\s*["\'].*?%.*["\']',
            r'cursor\.execute\s*\(\s*f["\']',
            r'["\'].*?\s*\+.*?\s*["\'].*?execute'
        ]

        for pattern in sql_patterns:
            if re.search(pattern, line):
                return {
                    "file": file_path,
                    "line": line_num,
                    "severity": "high",
                    "issue": "Potential SQL injection vulnerability",
                    "code": line,
                    "recommendation": "Use parameterized queries or ORM instead of string formatting"
                }

        # Path traversal
        if "../" in line or "..\\" in line:
            return {
                "file": file_path,
                "line": line_num,
                "severity": "medium",
                "issue": "Potential path traversal vulnerability",
                "code": line,
                "recommendation": "Validate and sanitize file paths"
            }

        return None

    def scan_shell_scripts(self) -> Optional[Dict[str, Any]]:
        """Scan shell scripts for security vulnerabilities"""
        shell_files = list(self.project_root.glob("**/*.sh"))
        if not shell_files:
            return None

        results = {
            "files_scanned": len(shell_files),
            "vulnerabilities": []
        }

        for sh_file in shell_files:
            try:
                file_vulns = self._scan_shell_file(sh_file)
                results["vulnerabilities"].extend(file_vulns)
            except Exception as e:
                print(f"⚠️ Error scanning {sh_file}: {e}")

        return results

    def _scan_shell_file(self, file_path: Path) -> List[Dict[str, Any]]:
        """Scan a single shell script"""
        vulnerabilities = []

        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()

            lines = content.split('\n')

            for i, line in enumerate(lines, 1):
                line_clean = line.strip()

                # Check for shell vulnerabilities
                vuln = self._check_shell_vulnerability(line_clean, i, str(file_path))
                if vuln:
                    vulnerabilities.append(vuln)

        except Exception as e:
            vulnerabilities.append({
                "file": str(file_path),
                "line": 0,
                "severity": "info",
                "issue": f"Could not scan file: {e}",
                "recommendation": "Check file permissions and encoding"
            })

        return vulnerabilities

    def _check_shell_vulnerability(self, line: str, line_num: int, file_path: str) -> Optional[Dict[str, Any]]:
        """Check a line for shell security vulnerabilities"""

        # Dangerous commands
        dangerous_commands = {
            "rm -rf /": {"severity": "critical", "issue": "Dangerous rm command", "recommendation": "Never use rm -rf / - specify exact paths"},
            "chmod 777": {"severity": "high", "issue": "Overly permissive permissions", "recommendation": "Use minimal required permissions"},
            "curl | bash": {"severity": "high", "issue": "Piping curl to bash", "recommendation": "Download script first, review it, then execute"},
            "wget | bash": {"severity": "high", "issue": "Piping wget to bash", "recommendation": "Download script first, review it, then execute"},
            "sudo ": {"severity": "medium", "issue": "Use of sudo", "recommendation": "Minimize sudo usage and use specific permissions"}
        }

        for pattern, vuln_info in dangerous_commands.items():
            if pattern in line:
                return {
                    "file": file_path,
                    "line": line_num,
                    "severity": vuln_info["severity"],
                    "issue": vuln_info["issue"],
                    "code": line,
                    "recommendation": vuln_info["recommendation"]
                }

        # Variable injection
        if "$" in line and ("eval" in line or "source" in line):
            return {
                "file": file_path,
                "line": line_num,
                "severity": "high",
                "issue": "Potential command injection via variable",
                "code": line,
                "recommendation": "Validate and sanitize variables before using in commands"
            }

        # Hardcoded passwords
        password_patterns = [
            r'password\s*=\s*["\'][^"\']*["\']',
            r'PASSWORD\s*=\s*["\'][^"\']*["\']',
            r'passwd\s*=\s*["\'][^"\']*["\']'
        ]

        for pattern in password_patterns:
            if re.search(pattern, line, re.IGNORECASE):
                return {
                    "file": file_path,
                    "line": line_num,
                    "severity": "high",
                    "issue": "Potential hardcoded password",
                    "code": line,
                    "recommendation": "Use environment variables or secure credential storage"
                }

        return None

    def scan_config_files(self) -> Optional[Dict[str, Any]]:
        """Scan configuration files for security issues"""
        config_files = []
        config_patterns = ["**/*.yml", "**/*.yaml", "**/*.json", "**/*.conf", "**/*.ini"]

        for pattern in config_patterns:
            config_files.extend(list(self.project_root.glob(pattern)))

        if not config_files:
            return None

        results = {
            "files_scanned": len(config_files),
            "vulnerabilities": []
        }

        for config_file in config_files:
            try:
                file_vulns = self._scan_config_file(config_file)
                results["vulnerabilities"].extend(file_vulns)
            except Exception as e:
                print(f"⚠️ Error scanning {config_file}: {e}")

        return results

    def _scan_config_file(self, file_path: Path) -> List[Dict[str, Any]]:
        """Scan a configuration file"""
        vulnerabilities = []

        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()

            lines = content.split('\n')

            for i, line in enumerate(lines, 1):
                line_clean = line.strip()

                # Check for exposed secrets
                if any(keyword in line_clean.lower() for keyword in ["password", "secret", "key", "token"]):
                    if "=" in line_clean or ":" in line_clean:
                        vulnerabilities.append({
                            "file": str(file_path),
                            "line": i,
                            "severity": "medium",
                            "issue": "Potential sensitive data in config file",
                            "code": line_clean,
                            "recommendation": "Move sensitive data to environment variables or secure vaults"
                        })

        except Exception as e:
            vulnerabilities.append({
                "file": str(file_path),
                "line": 0,
                "severity": "info",
                "issue": f"Could not scan config file: {e}",
                "recommendation": "Check file permissions and format"
            })

        return vulnerabilities

    def scan_general_security(self) -> Optional[Dict[str, Any]]:
        """Scan for general security issues"""
        results = {
            "vulnerabilities": []
        }

        # Check for world-writable files
        for file_path in self.project_root.glob("**/*"):
            if file_path.is_file():
                try:
                    stat_info = file_path.stat()
                    # Check if world-writable
                    if stat_info.st_mode & 0o002:
                        results["vulnerabilities"].append({
                            "file": str(file_path),
                            "line": 0,
                            "severity": "medium",
                            "issue": "World-writable file",
                            "code": f"Permissions: {oct(stat_info.st_mode)}",
                            "recommendation": "Remove world-write permissions: chmod o-w"
                        })
                except:
                    pass

        # Check for large files that might contain sensitive data
        for file_path in self.project_root.glob("**/*"):
            if file_path.is_file():
                try:
                    size = file_path.stat().st_size
                    if size > 100 * 1024 * 1024:  # 100MB
                        results["vulnerabilities"].append({
                            "file": str(file_path),
                            "line": 0,
                            "severity": "low",
                            "issue": "Very large file",
                            "code": f"Size: {size} bytes",
                            "recommendation": "Consider if this file should be in version control"
                        })
                except:
                    pass

        return results if results["vulnerabilities"] else None

    def _calculate_summary(self) -> Dict[str, Any]:
        """Calculate vulnerability summary"""
        summary = {
            "total_vulnerabilities": 0,
            "critical_count": 0,
            "high_count": 0,
            "medium_count": 0,
            "low_count": 0,
            "info_count": 0
        }

        for severity in ["critical", "high", "medium", "low", "info"]:
            count = len(self.vulnerabilities[severity])
            summary[f"{severity}_count"] = count
            summary["total_vulnerabilities"] += count

        return summary

    def _generate_recommendations(self) -> List[str]:
        """Generate security recommendations"""
        recommendations = []
        summary = self._calculate_summary()

        if summary["critical_count"] > 0:
            recommendations.append(f"🚨 Address {summary['critical_count']} critical vulnerabilities immediately")

        if summary["high_count"] > 0:
            recommendations.append(f"⚠️ Fix {summary['high_count']} high-severity issues before deployment")

        if summary["medium_count"] > 0:
            recommendations.append(f"📋 Review {summary['medium_count']} medium-severity issues")

        if summary["total_vulnerabilities"] == 0:
            recommendations.append("✅ No security vulnerabilities found")

        recommendations.extend([
            "🔐 Use environment variables for sensitive configuration",
            "🛡️ Implement input validation and sanitization",
            "📝 Use parameterized queries to prevent SQL injection",
            "🔒 Apply principle of least privilege for file permissions",
            "🔍 Regularly scan for vulnerabilities in dependencies"
        ])

        return recommendations

    def print_report(self, results: Dict[str, Any]) -> None:
        """Print a formatted security report"""
        print("\n🔒 SECURITY SCAN REPORT")
        print("=" * 50)

        summary = results["summary"]
        print("\n📊 Summary:")
        print(f"  Total Vulnerabilities: {summary['total_vulnerabilities']}")
        print(f"  Critical: {summary['critical_count']}")
        print(f"  High: {summary['high_count']}")
        print(f"  Medium: {summary['medium_count']}")
        print(f"  Low: {summary['low_count']}")
        print(f"  Info: {summary['info_count']}")

        for severity in ["critical", "high", "medium", "low", "info"]:
            vulns = [v for v in self.vulnerabilities[severity]]
            if vulns:
                print(f"\n{severity.upper()} Severity:")
                for vuln in vulns[:5]:  # Show first 5
                    print(f"  • {vuln['file']}:{vuln['line']} - {vuln['issue']}")

        if results["recommendations"]:
            print("\n💡 Recommendations:")
            for rec in results["recommendations"]:
                print(f"  {rec}")

        print("\n" + "=" * 50)


def main():
    """Main security scanning function"""
    project_root = Path(__file__).parent.parent.parent

    scanner = SecurityScanner(project_root)
    results = scanner.scan_all_files()
    scanner.print_report(results)

    # Save results
    reports_dir = project_root / "quality-gates" / "security"
    reports_dir.mkdir(parents=True, exist_ok=True)

    import json
    import time
    report_file = reports_dir / f"security-report-{int(time.time())}.json"

    with open(report_file, 'w') as f:
        json.dump(results, f, indent=2)

    print(f"\n📄 Security report saved to: {report_file}")


if __name__ == "__main__":
    main()
