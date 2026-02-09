#!/bin/bash

# Complete build script for the interfaces package with incremental build support
# This script handles:
# 1. Hardhat compilation (generates artifacts and ethers-v6 types)
# 2. Type generation (WAGMI and ethers-v5 types)
# 3. TypeScript compilation (both v6 and v5 types)
#
# Usage:
#   build.sh           - Minimal output (only shows actions taken, not skipped)
#   build.sh --verbose - Full output (shows all details)

set -e  # Exit on any error

# Parse flags
VERBOSE=false
if [[ "$1" == "--verbose" ]]; then
    VERBOSE=true
fi

# Logging helpers
log_info() {
    # Only show in verbose mode (headers, status, skipped items)
    if [[ "$VERBOSE" == "true" ]]; then
        echo "$@"
    fi
}

log_action() {
    # Always show actions being taken
    echo "$@"
}

log_info "🔨 Starting build process..."

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
log_info "📦 Compiling contracts with Hardhat..."
pnpm hardhat compile $([[ "$VERBOSE" != "true" ]] && echo "--quiet")

# Step 1.5: Add interface IDs to generated factory files (only if needed)
missing_ids=$(grep -rL "static readonly interfaceId" types/factories --include="*__factory.ts" 2>/dev/null | wc -l)

if [[ $missing_ids -gt 0 ]]; then
    # Slow operation, only run if needed
    npx ts-node scripts/utils/addInterfaceIds.ts types/factories
fi

# Step 2: Generate types (only if needed)
log_info "🏗️  Checking type definitions..."

# Check if WAGMI types need regeneration
wagmi_sources=(
    "wagmi.config.mts"
    $(find_files "./artifacts/contracts/**/!(*.dbg).json")
)
if ! is_newer "wagmi/generated.ts" "${wagmi_sources[@]}"; then
    log_action "  - Generating WAGMI types..."
    pnpm wagmi generate
else
    log_info "  - WAGMI types are up to date"
fi

# Check if ethers-v5 types need regeneration
v5_artifacts=($(find_files "./artifacts/contracts/**/!(*.dbg).json") $(find_files "./artifacts/@openzeppelin/**/!(*.dbg).json"))
if ! is_newer "types-v5/index.ts" "${v5_artifacts[@]}"; then
    log_action "  - Generating ethers-v5 types..."
    pnpm typechain \
      --target ethers-v5 \
      --out-dir types-v5 \
      'artifacts/contracts/**/!(*.dbg).json' \
      'artifacts/@openzeppelin/**/!(*.dbg).json'
else
    log_info "  - ethers-v5 types are up to date"
fi

# Step 3: TypeScript compilation (only if needed)
log_info "🔧 Checking TypeScript compilation..."

# Check if v6 types need compilation
v6_sources=(
    "hardhat.config.ts"
    $(find_files "./src/**/*.ts")
    $(find_files "./types/**/*.ts")
    $(find_files "./wagmi/**/*.ts")
)
if ! is_newer "dist/tsconfig.tsbuildinfo" "${v6_sources[@]}"; then
    log_action "  - Compiling ethers-v6 types..."
    pnpm tsc
    touch dist/tsconfig.tsbuildinfo
else
    log_info "  - ethers-v6 types are up to date"
fi

# Check if v5 types need compilation
v5_sources=($(find_files "./types-v5/**/*.ts"))
if ! is_newer "dist-v5/tsconfig.v5.tsbuildinfo" "${v5_sources[@]}"; then
    log_action "  - Compiling ethers-v5 types..."
    pnpm tsc -p tsconfig.v5.json
    touch dist-v5/tsconfig.v5.tsbuildinfo
else
    log_info "  - ethers-v5 types are up to date"
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
    log_action "📁 Organizing compiled types..."
    mkdir -p dist/types-v5
    cp -r dist-v5/* dist/types-v5/
else
    log_info "📁 Compiled types organization is up to date"
fi

log_info "✅ Build completed successfully!"
log_info "📄 Generated types:"
log_info "  - ethers-v6: dist/types/"
log_info "  - ethers-v5: dist/types-v5/"
log_info "  - wagmi: dist/wagmi/"
