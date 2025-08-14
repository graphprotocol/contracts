#!/bin/bash
# Check for TODO comments in Solidity files
# Can run during lint-staged (pre-commit) or regular linting (changed files only)

# Exit on any error
set -e

# Determine if we're running in lint-staged context or regular linting
LINT_STAGED_MODE=false
if [ "${LINT_STAGED:-}" = "true" ] || [ $# -gt 0 ]; then
    LINT_STAGED_MODE=true
fi

# If no files passed and not in lint-staged mode, check git changed files
if [ $# -eq 0 ] && [ "$LINT_STAGED_MODE" = false ]; then
    # Get locally changed Solidity files (modified, added, but not committed)
    CHANGED_FILES=$(git diff --name-only --diff-filter=AM HEAD | grep '\.sol$' || true)
    # Get untracked Solidity files
    UNTRACKED_FILES=$(git ls-files --others --exclude-standard | grep '\.sol$' || true)
    # Combine both lists
    ALL_FILES="$CHANGED_FILES $UNTRACKED_FILES"
    if [ -z "$ALL_FILES" ]; then
        echo "✅ No locally changed or untracked Solidity files to check for TODO comments."
        exit 0
    fi
    # Convert to array
    set -- $ALL_FILES
fi

# Check if any files to process
if [ $# -eq 0 ]; then
    echo "✅ No files to check for TODO comments."
    exit 0
fi

# Initialize flag to track if TODOs are found
TODO_FOUND=false

# Check each file passed as argument
for file in "$@"; do
    # Only check if file exists and is a Solidity file
    if [ -f "$file" ] && [[ "$file" == *.sol ]]; then
        # Search for TODO comments (case insensitive)
        # Look for TODO, FIXME, XXX, HACK in comments
        if grep -i -n -E "(//.*\b(todo|fixme|xxx|hack)\b|/\*.*\b(todo|fixme|xxx|hack)\b)" "$file" > /dev/null 2>&1; then
            if [ "$TODO_FOUND" = false ]; then
                echo "❌ TODO comments found in Solidity files:"
                echo ""
                TODO_FOUND=true
            fi
            echo "📝 $file:"
            # Show the actual lines with TODO comments
            grep -i -n -E "(//.*\b(todo|fixme|xxx|hack)\b|/\*.*\b(todo|fixme|xxx|hack)\b)" "$file" | while read -r line; do
                echo "  $line"
            done
            echo ""
        fi
    fi
done

# Exit with error if TODOs were found
if [ "$TODO_FOUND" = true ]; then
    if [ "$LINT_STAGED_MODE" = true ]; then
        echo "❌ Please resolve all TODO comments in Solidity files before committing."
        echo "   This check runs during pre-commit to maintain code quality."
    else
        echo "❌ TODO comments found in locally changed Solidity files."
        echo "   Consider resolving these before committing."
    fi
    exit 1
fi

if [ "$LINT_STAGED_MODE" = true ]; then
    echo "✅ No TODO comments found in Solidity files."
else
    echo "✅ No TODO comments found in locally changed Solidity files."
fi
exit 0
