#!/usr/bin/env python3
"""
Check for TODO comments in Solidity files.

When called with file arguments: checks those specific files.
When called with no arguments: checks only git-changed files (modified/added/untracked).
"""

import re
import subprocess
import sys
from pathlib import Path
from typing import List, Tuple

# Pattern to match TODO comments in Solidity
# Matches TODO, FIXME, XXX, HACK in both single-line and multi-line comments
TODO_PATTERN = re.compile(
    r"(//.*\b(todo|fixme|xxx|hack)\b|/\*.*\b(todo|fixme|xxx|hack)\b)",
    re.IGNORECASE
)


def find_todos_in_file(file_path: Path) -> List[Tuple[int, str]]:
    """
    Find TODO comments in a Solidity file.

    Args:
        file_path: Path to the Solidity file

    Returns:
        List of tuples (line_number, line_content) for lines with TODOs
    """
    todos = []
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            for line_num, line in enumerate(f, start=1):
                if TODO_PATTERN.search(line):
                    todos.append((line_num, line.rstrip()))
    except Exception as e:
        print(f"⚠️  Error reading {file_path}: {e}", file=sys.stderr)
    return todos


def get_git_changed_files() -> List[str]:
    """
    Get locally changed Solidity files from git.

    Returns:
        List of changed .sol file paths
    """
    try:
        # Get modified and added files
        result = subprocess.run(
            ['git', 'diff', '--name-only', '--diff-filter=AM', 'HEAD'],
            capture_output=True,
            text=True,
            check=True
        )
        changed_files = [f for f in result.stdout.strip().split('\n') if f.endswith('.sol')]

        # Get untracked files
        result = subprocess.run(
            ['git', 'ls-files', '--others', '--exclude-standard'],
            capture_output=True,
            text=True,
            check=True
        )
        untracked_files = [f for f in result.stdout.strip().split('\n') if f.endswith('.sol')]

        # Combine and filter empty strings
        all_files = [f for f in changed_files + untracked_files if f]
        return all_files
    except subprocess.CalledProcessError:
        return []


def main():
    """Main entry point."""
    # Determine which files to check
    has_file_args = 1 < len(sys.argv)

    if has_file_args:
        # Check specific files passed as arguments
        files_to_check = [f for f in sys.argv[1:] if f.endswith('.sol')]
    else:
        # Check only git-changed files
        files_to_check = get_git_changed_files()
        if not files_to_check:
            print("✅ No locally changed or untracked Solidity files to check for TODO comments.")
            return 0

    if not files_to_check:
        print("✅ No files to check for TODO comments.")
        return 0

    # Check each file for TODOs
    files_checked = 0
    files_with_todos = 0
    total_todos = 0
    todo_found = False

    for file_path_str in files_to_check:
        file_path = Path(file_path_str)

        # Only check if file exists and is a Solidity file
        if not file_path.is_file():
            continue

        files_checked += 1
        todos = find_todos_in_file(file_path)
        if todos:
            if not todo_found:
                print("❌ TODO comments found in Solidity files:")
                print()
                todo_found = True

            files_with_todos += 1
            total_todos += len(todos)

            print(f"📝 {file_path}:")
            for line_num, line in todos:
                print(f"  {line_num}: {line}")
            print()

    # Exit with appropriate message
    file_type = "specified" if has_file_args else "locally changed"
    icon = "❌" if todo_found else "✅"

    print(f"{icon} Found {total_todos} TODO comment(s) in {files_with_todos}/{files_checked} {file_type} Solidity file(s).")

    return 1 if todo_found else 0


if __name__ == "__main__":
    sys.exit(main())
