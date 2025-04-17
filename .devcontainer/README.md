# Graph Protocol Contracts Dev Container

This directory contains configuration files for the Graph Protocol contracts development container.

> **Note:** This dev container setup is a work in progress and not fully portable yet due to dependencies on the base image (`rem/dev:latest`). Some paths and configurations are specific to the current environment.

## Overview

The dev container provides a consistent development environment with caching to improve performance.

### Key Components

1. **Docker Compose Configuration**: Defines the container setup, volume mounts, and environment variables
2. **Dockerfile**: Specifies the container image and installed tools
3. **project-setup.sh**: Configures the environment after container creation
4. **host-setup.sh**: Sets up the host environment before starting the container

## Cache System

The container uses a simple caching system:

1. **Host Cache Directories**: Created on the host and mounted into the container
   - `/cache/vscode-cache` → `/home/vscode/.cache`
   - `/cache/vscode-config` → `/home/vscode/.config`
   - `/cache/vscode-data` → `/home/vscode/.local/share`
   - `/cache/vscode-bin` → `/home/vscode/.local/bin`
   - `/cache/hardhat` → Package-specific cache directories

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
- Source shell customizations if available in PATH (currently depends on base image configuration)

## Environment Variables

Environment variables are defined in the `docker-compose.yml` file, making the configuration self-contained and predictable.

## Troubleshooting

If you encounter permission denied errors when trying to access directories, make sure you've run the `host-setup.sh` script on the host before starting the container:

```bash
sudo .devcontainer/host-setup.sh
```

For other issues, check the `project-setup.sh` script for any errors.
