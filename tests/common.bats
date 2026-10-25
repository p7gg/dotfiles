#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # shellcheck source=arch/lib/common.sh
    source "$REPO_ROOT/arch/lib/common.sh"
    DRY_RUN=0
    ERROR_REPORTED=0
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

@test "cleanup_tmp removes registered files" {
    touch "$TEST_TMP/temp-file"
    register_tmp "$TEST_TMP/temp-file"
    cleanup_tmp

    [ ! -e "$TEST_TMP/temp-file" ]
}
