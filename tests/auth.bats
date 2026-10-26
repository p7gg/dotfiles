#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
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

    run env -u WSL_DISTRO_NAME HOME="$test_home" PATH="$test_bin:$PATH" \
        "$REPO_ROOT/arch/auth.sh" --check --email test@example.com \
        --skip-gh --skip-gcloud --skip-tailscale --skip-mcp
}

@test "auth --help and unknown options are handled" {
    run "$REPO_ROOT/arch/auth.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: arch/auth.sh"* ]]
    [[ "$output" == *"--bws-account NAME"* ]]

    run "$REPO_ROOT/arch/auth.sh" --not-a-real-option
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
