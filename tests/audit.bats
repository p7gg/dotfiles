#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # shellcheck source=arch/lib/common.sh
    source "$REPO_ROOT/arch/lib/common.sh"
    TEST_TMP="$(mktemp -d)"
    TEST_DATA="$TEST_TMP/data"
    TEST_BIN="$TEST_TMP/bin"

    mkdir -p "$TEST_DATA" "$TEST_BIN"

    cat >"$TEST_BIN/pacman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    -Qqen)
        cat "$FAKE_PACMAN_DATA/native-explicit"
        ;;
    -Qqn)
        cat "$FAKE_PACMAN_DATA/native-all"
        ;;
    -Qqem)
        cat "$FAKE_PACMAN_DATA/aur-explicit"
        ;;
    -Qqm)
        cat "$FAKE_PACMAN_DATA/aur-all"
        ;;
    -Sgq)
        exit 1
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$TEST_BIN/pacman"

    filter_packages "$REPO_ROOT/arch/packages/base.txt" >"$TEST_DATA/native-all"
    filter_packages "$REPO_ROOT/arch/packages/native.txt" >>"$TEST_DATA/native-all"
    LC_ALL=C sort -u -o "$TEST_DATA/native-all" "$TEST_DATA/native-all"
    cp "$TEST_DATA/native-all" "$TEST_DATA/native-explicit"
    printf '%s\n' 'untracked-pkg' >>"$TEST_DATA/native-explicit"

    filter_packages "$REPO_ROOT/arch/packages/aur.txt" >"$TEST_DATA/aur-all"
    filter_packages "$REPO_ROOT/arch/packages/aur-native.txt" >>"$TEST_DATA/aur-all"
    LC_ALL=C sort -u -o "$TEST_DATA/aur-all" "$TEST_DATA/aur-all"
    cp "$TEST_DATA/aur-all" "$TEST_DATA/aur-explicit"
    printf '%s\n' 'paru' >>"$TEST_DATA/aur-explicit"
    printf '%s\n' 'paru-debug' >>"$TEST_DATA/aur-explicit"
    printf '%s\n' 'paru' >>"$TEST_DATA/aur-all"
    printf '%s\n' 'paru-debug' >>"$TEST_DATA/aur-all"

    export FAKE_PACMAN_DATA="$TEST_DATA"
    export PATH="$TEST_BIN:$PATH"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "--check ignores untracked packages" {
    run "$REPO_ROOT/arch/audit.sh" --profile native --check

    [ "$status" -eq 0 ]
}

@test "--strict fails when untracked packages are present" {
    run "$REPO_ROOT/arch/audit.sh" --profile native --check --strict

    [ "$status" -eq 1 ]
}

@test "--json reports untracked packages and honors audit-ignore.txt" {
    run "$REPO_ROOT/arch/audit.sh" --profile native --json

    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.native_untracked | index("untracked-pkg") != null'
    echo "$output" | jq -e '.aur_untracked | index("paru") == null'
    echo "$output" | jq -e '.aur_untracked | index("paru-debug") == null'
    echo "$output" | jq -e '.missing_drift == false'
}
