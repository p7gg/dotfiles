#!/usr/bin/env bash
#
# Render every chezmoi template with representative data. This catches template
# errors and conditional branches before a real apply changes a machine.

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
FAIL=0

trap 'rm -rf "$TMP_ROOT"' EXIT

pass() {
    printf 'ok: %s\n' "$*"
}

fail() {
    printf 'not ok: %s\n' "$*" >&2
    FAIL=1
}

expect_contains() {
    local file="$1"
    local pattern="$2"
    local label="$3"

    if grep -Eq -- "$pattern" "$file"; then
        pass "$label"
    else
        fail "$label"
    fi
}

expect_not_contains() {
    local file="$1"
    local pattern="$2"
    local label="$3"

    if grep -Eq -- "$pattern" "$file"; then
        fail "$label"
    else
        pass "$label"
    fi
}

write_config() {
    local work_email="$1"
    local config="$2"

    {
        printf '[data]\n'
        printf '    name = "Test User"\n'
        printf '    email = "test@example.com"\n'
        printf '    work_email = "%s"\n' "$work_email"
    } >"$config"
}

render() {
    local template="$1"
    local config="$2"
    local output="$3"

    chezmoi --config "$config" execute-template \
        <"$REPO_ROOT/home/$template" >"$output"
}

mkdir -p "$TMP_ROOT/blank" "$TMP_ROOT/work" "$TMP_ROOT/init-home/.config"

write_config "" "$TMP_ROOT/blank/chezmoi.toml"
write_config "work@example.com" "$TMP_ROOT/work/chezmoi.toml"

render dot_gitconfig.tmpl "$TMP_ROOT/blank/chezmoi.toml" "$TMP_ROOT/blank/gitconfig"
render dot_config/git/work.inc.tmpl "$TMP_ROOT/blank/chezmoi.toml" "$TMP_ROOT/blank/work.inc"
render private_dot_ssh/private_config.tmpl "$TMP_ROOT/blank/chezmoi.toml" "$TMP_ROOT/blank/ssh-config"
HOME="$TMP_ROOT/blank/home" XDG_CONFIG_HOME="$TMP_ROOT/blank/home/.config" \
    chezmoi --config "$TMP_ROOT/blank/chezmoi.toml" execute-template \
    <"$REPO_ROOT/home/dot_config/go/env.tmpl" >"$TMP_ROOT/blank/go-env"

expect_not_contains "$TMP_ROOT/blank/gitconfig" 'includeIf .*Projects/work' \
    "blank work email omits the work include"
expect_not_contains "$TMP_ROOT/blank/ssh-config" 'source\.developers\.google\.com' \
    "blank work email omits the Cloud Source host"
if [[ -s "$TMP_ROOT/blank/work.inc" ]]; then
    fail "blank work email leaves work.inc empty"
else
    pass "blank work email leaves work.inc empty"
fi
expect_contains "$TMP_ROOT/blank/go-env" "^GOPATH=$TMP_ROOT/blank/home/\.go$" \
    "go env uses the chezmoi home directory"

if command -v delta >/dev/null 2>&1; then
    expect_contains "$TMP_ROOT/blank/gitconfig" 'pager = delta' \
        "delta is configured when installed"
else
    expect_not_contains "$TMP_ROOT/blank/gitconfig" 'pager = delta' \
        "delta is omitted when missing"
fi

if command -v difft >/dev/null 2>&1; then
    expect_contains "$TMP_ROOT/blank/gitconfig" 'dt = !difft' \
        "difftastic alias is configured when installed"
else
    expect_not_contains "$TMP_ROOT/blank/gitconfig" 'dt = !difft' \
        "difftastic alias is omitted when missing"
fi

render dot_gitconfig.tmpl "$TMP_ROOT/work/chezmoi.toml" "$TMP_ROOT/work/gitconfig"
render dot_config/git/work.inc.tmpl "$TMP_ROOT/work/chezmoi.toml" "$TMP_ROOT/work/work.inc"
render private_dot_ssh/private_config.tmpl "$TMP_ROOT/work/chezmoi.toml" "$TMP_ROOT/work/ssh-config"

expect_contains "$TMP_ROOT/work/gitconfig" 'includeIf "gitdir:~/Projects/work/"' \
    "work email enables the work include"
expect_contains "$TMP_ROOT/work/work.inc" 'email = "work@example.com"' \
    "work.inc contains the work email"
expect_contains "$TMP_ROOT/work/ssh-config" 'User work@example\.com' \
    "Cloud Source host uses the work email"

# .chezmoi.toml.tmpl uses init-only prompt functions, so render it with a clean
# HOME and simulated prompt answers instead of the normal config path.
if HOME="$TMP_ROOT/init-home" \
    XDG_CONFIG_HOME="$TMP_ROOT/init-home/.config" \
    chezmoi execute-template --init \
    --promptString "Your full name=Test User" \
    --promptString "Your email address=test@example.com" \
    --promptString "Work email address (leave blank for none)=" \
    <"$REPO_ROOT/home/.chezmoi.toml.tmpl" >"$TMP_ROOT/init-home/chezmoi.out" 2>"$TMP_ROOT/init-home/error"; then
    expect_contains "$TMP_ROOT/init-home/chezmoi.out" '^sourceDir = ' \
        "init template writes sourceDir"
    expect_contains "$TMP_ROOT/init-home/chezmoi.out" 'command = "nano"' \
        "init template configures the editor"
    expect_contains "$TMP_ROOT/init-home/chezmoi.out" 'name = "Test User"' \
        "init template stores the name"
    expect_contains "$TMP_ROOT/init-home/chezmoi.out" 'work_email = ""' \
        "init template allows a blank work email"
else
    fail "init template renders with simulated prompts"
    sed 's/^/  /' "$TMP_ROOT/init-home/error" >&2 || true
fi

if ((FAIL)); then
    printf 'template tests failed\n' >&2
    exit 1
fi

printf 'template tests passed\n'
