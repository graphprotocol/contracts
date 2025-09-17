#!/usr/bin/env bash
# Host setup script for creating global cache volumes
# Run this script to create shared cache volumes across all dev containers
# Usage: .devcontainer/host-setup.sh

set -euo pipefail

echo "Setting up global cache volumes for dev containers..."

# Global cache volumes that should be shared across all projects
GLOBAL_VOLUMES=(
  "global-pnpm-cache"
  # Add other global caches here as needed
  # "global-pip-cache"
  # "global-npm-cache"
)

echo "Creating global cache volumes..."
for volume in "${GLOBAL_VOLUMES[@]}"; do
  if docker volume inspect "$volume" >/dev/null 2>&1; then
    echo "✓ $volume already exists"
  else
    echo "Creating $volume..."
    docker volume create "$volume"
    echo "✓ $volume created"
  fi
done

echo ""
echo "Setting up proper ownership for cache volumes..."
# The vscode user in devcontainers typically has UID 1000 and GID 1000
# We need to ensure the volumes have the correct ownership
for volume in "${GLOBAL_VOLUMES[@]}"; do
  echo "Setting ownership for $volume..."
  # Create a temporary container to fix ownership
  docker run --rm \
    -v "$volume":/volume \
    --user root \
    mcr.microsoft.com/devcontainers/base:debian \
    chown -R 1000:1000 /volume
  echo "✓ $volume ownership set to vscode user (1000:1000)"
done

echo ""
echo "Global cache volumes setup completed!"
echo "These volumes will be shared across all dev containers that reference them."
echo ""
echo "Created volumes:"
for volume in "${GLOBAL_VOLUMES[@]}"; do
  echo "  - $volume"
done
