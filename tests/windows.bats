#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    RUN_SH="$REPO_ROOT/provisioning/windows/run.sh"
    TEST_TMP="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "windows run.sh --help documents the audit command" {
    run "$RUN_SH" --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"audit [options]"* ]]
    [[ "$output" == *"WINDOWS_POWERSHELL"* ]]
}

@test "windows run.sh requires a command" {
    run "$RUN_SH"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "windows run.sh rejects unknown commands before touching Windows" {
    run "$RUN_SH" settings

    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown command: settings"* ]]
}

@test "windows run.sh invokes the Windows PowerShell host from WSL" {
    grep -qi microsoft /proc/version 2>/dev/null || skip "requires WSL interop"

    mkdir -p "$TEST_TMP/bin"
    cat >"$TEST_TMP/bin/wslpath" <<'EOF'
#!/usr/bin/env bash
printf 'C:\\repo\\%s\n' "${2##*/}"
EOF
    cat >"$TEST_TMP/bin/pwsh.exe" <<'EOF'
#!/usr/bin/env bash
printf 'PWSH %s\n' "$*"
EOF
    chmod +x "$TEST_TMP/bin/wslpath" "$TEST_TMP/bin/pwsh.exe"

    run env \
        PATH="$TEST_TMP/bin:$PATH" \
        WINDOWS_POWERSHELL="$TEST_TMP/bin/pwsh.exe" \
        "$RUN_SH" audit -Strict

    [ "$status" -eq 0 ]
    [[ "$output" == *"-NoProfile"* ]]
    [[ "$output" == *"-File C:\\repo\\audit.ps1"* ]]
    [[ "$output" == *"-Strict"* ]]
}

@test "windows run.sh rejects a bad WINDOWS_POWERSHELL override" {
    grep -qi microsoft /proc/version 2>/dev/null || skip "requires WSL interop"

    run env \
        PATH="$TEST_TMP/bin:$PATH" \
        WINDOWS_POWERSHELL="$TEST_TMP/missing-powershell" \
        "$RUN_SH" audit

    [ "$status" -eq 1 ]
    [[ "$output" == *"not executable"* ]]
}
