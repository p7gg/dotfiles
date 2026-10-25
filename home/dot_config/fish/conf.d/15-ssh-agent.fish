if status is-interactive
    # Reuse an ssh-agent started by arch/auth.sh. Native GNOME already provides
    # SSH_AUTH_SOCK through gnome-keyring, so this is mainly for WSL.
    set -l agent_env $HOME/.ssh/agent.env

    if not set -q SSH_AUTH_SOCK
        if test -r $agent_env
            source $agent_env
        end
    end

    if set -q SSH_AUTH_SOCK
        if type -q ssh-add
            ssh-add -l >/dev/null 2>&1
            set -l agent_status $status
            if test $agent_status -eq 2
                # Stale socket: forget it and let arch/auth.sh start a new agent.
                set -e SSH_AUTH_SOCK
                set -e SSH_AGENT_PID
            end
        end
    end
end
