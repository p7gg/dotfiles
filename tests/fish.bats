#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_TMP="$(mktemp -d)"
    TEST_BIN="$TEST_TMP/bin"
    TEST_REPO="$TEST_TMP/repo"

    mkdir -p "$TEST_BIN"

    # Stand in for fzf: keep the candidate list for assertions and print the
    # entry named by FZF_STUB_SELECT.
    cat >"$TEST_BIN/fzf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cat >"${FZF_STUB_INPUT:?}"
grep -F -- "${FZF_STUB_SELECT:?}" "$FZF_STUB_INPUT" | head -n 1
EOF
    chmod +x "$TEST_BIN/fzf"

    git init -q --bare "$TEST_TMP/remote.git"
    git init -q "$TEST_REPO"
    git -C "$TEST_REPO" config user.name "Test User"
    git -C "$TEST_REPO" config user.email "test@example.com"
    git -C "$TEST_REPO" config commit.gpgsign false
    git -C "$TEST_REPO" remote add origin "$TEST_TMP/remote.git"
    git -C "$TEST_REPO" commit -q --allow-empty -m "initial"
    git -C "$TEST_REPO" branch -m main
    git -C "$TEST_REPO" push -q -u origin main

    git -C "$TEST_REPO" switch -q -c topic
    git -C "$TEST_REPO" commit -q --allow-empty -m "topic"
    git -C "$TEST_REPO" push -q -u origin topic
    git -C "$TEST_REPO" switch -q main
    git -C "$TEST_REPO" branch -q -D topic
    git -C "$TEST_REPO" fetch -q --prune

    export PATH="$TEST_BIN:$PATH"
    export FZF_STUB_INPUT="$TEST_TMP/fzf-input"
    cd "$TEST_REPO"
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "picking a remote branch creates a tracking local branch" {
    export FZF_STUB_SELECT="origin/topic"

    run fish -c "source '$REPO_ROOT/home/dot_config/fish/functions/fzf-checkout.fish'; fzf-checkout"

    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "topic" ]
    [ "$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')" = "origin/topic" ]
}

@test "the picker groups branches and hides shadowed remote entries" {
    export FZF_STUB_SELECT="origin/topic"

    run fish -c "source '$REPO_ROOT/home/dot_config/fish/functions/fzf-checkout.fish'; fzf-checkout"

    [ "$status" -eq 0 ]
    grep -q 'local.*main' "$FZF_STUB_INPUT"
    grep -q 'remote.*origin/topic' "$FZF_STUB_INPUT"
    ! grep -q 'origin/main' "$FZF_STUB_INPUT"
    ! grep -q 'origin/HEAD' "$FZF_STUB_INPUT"
}

@test "picking a local branch switches to it" {
    git switch -q -c local-only
    git switch -q main
    export FZF_STUB_SELECT=$'\tlocal-only\t'

    run fish -c "source '$REPO_ROOT/home/dot_config/fish/functions/fzf-checkout.fish'; fzf-checkout"

    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "local-only" ]
}

@test "arguments delegate to git checkout" {
    run fish -c "source '$REPO_ROOT/home/dot_config/fish/functions/fzf-checkout.fish'; fzf-checkout -b from-args"

    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "from-args" ]
}

@test "branch names starting with a dash are not treated as options" {
    git update-ref refs/heads/-danger HEAD
    git switch -q main
    export FZF_STUB_SELECT="-danger"

    run fish -c "source '$REPO_ROOT/home/dot_config/fish/functions/fzf-checkout.fish'; fzf-checkout"

    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "-danger" ]
}

@test "WSL GPU drivers are selected inside WSL" {
    run env -u GALLIUM_DRIVER -u LIBVA_DRIVER_NAME WSL_DISTRO_NAME=arch \
        fish -c "source '$REPO_ROOT/home/dot_config/fish/conf.d/50-wsl-gpu.fish'; echo \$GALLIUM_DRIVER \$LIBVA_DRIVER_NAME"

    [ "$status" -eq 0 ]
    [ "$output" = "d3d12 d3d12" ]
}

@test "WSL GPU environment keeps an explicit driver override" {
    run env WSL_DISTRO_NAME=arch GALLIUM_DRIVER=zink \
        fish -c "source '$REPO_ROOT/home/dot_config/fish/conf.d/50-wsl-gpu.fish'; echo \$GALLIUM_DRIVER"

    [ "$status" -eq 0 ]
    [ "$output" = "zink" ]
}

@test "WSL GPU environment stays unset outside WSL" {
    run env -u WSL_DISTRO_NAME -u GALLIUM_DRIVER -u LIBVA_DRIVER_NAME \
        fish -c "source '$REPO_ROOT/home/dot_config/fish/conf.d/50-wsl-gpu.fish'; echo \"[\$GALLIUM_DRIVER][\$LIBVA_DRIVER_NAME]\""

    [ "$status" -eq 0 ]
    [ "$output" = "[][]" ]
}

@test "bws wrapper points at GNOME Keyring on native and WSL" {
    cat >"$TEST_BIN/secret-tool" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$TEST_BIN/secret-tool"

    for profile in native wsl; do
        if [[ "$profile" == wsl ]]; then
            run env WSL_DISTRO_NAME=arch BWS_ACCOUNT=work \
                fish --no-config -c "source '$REPO_ROOT/home/dot_config/fish/functions/bws.fish'; bws secret list"
        else
            run env -u WSL_DISTRO_NAME BWS_ACCOUNT=work \
                fish --no-config -c "source '$REPO_ROOT/home/dot_config/fish/functions/bws.fish'; bws secret list"
        fi

        [ "$status" -ne 0 ]
        [[ "$output" == *"GNOME Keyring for account 'work'"* ]]
        [[ "$output" == *"--bws-account work"* ]]
    done
}
