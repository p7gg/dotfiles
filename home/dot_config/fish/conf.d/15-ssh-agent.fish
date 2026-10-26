# Export the socket to every fish process, including the non-interactive shell
# that starts the VS Code Remote-WSL server. Native GNOME already exports
# SSH_AUTH_SOCK through gnome-keyring. The socket lives under XDG_RUNTIME_DIR,
# which is recreated every boot, so there is no cache to go stale.
if not set -q SSH_AUTH_SOCK; or test -z "$SSH_AUTH_SOCK"
    if set -q XDG_RUNTIME_DIR; and test -S $XDG_RUNTIME_DIR/ssh-agent.socket
        set -gx SSH_AUTH_SOCK $XDG_RUNTIME_DIR/ssh-agent.socket
    end
end

if status is-interactive
    # Prefer the session agent (GNOME Keyring on native Arch). On WSL the
    # systemd ssh-agent.socket unit starts an agent on first connection.
    set -l agent_status 2
    if set -q SSH_AUTH_SOCK; and type -q ssh-add
        ssh-add -l >/dev/null 2>&1
        set agent_status $status
    end

    if test $agent_status -eq 2
        # Stale or missing socket: drop it and try the systemd-managed agent.
        set -e SSH_AUTH_SOCK
        set -e SSH_AGENT_PID
        if set -q XDG_RUNTIME_DIR; and test -S $XDG_RUNTIME_DIR/ssh-agent.socket
            set -gx SSH_AUTH_SOCK $XDG_RUNTIME_DIR/ssh-agent.socket
            ssh-add -l >/dev/null 2>&1
            set agent_status $status
        end
    end

    # Load the default key when the agent is running but empty. A protected
    # key prompts once per boot; later shells reuse the loaded key.
    if test $agent_status -eq 1; and tty -s
        if test -r $HOME/.ssh/id_ed25519
            ssh-add $HOME/.ssh/id_ed25519
        end
    else if test $agent_status -eq 2; and set -q SSH_AUTH_SOCK
        echo "ssh-agent: not reachable at $SSH_AUTH_SOCK; run provisioning/arch/auth.sh" >&2
    end
end
