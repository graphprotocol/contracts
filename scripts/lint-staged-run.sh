#!/bin/bash

# Lint-staged runner script
# Runs linting commands while excluding specific generated files
# Usage: lint-staged-run.sh <command> <file1> [file2] ...

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <command> <file1> [file2] ..."
    echo "Example: $0 'eslint --fix --cache' file1.js file2.ts"
    exit 1
fi

COMMAND="$1"
shift
FILES=("$@")

# Define ignore patterns for generated files that should never be linted despite being in git
# Note: These are substrings to check for in the file path, not glob patterns
IGNORE_SUBSTRINGS=(
    "/.graphclient-extracted/"
)

# Function to check if a file should be ignored
should_ignore_file() {
    local file="$1"

    for substring in "${IGNORE_SUBSTRINGS[@]}"; do
        if [[ "$file" == *"$substring"* ]]; then
            return 0  # Should ignore
        fi
    done

    return 1  # Should not ignore
}

# Filter files
FILTERED_FILES=()
for file in "${FILES[@]}"; do
    if ! should_ignore_file "$file"; then
        FILTERED_FILES+=("$file")
    fi
done

# If no files to process, exit successfully
if [ ${#FILTERED_FILES[@]} -eq 0 ]; then
    exit 0
fi

# Execute command with filtered files
exec $COMMAND "${FILTERED_FILES[@]}"
