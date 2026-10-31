#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_TMP="$(mktemp -d)"
    FIXTURE="$TEST_TMP/repo"

    mkdir -p "$FIXTURE/provisioning/arch/packages" \
        "$FIXTURE/provisioning/windows/packages/optional" "$FIXTURE/docs"
    cp "$REPO_ROOT"/provisioning/arch/packages/*.txt "$FIXTURE/provisioning/arch/packages/"
    cp "$REPO_ROOT"/provisioning/windows/packages/*.txt "$FIXTURE/provisioning/windows/packages/"
    cp "$REPO_ROOT"/provisioning/windows/packages/optional/*.txt \
        "$FIXTURE/provisioning/windows/packages/optional/"
    cp "$REPO_ROOT/README.md" "$REPO_ROOT/AGENTS.md" "$FIXTURE/"
    cp -a "$REPO_ROOT/docs/." "$FIXTURE/docs/"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "documentation links and package coverage match the lists" {
    run "$REPO_ROOT/tests/check-docs.sh" --root "$FIXTURE"

    [ "$status" -eq 0 ]
    [[ "$output" == *"docs check passed"* ]]
}

@test "a tracked package missing from the catalog fails the docs check" {
    printf '%s\n' 'extra-test-package' >>"$FIXTURE/provisioning/arch/packages/wsl.txt"

    run "$REPO_ROOT/tests/check-docs.sh" --root "$FIXTURE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"no catalog entry for 'extra-test-package'"* ]]
}

@test "a missing linked asset fails the docs check" {
    rm "$FIXTURE/docs/assets/package-loop.svg"

    run "$REPO_ROOT/tests/check-docs.sh" --root "$FIXTURE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"broken link 'assets/package-loop.svg'"* ]]
}

@test "a package missing from the catalog fails the docs check" {
    sed -i '/`bat`/d' "$FIXTURE/docs/packages.md"

    run "$REPO_ROOT/tests/check-docs.sh" --root "$FIXTURE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"no catalog entry for 'bat'"* ]]
}

@test "a stale heading anchor fails the docs check" {
    sed -i 's|#native-arch--gnome|#native-arch-gnome|' "$FIXTURE/docs/README.md"

    run "$REPO_ROOT/tests/check-docs.sh" --root "$FIXTURE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"no heading anchor '#native-arch-gnome'"* ]]
}

@test "a Windows package missing from the catalog fails the docs check" {
    sed -i '/`Microsoft.WindowsTerminal`/d' "$FIXTURE/docs/windows.md"

    run "$REPO_ROOT/tests/check-docs.sh" --root "$FIXTURE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"no catalog entry for 'Microsoft.WindowsTerminal'"* ]]
}

@test "a duplicate Windows package fails the docs check" {
    printf '%s\n' 'Microsoft.WindowsTerminal' \
        >>"$FIXTURE/provisioning/windows/packages/optional/apps.txt"

    run "$REPO_ROOT/tests/check-docs.sh" --root "$FIXTURE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"duplicate Windows package names"* ]]
}
