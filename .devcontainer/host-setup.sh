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
echo "Cache volumes created successfully!"
echo "Note: Permissions will be set automatically when the dev container starts."

echo ""
echo "Global cache volumes setup completed!"
echo "These volumes will be shared across all dev containers that reference them."
echo ""
echo "Created volumes:"
for volume in "${GLOBAL_VOLUMES[@]}"; do
  echo "  - $volume"
done
