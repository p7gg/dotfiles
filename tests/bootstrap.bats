#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    # shellcheck source=provisioning/arch/lib/common.sh
    source "$REPO_ROOT/provisioning/arch/lib/common.sh"
}

@test "bootstrap --help documents the profile override" {
    run "$REPO_ROOT/provisioning/arch/bootstrap.sh" --help

    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: provisioning/arch/bootstrap.sh"* ]]
    [[ "$output" == *"--allow-profile-mismatch"* ]]
    [[ "$output" == *"--profile native|wsl"* ]]
}

@test "bootstrap rejects unknown options" {
    run "$REPO_ROOT/provisioning/arch/bootstrap.sh" --not-a-real-option

    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown option: --not-a-real-option"* ]]
}

@test "bootstrap requires an argument for --profile" {
    run "$REPO_ROOT/provisioning/arch/bootstrap.sh" --profile

    [ "$status" -eq 1 ]
    [[ "$output" == *"--profile requires an argument"* ]]
}

@test "bootstrap rejects an invalid profile" {
    run "$REPO_ROOT/provisioning/arch/bootstrap.sh" --profile solaris --check

    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid profile: solaris"* ]]
}

@test "bootstrap refuses a profile that mismatches the environment" {
    local opposite
    if is_wsl; then
        opposite="native"
    else
        opposite="wsl"
    fi

    run "$REPO_ROOT/provisioning/arch/bootstrap.sh" --profile "$opposite" --check

    [ "$status" -eq 1 ]
    [[ "$output" == *"refusing to install packages for the wrong profile"* ]]
    [[ "$output" == *"--allow-profile-mismatch"* ]]
}

@test "bootstrap warns and continues with --allow-profile-mismatch" {
    local opposite
    if is_wsl; then
        opposite="native"
    else
        opposite="wsl"
    fi

    run "$REPO_ROOT/provisioning/arch/bootstrap.sh" --profile "$opposite" \
        --allow-profile-mismatch --check

    [[ "$output" == *"continuing because --allow-profile-mismatch was passed"* ]]
}

@test "bootstrap builds AUR packages with the managed GOPATH" {
    run "$REPO_ROOT/provisioning/arch/bootstrap.sh" --dry-run --no-dotfiles \
        --no-opencode --no-fonts --no-services --no-system --no-shell \
        --no-mise --no-completions --no-hooks

    [ "$status" -eq 0 ]
    [[ "$output" == *"env GOPATH=$HOME/.go paru -S"* ]]
}
