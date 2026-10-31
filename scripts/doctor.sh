#!/usr/bin/env bash
#
# Print the state of the tools this repository depends on. This is read-only and
# intentionally does not fail on warnings from individual tools.

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=provisioning/arch/lib/common.sh
source "$REPO_ROOT/provisioning/arch/lib/common.sh"

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

opencode_bin="$HOME/.opencode/bin/opencode"

if pacman -Q opencode >/dev/null 2>&1; then
    warn "pacman package opencode is installed; remove it with: sudo pacman -Rns opencode"
fi

if [[ -x "$opencode_bin" ]]; then
    log "==> OpenCode"
    run_optional "$opencode_bin" --version || true
    opencode_path="$(command -v opencode || true)"
    if [[ -z "$opencode_path" ]]; then
        warn "opencode is not on PATH; expected $opencode_bin"
    elif [[ "$(realpath -m -- "$opencode_path")" != "$(realpath -m -- "$opencode_bin")" ]]; then
        warn "opencode resolves to $opencode_path; expected $opencode_bin"
    fi
else
    warn "opencode is not installed at $opencode_bin; run ./provisioning/arch/bootstrap.sh"
fi

login_shell="$(getent passwd "$USER" | cut -d: -f7 || true)"
if [[ -n "$login_shell" ]] && ! grep -qxF -- "$login_shell" /etc/shells; then
    canonical_shell="$(readlink -f -- "$login_shell" 2>/dev/null || true)"
    if [[ -n "$canonical_shell" ]] && grep -qxF -- "$canonical_shell" /etc/shells; then
        warn "login shell $login_shell is not listed in /etc/shells; run: sudo chsh -s $canonical_shell $USER"
    else
        warn "login shell $login_shell is not listed in /etc/shells"
    fi
fi

log "==> repository"
log "repository: $REPO_ROOT"
if [[ "$(git config --local --get gitbutler.signCommits 2>/dev/null || true)" == "false" ]]; then
    warn "gitbutler.signCommits=false; but commits in this repository will be unsigned"
fi
if [[ "$(git config --get commit.gpgsign 2>/dev/null || true)" == "false" ]]; then
    warn "commit.gpgsign=false; commits in this repository will be unsigned"
fi
if command -v chezmoi >/dev/null 2>&1; then
    run_optional chezmoi source-path || true
fi
log "available recipes:"
just --list
