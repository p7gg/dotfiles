#!/usr/bin/env bash
#
# Compare installed explicit packages with the tracked package lists.
# This is intentionally read-only: it never installs or removes anything.

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=arch/lib/common.sh
source "$REPO_ROOT/arch/lib/common.sh"

PROFILE="auto"
CHECK=0
STRICT=0
JSON=0

trap 'on_error' ERR

usage() {
    cat <<'EOF'
Usage: arch/audit.sh [options]

Options:
  --profile native|wsl  Package profile to compare (default: auto-detect)
  --check               Exit 1 when tracked packages are missing
  --strict              With --check, also exit 1 for untracked packages
  --json                Print machine-readable JSON instead of sections
  -h, --help            Show this help

The audit reports:
  - installed native packages not present in tracked lists
  - tracked native packages that are not installed
  - installed AUR/foreign packages not present in aur*.txt
  - tracked AUR packages that are not installed

Packages listed in arch/packages/audit-ignore.txt are omitted from the
untracked sections. That file is for bootstrap artifacts and OS-layer packages,
not for hiding real drift.

Optional Nerd Fonts from arch/packages/fonts.txt are recognized when installed
but are never required.
EOF
}

expand_groups() {
    local pkg members
    local -A groups=()

    # `pacman -Sgq` costs about a tenth of a second per call. Load the (small)
    # group-name index once and only ask for members of actual groups.
    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] && groups["$pkg"]=1
    done < <(pacman -Sg 2>/dev/null || true)

    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] || continue
        if [[ -n "${groups[$pkg]:-}" ]]; then
            members="$(pacman -Sgq "$pkg" 2>/dev/null || true)"
            if [[ -n "$members" ]]; then
                printf '%s\n' "$members"
                continue
            fi
        fi
        printf '%s\n' "$pkg"
    done

    return 0
}

filter_ignored() {
    local input="$1"
    local ignore="$2"
    local output="$3"

    if [[ -s "$ignore" ]]; then
        grep -vxF -f "$ignore" "$input" >"$output" || true
    else
        cp "$input" "$output"
    fi
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

json_array() {
    local file="$1"

    if [[ -s "$file" ]]; then
        jq -R . "$file" | jq -s .
    else
        printf '[]\n'
    fi
}

main() {
    local tmpdir ignore_file duplicates fonts_file
    local missing_drift=0 untracked_drift=0

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
        --strict)
            STRICT=1
            shift
            ;;
        --json)
            JSON=1
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

    if ((STRICT)) && ((CHECK == 0)); then
        die "--strict requires --check"
    fi

    # shellcheck source=/dev/null
    [[ -r /etc/os-release ]] && source /etc/os-release
    [[ "${ID:-}" == "arch" ]] || die "this script targets Arch Linux (found: ${ID:-unknown})"
    command -v pacman >/dev/null 2>&1 || die "pacman not found"
    if ((JSON)); then
        require_cmd jq
    fi

    if [[ "$PROFILE" == "auto" ]]; then
        PROFILE="$(detect_profile)"
    fi

    case "$PROFILE" in
    native | wsl) ;;
    *) die "invalid profile: $PROFILE (expected native or wsl)" ;;
    esac

    if [[ "$PROFILE" == "native" ]] && is_wsl; then
        warn "native profile selected inside WSL; desktop packages may not be appropriate"
    elif [[ "$PROFILE" == "wsl" ]] && ! is_wsl; then
        warn "wsl profile selected outside WSL"
    fi

    validate_package_lists \
        "$REPO_ROOT/arch/packages/base.txt" \
        "$REPO_ROOT/arch/packages/${PROFILE}.txt" \
        "$REPO_ROOT/arch/packages/aur.txt" \
        "$REPO_ROOT/arch/packages/aur-${PROFILE}.txt" ||
        die "fix the invalid package lists before auditing"

    fonts_file="$REPO_ROOT/arch/packages/fonts.txt"
    if [[ -f "$fonts_file" ]]; then
        validate_font_catalog "$fonts_file" ||
            die "fix the invalid font catalog before auditing"
    fi

    tmpdir="$(mktemp -d)"
    AUDIT_TMPDIR="$tmpdir"
    trap 'rm -rf "${AUDIT_TMPDIR:-}"' EXIT

    filter_packages "$REPO_ROOT/arch/packages/base.txt" >"$tmpdir/desired-raw.txt"
    filter_packages "$REPO_ROOT/arch/packages/${PROFILE}.txt" >>"$tmpdir/desired-raw.txt"
    expand_groups <"$tmpdir/desired-raw.txt" | LC_ALL=C sort -u >"$tmpdir/desired-native.txt"
    filter_packages "$REPO_ROOT/arch/packages/aur.txt" >"$tmpdir/desired-aur-raw.txt"
    filter_packages "$REPO_ROOT/arch/packages/aur-${PROFILE}.txt" >>"$tmpdir/desired-aur-raw.txt"
    LC_ALL=C sort -u "$tmpdir/desired-aur-raw.txt" >"$tmpdir/desired-aur.txt"

    if [[ -f "$fonts_file" ]]; then
        filter_optional_packages "$fonts_file" >"$tmpdir/optional-native.txt"
    else
        : >"$tmpdir/optional-native.txt"
    fi
    cat "$tmpdir/desired-native.txt" "$tmpdir/optional-native.txt" |
        LC_ALL=C sort -u >"$tmpdir/allowed-native.txt"

    if ! pacman -Qqen >"$tmpdir/current-native-explicit.txt"; then
        die "pacman -Qqen failed"
    fi
    if ! pacman -Qqn >"$tmpdir/current-native-all.txt"; then
        die "pacman -Qqn failed"
    fi
    if ! pacman -Qqem >"$tmpdir/current-aur-explicit.txt"; then
        die "pacman -Qqem failed"
    fi
    if ! pacman -Qqm >"$tmpdir/current-aur-all.txt"; then
        die "pacman -Qqm failed"
    fi

    LC_ALL=C sort -u -o "$tmpdir/current-native-explicit.txt" "$tmpdir/current-native-explicit.txt"
    LC_ALL=C sort -u -o "$tmpdir/current-native-all.txt" "$tmpdir/current-native-all.txt"
    LC_ALL=C sort -u -o "$tmpdir/current-aur-explicit.txt" "$tmpdir/current-aur-explicit.txt"
    LC_ALL=C sort -u -o "$tmpdir/current-aur-all.txt" "$tmpdir/current-aur-all.txt"

    LC_ALL=C comm -23 "$tmpdir/current-native-explicit.txt" "$tmpdir/allowed-native.txt" \
        >"$tmpdir/native-untracked.txt"
    LC_ALL=C comm -13 "$tmpdir/current-native-all.txt" "$tmpdir/desired-native.txt" \
        >"$tmpdir/native-missing.txt"
    LC_ALL=C comm -23 "$tmpdir/current-aur-explicit.txt" "$tmpdir/desired-aur.txt" \
        >"$tmpdir/aur-untracked.txt"
    LC_ALL=C comm -13 "$tmpdir/current-aur-all.txt" "$tmpdir/desired-aur.txt" \
        >"$tmpdir/aur-missing.txt"

    ignore_file="$REPO_ROOT/arch/packages/audit-ignore.txt"
    if [[ -f "$ignore_file" ]]; then
        filter_packages "$ignore_file" >"$tmpdir/ignore.txt"
        filter_ignored "$tmpdir/native-untracked.txt" "$tmpdir/ignore.txt" "$tmpdir/native-untracked.filtered"
        filter_ignored "$tmpdir/aur-untracked.txt" "$tmpdir/ignore.txt" "$tmpdir/aur-untracked.filtered"
        mv "$tmpdir/native-untracked.filtered" "$tmpdir/native-untracked.txt"
        mv "$tmpdir/aur-untracked.filtered" "$tmpdir/aur-untracked.txt"
    fi

    duplicates="$(cat "$tmpdir/desired-raw.txt" "$tmpdir/desired-aur-raw.txt" | LC_ALL=C sort | uniq -d)"
    if [[ -n "$duplicates" ]]; then
        warn "duplicate package entries across lists: $(printf '%s' "$duplicates" | tr '\n' ' ')"
    fi

    [[ -s "$tmpdir/native-untracked.txt" || -s "$tmpdir/aur-untracked.txt" ]] && untracked_drift=1
    [[ -s "$tmpdir/native-missing.txt" || -s "$tmpdir/aur-missing.txt" ]] && missing_drift=1

    if ((JSON)); then
        jq -n \
            --arg profile "$PROFILE" \
            --argjson native_untracked "$(json_array "$tmpdir/native-untracked.txt")" \
            --argjson native_missing "$(json_array "$tmpdir/native-missing.txt")" \
            --argjson aur_untracked "$(json_array "$tmpdir/aur-untracked.txt")" \
            --argjson aur_missing "$(json_array "$tmpdir/aur-missing.txt")" \
            --argjson missing_drift "$missing_drift" \
            --argjson untracked_drift "$untracked_drift" \
            '{
                profile: $profile,
                native_untracked: $native_untracked,
                native_missing: $native_missing,
                aur_untracked: $aur_untracked,
                aur_missing: $aur_missing,
                missing_drift: ($missing_drift == 1),
                untracked_drift: ($untracked_drift == 1)
            }'
    else
        log "Package audit for profile: $PROFILE"
        print_section "Official installed but not tracked" "$tmpdir/native-untracked.txt"
        print_section "Official tracked but not installed" "$tmpdir/native-missing.txt"
        print_section "AUR/foreign installed but not tracked" "$tmpdir/aur-untracked.txt"
        print_section "AUR/foreign tracked but not installed" "$tmpdir/aur-missing.txt"
    fi

    if ((CHECK)); then
        if ((missing_drift)); then
            if ((JSON == 0)); then
                log ""
                log "Missing tracked packages detected."
            fi
            exit 1
        fi
        if ((STRICT && untracked_drift)); then
            if ((JSON == 0)); then
                log ""
                log "Drift detected (strict mode)."
            fi
            exit 1
        fi
        if ((JSON == 0)); then
            log ""
            log "No missing tracked packages."
        fi
    elif ((JSON == 0 && missing_drift == 0 && untracked_drift == 0)); then
        log ""
        log "No drift detected."
    fi
}

main "$@"
