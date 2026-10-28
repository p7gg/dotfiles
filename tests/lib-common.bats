#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # shellcheck source=provisioning/arch/lib/common.sh
    source "$REPO_ROOT/provisioning/arch/lib/common.sh"
    DRY_RUN=0
    ERROR_REPORTED=0
    ROOT_RUNNER=run_cmd
    TEST_TMP="$(mktemp -d)"
}

teardown() {
    cleanup_tmp
    rm -rf "$TEST_TMP"
}

@test "filter_packages strips comments, blanks, and surrounding spaces" {
    cat >"$TEST_TMP/packages.txt" <<'EOF'
# comment
  fish
bat   # trailing comment

   eza
EOF

    run filter_packages "$TEST_TMP/packages.txt"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "fish" ]
    [ "${lines[1]}" = "bat" ]
    [ "${lines[2]}" = "eza" ]
}

@test "validate_package_lists accepts valid names and rejects option-like names" {
    printf '%s\n' 'fish' 'git-delta' 'google-cloud-cli' >"$TEST_TMP/valid.txt"
    run validate_package_lists "$TEST_TMP/valid.txt"
    [ "$status" -eq 0 ]

    printf '%s\n' '-bad' >"$TEST_TMP/invalid.txt"
    run validate_package_lists "$TEST_TMP/invalid.txt"
    [ "$status" -ne 0 ]
}

@test "filter_optional_packages extracts package names from a font catalog" {
    cat >"$TEST_TMP/fonts.txt" <<'EOF'
# Optional fonts
ttf-firacode-nerd|Fira Code
otf-geist-mono-nerd|Geist Mono
EOF

    run filter_optional_packages "$TEST_TMP/fonts.txt"

    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "ttf-firacode-nerd" ]
    [ "${lines[1]}" = "otf-geist-mono-nerd" ]
}

@test "validate_font_catalog accepts pkg|name entries and rejects malformed ones" {
    printf '%s\n' 'ttf-firacode-nerd|Fira Code' >"$TEST_TMP/valid-fonts.txt"
    run validate_font_catalog "$TEST_TMP/valid-fonts.txt"
    [ "$status" -eq 0 ]

    printf '%s\n' 'ttf-firacode-nerd' >"$TEST_TMP/missing-name.txt"
    run validate_font_catalog "$TEST_TMP/missing-name.txt"
    [ "$status" -ne 0 ]

    printf '%s\n' 'ttf-firacode-nerd|Fira Code' 'ttf-firacode-nerd|Duplicate' \
        >"$TEST_TMP/duplicate.txt"
    run validate_font_catalog "$TEST_TMP/duplicate.txt"
    [ "$status" -ne 0 ]
}

@test "ini_set_key updates, adds, and preserves sections" {
    cat >"$TEST_TMP/wsl.conf" <<'EOF'
[user]
default=old

[interop]
appendWindowsPath=true
EOF

    ini_set_key "$TEST_TMP/wsl.conf" user default new
    ini_set_key "$TEST_TMP/wsl.conf" network hostname arch-wsl

    grep -qx 'default=new' "$TEST_TMP/wsl.conf"
    grep -qx 'appendWindowsPath=true' "$TEST_TMP/wsl.conf"
    grep -qx '\[network\]' "$TEST_TMP/wsl.conf"
    grep -qx 'hostname=arch-wsl' "$TEST_TMP/wsl.conf"
}

@test "run_cmd in dry-run mode prints but does not execute" {
    DRY_RUN=1
    run run_cmd touch "$TEST_TMP/should-not-exist"

    [ "$status" -eq 0 ]
    [[ "$output" == *"touch"* ]]
    [ ! -e "$TEST_TMP/should-not-exist" ]
}

@test "has_authorized_key rejects comment-only files" {
    printf '%s\n' '# comment' '' >"$TEST_TMP/comments-only"
    run has_authorized_key "$TEST_TMP/comments-only"
    [ "$status" -ne 0 ]

    printf '%s\n' 'ssh-ed25519 AAAA test@example' >"$TEST_TMP/key"
    run has_authorized_key "$TEST_TMP/key"
    [ "$status" -eq 0 ]
}

@test "ensure_login_keyring is a no-op outside WSL" {
    unset WSL_DISTRO_NAME
    if is_wsl; then
        skip "test host is WSL"
    fi

    export XDG_DATA_HOME="$TEST_TMP/data"
    run ensure_login_keyring

    [ "$status" -eq 0 ]
    [ ! -e "$TEST_TMP/data/keyrings/login.keyring" ]
}

@test "ensure_login_keyring reports the WSL keyring in dry-run mode" {
    local test_bin="$TEST_TMP/bin"

    # Dry-run only checks that the daemon is on PATH; it never starts it.
    mkdir -p "$test_bin"
    cat >"$test_bin/gnome-keyring-daemon" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$test_bin/gnome-keyring-daemon"

    export WSL_DISTRO_NAME=arch
    export XDG_DATA_HOME="$TEST_TMP/data"
    export PATH="$test_bin:$PATH"
    DRY_RUN=1

    run ensure_login_keyring

    [ "$status" -eq 0 ]
    [[ "$output" == *"Would create the WSL login keyring"* ]]
    [ ! -e "$TEST_TMP/data/keyrings/login.keyring" ]
}

@test "cleanup_tmp removes registered files" {
    touch "$TEST_TMP/temp-file"
    register_tmp "$TEST_TMP/temp-file"
    cleanup_tmp

    [ ! -e "$TEST_TMP/temp-file" ]
}

@test "cleanup_tmp removes registered directories" {
    mkdir -p "$TEST_TMP/temp-dir/nested"
    register_tmp_dir "$TEST_TMP/temp-dir"
    cleanup_tmp

    [ ! -e "$TEST_TMP/temp-dir" ]
}

@test "backup_file keeps only the newest timestamped backups" {
    mkdir -p "$TEST_TMP/etc"
    printf '%s\n' 'old' >"$TEST_TMP/etc/app.conf"
    touch "$TEST_TMP/etc/app.conf.bak.20200101000001"
    touch "$TEST_TMP/etc/app.conf.bak.20200101000002"
    touch "$TEST_TMP/etc/app.conf.bak.20200101000003"
    touch "$TEST_TMP/etc/app.conf.bak.20200101000004"

    backup_file "$TEST_TMP/etc/app.conf"

    [ -f "$BACKUP_PATH" ]
    [ "$(find "$TEST_TMP/etc" -name 'app.conf.bak.[0-9]*' | wc -l)" -eq 3 ]
    [ ! -e "$TEST_TMP/etc/app.conf.bak.20200101000001" ]
    [ ! -e "$TEST_TMP/etc/app.conf.bak.20200101000002" ]
    [ -e "$TEST_TMP/etc/app.conf.bak.20200101000004" ]
}

@test "verify_sha512_integrity accepts npm integrity and rejects mismatches" {
    local integrity
    integrity='sha512-58IrmUxZ2c8rSOVJseJGZmNgRZMNPafBrLKZ0cO3+TH5Sq5B7dosKyB6NuEPi8uNRSI+VIePWzFufOO2vAGWKQ=='
    printf 'hello\n' >"$TEST_TMP/hello"

    run verify_sha512_integrity "$TEST_TMP/hello" "$integrity"
    [ "$status" -eq 0 ]

    printf 'tampered\n' >"$TEST_TMP/hello"
    run verify_sha512_integrity "$TEST_TMP/hello" "$integrity"
    [ "$status" -eq 1 ]

    run verify_sha512_integrity "$TEST_TMP/hello" "sha1-abc"
    [ "$status" -eq 2 ]
}

@test "profile_mismatch reports the environment that does not match" {
    export WSL_DISTRO_NAME=arch
    run profile_mismatch native
    [ "$status" -eq 0 ]
    [[ "$output" == *"native profile selected inside WSL"* ]]

    run profile_mismatch wsl
    [ "$status" -eq 1 ]

    unset WSL_DISTRO_NAME
    if ! is_wsl; then
        run profile_mismatch wsl
        [ "$status" -eq 0 ]
        [[ "$output" == *"wsl profile selected outside WSL"* ]]
    fi
}

@test "account_needs_password handles missing, locked, and usable accounts" {
    mkdir -p "$TEST_TMP/bin"
    cat >"$TEST_TMP/bin/id" <<'EOF'
#!/usr/bin/env bash
[[ "${2:-}" == "known" ]]
EOF
    cat >"$TEST_TMP/bin/passwd" <<'EOF'
#!/usr/bin/env bash
case "${FAKE_PASSWORD_STATE:-P}" in
P) printf '%s P 2026-10-25 -1 -1 -1 -1\n' "${2:-}" ;;
L) printf '%s L 2026-10-25 -1 -1 -1 -1\n' "${2:-}" ;;
*) exit 1 ;;
esac
EOF
    chmod +x "$TEST_TMP/bin/id" "$TEST_TMP/bin/passwd"
    PATH="$TEST_TMP/bin:$PATH"

    run account_needs_password missing
    [ "$status" -eq 0 ]

    export FAKE_PASSWORD_STATE=L
    run account_needs_password known
    [ "$status" -eq 0 ]

    export FAKE_PASSWORD_STATE=P
    run account_needs_password known
    [ "$status" -eq 1 ]
}
