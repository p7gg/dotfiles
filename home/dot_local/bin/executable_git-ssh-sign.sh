#!/bin/sh
#
# Git and GitButler sign commits by running `ssh-keygen -Y sign`. Unlike ssh(1),
# ssh-keygen does not read ~/.ssh/config, so the IdentityAgent entry does not
# apply; it only looks at SSH_AUTH_SOCK. Processes that do not start from a login
# shell (T3, OpenCode, systemd user units) do not inherit that variable, so
# ssh-keygen falls back to the passphrase-protected private key and opens an
# askpass dialog that nobody in an agent session can see. Point it at a reachable
# agent instead, and fail instead of prompting when there is no terminal.
#
# Git calls this through gpg.ssh.program; see docs/auth.md.

set -eu

runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# A socket file can outlive the agent that created it. Probe the inherited
# socket before trusting it, then prefer a reachable candidate that actually
# holds keys.
agent_has_keys() {
    ssh-add -l >/dev/null 2>&1
}

if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "${SSH_AUTH_SOCK}" ] && ! agent_has_keys; then
    unset SSH_AUTH_SOCK
fi

if [ -z "${SSH_AUTH_SOCK:-}" ] || [ ! -S "${SSH_AUTH_SOCK}" ]; then
    found=0
    for candidate in \
        "$runtime/ssh-agent.sock" \
        "$runtime/ssh-agent.socket" \
        "$runtime/keyring/ssh" \
        "$runtime/gcr/ssh"; do
        if [ -S "$candidate" ]; then
            # Export before probing: ssh-add runs as a child process and does
            # not see a plain shell variable.
            SSH_AUTH_SOCK="$candidate"
            export SSH_AUTH_SOCK
            if agent_has_keys; then
                found=1
                break
            fi
        fi
    done
    if [ "$found" -eq 0 ]; then
        unset SSH_AUTH_SOCK
    fi
fi

sign=0
previous=""
for argument in "$@"; do
    if [ "$previous" = "-Y" ] && [ "$argument" = "sign" ]; then
        sign=1
    fi
    previous="$argument"
done

if ! (: </dev/tty) 2>/dev/null; then
    # No controlling terminal: never wait for input that cannot be provided.
    # This also prevents ssh-keygen from spawning a hidden WSLg askpass dialog.
    SSH_ASKPASS_REQUIRE=never
    export SSH_ASKPASS_REQUIRE
    # Signing passes the payload as a file. Verification reads it from stdin, so
    # only detach stdin for signing.
    if [ "$sign" -eq 1 ]; then
        exec </dev/null
    fi
fi

exec /usr/bin/ssh-keygen "$@"
