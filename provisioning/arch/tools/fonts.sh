#!/usr/bin/env bash
#
# Optionally install selected Nerd Fonts from the official Arch repositories.
#
# Run without selection flags for an interactive menu. Use --list to inspect the
# catalog, --font for scripted selections, and --all for every catalog entry.

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"

# shellcheck source=provisioning/arch/lib/common.sh
source "$REPO_ROOT/provisioning/arch/lib/common.sh"

CATALOG="$REPO_ROOT/provisioning/arch/packages/fonts.txt"

DRY_RUN=0
ASSUME_YES=0
LIST_ONLY=0
INSTALL_ALL=0
NON_INTERACTIVE=0
declare -a FONT_SPECS=()
declare -a FONT_PACKAGES=()
declare -a FONT_NAMES=()
declare -A INSTALLED=()
declare -A SELECTED=()
ROOT_RUNNER=run_sudo
export ROOT_RUNNER

trap 'on_error' ERR

usage() {
    cat <<'EOF'
Usage: provisioning/arch/tools/fonts.sh [options]

Options:
  --list              List the font catalog and installed state
  --all               Install every font in the catalog
  --font SPEC         Install a font by number, package, or display name
                      (repeatable; comma-separated values are accepted)
  --dry-run           Print the pacman command without installing anything
  --yes               Pass --noconfirm to pacman
  --non-interactive   Never prompt when no selection is given
  -h, --help          Show this help

Run without --list, --all, or --font for an interactive selection menu.
Selections accept numbers and ranges (for example: 1 3-5), package names such as
ttf-firacode-nerd, display names such as "Fira Code", or all.

The catalog lives in provisioning/arch/packages/fonts.txt and contains optional packages only.
EOF
}

load_catalog() {
    local line pkg name
    local -a lines=()

    validate_font_catalog "$CATALOG" ||
        die "fix the invalid font catalog before installing fonts"

    mapfile -t lines < <(filter_packages "$CATALOG")
    for line in "${lines[@]}"; do
        pkg="${line%%|*}"
        name="${line#*|}"
        FONT_PACKAGES+=("$pkg")
        FONT_NAMES+=("$name")
    done
}

load_installed() {
    local pkg output
    local -a packages=()

    if ! output="$(pacman -Qq)"; then
        die "could not read installed packages with pacman -Qq"
    fi

    mapfile -t packages <<<"$output"
    for pkg in "${packages[@]}"; do
        [[ -n "$pkg" ]] || continue
        INSTALLED["$pkg"]=1
    done
}

is_installed() {
    [[ -n "${INSTALLED[$1]:-}" ]]
}

print_catalog() {
    local i state

    log "Optional Nerd Fonts:"
    for i in "${!FONT_PACKAGES[@]}"; do
        if is_installed "${FONT_PACKAGES[$i]}"; then
            state="installed"
        else
            state="not installed"
        fi
        printf '%3d) %-18s %-30s %s\n' \
            "$((i + 1))" "${FONT_NAMES[$i]}" "${FONT_PACKAGES[$i]}" "$state"
    done
}

# Add one selection token to SELECTED. Supports catalog numbers, inclusive
# number ranges, package names, case-insensitive display names, all, and none.
resolve_token() {
    local token="$1"
    local lower_token i start end

    token="${token#"${token%%[![:space:]]*}"}"
    token="${token%"${token##*[![:space:]]}"}"
    [[ -n "$token" ]] || return 1

    lower_token="${token,,}"

    if [[ "$lower_token" == "all" ]]; then
        for i in "${!FONT_PACKAGES[@]}"; do
            SELECTED["${FONT_PACKAGES[$i]}"]=1
        done
        return 0
    fi

    if [[ "$lower_token" == "none" ]]; then
        SELECTED=()
        return 0
    fi

    if [[ "$token" =~ ^[0-9]+$ ]]; then
        i=$((10#$token - 1))
        if ((i >= 0 && i < ${#FONT_PACKAGES[@]})); then
            SELECTED["${FONT_PACKAGES[$i]}"]=1
            return 0
        fi
        warn "font number out of range: $token"
        return 1
    fi

    if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        start=$((10#${BASH_REMATCH[1]} - 1))
        end=$((10#${BASH_REMATCH[2]} - 1))
        if ((start < 0 || end < start || end >= ${#FONT_PACKAGES[@]})); then
            warn "font range out of range: $token"
            return 1
        fi
        for ((i = start; i <= end; i++)); do
            SELECTED["${FONT_PACKAGES[$i]}"]=1
        done
        return 0
    fi

    for i in "${!FONT_PACKAGES[@]}"; do
        if [[ "${FONT_PACKAGES[$i]}" == "$token" ||
            "${FONT_NAMES[$i],,}" == "$lower_token" ]]; then
            SELECTED["${FONT_PACKAGES[$i]}"]=1
            return 0
        fi
    done

    warn "unknown font: $token"
    return 1
}

# --font values are comma-separated so display names may contain spaces.
apply_spec() {
    local spec="$1"
    local token status=0
    local -a tokens=()

    IFS=',' read -r -a tokens <<<"$spec"
    for token in "${tokens[@]}"; do
        resolve_token "$token" || status=1
    done

    return "$status"
}

interactive_select() {
    local answer normalized token status
    local -a tokens=()

    print_catalog
    while true; do
        printf '\nSelect fonts to install (numbers or ranges, all, Enter to skip): '
        if ! IFS= read -r answer; then
            printf '\n'
            return 0
        fi

        SELECTED=()
        if [[ -z "${answer//[[:space:]]/}" ]]; then
            return 0
        fi

        normalized="${answer//,/ }"
        read -r -a tokens <<<"$normalized"
        status=0
        for token in "${tokens[@]}"; do
            resolve_token "$token" || status=1
        done

        if ((status == 0)); then
            return 0
        fi

        warn "invalid selection; use numbers such as 1 3-5, package/display names, or all"
    done
}

install_selected() {
    local i pkg
    local -a missing=()
    local -a args=(pacman -S --needed)

    for i in "${!FONT_PACKAGES[@]}"; do
        pkg="${FONT_PACKAGES[$i]}"
        [[ -n "${SELECTED[$pkg]:-}" ]] || continue

        if is_installed "$pkg"; then
            log "Already installed: ${FONT_NAMES[$i]} ($pkg)"
            continue
        fi
        missing+=("$pkg")
    done

    if ((${#missing[@]} == 0)); then
        log "No selected fonts need installation."
        return 0
    fi

    ((ASSUME_YES)) && args+=(--noconfirm)

    if ((DRY_RUN == 0)); then
        require_cmd sudo
    fi

    log "Installing optional fonts: ${missing[*]}"
    run_sudo "${args[@]}" "${missing[@]}"
}

while (($# > 0)); do
    case "$1" in
    --list)
        LIST_ONLY=1
        shift
        ;;
    --all)
        INSTALL_ALL=1
        shift
        ;;
    --font)
        [[ $# -ge 2 ]] || die "--font requires an argument"
        FONT_SPECS+=("$2")
        shift 2
        ;;
    --font=*)
        FONT_SPECS+=("${1#*=}")
        shift
        ;;
    --dry-run)
        DRY_RUN=1
        shift
        ;;
    --yes)
        ASSUME_YES=1
        shift
        ;;
    --non-interactive)
        NON_INTERACTIVE=1
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

require_cmd pacman
load_catalog
load_installed

if ((LIST_ONLY)); then
    print_catalog
    exit 0
fi

if ((INSTALL_ALL)); then
    for pkg in "${FONT_PACKAGES[@]}"; do
        SELECTED["$pkg"]=1
    done
fi

for spec in "${FONT_SPECS[@]}"; do
    apply_spec "$spec" || die "invalid font selection: $spec"
done

if ((${#SELECTED[@]} == 0)); then
    if ((NON_INTERACTIVE)); then
        log "No fonts selected; run ./provisioning/arch/tools/fonts.sh interactively, or pass --font or --all."
        exit 0
    fi
    interactive_select
fi

install_selected
