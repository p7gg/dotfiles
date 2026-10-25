#!/usr/bin/env bash
#
# Compare installed explicit packages with the tracked package lists.
# This is intentionally read-only: it never installs or removes anything.

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

PROFILE="auto"
CHECK=0

usage() {
    cat <<'EOF'
Usage: arch/audit.sh [options]

Options:
  --profile native|wsl  Package profile to compare (default: auto-detect)
  --check               Exit 1 if any drift is found
  -h, --help            Show this help

The audit reports:
  - installed native packages not present in tracked lists
  - tracked native packages that are not installed
  - installed AUR/foreign packages not present in aur*.txt
  - tracked AUR packages that are not installed
EOF
}

log() {
    printf '%s\n' "$*"
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

is_wsl() {
    [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null
}

detect_profile() {
    if is_wsl; then
        printf 'wsl\n'
    else
        printf 'native\n'
    fi
}

filter_packages() {
    local file="$1"
    local line

    [[ -f "$file" ]] || return 0

    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -n "$line" ]] && printf '%s\n' "$line"
    done <"$file"

    return 0
}

expand_groups() {
    local pkg members

    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] || continue
        if members="$(pacman -Sgq "$pkg" 2>/dev/null)" && [[ -n "$members" ]]; then
            printf '%s\n' "$members"
        else
            printf '%s\n' "$pkg"
        fi
    done

    return 0
}

print_section() {
    local title="$1"
    local file="$2"
    local count

    count="$(wc -l <"$file" | tr -d ' ')"
    log ""
    log "$title ($count)"
    if ((count > 0)); then
        sed 's/^/  /' "$file"
    else
        log "  none"
    fi
}

while (($# > 0)); do
    case "$1" in
    --profile)
        [[ $# -ge 2 ]] || die "--profile requires an argument"
        PROFILE="$2"
        shift 2
        ;;
    --profile=*)
        PROFILE="${1#*=}"
        shift
        ;;
    --check)
        CHECK=1
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

# shellcheck source=/dev/null
[[ -r /etc/os-release ]] && source /etc/os-release
[[ "${ID:-}" == "arch" ]] || die "this script targets Arch Linux (found: ${ID:-unknown})"
command -v pacman >/dev/null 2>&1 || die "pacman not found"

if [[ "$PROFILE" == "auto" ]]; then
    PROFILE="$(detect_profile)"
fi

case "$PROFILE" in
native | wsl) ;;
*) die "invalid profile: $PROFILE (expected native or wsl)" ;;
esac

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

filter_packages "$REPO_ROOT/arch/packages/base.txt" >"$tmpdir/desired-raw.txt"
filter_packages "$REPO_ROOT/arch/packages/${PROFILE}.txt" >>"$tmpdir/desired-raw.txt"
expand_groups <"$tmpdir/desired-raw.txt" | LC_ALL=C sort -u >"$tmpdir/desired-native.txt"
filter_packages "$REPO_ROOT/arch/packages/aur.txt" >"$tmpdir/desired-aur-raw.txt"
filter_packages "$REPO_ROOT/arch/packages/aur-${PROFILE}.txt" >>"$tmpdir/desired-aur-raw.txt"
LC_ALL=C sort -u "$tmpdir/desired-aur-raw.txt" >"$tmpdir/desired-aur.txt"

(pacman -Qqen || true) | LC_ALL=C sort -u >"$tmpdir/current-native-explicit.txt"
(pacman -Qqn || true) | LC_ALL=C sort -u >"$tmpdir/current-native-all.txt"
(pacman -Qqem || true) | LC_ALL=C sort -u >"$tmpdir/current-aur-explicit.txt"
(pacman -Qqm || true) | LC_ALL=C sort -u >"$tmpdir/current-aur-all.txt"

LC_ALL=C comm -23 "$tmpdir/current-native-explicit.txt" "$tmpdir/desired-native.txt" >"$tmpdir/native-untracked.txt"
LC_ALL=C comm -13 "$tmpdir/current-native-all.txt" "$tmpdir/desired-native.txt" >"$tmpdir/native-missing.txt"
LC_ALL=C comm -23 "$tmpdir/current-aur-explicit.txt" "$tmpdir/desired-aur.txt" >"$tmpdir/aur-untracked.txt"
LC_ALL=C comm -13 "$tmpdir/current-aur-all.txt" "$tmpdir/desired-aur.txt" >"$tmpdir/aur-missing.txt"

log "Package audit for profile: $PROFILE"
print_section "Native installed but not tracked" "$tmpdir/native-untracked.txt"
print_section "Native tracked but not installed" "$tmpdir/native-missing.txt"
print_section "AUR/foreign installed but not tracked" "$tmpdir/aur-untracked.txt"
print_section "AUR/foreign tracked but not installed" "$tmpdir/aur-missing.txt"

drift=0
for file in "$tmpdir"/*-untracked.txt "$tmpdir"/*-missing.txt; do
    [[ -s "$file" ]] && drift=1
done

if ((drift == 0)); then
    log ""
    log "No drift detected."
elif ((CHECK)); then
    log ""
    log "Drift detected."
    exit 1
fi
