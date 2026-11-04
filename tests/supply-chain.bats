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

@test "OpenCode downloads are HTTPS-only" {
    grep -Fq -- "--proto '=https'" "$BOOTSTRAP"
    grep -Fq -- '--tlsv1.2' "$BOOTSTRAP"
    grep -Fq 'curl_https -o "$download_tmp/opencode.tgz" "$tarball"' "$BOOTSTRAP"
}

@test "the Mole install verifies the published release checksum" {
    grep -Fq 'https://github.com/tw93/Mole/releases/download/V${version}-linux' "$BOOTSTRAP"
    grep -Fq 'SHA256SUMS.txt' "$BOOTSTRAP"
    grep -Fq 'sha256sum -- "$download_tmp/$asset"' "$BOOTSTRAP"
    grep -Fq 'MOLE_VERSION' "$BOOTSTRAP"
}

@test "Mole resolves only stable Linux releases" {
    grep -Fq 'api.github.com/repos/tw93/Mole/releases' "$BOOTSTRAP"
    grep -Fq '.prerelease == false' "$BOOTSTRAP"
    grep -Fq 'test("^V[0-9]+\\.[0-9]+\\.[0-9]+-linux$")' "$BOOTSTRAP"
}

@test "documentation does not advertise the retired remote installer" {
    ! grep -Rq 'opencode.ai/v2/install' \
        "$REPO_ROOT/README.md" "$REPO_ROOT/docs" "$REPO_ROOT/provisioning/arch"
}

@test "paru is cloned at a pinned 40-character commit" {
    grep -Eq '^PARU_COMMIT="\$\{PARU_COMMIT:-[0-9a-f]{40}\}"' "$BOOTSTRAP"
    grep -Fq 'git -C "$tmp/paru" checkout --detach "$PARU_COMMIT"' "$BOOTSTRAP"
}

@test "WSL SSH agent relay is a fail-fast socat bridge" {
    grep -Fq 'UNIX-LISTEN' "$REPO_ROOT/home/dot_local/bin/executable_ssh-agent-bridge"
    grep -Fq 'npiperelay' "$REPO_ROOT/home/dot_local/bin/executable_ssh-agent-bridge"
    grep -Fq 'pipe/openssh-ssh-agent' "$REPO_ROOT/home/dot_local/bin/executable_ssh-agent-bridge"
    grep -Fq 'Restart=always' "$REPO_ROOT/home/dot_config/systemd/user/ssh-agent-bridge.service"
    grep -Fq 'NoNewPrivileges=yes' "$REPO_ROOT/home/dot_config/systemd/user/ssh-agent-bridge.service"
    grep -Fq 'PrivateTmp=yes' "$REPO_ROOT/home/dot_config/systemd/user/ssh-agent-bridge.service"
    grep -Fq 'socat' "$REPO_ROOT/provisioning/arch/packages/wsl.txt"
    [ ! -e "$REPO_ROOT/home/dot_config/systemd/user/wsl2-ssh-agent.service" ]
}
