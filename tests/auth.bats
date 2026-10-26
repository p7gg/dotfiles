#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "auth --help and unknown options are handled" {
    run "$REPO_ROOT/arch/auth.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: arch/auth.sh"* ]]
    [[ "$output" == *"--bws-account NAME"* ]]

    run "$REPO_ROOT/arch/auth.sh" --not-a-real-option
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown option: --not-a-real-option"* ]]
}
