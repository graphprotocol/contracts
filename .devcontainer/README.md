# Graph Protocol Contracts Dev Container

This directory contains configuration files for the Graph Protocol contracts development container.

> **Note:** This dev container setup is a work in progress and will not be fully portable.

## Overview

The dev container provides a consistent development environment with caching to improve performance.

### Key Components

1. **Docker Compose Configuration**: Defines the container setup, volume mounts, and environment variables
2. **Dockerfile**: Specifies the container image and installed tools
3. **project-setup.sh**: Configures the environment after container creation

## Setup Instructions

### Start the Dev Container

To start the dev container:

1. Open VS Code
2. Use the "Remote-Containers: Open Folder in Container" command
3. Select the repository directory (for example `/git/graphprotocol/contracts`)

When the container starts, the `project-setup.sh` script will automatically run and:

- Install project dependencies using pnpm
- Configure basic Git settings (user.name, user.email) from environment variables
- Source shell customizations if available in PATH

## Environment Variables

Environment variables are defined in two places:

1. **docker-compose.yml**: Contains most of the environment variables for tools and caching
2. **Environment File**: Personal settings are stored in `/opt/configs/graphprotocol/contracts.env` on the host

### Git Configuration

To configure Git user settings, add the following to your environment file:

```env
# Git settings
GIT_USER_NAME=Your Name
GIT_USER_EMAIL=your.email@example.com
```

These environment variables are needed for Git commit signing to work properly. If they are not defined, Git commit signing will not be configured, but the container will still work for other purposes.

## Troubleshooting

### Build Issues

If you encounter build or compilation issues:

1. **Rebuild the container**: This will start with fresh isolated caches
2. **Clean project caches**: Run `pnpm clean` to clear project-specific build artifacts
3. **Clear node modules**: Delete `node_modules` and run `pnpm install` again

### Git Authentication Issues

If you encounter issues with Git operations:

1. **GitHub CLI**: Use `gh auth login` to authenticate with GitHub
2. **Git Configuration**: Set user.name and user.email if not configured via environment variables
3. **Commit Signing**: Handle commit signing on your host machine for security

For other issues, check the `project-setup.sh` script for any errors.
