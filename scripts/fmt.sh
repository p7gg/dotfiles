#!/usr/bin/env bash
#
# Format the repository's shell, fish, and Just files.

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=arch/lib/common.sh
source "$REPO_ROOT/arch/lib/common.sh"

trap 'on_error' ERR

require_cmd shfmt
require_cmd fish_indent
require_cmd just

cd "$REPO_ROOT"

find "$REPO_ROOT" -name '*.sh' -not -path '*/.git/*' -print0 |
    xargs -0 -r shfmt -w

find "$REPO_ROOT/home" -name '*.fish' -print0 |
    xargs -0 -r -n1 fish_indent -w

just --fmt

log "formatted shell, fish, and Just files"
