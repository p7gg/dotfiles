#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_TMP="$(mktemp -d)"
    TEST_BIN="$TEST_TMP/bin"

    mkdir -p "$TEST_BIN"
    : >"$TEST_TMP/installed"
    : >"$TEST_TMP/pacman.log"

    cat >"$TEST_BIN/pacman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    -Qq)
        cat "$FAKE_PACMAN_INSTALLED"
        ;;
    -S)
        printf '%s\n' "$*" >>"$FAKE_PACMAN_LOG"
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$TEST_BIN/pacman"

    cat >"$TEST_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

exec "$@"
EOF
    chmod +x "$TEST_BIN/sudo"

    export FAKE_PACMAN_INSTALLED="$TEST_TMP/installed"
    export FAKE_PACMAN_LOG="$TEST_TMP/pacman.log"
    export PATH="$TEST_BIN:$PATH"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "--list shows the catalog and installed state" {
    run "$REPO_ROOT/arch/fonts.sh" --list

    [ "$status" -eq 0 ]
    [[ "$output" == *"JetBrains Mono"* ]]
    [[ "$output" == *"ttf-zed-mono-nerd"* ]]
    [[ "$output" == *"not installed"* ]]
}

@test "--font accepts a display name and dry-run does not install" {
    run "$REPO_ROOT/arch/fonts.sh" --font "Zed Mono" --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" == *"ttf-zed-mono-nerd"* ]]
    [ ! -s "$FAKE_PACMAN_LOG" ]
}

@test "--font accepts numbers and ranges" {
    run "$REPO_ROOT/arch/fonts.sh" --font "1,3-4" --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" == *"ttf-cascadia-code-nerd"* ]]
    [[ "$output" == *"ttf-firacode-nerd"* ]]
    [[ "$output" == *"otf-firamono-nerd"* ]]
}

@test "--font installs the selected package and passes --yes to pacman" {
    run "$REPO_ROOT/arch/fonts.sh" --font "Hack" --yes

    [ "$status" -eq 0 ]
    grep -qx -- '-S --needed --noconfirm ttf-hack-nerd' "$FAKE_PACMAN_LOG"
}

@test "already installed fonts are not reinstalled" {
    printf '%s\n' 'ttf-hack-nerd' >"$FAKE_PACMAN_INSTALLED"

    run "$REPO_ROOT/arch/fonts.sh" --font "Hack"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Already installed"* ]]
    [ ! -s "$FAKE_PACMAN_LOG" ]
}

@test "--all selects every catalog font" {
    run "$REPO_ROOT/arch/fonts.sh" --all --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" == *"ttf-cascadia-code-nerd"* ]]
    [[ "$output" == *"ttf-zed-mono-nerd"* ]]
}

@test "unknown font names fail without installing" {
    run "$REPO_ROOT/arch/fonts.sh" --font "Not A Font" --dry-run

    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown font"* ]]
    [ ! -s "$FAKE_PACMAN_LOG" ]
}

@test "interactive selection installs only the chosen fonts" {
    run bash -c 'printf "1 3\n" | "$1" --dry-run' _ "$REPO_ROOT/arch/fonts.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Installing optional fonts: ttf-cascadia-code-nerd ttf-firacode-nerd"* ]]
}

@test "empty interactive selection installs nothing by default" {
    run bash -c 'exec "$1" --dry-run </dev/null' _ "$REPO_ROOT/arch/fonts.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"No selected fonts need installation."* ]]
    [ ! -s "$FAKE_PACMAN_LOG" ]
}
