#!/usr/bin/env bash
#
# Generate fish completions for tools that expose a completion helper.
#
# Package-provided completions in /usr/share/fish/vendor_completions.d are
# loaded automatically by fish. This script only handles tools installed
# outside pacman, or whose completion helper produces a newer file.

set -Eeuo pipefail

COMPLETIONS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fish/completions"
MISE_AVAILABLE=0

log() {
    printf '%s\n' "$*"
}

warn() {
    printf 'warning: %s\n' "$*" >&2
}

command -v mise >/dev/null 2>&1 && MISE_AVAILABLE=1

mkdir -p "$COMPLETIONS_DIR"

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

generate_completion() {
    local name="$1"
    shift
    local tmp
    tmp="$(mktemp)"

    if run_tool "$@" >"$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
        install -Dm644 "$tmp" "$COMPLETIONS_DIR/${name}.fish"
        log "generated fish completion: ${name}"
    else
        warn "could not generate fish completion: ${name}"
    fi

    rm -f "$tmp"
}

generate_direct() {
    local name="$1"
    shift
    local tmp
    tmp="$(mktemp)"

    if "$@" >"$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
        install -Dm644 "$tmp" "$COMPLETIONS_DIR/${name}.fish"
        log "generated fish completion: ${name}"
    else
        warn "could not generate fish completion: ${name}"
    fi

    rm -f "$tmp"
}

if tool_available pnpm; then
    generate_completion pnpm pnpm completion fish
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
        install -Dm644 "$npm_completion" "$COMPLETIONS_DIR/npm.fish"
        log "installed fish completion: npm"
    else
        warn "could not locate npm's completion.fish"
    fi
fi

if tool_available bun; then
    if command -v fish >/dev/null 2>&1; then
        if SHELL="$(command -v fish)" run_tool bun completions >/dev/null 2>&1; then
            if [[ -f "$COMPLETIONS_DIR/bun.fish" ]]; then
                log "generated fish completion: bun"
            else
                warn "bun completions ran, but ${COMPLETIONS_DIR}/bun.fish was not created"
            fi
        else
            warn "could not generate fish completion: bun"
        fi
    else
        warn "fish is not installed; cannot generate bun completion"
    fi
fi

if command -v but >/dev/null 2>&1; then
    generate_direct but but completions fish
fi

log "Fish completions directory: $COMPLETIONS_DIR"
