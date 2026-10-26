#!/usr/bin/env bash
#
# Run the template and shell tests used by CI.

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=arch/lib/common.sh
source "$REPO_ROOT/arch/lib/common.sh"

trap 'on_error' ERR

require_cmd bats

cd "$REPO_ROOT"

"$REPO_ROOT/scripts/check-docs.sh"
"$REPO_ROOT/tests/render-templates.sh"
bats "$REPO_ROOT/tests"

log "tests passed"
