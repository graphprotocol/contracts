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

The container uses a conservative caching approach to prevent cache corruption issues:

1. **Local Cache Directories**: Each container instance maintains its own cache directories
   - `vscode-cache` → `/home/vscode/.cache` (VS Code cache)
   - `vscode-config` → `/home/vscode/.config` (VS Code configuration)
   - `vscode-data` → `/home/vscode/.local/share` (VS Code data)
   - `vscode-bin` → `/home/vscode/.local/bin` (User binaries)

2. **Safe Caches Only**: Only caches that won't cause cross-branch issues are configured
   - GitHub CLI: `/home/vscode/.cache/github`
   - Python packages: `/home/vscode/.cache/pip`

3. **Intentionally Not Cached**: These tools use their default cache locations to avoid contamination
   - NPM (different dependency versions per branch)
   - Foundry, Solidity (different compilation artifacts per branch)
   - Hardhat (different build artifacts per branch)

## Setup Instructions

### Start the Dev Container

To start the dev container:

1. Open VS Code
2. Use the "Remote-Containers: Open Folder in Container" command
3. Select the repository directory (for example `/git/graphprotocol/contracts`)

When the container starts, the `project-setup.sh` script will automatically run and:

- Install project dependencies using pnpm
- Configure Git to use SSH signing with your forwarded SSH key
- Source shell customizations if available in PATH

## Environment Variables

Environment variables are defined in two places:

1. **docker-compose.yml**: Contains most of the environment variables for tools and caching
2. **Environment File**: Personal settings are stored in `/opt/configs/graphprotocol/contracts.env` on the host

### Git Configuration

To enable Git commit signing, add the following settings to your environment file:

```env
# Git settings for commit signing
GIT_USER_NAME=Your Name
GIT_USER_EMAIL=your.email@example.com
```

These environment variables are needed for Git commit signing to work properly. If they are not defined, Git commit signing will not be configured, but the container will still work for other purposes.

## Troubleshooting

### Cache Issues

If you encounter build or compilation issues that seem related to cached artifacts:

1. **Rebuild the container**: This will start with fresh local caches
2. **Clean project caches**: Run `pnpm clean` to clear project-specific build artifacts
3. **Clear node modules**: Delete `node_modules` and run `pnpm install` again

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
