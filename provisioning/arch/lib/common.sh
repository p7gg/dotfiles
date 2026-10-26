#!/usr/bin/env bash
#
# Shared helpers for provisioning/arch entry points. Source this after setting
# REPO_ROOT and the script's own state (DRY_RUN, ROOT_RUNNER, etc.).
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
TMP_DIRS=()
# Keep timestamped backups of managed system files bounded. Override with
# BACKUP_RETENTION=... when a longer local history is useful.
BACKUP_RETENTION=${BACKUP_RETENTION:-3}

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

register_tmp_dir() {
    TMP_DIRS+=("$1")
}

cleanup_tmp() {
    local file dir

    for file in "${TMP_FILES[@]}"; do
        [[ -n "$file" ]] && rm -f -- "$file"
    done

    for dir in "${TMP_DIRS[@]}"; do
        [[ -n "$dir" ]] && rm -rf -- "$dir"
    done
}

is_wsl() {
    [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft /proc/version 2>/dev/null
}

# A file with only comments or blank lines is not enough to keep password
# authentication disabled, so require at least one key-like line.
has_authorized_key() {
    local file="$1"

    [[ -s "$file" ]] && grep -Eqv '^[[:space:]]*(#|$)' "$file"
}

detect_profile() {
    if is_wsl; then
        printf 'wsl\n'
    else
        printf 'native\n'
    fi
}

# Print the reason when a profile does not match the current environment.
# Auto-detection never mismatches; this guards an explicit --profile choice.
profile_mismatch() {
    local profile="$1"

    case "$profile" in
    native)
        if is_wsl; then
            printf 'native profile selected inside WSL\n'
            return 0
        fi
        ;;
    wsl)
        if ! is_wsl; then
            printf 'wsl profile selected outside WSL\n'
            return 0
        fi
        ;;
    esac

    return 1
}

# Report the password status field from `passwd -S` (P means a usable
# password). An unreadable entry returns an empty string.
password_state() {
    local user="$1"

    LC_ALL=C passwd -S "$user" 2>/dev/null | awk 'NR == 1 { print $2 }'
}

# A missing account or one without a usable password will make the caller
# prompt for one. Check this before a non-interactive run changes the system.
account_needs_password() {
    local user="$1"
    local state

    if ! id -u "$user" >/dev/null 2>&1; then
        return 0
    fi

    state="$(password_state "$user")"
    [[ "$state" == "P" ]] && return 1
    return 0
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

# Emit package names from an optional catalog whose entries use the format
# "package|Display Name". The display name is only used by provisioning/arch/tools/fonts.sh.
filter_optional_packages() {
    local file="$1"

    filter_packages "$file" | while IFS='|' read -r pkg _; do
        [[ -n "$pkg" ]] && printf '%s\n' "$pkg"
    done

    return 0
}

# Validate an optional "package|Display Name" catalog before it is offered to the
# user or used to allow packages during an audit.
validate_font_catalog() {
    local file="$1"
    local line pkg name status=0
    local -A seen=()

    if [[ ! -f "$file" ]]; then
        warn "font catalog not found: $file"
        return 1
    fi

    while IFS= read -r line; do
        if [[ "$line" != *"|"* ]]; then
            warn "invalid font entry in ${file#"$REPO_ROOT/"}: $line (expected package|Display Name)"
            status=1
            continue
        fi

        pkg="${line%%|*}"
        name="${line#*|}"

        if [[ ! "$pkg" =~ ^[a-z0-9@_+][a-z0-9@._+-]*$ ]]; then
            warn "invalid font package in ${file#"$REPO_ROOT/"}: $pkg"
            status=1
        elif [[ -n "${seen[$pkg]:-}" ]]; then
            warn "duplicate font package in ${file#"$REPO_ROOT/"}: $pkg"
            status=1
        else
            seen["$pkg"]=1
        fi

        if [[ -z "$name" || "$name" == *"|"* ]]; then
            warn "invalid font display name in ${file#"$REPO_ROOT/"}: $line"
            status=1
        fi
    done < <(filter_packages "$file")

    return "$status"
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

# Copy a managed file to a timestamped backup and expose the path in
# BACKUP_PATH. Older timestamped backups are pruned to BACKUP_RETENTION.
backup_file() {
    local file="$1"
    BACKUP_PATH="${file}.bak.$(date +%Y%m%d%H%M%S)"

    if ((DRY_RUN)); then
        log "Would back up $file to $BACKUP_PATH (keeping ${BACKUP_RETENTION} backups)"
        return 0
    fi

    [[ -f "$file" ]] || return 0
    root_run cp -a "$file" "$BACKUP_PATH"
    log "Backed up $file to $BACKUP_PATH"
    rotate_backups "$file"
}

# Remove all but the newest timestamped backups for one managed file.
rotate_backups() {
    local file="$1"
    local keep="${2:-$BACKUP_RETENTION}"
    local dir base
    local -a backups=()
    local index

    if [[ ! "$keep" =~ ^[0-9]+$ ]] || ((keep < 1)); then
        warn "invalid backup retention '$keep'; keeping 3 backups"
        keep=3
    fi

    dir="$(dirname -- "$file")"
    base="$(basename -- "$file")"
    mapfile -t backups < <(
        find "$dir" -maxdepth 1 -type f -name "${base}.bak.[0-9]*" -print 2>/dev/null |
            LC_ALL=C sort -r
    )

    for ((index = keep; index < ${#backups[@]}; index++)); do
        root_run rm -f -- "${backups[index]}"
    done
}

# Verify an npm-style sha512 integrity value against a downloaded file.
# Returns 0 on a match, 1 on a mismatch, and 2 when the value is unusable.
verify_sha512_integrity() {
    local file="$1"
    local integrity="$2"
    local expected actual

    [[ "$integrity" == sha512-* ]] || return 2
    expected="${integrity#sha512-}"
    expected="$(printf '%s' "$expected" | base64 -d 2>/dev/null |
        od -An -v -tx1 2>/dev/null | tr -d ' \n')" || true

    [[ ${#expected} -eq 128 ]] || return 2
    actual="$(sha512sum -- "$file" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]]
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
