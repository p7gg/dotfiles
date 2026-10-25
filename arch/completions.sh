#!/usr/bin/env bash
#
# Generate fish completions for tools that expose a completion helper.
#
# Package-provided completions in /usr/share/fish/vendor_completions.d are
# loaded automatically by fish. This script only handles tools installed
# outside pacman, or whose completion helper produces a newer file.

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=arch/lib/common.sh
source "$REPO_ROOT/arch/lib/common.sh"

COMPLETIONS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fish/completions"
OPENCODE_BIN="${OPENCODE_BIN:-$HOME/.opencode/bin/opencode}"
MISE_AVAILABLE=0
DRY_RUN=0
STRICT=0
FAILURES=0

trap 'on_error' ERR
trap cleanup_tmp EXIT

usage() {
    cat <<'EOF'
Usage: arch/completions.sh [options]

Options:
  --dry-run   Print what would be generated without writing files
  --strict    Exit 1 if any completion could not be generated
  -h, --help  Show this help
EOF
}

while (($# > 0)); do
    case "$1" in
    --dry-run)
        DRY_RUN=1
        shift
        ;;
    --strict)
        STRICT=1
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        die "unknown option: $1 (try --help)"
        ;;
    esac
done

command -v mise >/dev/null 2>&1 && MISE_AVAILABLE=1

if ((DRY_RUN == 0)); then
    mkdir -p "$COMPLETIONS_DIR"
fi

run_tool() {
    if ((MISE_AVAILABLE)); then
        mise exec -- "$@"
    else
        "$@"
    fi
}

tool_available() {
    local tool="$1"
    if ((MISE_AVAILABLE)); then
        mise exec -- "$tool" --version >/dev/null 2>&1 && return 0
        mise which "$tool" >/dev/null 2>&1 && return 0
    else
        command -v "$tool" >/dev/null 2>&1 && return 0
    fi
    return 1
}

install_completion() {
    local name="$1"
    local tmp="$2"

    if ((DRY_RUN)); then
        log "would generate fish completion: ${name}"
        return 0
    fi

    install -Dm644 "$tmp" "$COMPLETIONS_DIR/${name}.fish"
    log "generated fish completion: ${name}"
}

generate_completion() {
    local name="$1"
    shift
    local tmp

    tmp="$(mktemp)"
    register_tmp "$tmp"

    if run_tool "$@" >"$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
        install_completion "$name" "$tmp"
    else
        warn "could not generate fish completion: ${name}"
        FAILURES=$((FAILURES + 1))
    fi
}

generate_direct() {
    local name="$1"
    shift
    local tmp

    tmp="$(mktemp)"
    register_tmp "$tmp"

    if "$@" >"$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
        install_completion "$name" "$tmp"
    else
        warn "could not generate fish completion: ${name}"
        FAILURES=$((FAILURES + 1))
    fi
}

if tool_available pnpm; then
    generate_completion pnpm pnpm completion fish
else
    warn "pnpm is not available; skipping pnpm completion"
    FAILURES=$((FAILURES + 1))
fi

if tool_available npm; then
    npm_root="$(run_tool npm root -g 2>/dev/null || true)"
    npm_completion=""

    if [[ -n "$npm_root" ]]; then
        npm_completion="${npm_root}/npm/lib/utils/completion.fish"
    fi

    if [[ ! -f "$npm_completion" ]]; then
        npm_prefix="$(run_tool npm prefix -g 2>/dev/null || true)"
        if [[ -n "$npm_prefix" ]]; then
            npm_completion="${npm_prefix}/lib/node_modules/npm/lib/utils/completion.fish"
        fi
    fi

    if [[ -f "$npm_completion" ]]; then
        if ((DRY_RUN)); then
            log "would install fish completion: npm"
        else
            install -Dm644 "$npm_completion" "$COMPLETIONS_DIR/npm.fish"
            log "installed fish completion: npm"
        fi
    else
        warn "could not locate npm's completion.fish"
        FAILURES=$((FAILURES + 1))
    fi
else
    warn "npm is not available; skipping npm completion"
    FAILURES=$((FAILURES + 1))
fi

if tool_available bun; then
    if command -v fish >/dev/null 2>&1; then
        if ((DRY_RUN)); then
            log "would generate fish completion: bun"
        elif SHELL="$(command -v fish)" run_tool bun completions >/dev/null 2>&1; then
            if [[ -f "$COMPLETIONS_DIR/bun.fish" ]]; then
                log "generated fish completion: bun"
            else
                warn "bun completions ran, but ${COMPLETIONS_DIR}/bun.fish was not created"
                FAILURES=$((FAILURES + 1))
            fi
        else
            warn "could not generate fish completion: bun"
            FAILURES=$((FAILURES + 1))
        fi
    else
        warn "fish is not installed; cannot generate bun completion"
        FAILURES=$((FAILURES + 1))
    fi
else
    warn "bun is not available; skipping bun completion"
    FAILURES=$((FAILURES + 1))
fi

if command -v but >/dev/null 2>&1; then
    generate_direct but but completions fish
else
    warn "but is not available; skipping but completion"
    FAILURES=$((FAILURES + 1))
fi

if [[ -x "$OPENCODE_BIN" ]]; then
    generate_direct opencode "$OPENCODE_BIN" --completions fish
elif command -v opencode >/dev/null 2>&1; then
    generate_direct opencode opencode --completions fish
else
    warn "opencode is not available; skipping opencode completion"
    FAILURES=$((FAILURES + 1))
fi

log "Fish completions directory: $COMPLETIONS_DIR"

if ((FAILURES > 0)); then
    warn "$FAILURES completion step(s) failed"
    if ((STRICT)); then
        exit 1
    fi
fi
