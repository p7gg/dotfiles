#!/usr/bin/env bash
#
# Check docs against the package lists and validate local Markdown links and
# assets. Run from just test and CI; no network access is required.

set -Eeuo pipefail

SCRIPT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_ROOT="$SCRIPT_ROOT"
FAIL=0

# shellcheck source=arch/lib/common.sh
source "$SCRIPT_ROOT/arch/lib/common.sh"

trap 'on_error' ERR

usage() {
    cat <<'EOF'
Usage: scripts/check-docs.sh [--root DIR]

Verify package counts and source-list counts in the documentation and SVG
assets, then check that every relative Markdown link and HTML asset resolves.
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

count_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        fail "missing package list: ${file#"$CHECK_ROOT/"}"
        printf '0\n'
        return 0
    fi

    filter_packages "$file" | wc -l | tr -d ' '
}

expect_literal() {
    local file="$1"
    local needle="$2"
    local label="$3"

    if [[ ! -f "$file" ]]; then
        fail "missing documentation file: ${file#"$CHECK_ROOT/"}"
        return 0
    fi

    if ! tr '\n' ' ' <"$file" | tr -s '[:space:]' ' ' | grep -Fq -- "$needle"; then
        fail "${file#"$CHECK_ROOT/"}: expected $label"
    fi
}

expect_regex() {
    local file="$1"
    local pattern="$2"
    local label="$3"

    if [[ ! -f "$file" ]]; then
        fail "missing documentation file: ${file#"$CHECK_ROOT/"}"
        return 0
    fi

    if ! grep -Eq -- "$pattern" "$file"; then
        fail "${file#"$CHECK_ROOT/"}: expected $label"
    fi
}

slugify_heading() {
    sed -E 's/<[^>]*>//g; s/`//g' |
        tr '[:upper:]' '[:lower:]' |
        sed -E 's/[^a-z0-9 _-]//g; s/ /-/g'
}

heading_slugs() {
    local file="$1"

    grep -E '^#{1,6}[[:space:]]+' "$file" 2>/dev/null |
        sed -E 's/^#{1,6}[[:space:]]+//' |
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

    find "$CHECK_ROOT/docs" "$CHECK_ROOT/windows" -type f -name '*.md' 2>/dev/null |
        LC_ALL=C sort
}

packages_dir="$CHECK_ROOT/arch/packages"
base_count="$(count_file "$packages_dir/base.txt")"
native_count="$(count_file "$packages_dir/native.txt")"
wsl_count="$(count_file "$packages_dir/wsl.txt")"
aur_count="$(count_file "$packages_dir/aur.txt")"
aur_native_count="$(count_file "$packages_dir/aur-native.txt")"
aur_wsl_count="$(count_file "$packages_dir/aur-wsl.txt")"
fonts_count="$(count_file "$packages_dir/fonts.txt")"

all_required="$(
    for file in base.txt native.txt wsl.txt aur.txt aur-native.txt aur-wsl.txt; do
        filter_packages "$packages_dir/$file"
    done | LC_ALL=C sort
)"
duplicates="$(uniq -d <<<"$all_required")"
if [[ -n "$duplicates" ]]; then
    fail "duplicate package names across required lists: $(tr '\n' ' ' <<<"$duplicates")"
fi

total_count="$(uniq <<<"$all_required" | wc -l | tr -d ' ')"
native_total=$((base_count + native_count + aur_count + aur_native_count))
wsl_total=$((base_count + wsl_count + aur_count + aur_wsl_count))

expected_total=67
expected_native=60
expected_wsl=58
expected_fonts=18

((total_count == expected_total)) ||
    fail "package lists contain $total_count distinct names; expected $expected_total"
((native_total == expected_native)) ||
    fail "native profile resolves to $native_total packages; expected $expected_native"
((wsl_total == expected_wsl)) ||
    fail "WSL profile resolves to $wsl_total packages; expected $expected_wsl"
((fonts_count == expected_fonts)) ||
    fail "font catalog contains $fonts_count packages; expected $expected_fonts"

readme="$CHECK_ROOT/README.md"
docs_readme="$CHECK_ROOT/docs/README.md"
packages_doc="$CHECK_ROOT/docs/packages.md"
flow_svg="$CHECK_ROOT/docs/assets/provisioning-flow.svg"

expect_literal "$readme" \
    "67 tracked package names: 60 apply to the native profile and 58 to WSL" \
    "the 67/60/58 package summary"
expect_literal "$readme" "67 tracked packages (60 native, 58 WSL)" \
    "the package catalog summary count"
expect_literal "$readme" "18 optional Nerd Fonts" "the optional font count"
expect_literal "$docs_readme" \
    "All 67 tracked packages (60 native, 58 WSL) plus" \
    "the 67/60/58 package summary"
expect_literal "$docs_readme" "18 optional Nerd Fonts" "the optional font count"
expect_literal "$packages_doc" \
    "**67 tracked required package names**" "the required package total"
expect_literal "$packages_doc" \
    "**51** are installed on both profiles: 46 official packages plus 5 AUR packages" \
    "the shared package breakdown"
expect_literal "$packages_doc" \
    "**9** are native-only: 5 official packages plus 4 AUR packages" \
    "the native-only package breakdown"
expect_literal "$packages_doc" \
    "**7** are WSL-only: 6 official packages plus 1 AUR package" \
    "the WSL-only package breakdown"
expect_literal "$packages_doc" \
    "\`base.txt\` + \`native.txt\` + \`aur.txt\` + \`aur-native.txt\` | 60 |" \
    "the 60-package native profile row"
expect_literal "$packages_doc" \
    "\`base.txt\` + \`wsl.txt\` + \`aur.txt\` + \`aur-wsl.txt\` | 58 |" \
    "the 58-package WSL profile row"

while IFS='|' read -r file count; do
    source_word="packages"
    ((count == 1)) && source_word="package"
    expect_literal "$packages_doc" \
        "Source: \`arch/packages/$file\` — $count $source_word" \
        "the $file count ($count)"
done <<EOF
base.txt|$base_count
aur.txt|$aur_count
native.txt|$native_count
aur-native.txt|$aur_native_count
wsl.txt|$wsl_count
aur-wsl.txt|$aur_wsl_count
fonts.txt|$fonts_count
EOF

expect_literal "$flow_svg" ">60 packages</text>" "the native package count in the SVG"
expect_literal "$flow_svg" ">58 packages</text>" "the WSL package count in the SVG"

while IFS= read -r file; do
    check_markdown_file "$file"
done < <(markdown_files)

if ((FAIL > 0)); then
    printf 'docs check failed with %d issue(s)\n' "$FAIL" >&2
    exit 1
fi

log "docs check passed: $total_count packages ($native_total native, $wsl_total WSL), $fonts_count optional fonts, and all local links and assets resolve"
