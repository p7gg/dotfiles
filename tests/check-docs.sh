#!/usr/bin/env bash
#
# Check docs against the package lists and validate local Markdown links and
# assets. Run from just test and CI; no network access is required.

set -Eeuo pipefail

SCRIPT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_ROOT="$SCRIPT_ROOT"
FAIL=0

# shellcheck source=provisioning/arch/lib/common.sh
source "$SCRIPT_ROOT/provisioning/arch/lib/common.sh"

trap 'on_error' ERR

usage() {
    cat <<'EOF'
Usage: tests/check-docs.sh [--root DIR]

Verify that tracked packages are documented and that every relative Markdown
link and HTML asset resolves.
EOF
}

fail() {
    printf 'error: %s\n' "$*" >&2
    FAIL=$((FAIL + 1))
}

while (($# > 0)); do
    case "$1" in
    --root)
        [[ $# -ge 2 ]] || die "--root requires an argument"
        CHECK_ROOT="$2"
        shift 2
        ;;
    --root=*)
        CHECK_ROOT="${1#*=}"
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

[[ -d "$CHECK_ROOT" ]] || die "not a directory: $CHECK_ROOT"

slugify_heading() {
    sed -E 's/<[^>]*>//g; s/`//g' |
        tr '[:upper:]' '[:lower:]' |
        sed -E 's/[^a-z0-9 _-]//g; s/ /-/g'
}

heading_slugs() {
    local file="$1"

    # Ignore headings inside fenced code blocks; shell/PowerShell comments that
    # start with '#' are not Markdown anchors.
    awk '
        /^```/ { in_code = !in_code; next }
        !in_code && /^#{1,6}[[:space:]]+/ {
            sub(/^#{1,6}[[:space:]]+/, "")
            print
        }
    ' "$file" 2>/dev/null |
        while IFS= read -r heading; do
            slugify_heading <<<"$heading"
        done || true
}

check_anchor() {
    local file="$1"
    local target="$2"
    local anchor="$3"
    local slugs

    slugs="$(heading_slugs "$file")"
    if ! grep -Fxq -- "$anchor" <<<"$slugs"; then
        fail "${target#"$CHECK_ROOT/"}: no heading anchor '#$anchor'"
    fi
}

check_link() {
    local source_file="$1"
    local target="$2"
    local path anchor resolved candidate

    case "$target" in
    '' | '#'* | http://* | https://* | mailto:* | tel:* | data:*)
        # Anchor-only links are checked separately below.
        if [[ "$target" == '#'* && ${#target} -gt 1 ]]; then
            anchor="${target#\#}"
            check_anchor "$source_file" "$source_file" "$anchor"
        fi
        return 0
        ;;
    /*)
        # Site-root paths are not repository-root paths on GitHub.
        return 0
        ;;
    esac

    path="${target%%#*}"
    if [[ "$target" == *"#"* ]]; then
        anchor="${target#*#}"
    else
        anchor=""
    fi
    path="${path%%\?*}"
    path="${path#<}"
    path="${path%>}"
    path="${path%% \"*}"
    path="${path//%20/ }"

    [[ -n "$path" ]] || return 0

    candidate="$(dirname -- "$source_file")/$path"
    if [[ ! -e "$candidate" ]]; then
        fail "${source_file#"$CHECK_ROOT/"}: broken link '$target'"
        return 0
    fi

    if [[ -n "$anchor" && -f "$candidate" ]]; then
        resolved="$candidate"
        check_anchor "$resolved" "$candidate" "$anchor"
    fi
}

check_markdown_file() {
    local file="$1"
    local target

    while IFS= read -r target; do
        [[ -n "$target" ]] && check_link "$file" "$target"
    done < <(grep -oE '\]\([^)]+\)' "$file" 2>/dev/null | sed 's/^](//; s/)$//' || true)

    while IFS= read -r target; do
        [[ -n "$target" ]] && check_link "$file" "$target"
    done < <(grep -oE '(src|href)="[^"]+"' "$file" 2>/dev/null |
        sed -E 's/^[a-z]+="//; s/"$//' || true)
}

markdown_files() {
    local file

    for file in "$CHECK_ROOT/README.md" "$CHECK_ROOT/AGENTS.md"; do
        [[ -f "$file" ]] && printf '%s\n' "$file"
    done

    find "$CHECK_ROOT/docs" -type f -name '*.md' 2>/dev/null |
        LC_ALL=C sort
}

packages_dir="$CHECK_ROOT/provisioning/arch/packages"
package_files=(base.txt native.txt wsl.txt aur.txt aur-native.txt aur-wsl.txt fonts.txt)
for file in "${package_files[@]}"; do
    [[ -f "$packages_dir/$file" ]] ||
        fail "missing package list: provisioning/arch/packages/$file"
done

all_required="$(
    for file in base.txt native.txt wsl.txt aur.txt aur-native.txt aur-wsl.txt; do
        filter_packages "$packages_dir/$file"
    done | LC_ALL=C sort
)"
duplicates="$(uniq -d <<<"$all_required")"
if [[ -n "$duplicates" ]]; then
    fail "duplicate package names across required lists: $(tr '\n' ' ' <<<"$duplicates")"
fi

packages_doc="$CHECK_ROOT/docs/packages.md"

# Every tracked package and optional font must still appear by name in the
# catalog without duplicating exact totals in the docs.
check_documented_package() {
    local package="$1"
    local source="$2"

    if ! grep -Fq -- "\`$package\`" "$packages_doc"; then
        fail "docs/packages.md: no catalog entry for '$package' (from $source)"
    fi
}

for file in base.txt native.txt wsl.txt aur.txt aur-native.txt aur-wsl.txt; do
    while IFS= read -r package; do
        check_documented_package "$package" "$file"
    done < <(filter_packages "$packages_dir/$file")
done

while IFS= read -r package; do
    check_documented_package "$package" "fonts.txt"
done < <(filter_optional_packages "$packages_dir/fonts.txt")

windows_packages_dir="$CHECK_ROOT/provisioning/windows/packages"
windows_doc="$CHECK_ROOT/docs/windows.md"

if [[ -d "$windows_packages_dir" ]]; then
    if [[ ! -f "$windows_doc" ]]; then
        fail "missing documentation file: docs/windows.md"
    else
        windows_packages=()
        windows_files=("$windows_packages_dir/required.txt")
        if [[ -d "$windows_packages_dir/optional" ]]; then
            while IFS= read -r file; do
                windows_files+=("$file")
            done < <(find "$windows_packages_dir/optional" -maxdepth 1 -type f -name '*.txt' | LC_ALL=C sort)
        fi

        for path in "${windows_files[@]}"; do
            if [[ ! -f "$path" ]]; then
                fail "missing package list: ${path#"$CHECK_ROOT/"}"
                continue
            fi
            while IFS= read -r package; do
                windows_packages+=("$package")
                if ! grep -Fq -- "\`$package\`" "$windows_doc"; then
                    fail "docs/windows.md: no catalog entry for '$package' (from ${path#"$CHECK_ROOT/"})"
                fi
            done < <(filter_packages "$path")
        done

        windows_duplicates="$(printf '%s\n' "${windows_packages[@]}" | LC_ALL=C sort | uniq -d)"
        if [[ -n "$windows_duplicates" ]]; then
            fail "duplicate Windows package names: $(tr '\n' ' ' <<<"$windows_duplicates")"
        fi

        aliases_file="$windows_packages_dir/aliases.txt"
        if [[ -f "$aliases_file" ]]; then
            while IFS='|' read -r alias_id alias_name; do
                alias_id="$(sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"${alias_id%%#*}")"
                alias_name="$(sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"${alias_name%%#*}")"
                if [[ -z "$alias_id" || -z "$alias_name" ]]; then
                    fail "invalid alias entry in provisioning/windows/packages/aliases.txt"
                    continue
                fi
                if ! printf '%s\n' "${windows_packages[@]}" | grep -qxF -- "$alias_id"; then
                    fail "aliases.txt: '$alias_id' is not a tracked Windows package"
                fi
            done < <(grep -vE '^[[:space:]]*(#|$)' "$aliases_file")
        fi
    fi
fi

while IFS= read -r file; do
    check_markdown_file "$file"
done < <(markdown_files)

if ((FAIL > 0)); then
    printf 'docs check failed with %d issue(s)\n' "$FAIL" >&2
    exit 1
fi

log "docs check passed: all tracked package names are documented, and all local links and assets resolve"
