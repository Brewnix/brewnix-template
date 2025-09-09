#!/usr/bin/env python3
"""
BrewNix Linting Configuration
Comprehensive linting rules for multiple languages
"""

import os
import sys
from pathlib import Path


class LintingConfig:
    """Configuration for various linting tools"""

    def __init__(self, project_root: Path):
        self.project_root = project_root

    def generate_flake8_config(self) -> str:
        """Generate flake8 configuration"""
        config = """[flake8]
max-line-length = 100
max-complexity = 10
ignore =
    E203,  # whitespace before ':'
    E501,  # line too long (handled by max-line-length)
    W503,  # line break before binary operator
    F401,  # module imported but unused (handled by other tools)
    F841,  # local variable assigned but never used
exclude =
    .git,
    __pycache__,
    .pytest_cache,
    venv,
    .venv,
    env,
    .env,
    build,
    dist,
    *.egg-info,
    .tox,
    .coverage,
    htmlcov,
    .mypy_cache,
    tests/coverage,
    tests/reports,
    quality-gates/reports
per-file-ignores =
    __init__.py:F401
    tests/*:S101  # assert used in tests
    scripts/*:T201,T203  # print and exit allowed in scripts
"""
        return config

    def generate_shellcheck_config(self) -> str:
        """Generate shellcheck configuration"""
        config = """# BrewNix Shell Script Linting Configuration

# Enable all warnings and style checks
enable=all

# Disable specific checks that are not relevant for BrewNix
disable=SC1090,SC1091,SC2001,SC2016,SC2034,SC2046,SC2086,SC2119,SC2120

# Source external files (allowed for BrewNix)
disable=SC1090

# Allow variable indirection (used in BrewNix scripts)
disable=SC2034

# Allow word splitting (controlled in BrewNix)
disable=SC2046,SC2086

# Allow unused functions (library functions)
disable=SC2119,SC2120

# Allow sed patterns (used extensively in BrewNix)
disable=SC2001

# Allow eval usage (controlled in BrewNix)
disable=SC2034
"""
        return config

    def generate_pylint_config(self) -> str:
        """Generate pylint configuration"""
        config = """[MASTER]
disable=
    C0114,  # missing-module-docstring
    C0115,  # missing-class-docstring
    C0116,  # missing-function-docstring
    R0903,  # too-few-public-methods
    R0912,  # too-many-branches
    R0915,  # too-many-statements
    W0613,  # unused-argument (common in callbacks)
    C0103,  # invalid-name (allow flexibility)
    R0913,  # too-many-arguments
    R0914,  # too-many-locals
    C0301,  # line-too-long (handled by flake8)

[FORMAT]
max-line-length=100

[DESIGN]
max-complexity=10

[REPORTS]
output-format=colorized

[IMPORTS]
allow-wildcard-with-all=no

[VARIABLES]
dummy-variables-rgx=^_.*$
"""
        return config

    def generate_eslint_config(self) -> str:
        """Generate ESLint configuration for JavaScript/TypeScript"""
        config = """{
  "env": {
    "browser": true,
    "es2021": true,
    "node": true
  },
  "extends": [
    "eslint:recommended"
  ],
  "parserOptions": {
    "ecmaVersion": "latest",
    "sourceType": "module"
  },
  "rules": {
    "indent": ["error", 2],
    "linebreak-style": ["error", "unix"],
    "quotes": ["error", "single"],
    "semi": ["error", "always"],
    "no-unused-vars": "warn",
    "no-console": "off",
    "complexity": ["warn", 10],
    "max-lines": ["warn", 300],
    "max-lines-per-function": ["warn", 50]
  },
  "ignorePatterns": [
    "node_modules/",
    "build/",
    "dist/",
    "*.min.js"
  ]
}
"""
        return config

    def generate_yaml_lint_config(self) -> str:
        """Generate yamllint configuration"""
        config = """extends: default

rules:
  line-length:
    max: 120
    level: warning

  indentation:
    spaces: 2
    indent-sequences: true
    check-multi-line-strings: false

  comments-indentation: disable
  comments: disable
  empty-lines:
    max-start: 2
    max-end: 1
    max: 2

  document-start: disable
  document-end: disable

  truthy:
    allowed-values: ['true', 'false']
    check-keys: false

ignore: |
  /vendor/
  /build/
  /dist/
  /.git/
  /node_modules/
"""
        return config

    def create_config_files(self) -> None:
        """Create all linting configuration files"""
        configs_dir = self.project_root / "quality-gates" / "linting"
        configs_dir.mkdir(parents=True, exist_ok=True)

        # Create .flake8
        flake8_config = configs_dir / ".flake8"
        with open(flake8_config, 'w') as f:
            f.write(self.generate_flake8_config())
        print(f"✅ Created {flake8_config}")

        # Create .shellcheckrc
        shellcheck_config = configs_dir / ".shellcheckrc"
        with open(shellcheck_config, 'w') as f:
            f.write(self.generate_shellcheck_config())
        print(f"✅ Created {shellcheck_config}")

        # Create .pylintrc
        pylint_config = configs_dir / ".pylintrc"
        with open(pylint_config, 'w') as f:
            f.write(self.generate_pylint_config())
        print(f"✅ Created {pylint_config}")

        # Create .eslintrc.json
        eslint_config = configs_dir / ".eslintrc.json"
        with open(eslint_config, 'w') as f:
            f.write(self.generate_eslint_config())
        print(f"✅ Created {eslint_config}")

        # Create .yamllint
        yamllint_config = configs_dir / ".yamllint"
        with open(yamllint_config, 'w') as f:
            f.write(self.generate_yaml_lint_config())
        print(f"✅ Created {yamllint_config}")

        print("\n📋 Linting Configuration Summary:")
        print("  • flake8: Python linting with style and complexity checks")
        print("  • shellcheck: Shell script linting with security focus")
        print("  • pylint: Advanced Python code analysis")
        print("  • eslint: JavaScript/TypeScript linting")
        print("  • yamllint: YAML file validation and formatting")


def main():
    """Main configuration generator"""
    project_root = Path(__file__).parent.parent.parent

    print("🔧 Generating BrewNix Linting Configuration...")

    config_gen = LintingConfig(project_root)
    config_gen.create_config_files()

    print("\n✅ All linting configurations generated successfully!")
    print("\n💡 To use these configurations:")
    print("  • Copy .flake8 to project root for Python linting")
    print("  • Copy .shellcheckrc to project root for shell linting")
    print("  • Copy .pylintrc to project root for advanced Python analysis")
    print("  • Copy .eslintrc.json to project root for JavaScript/TypeScript")
    print("  • Copy .yamllint to project root for YAML validation")


if __name__ == "__main__":
    main()
