#!/usr/bin/env bash
# Host setup script for Graph Protocol Contracts dev container
# Run this script on the host before starting the dev container
# Usage: sudo .devcontainer/host-setup.sh

set -euo pipefail

echo "Setting up host environment for Graph Protocol Contracts dev container..."

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: This script must be run as root (sudo)" >&2
  exit 1
fi

CACHE_DIRS=(
  "/cache/vscode-cache"
  "/cache/vscode-config"
  "/cache/vscode-data"
  "/cache/vscode-bin"
  "/cache/hardhat"
  "/cache/npm"
  "/cache/yarn"
  "/cache/pip"
  "/cache/pycache"
  "/cache/solidity"
  "/cache/foundry"
  "/cache/github"
  "/cache/apt"
  "/cache/apt-lib"
)

echo "Creating cache directories..."
for dir in "${CACHE_DIRS[@]}"; do
  if [ ! -d "$dir" ]; then
    echo "Creating $dir"
    mkdir -p "$dir"
    chmod 777 "$dir"
  else
    echo "$dir already exists"
  fi
done

# Note: Package-specific directories will be created by the project-setup.sh script
# inside the container, as they are tied to the project structure

echo "Host setup completed successfully!"
echo "You can now start or rebuild your dev container."
