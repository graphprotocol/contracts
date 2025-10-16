#!/bin/bash

# Complete build script for the interfaces package with incremental build support
# This script handles:
# 1. Hardhat compilation (generates artifacts and ethers-v6 types)
# 2. Type generation (WAGMI and ethers-v5 types)
# 3. TypeScript compilation (both v6 and v5 types)

set -e  # Exit on any error

echo "🔨 Starting build process..."

# Helper function to check if target is newer than sources
is_newer() {
    local target="$1"
    shift
    local sources=("$@")

    # If target doesn't exist, it needs to be built
    if [[ ! -e "$target" ]]; then
        return 1
    fi

    # Check if any source is newer than target
    for source in "${sources[@]}"; do
        if [[ -e "$source" && "$source" -nt "$target" ]]; then
            return 1
        fi
    done

    return 0
}

# Helper function to find files matching patterns
find_files() {
    local pattern="$1"
    find . -path "$pattern" -type f 2>/dev/null || true
}

# Step 1: Hardhat compilation
echo "📦 Compiling contracts with Hardhat..."
pnpm hardhat compile

# Step 1.5: Add interface IDs to generated factory files (only if needed)
missing_ids=$(grep -rL "static readonly interfaceId" types/factories --include="*__factory.ts" 2>/dev/null | wc -l)

if [[ $missing_ids -gt 0 ]]; then
    # Slow operation, only run if needed
    npx ts-node scripts/utils/addInterfaceIds.ts types/factories
fi

# Step 2: Generate types (only if needed)
echo "🏗️  Checking type definitions..."

# Check if WAGMI types need regeneration
wagmi_sources=(
    "wagmi.config.mts"
    $(find_files "./artifacts/contracts/**/!(*.dbg).json")
)
if ! is_newer "wagmi/generated.ts" "${wagmi_sources[@]}"; then
    echo "  - Generating WAGMI types..."
    pnpm wagmi generate
else
    echo "  - WAGMI types are up to date"
fi

# Check if ethers-v5 types need regeneration
v5_artifacts=($(find_files "./artifacts/contracts/**/!(*.dbg).json") $(find_files "./artifacts/@openzeppelin/**/!(*.dbg).json"))
if ! is_newer "types-v5/index.ts" "${v5_artifacts[@]}"; then
    echo "  - Generating ethers-v5 types..."
    pnpm typechain \
      --target ethers-v5 \
      --out-dir types-v5 \
      'artifacts/contracts/**/!(*.dbg).json' \
      'artifacts/@openzeppelin/**/!(*.dbg).json'
else
    echo "  - ethers-v5 types are up to date"
fi

# Step 3: TypeScript compilation (only if needed)
echo "🔧 Checking TypeScript compilation..."

# Check if v6 types need compilation
v6_sources=(
    "hardhat.config.ts"
    $(find_files "./src/**/*.ts")
    $(find_files "./types/**/*.ts")
    $(find_files "./wagmi/**/*.ts")
)
if ! is_newer "dist/tsconfig.tsbuildinfo" "${v6_sources[@]}"; then
    echo "  - Compiling ethers-v6 types..."
    pnpm tsc
    touch dist/tsconfig.tsbuildinfo
else
    echo "  - ethers-v6 types are up to date"
fi

# Check if v5 types need compilation
v5_sources=($(find_files "./types-v5/**/*.ts"))
if ! is_newer "dist-v5/tsconfig.v5.tsbuildinfo" "${v5_sources[@]}"; then
    echo "  - Compiling ethers-v5 types..."
    pnpm tsc -p tsconfig.v5.json
    touch dist-v5/tsconfig.v5.tsbuildinfo
else
    echo "  - ethers-v5 types are up to date"
fi

# Step 4: Merge v5 types into dist directory (only if needed)
needs_copy=false
if [[ -d "dist-v5" ]]; then
    if [[ ! -d "dist/types-v5" ]]; then
        needs_copy=true
    else
        # Check if any file in dist-v5 is newer than the corresponding file in dist/types-v5
        while IFS= read -r -d '' file; do
            relative_path="${file#dist-v5/}"
            target_file="dist/types-v5/$relative_path"
            if [[ ! -e "$target_file" || "$file" -nt "$target_file" ]]; then
                needs_copy=true
                break
            fi
        done < <(find dist-v5 -type f -print0)
    fi
fi

if [[ "$needs_copy" == "true" ]]; then
    echo "📁 Organizing compiled types..."
    mkdir -p dist/types-v5
    cp -r dist-v5/* dist/types-v5/
else
    echo "📁 Compiled types organization is up to date"
fi

echo "✅ Build completed successfully!"
echo "📄 Generated types:"
echo "  - ethers-v6: dist/types/"
echo "  - ethers-v5: dist/types-v5/"
echo "  - wagmi: dist/wagmi/"