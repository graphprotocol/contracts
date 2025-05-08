# Graph Protocol Contracts Dev Container

This directory contains configuration files for the Graph Protocol contracts development container.

> **Note:** This dev container setup is a work in progress and will not be fully portable.

## Overview

The dev container provides a consistent development environment with caching to improve performance.

### Key Components

1. **Docker Compose Configuration**: Defines the container setup, volume mounts, and environment variables
2. **Dockerfile**: Specifies the container image and installed tools
3. **project-setup.sh**: Configures the environment after container creation
4. **host-setup.sh**: Sets up the host environment before starting the container
5. **setup-git-signing.sh**: Automatically configures Git to use SSH signing with forwarded SSH keys

## Cache System

The container uses a simple caching system:

1. **Host Cache Directories**: Created on the host and mounted into the container
   - `/cache/vscode-cache` → `/home/vscode/.cache`
   - `/cache/vscode-config` → `/home/vscode/.config`
   - `/cache/vscode-data` → `/home/vscode/.local/share`
   - `/cache/vscode-bin` → `/home/vscode/.local/bin`
   - `/cache/*` → Tool-specific cache directories

2. **Package Cache Symlinks**: Created inside the container by project-setup.sh
   - Each package's cache directory is symlinked to a subdirectory in `/cache/hardhat`

## Setup Instructions

### 1. Host Setup (One-time)

Before starting the dev container for the first time, run the included host setup script to create the necessary cache directories on the host:

```bash
sudo /git/graphprotocol/contracts/.devcontainer/host-setup.sh
```

This script creates all required cache directories on the host, including:

- Standard VS Code directories (for .cache, .config, etc.)
- Tool-specific cache directories (for npm, yarn, cargo, etc.)

The script is idempotent and can be run multiple times without issues.

### 2. Start the Dev Container

After creating the cache directories, you can start the dev container:

1. Open VS Code
2. Use the "Remote-Containers: Open Folder in Container" command
3. Select the repository directory

When the container starts, the `project-setup.sh` script will automatically run and:

- Create package-specific cache directories
- Set up symlinks for package cache directories
- Install project dependencies using yarn
- Configure Git to use SSH signing with your forwarded SSH key
- Source shell customizations if available in PATH (currently depends on base image configuration)

## Environment Variables

Environment variables are defined in two places:

1. **docker-compose.yml**: Contains most of the environment variables for tools and caching
2. **Environment File**: Personal settings are stored in `/opt/configs/graphprotocol/contracts.env`

### Git Configuration

To enable Git commit signing, add the following settings to your environment file:

```env
# Git settings for commit signing
GIT_USER_NAME=Your Name
GIT_USER_EMAIL=your.email@example.com
```

These environment variables are needed for Git commit signing to work properly. If they are not defined, Git commit signing will not be configured, but the container will still work for other purposes.

## Troubleshooting

If you encounter permission denied errors when trying to access directories, make sure you've run the `host-setup.sh` script on the host before starting the container:

```bash
sudo .devcontainer/host-setup.sh
```

### Git SSH Signing Issues

If you encounter issues with Git SSH signing:

1. **SSH Agent Forwarding**: Make sure SSH agent forwarding is properly set up in your VS Code settings
2. **GitHub Configuration**: Ensure your SSH key is added to GitHub as a signing key in your account settings
3. **Manual Setup**: If automatic setup fails, you can manually configure SSH signing:

```bash
# Check available SSH keys
ssh-add -l

# Configure Git to use SSH signing
git config --global gpg.format ssh
git config --global user.signingkey "key::ssh-ed25519 YOUR_KEY_CONTENT"
git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers
git config --global commit.gpgsign true

# Create allowed signers file
echo "your.email@example.com ssh-ed25519 YOUR_KEY_CONTENT" > ~/.ssh/allowed_signers
```

For other issues, check the `project-setup.sh` and `setup-git-signing.sh` scripts for any errors.
