#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <artifacts-dir-1> <artifacts-dir-2>"
  exit 1
fi

DIR1="$1"
DIR2="$2"

TMPDIR=$(mktemp -d)

# Function to extract, strip metadata, and chunk bytecode
process() {
  local file="$1"
  local out="$2"

  jq -r '.deployedBytecode' "$file" | fold -w 64 > "$out"
}

# Find all JSON files in DIR1
find "$DIR1" -type f -name '*.json' ! -name '*dbg.json' ! -name 'I*.json' | while read -r file1; do
  # Get relative path
  rel_path="${file1#$DIR1/}"
  file2="$DIR2/$rel_path"

  if [ ! -f "$file2" ]; then
    echo "⚠️  Missing in second dir: $rel_path"
    continue
  fi

  tmp1="$TMPDIR/1"
  tmp2="$TMPDIR/2"

  process "$file1" "$tmp1"
  process "$file2" "$tmp2"

  if ! diff -q "$tmp1" "$tmp2" > /dev/null; then
    echo "🧨 Difference found in: $rel_path"
    if command -v colordiff &> /dev/null; then
      colordiff -u "$tmp1" "$tmp2"
    else
      diff -u "$tmp1" "$tmp2"
    fi
    echo
  fi
done

rm -rf "$TMPDIR"
