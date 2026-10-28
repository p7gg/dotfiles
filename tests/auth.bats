#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

# --check only needs the daemon on PATH; it never starts it.
stub_gnome_keyring_daemon() {
    local test_bin="$1"

    cat >"$test_bin/gnome-keyring-daemon" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$test_bin/gnome-keyring-daemon"
}

auth_check() {
    local secret_tool_output="$1"
    local test_bin="$BATS_TEST_TMPDIR/bin"
    local test_home="$BATS_TEST_TMPDIR/home"

    mkdir -p "$test_bin" "$test_home/.ssh"

    cat >"$test_bin/bws" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    if [[ -n "$secret_tool_output" ]]; then
        cat >"$test_bin/secret-tool" <<'EOF'
#!/usr/bin/env bash
printf '[%s]\n' '/org/freedesktop/secrets/collection/login/1'
EOF
    else
        # libsecret's search exits 0 even when no item matches.
        cat >"$test_bin/secret-tool" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    fi
    chmod +x "$test_bin/bws" "$test_bin/secret-tool"
    stub_gnome_keyring_daemon "$test_bin"

    run env -u WSL_DISTRO_NAME HOME="$test_home" PATH="$test_bin:$PATH" \
        "$REPO_ROOT/provisioning/arch/auth.sh" --check --email test@example.com \
        --skip-gh --skip-gcloud --skip-tailscale --skip-mcp
}

@test "auth --help and unknown options are handled" {
    run "$REPO_ROOT/provisioning/arch/auth.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: provisioning/arch/auth.sh"* ]]
    [[ "$output" == *"--bws-account NAME"* ]]

    run "$REPO_ROOT/provisioning/arch/auth.sh" --not-a-real-option
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown option: --not-a-real-option"* ]]
}

@test "auth --check reports a missing native BWS token" {
    auth_check ""

    [ "$status" -eq 1 ]
    [[ "$output" == *"BWS token is not stored"* ]]
    [[ "$output" != *"Bitwarden Secrets Manager token is already stored"* ]]
}

@test "auth --check skips BWS setup when the keyring entry exists" {
    auth_check "present"

    [[ "$output" == *"Bitwarden Secrets Manager token is already stored"* ]]
    [[ "$output" != *"BWS token is not stored"* ]]
}

@test "auth --check uses GNOME Keyring on WSL too" {
    local test_bin="$BATS_TEST_TMPDIR/bin"
    local test_home="$BATS_TEST_TMPDIR/home"

    mkdir -p "$test_bin" "$test_home/.ssh"

    cat >"$test_bin/bws" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat >"$test_bin/secret-tool" <<'EOF'
#!/usr/bin/env bash
printf '[%s]\n' '/org/freedesktop/secrets/collection/login/1'
EOF
    chmod +x "$test_bin/bws" "$test_bin/secret-tool"
    stub_gnome_keyring_daemon "$test_bin"

    run env WSL_DISTRO_NAME=arch HOME="$test_home" PATH="$test_bin:$PATH" \
        "$REPO_ROOT/provisioning/arch/auth.sh" --check --email test@example.com \
        --skip-gh --skip-gcloud --skip-tailscale --skip-mcp

    [[ "$output" == *"Bitwarden Secrets Manager token is already stored"* ]]
    [[ "$output" == *"replace: secret-tool store"* ]]
    [[ "$output" != *"BWS token is not stored"* ]]
    [[ "$output" != *"pass insert"* ]]
}

@test "auth --check reports a legacy pass entry instead of using it" {
    local test_bin="$BATS_TEST_TMPDIR/bin"
    local test_home="$BATS_TEST_TMPDIR/home"

    mkdir -p "$test_bin" "$test_home/.ssh" "$test_home/.password-store/bitwarden"
    : >"$test_home/.password-store/bitwarden/bws-token.gpg"

    cat >"$test_bin/bws" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    # libsecret's search exits 0 even when no item matches.
    cat >"$test_bin/secret-tool" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$test_bin/bws" "$test_bin/secret-tool"
    stub_gnome_keyring_daemon "$test_bin"

    run env WSL_DISTRO_NAME=arch HOME="$test_home" PATH="$test_bin:$PATH" \
        "$REPO_ROOT/provisioning/arch/auth.sh" --check --email test@example.com \
        --skip-gh --skip-gcloud --skip-tailscale --skip-mcp

    [ "$status" -eq 1 ]
    [[ "$output" == *"legacy pass entry found"* ]]
    [[ "$output" == *"secret-tool store"* ]]
    [[ "$output" == *"pass rm -f bitwarden/bws-token"* ]]
}
