#!/bin/bash
# Project-specific setup script for graph
set -euo pipefail

echo "Running project-specific setup for graph..."

# Get the script directory and repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Script directory: $SCRIPT_DIR"
echo "Repository root: $REPO_ROOT"

# Ensure pnpm cache directory exists with correct permissions
echo "Setting up pnpm cache directory..."
# Fix ownership if the directory exists but is owned by root
if [ -d ~/.cache/pnpm ] && [ "$(stat -c %U ~/.cache/pnpm 2>/dev/null || echo 'vscode')" = "root" ]; then
  echo "Fixing pnpm cache directory ownership..."
  sudo chown -R vscode:vscode ~/.cache/pnpm
fi
# Create the directory structure with proper permissions
if mkdir -p ~/.cache/pnpm/store 2>/dev/null || sudo mkdir -p ~/.cache/pnpm/store; then
  # Ensure the directory is writable by the vscode user (use sudo if needed)
  if [ "$(stat -c %U ~/.cache/pnpm 2>/dev/null || echo 'vscode')" = "root" ]; then
    sudo chown -R vscode:vscode ~/.cache/pnpm
  fi
  chmod -R 755 ~/.cache/pnpm
  echo "✓ pnpm cache directory created successfully"
else
  echo "❌ Failed to create pnpm cache directory"
  exit 1
fi

# Install project dependencies
echo "Installing project dependencies..."
if [ -f "$REPO_ROOT/package.json" ]; then
  echo "Running pnpm to install dependencies..."
  cd "$REPO_ROOT"
  # Note: With set -e, if pnpm fails, the script will exit
  # This is desirable as we want to ensure dependencies are properly installed
  pnpm install
else
  echo "No package.json found in the root directory, skipping dependency installation"
fi

# Add CONTAINER_BIN_PATH to PATH if it's set
if [ -n "${CONTAINER_BIN_PATH:-}" ]; then
  echo "CONTAINER_BIN_PATH is set to: $CONTAINER_BIN_PATH"
  echo "Adding CONTAINER_BIN_PATH to PATH..."

  # Add to current PATH
  export PATH="$CONTAINER_BIN_PATH:$PATH"

  # Add to .bashrc if not already there
  if ! grep -q "export PATH=\"\$CONTAINER_BIN_PATH:\$PATH\"" "$HOME/.bashrc"; then
    echo "Adding CONTAINER_BIN_PATH to .bashrc..."
    echo '
# Add CONTAINER_BIN_PATH to PATH if set
if [ -n "${CONTAINER_BIN_PATH:-}" ]; then
  export PATH="$CONTAINER_BIN_PATH:$PATH"
fi' >> "$HOME/.bashrc"
  fi

  echo "CONTAINER_BIN_PATH added to PATH"
else
  echo "CONTAINER_BIN_PATH is not set, skipping PATH modification"
fi

# Source shell customizations if available in PATH
if command -v shell-customizations &> /dev/null; then
  SHELL_CUSTOMIZATIONS_PATH=$(command -v shell-customizations)
  echo "Found shell customizations in PATH at: ${SHELL_CUSTOMIZATIONS_PATH}"
  echo "Sourcing shell customizations..."
  source "${SHELL_CUSTOMIZATIONS_PATH}"

  # Add to .bashrc if not already there
  if ! grep -q "source.*shell-customizations" "$HOME/.bashrc"; then
    echo "Adding shell customizations to .bashrc..."
    echo "source ${SHELL_CUSTOMIZATIONS_PATH}" >> "$HOME/.bashrc"
  fi
else
  echo "Shell customizations not found in PATH, skipping..."
fi

# Set up Git SSH signing
if [ -f "$SCRIPT_DIR/setup-git-signing.sh" ]; then
  "$SCRIPT_DIR/setup-git-signing.sh"
else
  echo "WARNING: setup-git-signing.sh not found, skipping Git SSH signing setup"
fi

echo "Project-specific setup completed"
