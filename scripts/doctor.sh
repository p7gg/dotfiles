#!/usr/bin/env bash
#
# Print the state of the tools this repository depends on. This is read-only and
# intentionally does not fail on warnings from individual tools.

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=arch/lib/common.sh
source "$REPO_ROOT/arch/lib/common.sh"

trap 'on_error' ERR

cd "$REPO_ROOT"

log "==> chezmoi"
run_optional chezmoi doctor || true

if command -v mise >/dev/null 2>&1; then
    log "==> mise"
    run_optional mise doctor || true
else
    warn "mise is not installed"
fi

if command -v gh >/dev/null 2>&1; then
    log "==> GitHub CLI"
    run_optional gh auth status || true
else
    warn "gh is not installed"
fi

if command -v tailscale >/dev/null 2>&1; then
    log "==> Tailscale"
    run_optional tailscale status || true
else
    warn "tailscale is not installed"
fi

if command -v opencode >/dev/null 2>&1; then
    opencode_path="$(command -v opencode)"
    if [[ "$opencode_path" != "/usr/bin/opencode" ]]; then
        warn "opencode resolves to $opencode_path; expected /usr/bin/opencode from extra"
    fi
    if [[ ":$PATH:" == *":$HOME/.opencode/bin:"* ]]; then
        warn "$HOME/.opencode/bin is on PATH and can shadow the extra package"
    fi
else
    warn "opencode is not installed"
fi

log "==> repository"
log "repository: $REPO_ROOT"
if command -v chezmoi >/dev/null 2>&1; then
    run_optional chezmoi source-path || true
fi
log "available recipes:"
just --list
