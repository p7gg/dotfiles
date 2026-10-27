#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    WRAPPER="$REPO_ROOT/home/dot_local/bin/executable_git-ssh-sign.sh"
    TEST_TMP="$(mktemp -d /tmp/git-ssh-sign.XXXXXX)"
    TEST_RUNTIME="$TEST_TMP/runtime"
    TEST_KEY="$TEST_TMP/id_ed25519"
    TEST_AGENT_SOCKET="$TEST_RUNTIME/wsl2-ssh-agent.sock"

    mkdir -p "$TEST_RUNTIME"
    ssh-keygen -q -t ed25519 -N "" -C "test@example.com" -f "$TEST_KEY"
}

teardown() {
    if [[ -n "${SSH_AGENT_PID:-}" ]]; then
        ssh-agent -k >/dev/null 2>&1 || true
    fi
    rm -rf "$TEST_TMP"
}

start_agent() {
    eval "$(ssh-agent -s -a "$TEST_AGENT_SOCKET")" >/dev/null
    ssh-add "$TEST_KEY" >/dev/null 2>&1
}

@test "authorized_keys comments contain no personal email or stale GitHub titles" {
    local keys="$REPO_ROOT/home/private_dot_ssh/private_authorized_keys"

    ! grep -Eq '^ssh-[^ ]+ [^ ]+ .*@' "$keys"
    ! grep -Fq 'gh-cli' "$keys"
    grep -Fq 'arch-wsl-auth, arch-wsl-signing' "$keys"
    grep -Fq 'P7-LAPTOP-auth, P7-LAPTOP-signing' "$keys"
}

@test "git-ssh-sign finds the Windows bridge when SSH_AUTH_SOCK is unset" {
    start_agent
    printf 'payload\n' >"$TEST_TMP/msg"

    run env -u SSH_AUTH_SOCK -u SSH_AGENT_PID XDG_RUNTIME_DIR="$TEST_RUNTIME" \
        "$WRAPPER" -Y sign -n git -f "$TEST_KEY.pub" "$TEST_TMP/msg"

    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/msg.sig" ]
}

@test "git-ssh-sign fails instead of prompting without a terminal" {
    command -v setsid >/dev/null || skip "setsid is not available"
    ssh-keygen -q -t ed25519 -N "secret" -f "$TEST_TMP/protected"
    printf 'payload\n' >"$TEST_TMP/msg"

    run env -u SSH_AUTH_SOCK -u SSH_AGENT_PID XDG_RUNTIME_DIR="$TEST_RUNTIME" \
        setsid -w timeout 5 "$WRAPPER" -Y sign -n git -f "$TEST_TMP/protected.pub" "$TEST_TMP/msg"

    [ "$status" -ne 0 ]
    [ "$status" -ne 124 ]
    [[ "$output" == *"passphrase"* ]]
}

@test "git commit signs through the wrapper without SSH_AUTH_SOCK" {
    start_agent
    local repo="$TEST_TMP/repo"
    local allowed="$TEST_TMP/allowed_signers"

    git init -q "$repo"
    git -C "$repo" config user.name "Test User"
    git -C "$repo" config user.email "test@example.com"
    git -C "$repo" config gpg.format ssh
    git -C "$repo" config user.signingkey "$TEST_KEY.pub"
    git -C "$repo" config gpg.ssh.program "$WRAPPER"
    git -C "$repo" config gpg.ssh.allowedSignersFile "$allowed"
    git -C "$repo" config commit.gpgsign true
    printf 'test@example.com %s\n' "$(awk '{print $1, $2}' "$TEST_KEY.pub")" >"$allowed"
    printf 'content\n' >"$repo/file"
    git -C "$repo" add file

    run env -u SSH_AUTH_SOCK -u SSH_AGENT_PID XDG_RUNTIME_DIR="$TEST_RUNTIME" \
        git -C "$repo" commit -m "signed"

    [ "$status" -eq 0 ]

    run git -C "$repo" log --show-signature -1

    [ "$status" -eq 0 ]
    [[ "$output" == *'Good "git" signature'* ]]
}
