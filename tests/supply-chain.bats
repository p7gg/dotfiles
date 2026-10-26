#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    BOOTSTRAP="$REPO_ROOT/provisioning/arch/bootstrap.sh"
}

@test "bootstrap never pipes a remote installer into a shell" {
    ! grep -Eq 'curl[^|]*\|[[:space:]]*(bash|sh)' "$BOOTSTRAP"
}

@test "the OpenCode install verifies npm sha512 integrity" {
    grep -Fq 'verify_sha512_integrity "$download_tmp/opencode.tgz" "$integrity"' "$BOOTSTRAP"
    grep -Fq 'registry.npmjs.org' "$BOOTSTRAP"
    grep -Fq 'OPENCODE_VERSION' "$BOOTSTRAP"
}

@test "paru is cloned at a pinned 40-character commit" {
    grep -Eq '^PARU_COMMIT="\$\{PARU_COMMIT:-[0-9a-f]{40}\}"' "$BOOTSTRAP"
    grep -Fq 'git -C "$tmp/paru" checkout --detach "$PARU_COMMIT"' "$BOOTSTRAP"
}

@test "documentation no longer advertises the remote OpenCode installer" {
    ! grep -Rq 'opencode.ai/v2/install' \
        "$REPO_ROOT/README.md" "$REPO_ROOT/docs" "$REPO_ROOT/provisioning/arch"
}
