FROM mcr.microsoft.com/devcontainers/base:debian

# Set non-interactive frontend for apt
ENV DEBIAN_FRONTEND=noninteractive

# Switch to root for installing packages
USER root

# Install additional dependencies
RUN apt update && apt install -y \
    build-essential \
    curl \
    jq \
    python3 \
    python3-pip \
    python3-venv \
    pipx \
    && apt clean \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 20.x using NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt update && \
    apt install -y nodejs && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# Install Solidity compiler using pipx (isolated environment)
RUN pipx install solc-select && \
    pipx ensurepath && \
    /root/.local/bin/solc-select install 0.8.27 && \
    /root/.local/bin/solc-select use 0.8.27 && \
    # Copy binaries to /usr/local/bin with proper permissions (not symlinks)
    cp /root/.local/bin/solc /usr/local/bin/solc && \
    cp /root/.local/bin/solc-select /usr/local/bin/solc-select && \
    chmod 755 /usr/local/bin/solc && \
    chmod 755 /usr/local/bin/solc-select && \
    # Make sure pipx directory is accessible
    chmod -R a+rx /root/.local/pipx && \
    # Set up for vscode user
    mkdir -p /home/vscode/.solc-select && \
    cp -r /root/.solc-select/* /home/vscode/.solc-select/ && \
    chown -R vscode:vscode /home/vscode/.solc-select

RUN npm install -g ethers@6.13.4

# Install cloc for code analysis
RUN npm install -g cloc

# Install Foundry for Anvil (as root for global installation)
RUN curl -L https://foundry.paradigm.xyz | bash && \
    /root/.foundry/bin/foundryup && \
    # Copy binaries to /usr/local/bin with proper permissions
    cp /root/.foundry/bin/anvil /usr/local/bin/anvil && \
    cp /root/.foundry/bin/cast /usr/local/bin/cast && \
    cp /root/.foundry/bin/forge /usr/local/bin/forge && \
    cp /root/.foundry/bin/chisel /usr/local/bin/chisel && \
    # Ensure proper permissions
    chmod 755 /usr/local/bin/anvil && \
    chmod 755 /usr/local/bin/cast && \
    chmod 755 /usr/local/bin/forge && \
    chmod 755 /usr/local/bin/chisel

# Set up yarn and pnpm
RUN corepack enable && \
    corepack prepare yarn@4.0.2 --activate && \
    corepack prepare pnpm@9.0.6 --activate

# Ensure all users have access to the tools
RUN chmod 755 /usr/local/bin/* && \
    # Create a directory for vscode user's binaries
    mkdir -p /home/vscode/.local/bin && \
    chown -R vscode:vscode /home/vscode/.local/bin

# Switch back to vscode user
USER vscode

# Set environment variables
ENV PATH="/usr/local/bin:/home/vscode/.foundry/bin:/home/vscode/.local/bin:/root/.local/bin:$PATH"

# Create .bashrc additions for PATH
RUN echo 'export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"' >> $HOME/.bashrc

# Set the default command
CMD ["sleep", "infinity"]
