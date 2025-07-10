#!/bin/bash

# Complete build script for the interfaces package
# This script handles:
# 1. Hardhat compilation (generates artifacts and ethers-v6 types)
# 2. Type generation (WAGMI and ethers-v5 types)
# 3. TypeScript compilation (both v6 and v5 types)

set -e  # Exit on any error

echo "🔨 Starting complete build process..."

# Step 1: Hardhat compilation
echo "📦 Compiling contracts with Hardhat..."
hardhat compile

# Step 2: Generate types
echo "🏗️  Generating type definitions..."

# Build wagmi types
echo "  - Generating WAGMI types..."
pnpm wagmi generate

# Build ethers-v5 types
echo "  - Generating ethers-v5 types..."
pnpm typechain \
  --target ethers-v5 \
  --out-dir types-v5 \
  'artifacts/contracts/**/!(*.dbg).json' \
  'artifacts/@openzeppelin/**/!(*.dbg).json'

# Step 3: TypeScript compilation
echo "🔧 Compiling TypeScript..."

# Compile v6 types (default tsconfig)
echo "  - Compiling ethers-v6 types..."
tsc

# Compile v5 types (separate tsconfig)
echo "  - Compiling ethers-v5 types..."
tsc -p tsconfig.v5.json

# Step 4: Merge v5 types into dist directory
echo "📁 Organizing compiled types..."
mkdir -p dist/types-v5
cp -r dist-v5/* dist/types-v5/

echo "✅ Build completed successfully!"
echo "📄 Generated types:"
echo "  - ethers-v6: dist/types/"
echo "  - ethers-v5: dist/types-v5/"
echo "  - wagmi: dist/wagmi/"