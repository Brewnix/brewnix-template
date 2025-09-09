#!/usr/bin/env python3
"""
BrewNix Code Complexity Analyzer
Analyzes code complexity across multiple languages and file types
"""

import os
import re
import ast
import subprocess
from pathlib import Path
from typing import Dict, List, Any, Optional


class ComplexityAnalyzer:
    """Analyzes code complexity for various languages"""

    def __init__(self, project_root: Path):
        self.project_root = project_root
        self.thresholds = {
            "cyclomatic": 10,
            "lines_per_function": 50,
            "lines_per_file": 300,
            "nesting_depth": 4
        }

    def analyze_all_files(self) -> Dict[str, Any]:
        """Analyze complexity of all supported files"""
        print("🧠 Analyzing Code Complexity...")

        results = {
            "summary": {
                "total_files": 0,
                "complex_files": 0,
                "high_complexity_functions": 0,
                "long_functions": 0,
                "long_files": 0
            },
            "languages": {},
            "recommendations": []
        }

        # Analyze Python files
        python_results = self.analyze_python_files()
        if python_results:
            results["languages"]["python"] = python_results
            results["summary"]["total_files"] += python_results["file_count"]

        # Analyze shell files
        shell_results = self.analyze_shell_files()
        if shell_results:
            results["languages"]["shell"] = shell_results
            results["summary"]["total_files"] += shell_results["file_count"]

        # Analyze JavaScript/TypeScript files
        js_results = self.analyze_javascript_files()
        if js_results:
            results["languages"]["javascript"] = js_results
            results["summary"]["total_files"] += js_results["file_count"]

        # Calculate summary statistics
        self._calculate_summary_stats(results)

        # Generate recommendations
        results["recommendations"] = self._generate_recommendations(results)

        return results

    def analyze_python_files(self) -> Optional[Dict[str, Any]]:
        """Analyze Python file complexity"""
        python_files = list(self.project_root.glob("**/*.py"))
        if not python_files:
            return None

        results = {
            "file_count": len(python_files),
            "files": [],
            "complex_functions": [],
            "long_functions": [],
            "long_files": []
        }

        for py_file in python_files:
            try:
                file_result = self._analyze_python_file(py_file)
                results["files"].append(file_result)

                # Check for complex functions
                for func in file_result.get("functions", []):
                    if func.get("complexity", 0) > self.thresholds["cyclomatic"]:
                        results["complex_functions"].append({
                            "file": str(py_file),
                            "function": func["name"],
                            "complexity": func["complexity"],
                            "line": func["line"]
                        })

                    if func.get("lines", 0) > self.thresholds["lines_per_function"]:
                        results["long_functions"].append({
                            "file": str(py_file),
                            "function": func["name"],
                            "lines": func["lines"],
                            "line": func["line"]
                        })

                # Check for long files
                if file_result.get("total_lines", 0) > self.thresholds["lines_per_file"]:
                    results["long_files"].append({
                        "file": str(py_file),
                        "lines": file_result["total_lines"]
                    })

            except Exception as e:
                print(f"⚠️ Error analyzing {py_file}: {e}")

        return results

    def _analyze_python_file(self, file_path: Path) -> Dict[str, Any]:
        """Analyze a single Python file"""
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()

        lines = content.split('\n')
        tree = ast.parse(content)

        result = {
            "file": str(file_path),
            "total_lines": len(lines),
            "functions": [],
            "classes": []
        }

        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef):
                func_result = self._analyze_python_function(node, lines)
                result["functions"].append(func_result)

            elif isinstance(node, ast.ClassDef):
                result["classes"].append({
                    "name": node.name,
                    "line": node.lineno,
                    "methods": len([n for n in node.body if isinstance(n, ast.FunctionDef)])
                })

        return result

    def _analyze_python_function(self, node: ast.FunctionDef, lines: List[str]) -> Dict[str, Any]:
        """Analyze a Python function for complexity"""
        start_line = node.lineno - 1
        end_line = getattr(node, 'end_lineno', start_line + 10) - 1

        function_lines = lines[start_line:end_line + 1]
        complexity = self._calculate_cyclomatic_complexity(function_lines)

        return {
            "name": node.name,
            "line": node.lineno,
            "lines": len(function_lines),
            "complexity": complexity,
            "args": len(node.args.args)
        }

    def _calculate_cyclomatic_complexity(self, lines: List[str]) -> int:
        """Calculate cyclomatic complexity of code lines"""
        complexity = 1  # Base complexity

        for line in lines:
            line = line.strip()
            # Count control flow keywords
            if any(keyword in line for keyword in ['if ', 'elif ', 'for ', 'while ', 'case ', '&&', '||']):
                complexity += 1
            if 'except ' in line:
                complexity += 1
            if line.count(' and ') + line.count(' or ') > 0:
                complexity += line.count(' and ') + line.count(' or ')

        return complexity

    def analyze_shell_files(self) -> Optional[Dict[str, Any]]:
        """Analyze shell script complexity"""
        shell_files = list(self.project_root.glob("**/*.sh"))
        if not shell_files:
            return None

        results = {
            "file_count": len(shell_files),
            "files": [],
            "complex_functions": [],
            "long_functions": [],
            "long_files": []
        }

        for sh_file in shell_files:
            try:
                file_result = self._analyze_shell_file(sh_file)
                results["files"].append(file_result)

                # Check for long files
                if file_result.get("total_lines", 0) > self.thresholds["lines_per_file"]:
                    results["long_files"].append({
                        "file": str(sh_file),
                        "lines": file_result["total_lines"]
                    })

                # Check for complex functions
                for func in file_result.get("functions", []):
                    if func.get("lines", 0) > self.thresholds["lines_per_function"]:
                        results["long_functions"].append({
                            "file": str(sh_file),
                            "function": func["name"],
                            "lines": func["lines"],
                            "line": func["line"]
                        })

            except Exception as e:
                print(f"⚠️ Error analyzing {sh_file}: {e}")

        return results

    def _analyze_shell_file(self, file_path: Path) -> Dict[str, Any]:
        """Analyze a single shell script file"""
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()

        lines = content.split('\n')

        result = {
            "file": str(file_path),
            "total_lines": len(lines),
            "functions": []
        }

        # Find function definitions
        for i, line in enumerate(lines):
            # Match function definitions: function_name() { or function function_name {
            func_match = re.match(r'^(?:function\s+)?(\w+)\s*\(\)\s*\{', line.strip())
            if func_match:
                func_name = func_match.group(1)
                # Find function end
                end_line = self._find_shell_function_end(lines, i)
                func_lines = end_line - i if end_line else 10

                result["functions"].append({
                    "name": func_name,
                    "line": i + 1,
                    "lines": func_lines
                })

        return result

    def _find_shell_function_end(self, lines: List[str], start_idx: int) -> Optional[int]:
        """Find the end of a shell function"""
        brace_count = 0
        for i in range(start_idx, len(lines)):
            line = lines[i].strip()
            brace_count += line.count('{') - line.count('}')
            if brace_count == 0 and '}' in line:
                return i
        return None

    def analyze_javascript_files(self) -> Optional[Dict[str, Any]]:
        """Analyze JavaScript/TypeScript file complexity"""
        js_files = list(self.project_root.glob("**/*.js")) + list(self.project_root.glob("**/*.ts"))
        if not js_files:
            return None

        results = {
            "file_count": len(js_files),
            "files": [],
            "complex_functions": [],
            "long_functions": [],
            "long_files": []
        }

        for js_file in js_files:
            try:
                file_result = self._analyze_javascript_file(js_file)
                results["files"].append(file_result)

                # Check for complex/long functions
                for func in file_result.get("functions", []):
                    if func.get("complexity", 0) > self.thresholds["cyclomatic"]:
                        results["complex_functions"].append({
                            "file": str(js_file),
                            "function": func["name"],
                            "complexity": func["complexity"],
                            "line": func["line"]
                        })

                    if func.get("lines", 0) > self.thresholds["lines_per_function"]:
                        results["long_functions"].append({
                            "file": str(js_file),
                            "function": func["name"],
                            "lines": func["lines"],
                            "line": func["line"]
                        })

                # Check for long files
                if file_result.get("total_lines", 0) > self.thresholds["lines_per_file"]:
                    results["long_files"].append({
                        "file": str(js_file),
                        "lines": file_result["total_lines"]
                    })

            except Exception as e:
                print(f"⚠️ Error analyzing {js_file}: {e}")

        return results

    def _analyze_javascript_file(self, file_path: Path) -> Dict[str, Any]:
        """Analyze a single JavaScript/TypeScript file"""
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()

        lines = content.split('\n')

        result = {
            "file": str(file_path),
            "total_lines": len(lines),
            "functions": []
        }

        # Find function definitions (basic pattern matching)
        for i, line in enumerate(lines):
            # Match function declarations: function name(...) { or const name = (...) => {
            func_match = re.match(r'(?:function\s+|(?:const|let|var)\s+\w+\s*=\s*(?:\([^)]*\)\s*=>)?\s*)(\w+)\s*\([^)]*\)\s*\{', line.strip())
            if func_match:
                func_name = func_match.group(1) if func_match.group(1) else "anonymous"
                # Estimate function length
                func_lines = self._estimate_js_function_length(lines, i)

                # Calculate basic complexity
                complexity = self._calculate_js_complexity(lines[i:i+func_lines])

                result["functions"].append({
                    "name": func_name,
                    "line": i + 1,
                    "lines": func_lines,
                    "complexity": complexity
                })

        return result

    def _estimate_js_function_length(self, lines: List[str], start_idx: int) -> int:
        """Estimate JavaScript function length"""
        brace_count = 0
        for i in range(start_idx, min(start_idx + 100, len(lines))):
            line = lines[i].strip()
            brace_count += line.count('{') - line.count('}')
            if brace_count == 0 and '}' in line:
                return i - start_idx + 1
        return min(50, len(lines) - start_idx)  # Default estimate

    def _calculate_js_complexity(self, lines: List[str]) -> int:
        """Calculate JavaScript complexity"""
        complexity = 1

        for line in lines:
            line = line.strip()
            if any(keyword in line for keyword in ['if ', 'for ', 'while ', 'switch ', '&&', '||', '?']):
                complexity += 1
            if 'catch ' in line:
                complexity += 1

        return complexity

    def _calculate_summary_stats(self, results: Dict[str, Any]) -> None:
        """Calculate summary statistics across all languages"""
        summary = results["summary"]

        for lang_results in results["languages"].values():
            summary["complex_files"] += len(lang_results.get("complex_functions", []))
            summary["high_complexity_functions"] += len(lang_results.get("complex_functions", []))
            summary["long_functions"] += len(lang_results.get("long_functions", []))
            summary["long_files"] += len(lang_results.get("long_files", []))

    def _generate_recommendations(self, results: Dict[str, Any]) -> List[str]:
        """Generate recommendations based on analysis"""
        recommendations = []

        summary = results["summary"]

        if summary["high_complexity_functions"] > 0:
            recommendations.append(f"🔧 Refactor {summary['high_complexity_functions']} high-complexity functions (break into smaller functions)")

        if summary["long_functions"] > 0:
            recommendations.append(f"📏 Split {summary['long_functions']} long functions into smaller, focused functions")

        if summary["long_files"] > 0:
            recommendations.append(f"📂 Break down {summary['long_files']} long files into multiple modules")

        if summary["complex_files"] > 0:
            recommendations.append(f"🏗️ Consider architectural improvements for {summary['complex_files']} complex files")

        if not recommendations:
            recommendations.append("✅ Code complexity is within acceptable limits")

        return recommendations

    def print_report(self, results: Dict[str, Any]) -> None:
        """Print a formatted complexity report"""
        print("\n🧠 CODE COMPLEXITY ANALYSIS REPORT")
        print("=" * 50)

        summary = results["summary"]
        print("\n📊 Summary:")
        print(f"  Total Files Analyzed: {summary['total_files']}")
        print(f"  Files with Complex Functions: {summary['complex_files']}")
        print(f"  High Complexity Functions: {summary['high_complexity_functions']}")
        print(f"  Long Functions: {summary['long_functions']}")
        print(f"  Long Files: {summary['long_files']}")

        for lang, lang_results in results["languages"].items():
            print(f"\n{lang.upper()} Analysis:")
            print(f"  Files: {lang_results['file_count']}")

            if lang_results.get("complex_functions"):
                print(f"  Complex Functions: {len(lang_results['complex_functions'])}")
                for func in lang_results["complex_functions"][:5]:  # Show first 5
                    print(f"    • {func['function']} (complexity: {func['complexity']})")

            if lang_results.get("long_functions"):
                print(f"  Long Functions: {len(lang_results['long_functions'])}")
                for func in lang_results["long_functions"][:5]:  # Show first 5
                    print(f"    • {func['function']} ({func['lines']} lines)")

        if results["recommendations"]:
            print("\n💡 Recommendations:")
            for rec in results["recommendations"]:
                print(f"  {rec}")

        print("\n" + "=" * 50)


def main():
    """Main complexity analysis function"""
    project_root = Path(__file__).parent.parent.parent

    analyzer = ComplexityAnalyzer(project_root)
    results = analyzer.analyze_all_files()
    analyzer.print_report(results)

    # Save results
    reports_dir = project_root / "quality-gates" / "complexity"
    reports_dir.mkdir(parents=True, exist_ok=True)

    import json
    import time
    report_file = reports_dir / f"complexity-report-{int(time.time())}.json"

    with open(report_file, 'w') as f:
        json.dump(results, f, indent=2)

    print(f"\n📄 Complexity report saved to: {report_file}")


if __name__ == "__main__":
    main()
