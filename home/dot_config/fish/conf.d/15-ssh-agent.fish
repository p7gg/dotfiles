# Export the Windows SSH agent relay socket to every fish process, including
# the non-interactive shell that starts the VS Code Remote-WSL server. Native
# GNOME exports SSH_AUTH_SOCK through gnome-keyring; on WSL the relay replaces
# the separate ssh-agent. The socket lives under XDG_RUNTIME_DIR, which is
# recreated every boot, so there is no cache to go stale.
if not set -q SSH_AUTH_SOCK; or test -z "$SSH_AUTH_SOCK"
    if set -q XDG_RUNTIME_DIR; and test -S $XDG_RUNTIME_DIR/ssh-agent.sock
        set -gx SSH_AUTH_SOCK $XDG_RUNTIME_DIR/ssh-agent.sock
    end
end
