#!/usr/bin/env bash
#
# Run the same checks locally and in CI. Keep this script as the single entry
# point so CI and .lefthook.yml cannot drift apart.
#
# Usage: scripts/lint.sh [--staged]

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=arch/lib/common.sh
source "$REPO_ROOT/arch/lib/common.sh"

trap 'on_error' ERR

STAGED=0
FAIL=0
SH_FILES=()
FISH_FILES=()

while (($# > 0)); do
    case "$1" in
    --staged)
        STAGED=1
        shift
        ;;
    -h | --help)
        printf 'Usage: scripts/lint.sh [--staged]\n'
        exit 0
        ;;
    *)
        die "unknown option: $1"
        ;;
    esac
done

cd "$REPO_ROOT"

check() {
    local name="$1"
    shift

    log "==> $name"
    if ! "$@"; then
        warn "$name failed"
        FAIL=1
    fi
}

collect_files() {
    if ((STAGED)); then
        mapfile -t SH_FILES < <(
            git diff --cached --name-only --diff-filter=ACM -- '*.sh'
        )
        mapfile -t FISH_FILES < <(
            git diff --cached --name-only --diff-filter=ACM -- '*.fish'
        )
    else
        mapfile -t SH_FILES < <(
            find "$REPO_ROOT" -name '*.sh' -not -path '*/.git/*'
        )
        mapfile -t FISH_FILES < <(
            find "$REPO_ROOT/home" -name '*.fish'
        )
    fi
}

check_bash_syntax() {
    local file

    if ((${#SH_FILES[@]} == 0)); then
        log "no shell files"
        return 0
    fi

    for file in "${SH_FILES[@]}"; do
        bash -n "$file"
    done
}

check_shellcheck() {
    if ((${#SH_FILES[@]} == 0)); then
        log "no shell files"
        return 0
    fi

    shellcheck -x "${SH_FILES[@]}"
}

check_shfmt() {
    if ((${#SH_FILES[@]} == 0)); then
        log "no shell files"
        return 0
    fi

    shfmt -d "${SH_FILES[@]}"
}

check_fish_syntax() {
    local file

    if ((${#FISH_FILES[@]} == 0)); then
        log "no fish files"
        return 0
    fi

    for file in "${FISH_FILES[@]}"; do
        fish --no-execute "$file"
    done
}

check_fish_format() {
    local file

    if ((${#FISH_FILES[@]} == 0)); then
        log "no fish files"
        return 0
    fi

    for file in "${FISH_FILES[@]}"; do
        fish_indent --check "$file"
    done
}

check_workflows() {
    actionlint
}

check_secrets() {
    if ((STAGED)); then
        gitleaks git --staged --redact --no-banner
    else
        gitleaks git --redact --no-banner
    fi
}

require_cmd shellcheck
require_cmd shfmt
require_cmd fish
require_cmd just
require_cmd actionlint
require_cmd gitleaks

collect_files

check "Bash syntax" check_bash_syntax
check "ShellCheck" check_shellcheck
check "shfmt" check_shfmt
check "fish syntax" check_fish_syntax
check "fish formatting" check_fish_format
check "justfile formatting" just --fmt --check
check "GitHub Actions" check_workflows
check "secret scan" check_secrets

if ((FAIL)); then
    warn "lint failed"
    exit 1
fi

log "lint passed"
