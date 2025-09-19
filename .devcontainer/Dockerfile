FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

# Switch to root for installing packages
USER root

# Install additional dependencies
RUN apt update && DEBIAN_FRONTEND=noninteractive apt install -y \
    build-essential \
    jq \
    && apt clean \
    && rm -rf /var/lib/apt/lists/*

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
