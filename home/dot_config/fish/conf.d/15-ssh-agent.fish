# Export the Windows agent bridge socket to every fish process, including the
# non-interactive shell that starts the VS Code Remote-WSL server. Native GNOME
# exports SSH_AUTH_SOCK through gnome-keyring; on WSL the bridge replaces the
# separate ssh-agent. The socket lives under XDG_RUNTIME_DIR, which is recreated
# every boot, so there is no cache to go stale.
if not set -q SSH_AUTH_SOCK; or test -z "$SSH_AUTH_SOCK"
    if set -q XDG_RUNTIME_DIR; and test -S $XDG_RUNTIME_DIR/wsl2-ssh-agent.sock
        set -gx SSH_AUTH_SOCK $XDG_RUNTIME_DIR/wsl2-ssh-agent.sock
    end
end

if status is-interactive
    set -l agent_status 2
    if set -q SSH_AUTH_SOCK; and type -q ssh-add
        ssh-add -l >/dev/null 2>&1
        set agent_status $status
    end

    # Load the default key when the bridge is running but empty. A protected
    # key prompts once per Windows boot; later shells reuse the loaded key.
    if test $agent_status -eq 1; and tty -s
        if test -r $HOME/.ssh/id_ed25519
            ssh-add $HOME/.ssh/id_ed25519
        end
    else if test $agent_status -eq 2; and set -q SSH_AUTH_SOCK
        echo "ssh-agent: not reachable at $SSH_AUTH_SOCK; run provisioning/arch/auth.sh" >&2
    end
end
