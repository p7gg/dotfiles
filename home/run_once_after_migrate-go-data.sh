#!/usr/bin/env bash
#
# Go now stores its data in ~/.go (see dot_config/go/env.tmpl). Move the old
# default ~/go directory once so an existing module cache is not orphaned.

set -Eeuo pipefail

legacy="$HOME/go"
current="$HOME/.go"

if [[ ! -d "$legacy" ]]; then
    exit 0
fi

if [[ -e "$current" ]]; then
    # An empty ~/.go can be replaced; anything else is left for the user.
    if [[ -d "$current" && ! -L "$current" ]] && rmdir "$current" 2>/dev/null; then
        :
    else
        printf 'warning: both %s and %s exist; leaving Go data unmoved\n' \
            "$legacy" "$current" >&2
        exit 0
    fi
fi

mv -- "$legacy" "$current"
printf 'Moved Go data from %s to %s\n' "$legacy" "$current"
