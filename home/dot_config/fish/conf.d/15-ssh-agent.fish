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
                # Stale socket: forget it, then try the saved agent environment
                # once before giving up.
                set -e SSH_AUTH_SOCK
                set -e SSH_AGENT_PID

                if test -r $agent_env
                    source $agent_env
                    if set -q SSH_AUTH_SOCK
                        ssh-add -l >/dev/null 2>&1
                        set agent_status $status
                        if test $agent_status -eq 2
                            set -e SSH_AUTH_SOCK
                            set -e SSH_AGENT_PID
                        end
                    end
                end

                if not set -q SSH_AUTH_SOCK
                    echo "ssh-agent: not running; run ./arch/auth.sh to start one" >&2
                end
            end
        end
    end
end
