#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "wsl-init --help and argument validation run before privilege checks" {
    run "$REPO_ROOT/provisioning/arch/wsl-init.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: sudo provisioning/arch/wsl-init.sh"* ]]
    [[ "$output" == *"--non-interactive"* ]]

    run "$REPO_ROOT/provisioning/arch/wsl-init.sh" --not-a-real-option
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown option: --not-a-real-option"* ]]

    run "$REPO_ROOT/provisioning/arch/wsl-init.sh" --user
    [ "$status" -eq 1 ]
    [[ "$output" == *"--user requires an argument"* ]]

    run "$REPO_ROOT/provisioning/arch/wsl-init.sh" --hostname
    [ "$status" -eq 1 ]
    [[ "$output" == *"--hostname requires an argument"* ]]

    run "$REPO_ROOT/provisioning/arch/wsl-init.sh" --user root --check
    [ "$status" -eq 1 ]
    [[ "$output" == *"refusing to use root"* ]]

    run "$REPO_ROOT/provisioning/arch/wsl-init.sh" --user valid-user --hostname 'bad host' --check
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid hostname: bad host"* ]]
}

@test "wsl-init --non-interactive requires --user" {
    run env -u SUDO_USER "$REPO_ROOT/provisioning/arch/wsl-init.sh" --non-interactive --check

    [ "$status" -eq 1 ]
    [[ "$output" == *"no user specified; pass --user NAME"* ]]
}

@test "wsl-init --check fails when password prompts are unavoidable" {
    [ "$EUID" -eq 0 ] || skip "requires root"
    for cmd in passwd pacman pacman-key useradd usermod locale-gen; do
        command -v "$cmd" >/dev/null 2>&1 || skip "requires $cmd"
    done

    run env WSL_DISTRO_NAME=arch "$REPO_ROOT/provisioning/arch/wsl-init.sh" \
        --check --user codespace-test-user --hostname codespace-test --non-interactive

    [ "$status" -eq 1 ]
    [[ "$output" == *"password setup is required"* ]]
}
