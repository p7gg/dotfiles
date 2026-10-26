#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "authorized_keys comments contain no personal email or stale GitHub titles" {
    local keys="$REPO_ROOT/home/private_dot_ssh/private_authorized_keys"

    ! grep -Eq '^ssh-[^ ]+ [^ ]+ .*@' "$keys"
    ! grep -Fq 'gh-cli' "$keys"
    grep -Fq 'arch-wsl-auth, arch-wsl-signing' "$keys"
    grep -Fq 'P7-LAPTOP-auth, P7-LAPTOP-signing' "$keys"
}
