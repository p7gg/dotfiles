#!/usr/bin/env bash
#
# Shared helpers for arch/*.sh. Source this after setting REPO_ROOT and the
# script's own state (DRY_RUN, ROOT_RUNNER, etc.).
#
# Scripts should set:
#   DRY_RUN=0|1       Print commands without executing them when 1.
#   ROOT_RUNNER=...   Function used for privileged commands: run_sudo or run.
#
# The library intentionally avoids enabling set -e; each entry point owns its
# own shell options and error trap.

ERROR_REPORTED=${ERROR_REPORTED:-0}
DRY_RUN=${DRY_RUN:-0}
TMP_FILES=()

log() {
    printf '%s\n' "$*"
}

warn() {
    printf 'warning: %s\n' "$*" >&2
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

# Report the failing command once, with its source and line. Call this from an
# ERR trap: trap 'on_error' ERR.
on_error() {
    local status=$?

    ((ERROR_REPORTED == 0)) || return 0
    ERROR_REPORTED=1

    printf 'error: command failed (status %s): %s\n' \
        "$status" "${BASH_COMMAND:-unknown}" >&2
    printf '       at %s:%s\n' \
        "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}" "${BASH_LINENO[0]:-$LINENO}" >&2
}

# Print a command, then run it unless this is a dry run. A failed command is
# fatal and includes the exact command in the error message.
run_cmd() {
    printf '+'
    printf ' %q' "$@"
    printf '\n'

    if ((DRY_RUN == 0)); then
        "$@" || die "command failed: $(printf '%q ' "$@")"
    fi
}

# Like run_cmd, but a failure is a warning. Use for best-effort steps such as
# completion generation or optional Git hooks.
run_optional() {
    printf '+'
    printf ' %q' "$@"
    printf '\n'

    if ((DRY_RUN == 0)); then
        if ! "$@"; then
            warn "command failed: $(printf '%q ' "$@")"
            return 1
        fi
    fi
}

run_sudo() {
    run_cmd sudo "$@"
}

root_run() {
    local runner="${ROOT_RUNNER:-run_sudo}"
    "$runner" "$@"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

register_tmp() {
    TMP_FILES+=("$1")
}

cleanup_tmp() {
    local file

    for file in "${TMP_FILES[@]}"; do
        [[ -n "$file" ]] && rm -f -- "$file"
    done
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

list_has_packages() {
    local file="$1"
    [[ -f "$file" ]] && [[ -n "$(filter_packages "$file")" ]]
}

# Refuse package names that pacman would interpret as options or that cannot be
# valid Arch package names. This catches typos before a long pacman transaction.
validate_package_lists() {
    local file line status=0

    for file in "$@"; do
        if [[ ! -f "$file" ]]; then
            warn "package list not found: $file"
            status=1
            continue
        fi

        while IFS= read -r line; do
            if [[ ! "$line" =~ ^[a-z0-9@_+][a-z0-9@._+-]*$ ]]; then
                warn "invalid package name in ${file#"$REPO_ROOT/"}: $line"
                status=1
            fi
        done < <(filter_packages "$file")
    done

    return "$status"
}

ensure_keyring() {
    local key_count

    key_count="$(pacman-key --list-keys 2>/dev/null | grep -c '^pub' || true)"

    if ((key_count == 0)); then
        warn "pacman keyring is empty; initializing it (common on fresh WSL images)"
        root_run pacman-key --init
        root_run pacman-key --populate archlinux
        return 0
    fi

    if ((key_count < 2)); then
        warn "pacman keyring has no Arch packager keys; populating it"
        root_run pacman-key --populate archlinux
        return 0
    fi

    log "pacman keyring already initialized"
}

# Copy a managed file to a timestamped backup and expose the path in BACKUP_PATH.
backup_file() {
    local file="$1"
    BACKUP_PATH="${file}.bak.$(date +%Y%m%d%H%M%S)"

    if ((DRY_RUN)); then
        log "Would back up $file to $BACKUP_PATH"
        return 0
    fi

    [[ -f "$file" ]] || return 0
    root_run cp -a "$file" "$BACKUP_PATH"
    log "Backed up $file to $BACKUP_PATH"
}

# Set or replace one key in an INI section. The file is written atomically after
# the complete transformation succeeds.
ini_set_key() {
    local file="$1"
    local section="$2"
    local key="$3"
    local value="$4"
    local tmp

    tmp="$(mktemp)"

    if ! awk -v section="$section" -v key="$key" -v value="$value" '
        function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
        }
        function flush_section() {
            if (in_section && !found) {
                print key "=" value
            }
            in_section = 0
            found = 0
        }
        {
            line = $0
            if (line ~ /^[[:space:]]*\[[^]]+\][[:space:]]*$/) {
                flush_section()
                header = trim(line)
                if (header == "[" section "]") {
                    in_section = 1
                    section_seen = 1
                }
                print
                next
            }
            if (in_section) {
                candidate = line
                sub(/^[[:space:]]*/, "", candidate)
                if (candidate ~ "^" key "[[:space:]]*=") {
                    if (!found) {
                        print key "=" value
                        found = 1
                    }
                    next
                }
            }
            print
        }
        END {
            flush_section()
            if (!section_seen) {
                print "[" section "]"
                print key "=" value
            }
        }
    ' "$file" >"$tmp"; then
        rm -f "$tmp"
        return 1
    fi

    if ((DRY_RUN)); then
        log "Would set [$section] $key=$value in $file"
        rm -f "$tmp"
        return 0
    fi

    install -Dm644 "$tmp" "$file"
    rm -f "$tmp"
}
