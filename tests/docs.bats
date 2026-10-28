#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_TMP="$(mktemp -d)"
    FIXTURE="$TEST_TMP/repo"

    mkdir -p "$FIXTURE/provisioning/arch/packages" "$FIXTURE/provisioning/windows/packages" "$FIXTURE/docs"
    cp "$REPO_ROOT"/provisioning/arch/packages/*.txt "$FIXTURE/provisioning/arch/packages/"
    cp "$REPO_ROOT"/provisioning/windows/packages/*.txt "$FIXTURE/provisioning/windows/packages/"
    cp "$REPO_ROOT/README.md" "$REPO_ROOT/AGENTS.md" "$FIXTURE/"
    cp -a "$REPO_ROOT/docs/." "$FIXTURE/docs/"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "documentation counts and local links match the package lists" {
    run "$REPO_ROOT/tests/check-docs.sh" --root "$FIXTURE"

    [ "$status" -eq 0 ]
    [[ "$output" == *"docs check passed"* ]]
    [[ "$output" == *"67 packages (61 native, 58 WSL)"* ]]
}

@test "a stale total count fails the docs check" {
    sed -i 's/There are 67 tracked package names/There are 68 tracked package names/' \
        "$FIXTURE/README.md"

    run "$REPO_ROOT/tests/check-docs.sh" --root "$FIXTURE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"expected the 67/61/58 package summary"* ]]
}

@test "a package list change fails until the documented counts are updated" {
    printf '%s\n' 'extra-test-package' >>"$FIXTURE/provisioning/arch/packages/wsl.txt"

    run "$REPO_ROOT/tests/check-docs.sh" --root "$FIXTURE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"expected 67"* ]]
    [[ "$output" == *"WSL profile resolves to 59 packages; expected 58"* ]]
}

@test "a per-file count mismatch fails the docs check" {
    sed -i 's/`provisioning\/arch\/packages\/base.txt` — 47 packages/`provisioning\/arch\/packages\/base.txt` — 46 packages/' \
        "$FIXTURE/docs/packages.md"

    run "$REPO_ROOT/tests/check-docs.sh" --root "$FIXTURE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"the base.txt count (47)"* ]]
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

@test "a stale package count in the provisioning SVG fails the docs check" {
    sed -i 's/>61 packages</>62 packages</' \
        "$FIXTURE/docs/assets/provisioning-flow.svg"

    run "$REPO_ROOT/tests/check-docs.sh" --root "$FIXTURE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"the native package count in the SVG"* ]]
}

@test "a Windows package missing from the catalog fails the docs check" {
    sed -i '/`Microsoft.WindowsTerminal`/d' "$FIXTURE/docs/windows.md"

    run "$REPO_ROOT/tests/check-docs.sh" --root "$FIXTURE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"no catalog entry for 'Microsoft.WindowsTerminal'"* ]]
}

@test "a duplicate Windows package fails the docs check" {
    printf '%s\n' 'Microsoft.WindowsTerminal' \
        >>"$FIXTURE/provisioning/windows/packages/optional.txt"

    run "$REPO_ROOT/tests/check-docs.sh" --root "$FIXTURE"

    [ "$status" -eq 1 ]
    [[ "$output" == *"duplicate Windows package names"* ]]
}
