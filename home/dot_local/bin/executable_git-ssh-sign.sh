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

if [ -z "${SSH_AUTH_SOCK:-}" ] || [ ! -S "${SSH_AUTH_SOCK}" ]; then
    for candidate in \
        "$runtime/wsl2-ssh-agent.sock" \
        "$runtime/ssh-agent.socket" \
        "$runtime/keyring/ssh" \
        "$runtime/gcr/ssh"; do
        if [ -S "$candidate" ]; then
            SSH_AUTH_SOCK="$candidate"
            export SSH_AUTH_SOCK
            break
        fi
    done
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
