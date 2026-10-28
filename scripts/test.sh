#!/usr/bin/env bash
#
# Run the template and shell tests used by CI.

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=provisioning/arch/lib/common.sh
source "$REPO_ROOT/provisioning/arch/lib/common.sh"

trap 'on_error' ERR

require_cmd bats

cd "$REPO_ROOT"

"$REPO_ROOT/tests/check-docs.sh"
"$REPO_ROOT/tests/render-templates.sh"
bats "$REPO_ROOT/tests"

# Exercise the Windows helpers when running inside WSL. The Arch CI container
# has no pwsh.exe, so this block is skipped there.
if command -v pwsh.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
    log "Running Windows PowerShell helper tests"
    pwsh.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \
        "$(wslpath -w "$REPO_ROOT/tests/windows-lib.ps1")"
fi

log "tests passed"
