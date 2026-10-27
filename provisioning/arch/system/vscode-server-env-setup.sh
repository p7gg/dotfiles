#!/bin/sh
#
# Installed to ~/.vscode-server/server-env-setup by provisioning/arch/auth.sh on WSL.
# VS Code's Remote-WSL launcher sources this file before starting the server,
# so the extension host and its git commands inherit the SSH agent socket.
#
# The Windows Bitwarden agent owns the key; there is no private key file in WSL
# to unlock. If the vault is locked, Bitwarden prompts on Windows when a signing
# request arrives.

export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh-agent.sock"
