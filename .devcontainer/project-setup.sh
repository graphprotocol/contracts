#!/bin/bash
# Project-specific setup script for graph
set -euo pipefail

echo "Running project-specific setup for graph..."

# Get the script directory and repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "Script directory: $SCRIPT_DIR"
echo "Repository root: $REPO_ROOT"

# Check if cache directories exist
echo "Checking if cache directories exist..."

# Required cache directories
REQUIRED_DIRS=(
  "/cache/hardhat"
  "/cache/npm"
  "/cache/yarn"
)

# Check if required directories exist
missing_dirs=()
for dir in "${REQUIRED_DIRS[@]}"; do
  if [ ! -d "$dir" ]; then
    missing_dirs+=("$dir")
  fi
done

# If any required directories are missing, show a warning
# Note: With set -u, we need to ensure missing_dirs is always initialized
if [ "${#missing_dirs[@]}" -gt 0 ]; then
  echo "WARNING: The following required cache directories are missing:"
  for dir in "${missing_dirs[@]}"; do
    echo "  - $dir"
  done
  echo "Please run the host setup script before starting the container:"
  echo "  sudo .devcontainer/host-setup.sh"
  echo "Continuing anyway, but you may encounter issues..."
fi

# Set up cache symlinks
echo "Setting up cache symlinks..."

# Function to create symlinks for package cache directories
setup_cache_symlink() {
  # With set -u, we need to ensure all parameters are provided
  if [ "$#" -ne 1 ]; then
    echo "Error: setup_cache_symlink requires exactly 1 argument (package_name)"
    return 1
  fi

  local package_name=$1
  local cache_path="$REPO_ROOT/packages/${package_name}/cache"
  local cache_dest="/cache/hardhat/${package_name}"

  # Skip if the package directory doesn't exist
  if [ ! -d "$REPO_ROOT/packages/${package_name}" ]; then
    return
  fi

  # Create the package-specific cache directory if it doesn't exist
  if [ ! -d "$cache_dest" ]; then
    echo "Creating package-specific cache directory: $cache_dest"
    mkdir -p "$cache_dest"
    chmod -R 777 "$cache_dest"
  fi

  # Create the symlink (will replace existing symlink if it exists)
  ln -sf "$cache_dest" "$cache_path"
  echo "Created symlink for ${package_name} cache"
}

# Set up cache symlinks for main packages
setup_cache_symlink "contracts"
setup_cache_symlink "horizon"
setup_cache_symlink "subgraph-service"
setup_cache_symlink "data-edge"

# Install project dependencies
echo "Installing project dependencies..."
if [ -f "$REPO_ROOT/package.json" ]; then
  echo "Running yarn to install dependencies..."
  cd "$REPO_ROOT"
  # Note: With set -e, if yarn fails, the script will exit
  # This is desirable as we want to ensure dependencies are properly installed
  yarn
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
