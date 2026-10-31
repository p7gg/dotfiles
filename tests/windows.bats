#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    RUN_SH="$REPO_ROOT/provisioning/windows/run.sh"
    TEST_TMP="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_TMP"
}

install_stubs() {
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
}

@test "windows run.sh documents commands and rejects missing or unknown ones" {
    run "$RUN_SH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"audit [options]"* ]]
    [[ "$output" == *"bootstrap [options]"* ]]
    [[ "$output" == *"settings [options]"* ]]
    [[ "$output" == *"WINDOWS_POWERSHELL"* ]]

    run "$RUN_SH"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage:"* ]]

    run "$RUN_SH" nonsense
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown command: nonsense"* ]]
}

@test "windows run.sh invokes the Windows PowerShell host from WSL" {
    grep -qi microsoft /proc/version 2>/dev/null || skip "requires WSL interop"
    install_stubs

    run env \
        PATH="$TEST_TMP/bin:$PATH" \
        WINDOWS_POWERSHELL="$TEST_TMP/bin/pwsh.exe" \
        "$RUN_SH" audit -Strict

    [ "$status" -eq 0 ]
    [[ "$output" == *"-NoProfile"* ]]
    [[ "$output" == *"-File C:\\repo\\audit.ps1"* ]]
    [[ "$output" == *"-Strict"* ]]
}

@test "windows run.sh invokes the bootstrap script" {
    grep -qi microsoft /proc/version 2>/dev/null || skip "requires WSL interop"
    install_stubs

    run env \
        PATH="$TEST_TMP/bin:$PATH" \
        WINDOWS_POWERSHELL="$TEST_TMP/bin/pwsh.exe" \
        "$RUN_SH" bootstrap -DryRun

    [ "$status" -eq 0 ]
    [[ "$output" == *"-File C:\\repo\\bootstrap.ps1"* ]]
    [[ "$output" == *"-DryRun"* ]]
}

@test "windows run.sh invokes the settings script" {
    grep -qi microsoft /proc/version 2>/dev/null || skip "requires WSL interop"
    install_stubs

    run env \
        PATH="$TEST_TMP/bin:$PATH" \
        WINDOWS_POWERSHELL="$TEST_TMP/bin/pwsh.exe" \
        "$RUN_SH" settings -DryRun

    [ "$status" -eq 0 ]
    [[ "$output" == *"-File C:\\repo\\settings.ps1"* ]]
    [[ "$output" == *"-DryRun"* ]]
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
