#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SCRIPT="$REPO_ROOT/home/run_once_after_migrate-go-data.sh"
    TEST_HOME="$(mktemp -d)"
}

teardown() {
    rm -rf "$TEST_HOME"
}

@test "go migration moves a legacy ~/go to ~/.go" {
    mkdir -p "$TEST_HOME/go/pkg/mod/example"
    printf 'cached\n' >"$TEST_HOME/go/pkg/mod/example/file"

    run env HOME="$TEST_HOME" "$SCRIPT"

    [ "$status" -eq 0 ]
    [ -f "$TEST_HOME/.go/pkg/mod/example/file" ]
    [ ! -e "$TEST_HOME/go" ]
}

@test "go migration is a no-op without a legacy ~/go" {
    run env HOME="$TEST_HOME" "$SCRIPT"

    [ "$status" -eq 0 ]
    [ ! -e "$TEST_HOME/.go" ]
}

@test "go migration does not overwrite an existing ~/.go" {
    mkdir -p "$TEST_HOME/go/pkg" "$TEST_HOME/.go/pkg"
    printf 'old\n' >"$TEST_HOME/go/pkg/old"
    printf 'new\n' >"$TEST_HOME/.go/pkg/new"

    run env HOME="$TEST_HOME" "$SCRIPT"

    [ "$status" -eq 0 ]
    [ -f "$TEST_HOME/go/pkg/old" ]
    [ -f "$TEST_HOME/.go/pkg/new" ]
    [[ "$output" == *"warning:"* ]]
}

@test "go migration replaces an empty ~/.go" {
    mkdir -p "$TEST_HOME/go/pkg" "$TEST_HOME/.go"
    printf 'cached\n' >"$TEST_HOME/go/pkg/file"

    run env HOME="$TEST_HOME" "$SCRIPT"

    [ "$status" -eq 0 ]
    [ -f "$TEST_HOME/.go/pkg/file" ]
    [ ! -e "$TEST_HOME/go" ]
}
