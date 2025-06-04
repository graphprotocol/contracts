#!/bin/env bash
# Automatically configure Git to use SSH signing with forwarded SSH keys
set -euo pipefail

echo "Setting up Git SSH signing..."

# Check if SSH agent forwarding is working
if ! ssh-add -l &>/dev/null; then
  echo "ERROR: No SSH keys found in agent. SSH agent forwarding is not set up correctly."
  echo "SSH signing will not work without SSH agent forwarding."
  exit 1
fi

# Get the first SSH key from the agent
SSH_KEY=$(ssh-add -L | head -n 1)
if [ -z "$SSH_KEY" ]; then
  echo "ERROR: No SSH keys found in agent. SSH signing will not work."
  exit 1
fi

# Extract the key type and key content
KEY_TYPE=$(echo "$SSH_KEY" | awk '{print $1}')
KEY_CONTENT=$(echo "$SSH_KEY" | awk '{print $2}')

# Check if Git user settings are available
if [[ -z "${GIT_USER_NAME:-}" || -z "${GIT_USER_EMAIL:-}" ]]; then
  echo "WARNING: Git user settings (GIT_USER_NAME and/or GIT_USER_EMAIL) are not set."
  echo "Git commit signing will not be configured."
  echo "If you need Git commit signing, add these variables to your environment file."
  exit 0
fi

# Set Git user name from environment variable
echo "Setting Git user.name: $GIT_USER_NAME"
git config --global user.name "$GIT_USER_NAME"

# Set Git user email from environment variable
echo "Setting Git user.email: $GIT_USER_EMAIL"
git config --global user.email "$GIT_USER_EMAIL"

# Create the .ssh directory if it doesn't exist
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Create or update the allowed signers file
echo "Updating allowed signers file..."
ALLOWED_SIGNERS_FILE=~/.ssh/allowed_signers
SIGNER_LINE="$GIT_USER_EMAIL $KEY_TYPE $KEY_CONTENT"

# Create the file if it doesn't exist
if [ ! -f "$ALLOWED_SIGNERS_FILE" ]; then
  echo "$SIGNER_LINE" > "$ALLOWED_SIGNERS_FILE"
  echo "Created new allowed signers file."
else
  # Check if the key is already in the file
  if ! grep -q "$KEY_CONTENT" "$ALLOWED_SIGNERS_FILE"; then
    # Append the key if it's not already there
    echo "$SIGNER_LINE" >> "$ALLOWED_SIGNERS_FILE"
    echo "Added new key to allowed signers file."
  else
    echo "Key already exists in allowed signers file."
  fi
fi

chmod 600 "$ALLOWED_SIGNERS_FILE"

# Configure Git to use SSH signing
echo "Configuring Git to use SSH signing..."
git config --global gpg.format ssh
git config --global user.signingkey "key::$KEY_TYPE $KEY_CONTENT"
git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers
git config --global commit.gpgsign true

echo "Git SSH signing setup complete!"
echo "Your commits will now be automatically signed using your SSH key."
echo "Make sure this key is added to GitHub as a signing key in your account settings."
