#!/usr/bin/env python3
"""
BrewNix Code Review Automation
Automated code review tools and best practices validation
"""

import os
import re
import ast
from pathlib import Path
from typing import Dict, List, Any, Optional


class CodeReviewAutomator:
    """Automated code review and best practices validation"""

    def __init__(self, project_root: Path):
        self.project_root = project_root
        self.issues = {
            "style": [],
            "logic": [],
            "security": [],
            "performance": [],
            "maintainability": []
        }

    def run_full_review(self) -> Dict[str, Any]:
        """Run comprehensive code review"""
        print("🔍 Running Automated Code Review...")

        results = {
            "issues": self.issues.copy(),
            "summary": {},
            "languages": {},
            "recommendations": [],
            "score": 0
        }

        # Review Python files
        python_results = self.review_python_files()
        if python_results:
            results["languages"]["python"] = python_results

        # Review shell scripts
        shell_results = self.review_shell_scripts()
        if shell_results:
            results["languages"]["shell"] = shell_results

        # Review configuration files
        config_results = self.review_config_files()
        if config_results:
            results["languages"]["config"] = config_results

        # Review documentation
        docs_results = self.review_documentation()
        if docs_results:
            results["languages"]["documentation"] = docs_results

        # Calculate summary and score
        results["summary"] = self._calculate_summary()
        results["score"] = self._calculate_score()
        results["recommendations"] = self._generate_recommendations()

        return results

    def review_python_files(self) -> Optional[Dict[str, Any]]:
        """Review Python files for best practices"""
        python_files = list(self.project_root.glob("**/*.py"))
        if not python_files:
            return None

        results = {
            "files_reviewed": len(python_files),
            "issues": []
        }

        for py_file in python_files:
            try:
                file_issues = self._review_python_file(py_file)
                results["issues"].extend(file_issues)
            except Exception as e:
                print(f"⚠️ Error reviewing {py_file}: {e}")

        return results

    def _review_python_file(self, file_path: Path) -> List[Dict[str, Any]]:
        """Review a single Python file"""
        issues = []

        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()

            lines = content.split('\n')

            # Parse AST for structural analysis
            try:
                tree = ast.parse(content)
                ast_issues = self._analyze_ast(tree, str(file_path))
                issues.extend(ast_issues)
            except SyntaxError as e:
                issues.append({
                    "file": str(file_path),
                    "line": e.lineno or 0,
                    "category": "logic",
                    "severity": "high",
                    "issue": f"Syntax error: {e.msg}",
                    "recommendation": "Fix syntax error before proceeding"
                })

            # Line-by-line analysis
            for i, line in enumerate(lines, 1):
                line_clean = line.strip()

                # Skip empty lines and comments
                if not line_clean or line_clean.startswith('#'):
                    continue

                line_issues = self._analyze_python_line(line_clean, i, str(file_path))
                issues.extend(line_issues)

        except Exception as e:
            issues.append({
                "file": str(file_path),
                "line": 0,
                "category": "logic",
                "severity": "info",
                "issue": f"Could not review file: {e}",
                "recommendation": "Check file permissions and encoding"
            })

        return issues

    def _analyze_ast(self, tree: ast.AST, file_path: str) -> List[Dict[str, Any]]:
        """Analyze Python AST for structural issues"""
        issues = []

        class CodeAnalyzer(ast.NodeVisitor):
            def __init__(self, file_path):
                self.file_path = file_path
                self.issues = []

            def visit_FunctionDef(self, node):
                # Check function length
                if len(node.body) > 50:
                    self.issues.append({
                        "file": self.file_path,
                        "line": node.lineno,
                        "category": "maintainability",
                        "severity": "medium",
                        "issue": f"Function '{node.name}' is too long ({len(node.body)} lines)",
                        "recommendation": "Break down into smaller functions (max 30 lines)"
                    })

                # Check parameter count
                if len(node.args.args) > 5:
                    self.issues.append({
                        "file": self.file_path,
                        "line": node.lineno,
                        "category": "maintainability",
                        "severity": "medium",
                        "issue": f"Function '{node.name}' has too many parameters ({len(node.args.args)})",
                        "recommendation": "Use a configuration object or reduce parameters"
                    })

                self.generic_visit(node)

            def visit_ClassDef(self, node):
                # Check class length
                if len(node.body) > 200:
                    self.issues.append({
                        "file": self.file_path,
                        "line": node.lineno,
                        "category": "maintainability",
                        "severity": "medium",
                        "issue": f"Class '{node.name}' is too large ({len(node.body)} lines)",
                        "recommendation": "Split into smaller classes or modules"
                    })

                self.generic_visit(node)

            def visit_If(self, node):
                # Check nested if statements
                def count_nested_ifs(node, depth=0):
                    max_depth = depth
                    if isinstance(node, ast.If):
                        max_depth = max(max_depth, depth + 1)
                        for child in node.body + node.orelse:
                            max_depth = max(max_depth, count_nested_ifs(child, depth + 1))
                    return max_depth

                nested_depth = count_nested_ifs(node)
                if nested_depth > 3:
                    self.issues.append({
                        "file": self.file_path,
                        "line": node.lineno,
                        "category": "maintainability",
                        "severity": "medium",
                        "issue": f"Deeply nested if statements (depth {nested_depth})",
                        "recommendation": "Extract nested logic into separate functions"
                    })

                self.generic_visit(node)

        analyzer = CodeAnalyzer(file_path)
        analyzer.visit(tree)
        return analyzer.issues

    def _analyze_python_line(self, line: str, line_num: int, file_path: str) -> List[Dict[str, Any]]:
        """Analyze a single line of Python code"""
        issues = []

        # Check line length
        if len(line) > 88:  # PEP 8 recommends 79, but 88 is common
            issues.append({
                "file": file_path,
                "line": line_num,
                "category": "style",
                "severity": "low",
                "issue": f"Line too long ({len(line)} characters)",
                "recommendation": "Break line to fit within 88 characters"
            })

        # Check for TODO comments
        if "TODO" in line.upper():
            issues.append({
                "file": file_path,
                "line": line_num,
                "category": "maintainability",
                "severity": "low",
                "issue": "TODO comment found",
                "recommendation": "Address TODO or convert to proper issue tracking"
            })

        # Check for print statements in production code
        if "print(" in line and not file_path.endswith("test.py"):
            issues.append({
                "file": file_path,
                "line": line_num,
                "category": "style",
                "severity": "medium",
                "issue": "Print statement in production code",
                "recommendation": "Use proper logging instead of print statements"
            })

        # Check for bare except clauses
        if "except:" in line and "Exception" not in line:
            issues.append({
                "file": file_path,
                "line": line_num,
                "category": "logic",
                "severity": "medium",
                "issue": "Bare except clause",
                "recommendation": "Specify exception types to catch"
            })

        # Check for magic numbers
        magic_numbers = re.findall(r'\b\d{2,}\b', line)
        for num in magic_numbers:
            if num not in ['0', '1', '100']:  # Common acceptable numbers
                issues.append({
                    "file": file_path,
                    "line": line_num,
                    "category": "maintainability",
                    "severity": "low",
                    "issue": f"Magic number '{num}' found",
                    "recommendation": "Replace with named constant"
                })

        return issues

    def review_shell_scripts(self) -> Optional[Dict[str, Any]]:
        """Review shell scripts for best practices"""
        shell_files = list(self.project_root.glob("**/*.sh"))
        if not shell_files:
            return None

        results = {
            "files_reviewed": len(shell_files),
            "issues": []
        }

        for sh_file in shell_files:
            try:
                file_issues = self._review_shell_file(sh_file)
                results["issues"].extend(file_issues)
            except Exception as e:
                print(f"⚠️ Error reviewing {sh_file}: {e}")

        return results

    def _review_shell_file(self, file_path: Path) -> List[Dict[str, Any]]:
        """Review a single shell script"""
        issues = []

        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()

            lines = content.split('\n')

            for i, line in enumerate(lines, 1):
                line_clean = line.strip()

                # Skip empty lines and comments
                if not line_clean or line_clean.startswith('#'):
                    continue

                line_issues = self._analyze_shell_line(line_clean, i, str(file_path))
                issues.extend(line_issues)

        except Exception as e:
            issues.append({
                "file": str(file_path),
                "line": 0,
                "category": "logic",
                "severity": "info",
                "issue": f"Could not review file: {e}",
                "recommendation": "Check file permissions and encoding"
            })

        return issues

    def _analyze_shell_line(self, line: str, line_num: int, file_path: str) -> List[Dict[str, Any]]:
        """Analyze a single line of shell script"""
        issues = []

        # Check for unquoted variables
        if re.search(r'\$[A-Za-z_][A-Za-z0-9_]*[^"]', line):
            issues.append({
                "file": file_path,
                "line": line_num,
                "category": "logic",
                "severity": "medium",
                "issue": "Unquoted variable expansion",
                "recommendation": "Quote variable expansions to prevent word splitting"
            })

        # Check for set -e missing
        if line_num == 1 and "set -e" not in line:
            issues.append({
                "file": file_path,
                "line": line_num,
                "category": "logic",
                "severity": "medium",
                "issue": "Missing 'set -e' for error handling",
                "recommendation": "Add 'set -e' at script beginning to exit on errors"
            })

        # Check for hardcoded paths
        if "/usr/local" in line or "/opt/" in line:
            issues.append({
                "file": file_path,
                "line": line_num,
                "category": "maintainability",
                "severity": "low",
                "issue": "Hardcoded system path",
                "recommendation": "Use variables for configurable paths"
            })

        return issues

    def review_config_files(self) -> Optional[Dict[str, Any]]:
        """Review configuration files"""
        config_files = []
        config_patterns = ["**/*.yml", "**/*.yaml", "**/*.json", "**/*.conf", "**/*.ini"]

        for pattern in config_patterns:
            config_files.extend(list(self.project_root.glob(pattern)))

        if not config_files:
            return None

        results = {
            "files_reviewed": len(config_files),
            "issues": []
        }

        for config_file in config_files:
            try:
                file_issues = self._review_config_file(config_file)
                results["issues"].extend(file_issues)
            except Exception as e:
                print(f"⚠️ Error reviewing {config_file}: {e}")

        return results

    def _review_config_file(self, file_path: Path) -> List[Dict[str, Any]]:
        """Review a configuration file"""
        issues = []

        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()

            lines = content.split('\n')

            for i, line in enumerate(lines, 1):
                line_clean = line.strip()

                # Check for commented out code
                if line_clean.startswith('#') and ('=' in line_clean or ':' in line_clean):
                    issues.append({
                        "file": str(file_path),
                        "line": i,
                        "category": "maintainability",
                        "severity": "low",
                        "issue": "Commented out configuration",
                        "recommendation": "Remove commented configuration or document why it's disabled"
                    })

        except Exception as e:
            issues.append({
                "file": str(file_path),
                "line": 0,
                "category": "logic",
                "severity": "info",
                "issue": f"Could not review config file: {e}",
                "recommendation": "Check file permissions and format"
            })

        return issues

    def review_documentation(self) -> Optional[Dict[str, Any]]:
        """Review documentation completeness"""
        results = {
            "issues": []
        }

        # Check for README files
        readme_files = list(self.project_root.glob("**/README*"))
        if not readme_files:
            results["issues"].append({
                "file": "project_root",
                "line": 0,
                "category": "maintainability",
                "severity": "medium",
                "issue": "Missing README file",
                "recommendation": "Add README.md with project description and setup instructions"
            })

        # Check for docstrings in Python files
        python_files = list(self.project_root.glob("**/*.py"))
        undocumented_functions = 0

        for py_file in python_files:
            try:
                with open(py_file, 'r', encoding='utf-8') as f:
                    content = f.read()

                tree = ast.parse(content)
                for node in ast.walk(tree):
                    if isinstance(node, (ast.FunctionDef, ast.ClassDef)):
                        if not ast.get_docstring(node):
                            undocumented_functions += 1
            except:
                pass

        if undocumented_functions > 0:
            results["issues"].append({
                "file": "multiple_files",
                "line": 0,
                "category": "maintainability",
                "severity": "low",
                "issue": f"{undocumented_functions} functions/classes missing docstrings",
                "recommendation": "Add docstrings to all public functions and classes"
            })

        return results if results["issues"] else None

    def _calculate_summary(self) -> Dict[str, Any]:
        """Calculate review summary"""
        summary = {
            "total_issues": 0,
            "style_count": 0,
            "logic_count": 0,
            "security_count": 0,
            "performance_count": 0,
            "maintainability_count": 0
        }

        for category in ["style", "logic", "security", "performance", "maintainability"]:
            count = len(self.issues[category])
            summary[f"{category}_count"] = count
            summary["total_issues"] += count

        return summary

    def _calculate_score(self) -> int:
        """Calculate code quality score (0-100)"""
        summary = self._calculate_summary()

        # Base score
        score = 100

        # Deduct points for issues
        deductions = {
            "style": 1,
            "logic": 5,
            "security": 10,
            "performance": 3,
            "maintainability": 2
        }

        for category, deduction in deductions.items():
            count = summary[f"{category}_count"]
            score -= min(count * deduction, 20)  # Cap deduction per category

        return max(0, score)

    def _generate_recommendations(self) -> List[str]:
        """Generate review recommendations"""
        recommendations = []
        summary = self._calculate_summary()
        score = self._calculate_score()

        if score >= 90:
            recommendations.append("✅ Excellent code quality!")
        elif score >= 75:
            recommendations.append("👍 Good code quality with minor improvements needed")
        elif score >= 60:
            recommendations.append("⚠️ Code quality needs attention")
        else:
            recommendations.append("🚨 Code quality requires significant improvements")

        if summary["logic_count"] > 0:
            recommendations.append(f"🔧 Fix {summary['logic_count']} logic issues for better reliability")

        if summary["security_count"] > 0:
            recommendations.append(f"🔒 Address {summary['security_count']} security concerns")

        if summary["maintainability_count"] > 0:
            recommendations.append(f"📚 Improve {summary['maintainability_count']} maintainability issues")

        recommendations.extend([
            "📖 Add comprehensive docstrings to all public functions",
            "🧪 Ensure all code is covered by unit tests",
            "🔄 Run automated tests before committing changes",
            "👥 Consider code reviews for complex changes"
        ])

        return recommendations

    def print_report(self, results: Dict[str, Any]) -> None:
        """Print a formatted code review report"""
        print("\n🔍 CODE REVIEW REPORT")
        print("=" * 50)

        summary = results["summary"]
        score = results["score"]

        print(f"\n📊 Overall Score: {score}/100")

        if score >= 90:
            print("🎉 Excellent!")
        elif score >= 75:
            print("👍 Good")
        elif score >= 60:
            print("⚠️ Needs Improvement")
        else:
            print("🚨 Requires Attention")

        print("\n📈 Summary:")
        print(f"  Total Issues: {summary['total_issues']}")
        print(f"  Style: {summary['style_count']}")
        print(f"  Logic: {summary['logic_count']}")
        print(f"  Security: {summary['security_count']}")
        print(f"  Performance: {summary['performance_count']}")
        print(f"  Maintainability: {summary['maintainability_count']}")

        for category in ["logic", "security", "performance", "maintainability", "style"]:
            issues = self.issues[category]
            if issues:
                print(f"\n{category.upper()} Issues:")
                for issue in issues[:3]:  # Show first 3
                    print(f"  • {issue['file']}:{issue['line']} - {issue['issue']}")

        if results["recommendations"]:
            print("\n💡 Recommendations:")
            for rec in results["recommendations"]:
                print(f"  {rec}")

        print("\n" + "=" * 50)


def main():
    """Main code review function"""
    project_root = Path(__file__).parent.parent.parent

    reviewer = CodeReviewAutomator(project_root)
    results = reviewer.run_full_review()
    reviewer.print_report(results)

    # Save results
    reports_dir = project_root / "quality-gates" / "review"
    reports_dir.mkdir(parents=True, exist_ok=True)

    import json
    import time
    report_file = reports_dir / f"review-report-{int(time.time())}.json"

    with open(report_file, 'w') as f:
        json.dump(results, f, indent=2)

    print(f"\n📄 Code review report saved to: {report_file}")


if __name__ == "__main__":
    main()
