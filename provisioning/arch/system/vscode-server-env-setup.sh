#!/bin/sh
#
# Installed to ~/.vscode-server/server-env-setup by provisioning/arch/auth.sh on WSL.
# VS Code's Remote-WSL launcher sources this file before starting the server,
# so the extension host and its git commands inherit the SSH agent socket.
#
# The key load is best-effort: a cancelled dialog must not block the server.
# When no terminal has loaded the key yet, ask for the passphrase through a
# WSLg dialog instead of failing the first git operation.

export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wsl2-ssh-agent.sock"

vscode_setup_ssh_key() {
    vscode_key="$HOME/.ssh/id_ed25519"
    vscode_askpass=""

    [ -r "$vscode_key" ] || return 0
    [ -r "$vscode_key.pub" ] || return 0
    [ -S "$SSH_AUTH_SOCK" ] || return 0
    [ -n "${DISPLAY:-}" ] || return 0

    command -v ssh-add >/dev/null 2>&1 || return 0
    command -v ssh-keygen >/dev/null 2>&1 || return 0
    command -v timeout >/dev/null 2>&1 || return 0

    vscode_askpass="$(command -v x11-ssh-askpass 2>/dev/null || true)"
    if [ -z "$vscode_askpass" ] && [ -x /usr/lib/ssh/x11-ssh-askpass ]; then
        vscode_askpass=/usr/lib/ssh/x11-ssh-askpass
    fi
    [ -n "$vscode_askpass" ] || return 0

    vscode_fingerprint="$(ssh-keygen -lf "$vscode_key.pub" 2>/dev/null | awk '{print $2}')"
    [ -n "$vscode_fingerprint" ] || return 0

    if ssh-add -l 2>/dev/null | grep -qF "$vscode_fingerprint"; then
        return 0
    fi

    printf 'ssh-agent: loading %s (passphrase dialog)\n' "$vscode_key"
    if ! SSH_ASKPASS="$vscode_askpass" SSH_ASKPASS_REQUIRE=force \
        timeout 120 ssh-add "$vscode_key" </dev/null >/dev/null 2>&1; then
        printf 'ssh-agent: key not loaded (dialog cancelled or timed out)\n' >&2
    fi
}

vscode_setup_ssh_key
unset -f vscode_setup_ssh_key
unset vscode_key vscode_askpass vscode_fingerprint
