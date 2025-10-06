#!/usr/bin/env bash
#
# Bytecode Comparison Tool (Metadata-Stripped)
#
# Compares functional bytecode between two contract artifact directories,
# excluding metadata hashes to focus on actual code differences.
#
# This is an enhanced version of bytecode-diff.sh that strips Solidity
# metadata hashes before comparison, allowing you to identify functional
# differences vs compilation environment differences.
#
# Usage: ./bytecode-diff-no-metadata.sh <dir1> <dir2>
# Example: ./bytecode-diff-no-metadata.sh /path/to/old/artifacts /path/to/new/artifacts
#
# Metadata Pattern Stripped: a264697066735822[64 hex chars]64736f6c63[6 hex chars]
# This represents: "ipfs" + IPFS hash + "solc" + Solidity version
#

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <artifacts-dir-1> <artifacts-dir-2>"
  echo "This script compares bytecode excluding metadata hashes"
  echo "Metadata hashes are embedded by Solidity and don't affect contract functionality"
  exit 1
fi

DIR1="$1"
DIR2="$2"

TMPDIR=$(mktemp -d)

# Function to extract bytecode and strip metadata hash
strip_metadata() {
  local file="$1"
  local out="$2"

  # Extract bytecode
  local bytecode=$(jq -r '.bytecode' "$file")

  # Remove 0x prefix if present
  bytecode=${bytecode#0x}

  # Strip metadata hash - Solidity metadata follows pattern:
  # a264697066735822<32-byte-hash>64736f6c63<version>
  # Where:
  # - a264697066735822 = "ipfs" in hex + length prefix
  # - 64736f6c63 = "solc" in hex
  # We'll remove everything from the last occurrence of a264697066735822 to the end

  # Use sed to remove the metadata pattern from the end
  # This removes everything from a264697066735822 (ipfs marker) to the end
  bytecode=$(echo "$bytecode" | sed 's/a264697066735822.*$//')

  # Output in chunks of 64 characters for easier diffing
  echo "$bytecode" | fold -w 64 > "$out"
}

echo "🔍 Comparing bytecode (excluding metadata hashes) for repository contracts..."
echo "DIR1: $DIR1"
echo "DIR2: $DIR2"
echo

# Create lists of contracts in each directory
contracts1="$TMPDIR/contracts1.txt"
contracts2="$TMPDIR/contracts2.txt"

find "$DIR1/contracts" -type f -name '*.json' ! -name '*dbg.json' ! -name 'I*.json' 2>/dev/null | while read -r file; do
  rel_path="${file#$DIR1/contracts/}"
  echo "$rel_path"
done | sort > "$contracts1"

find "$DIR2/contracts" -type f -name '*.json' ! -name '*dbg.json' ! -name 'I*.json' 2>/dev/null | while read -r file; do
  rel_path="${file#$DIR2/contracts/}"
  echo "$rel_path"
done | sort > "$contracts2"

# Find common contracts
common_contracts="$TMPDIR/common.txt"
comm -12 "$contracts1" "$contracts2" > "$common_contracts"

common_count=$(wc -l < "$common_contracts")
echo "📊 Found $common_count common contracts to compare"
echo

if [ "$common_count" -eq 0 ]; then
  echo "❌ No common contracts found!"
  exit 1
fi

# Compare bytecode for common contracts
diff_count=0
same_count=0
no_bytecode_count=0

# Store results for summary
same_contracts="$TMPDIR/same.txt"
diff_contracts="$TMPDIR/different.txt"
touch "$same_contracts" "$diff_contracts"

echo "Processing contracts..."

while read -r contract; do
  file1="$DIR1/contracts/$contract"
  file2="$DIR2/contracts/$contract"

  # Extract and strip metadata
  tmp1="$TMPDIR/1"
  tmp2="$TMPDIR/2"

  strip_metadata "$file1" "$tmp1"
  strip_metadata "$file2" "$tmp2"

  # Skip if no bytecode (interfaces, abstract contracts)
  if [ ! -s "$tmp1" ] || [ "$(wc -c < "$tmp1")" -le 3 ]; then
    no_bytecode_count=$((no_bytecode_count + 1))
    continue
  fi

  contract_name=$(jq -r '.contractName // "Unknown"' "$file1" 2>/dev/null || echo "Unknown")

  if ! diff -q "$tmp1" "$tmp2" > /dev/null; then
    diff_count=$((diff_count + 1))
    echo "$contract ($contract_name)" >> "$diff_contracts"
    echo "🧨 $contract"
  else
    same_count=$((same_count + 1))
    echo "$contract ($contract_name)" >> "$same_contracts"
    echo "✅ $contract"
  fi
done < "$common_contracts"

echo
echo "📋 SUMMARY LISTS:"
echo
echo "✅ FUNCTIONALLY IDENTICAL ($same_count contracts):"
if [ -s "$same_contracts" ]; then
  cat "$same_contracts" | sed 's/^/  - /'
else
  echo "  (none)"
fi

echo
echo "🧨 FUNCTIONAL DIFFERENCES ($diff_count contracts):"
if [ -s "$diff_contracts" ]; then
  cat "$diff_contracts" | sed 's/^/  - /'
else
  echo "  (none)"
fi

echo
echo "📊 Final Summary:"
echo "   Total contracts compared: $((same_count + diff_count))"
echo "   No bytecode (interfaces/abstract): $no_bytecode_count"
echo "   Functionally identical: $same_count"
echo "   Functional differences: $diff_count"

if [ "$diff_count" -eq 0 ]; then
  echo
  echo "🎉 SUCCESS: All contracts are functionally identical!"
  echo "   The previous differences were only in metadata hashes."
else
  echo
  echo "⚠️  ATTENTION: Found $diff_count contracts with functional differences!"
  echo "   These contracts have actual code changes that affect functionality."
fi

rm -rf "$TMPDIR"
