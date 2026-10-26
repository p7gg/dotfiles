#!/usr/bin/env bash
#
# One-time root initialization for Arch Linux inside WSL.
#
# Follow https://wiki.archlinux.org/title/Install_Arch_Linux_on_WSL for the
# initial import. This script only handles the post-import system setup that
# must run as root. Run provisioning/arch/bootstrap.sh as the normal user afterwards.

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=provisioning/arch/lib/common.sh
source "$REPO_ROOT/provisioning/arch/lib/common.sh"

TARGET_USER="${SUDO_USER:-}"
TARGET_HOSTNAME="arch-wsl"
HOSTNAME_SET=0
ENABLE_SYSTEMD=0
DRY_RUN=0
ASSUME_YES=0
CHECK_ONLY=0
NON_INTERACTIVE=0
ROOT_RUNNER=run_cmd
export ROOT_RUNNER

trap 'on_error' ERR
trap cleanup_tmp EXIT

usage() {
    cat <<'EOF'
Usage: sudo provisioning/arch/wsl-init.sh [options]

Options:
  --user NAME        Linux user to create/configure (default: SUDO_USER)
  --hostname NAME    Machine name for WSL (default: arch-wsl; prompted when omitted)
  --systemd          Enable systemd in /etc/wsl.conf
  --check            Validate prerequisites and exit without changing anything
  --dry-run          Print actions without changing anything
  --yes              Pass --noconfirm to pacman
  --non-interactive  Never prompt (implies --yes); fail before changes when a
                     password must be set
  -h, --help         Show this help

Run this inside WSL, as root, once after importing the Arch image. Then run
`wsl --shutdown` from Windows and reopen the distro. The target user must not be
root; create or name a normal Linux user instead.

The machine name (hostname) is prompted when --hostname is omitted and a
terminal is attached. The root password is set right before the target user is
created, if the root account is locked or has none. An existing root password is
left unchanged. For unattended runs, set the root and target-user passwords
first; the script refuses to reach an interactive passwd prompt without a TTY.

Environment:
  BACKUP_RETENTION  Timestamped backups to keep per managed file (default: 3)
EOF
}

validate_target_user() {
    [[ -n "$TARGET_USER" ]] || die "username must not be empty"
    [[ "$TARGET_USER" != "root" ]] ||
        die "refusing to use root as the WSL default user; pass --user NAME"
    [[ "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "invalid username: $TARGET_USER"
}

validate_target_hostname() {
    [[ "$TARGET_HOSTNAME" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] ||
        die "invalid hostname: $TARGET_HOSTNAME"
}

ensure_password() {
    local user="$1"
    local state

    if ! id -u "$user" >/dev/null 2>&1; then
        if ((DRY_RUN)); then
            log "Would set a password for $user"
            return 0
        fi
        die "cannot set a password: user does not exist: $user"
    fi

    state="$(password_state "$user")"
    if [[ "$state" == "P" ]]; then
        log "$user already has a password; leaving it unchanged"
        return 0
    fi

    if ((DRY_RUN)); then
        log "Would set a password for $user"
        return 0
    fi

    log "Set a password for $user"
    passwd "$user"
}

password_prompt_targets() {
    if account_needs_password root; then
        printf 'root\n'
    fi
    if account_needs_password "$TARGET_USER"; then
        printf '%s\n' "$TARGET_USER"
    fi
}

# Fail before pacman or account changes when the remaining password steps need
# a terminal that is not available. --check reports the same condition.
preflight_passwords() {
    local targets target_list

    targets="$(password_prompt_targets)"
    if [[ -z "$targets" ]]; then
        log "Passwords are already set for root and $TARGET_USER"
        return 0
    fi

    target_list="$(tr '\n' ' ' <<<"$targets" | sed 's/ $//')"

    if ((CHECK_ONLY)); then
        if ((NON_INTERACTIVE)) || [[ ! -t 0 ]]; then
            warn "password setup is required for: $target_list"
            warn "run interactively or set those passwords before an unattended run"
            return 1
        fi
        log "Password prompts are required for: $target_list"
        return 0
    fi

    if ((DRY_RUN)); then
        log "Would set passwords for: $target_list"
        return 0
    fi

    if ((NON_INTERACTIVE)) || [[ ! -t 0 ]]; then
        die "password setup is required for: $target_list; set the passwords first or rerun in a terminal (unattended runs cannot answer passwd prompts)"
    fi

    log "Passwords will be requested for: $target_list"
    return 0
}

write_sudoers() {
    local file="/etc/sudoers.d/10-wheel"
    local tmp

    if ((DRY_RUN)); then
        log "Would ensure $file grants wheel sudo access"
        return 0
    fi

    if [[ -f "$file" ]]; then
        log "$file already exists; validating it"
        visudo -cf "$file"
        if ! grep -qE '^%wheel[[:space:]]+ALL=\(ALL:ALL\)[[:space:]]+ALL$' "$file"; then
            warn "$file does not grant wheel sudo access; review it manually"
        fi
        return 0
    fi

    log "Creating $file"
    tmp="$(mktemp)"
    register_tmp "$tmp"
    printf '%s\n' '%wheel ALL=(ALL:ALL) ALL' >"$tmp"
    visudo -cf "$tmp"
    install -Dm440 "$tmp" "$file"
}

setup_locale() {
    local config="/etc/locale.conf"

    if ((DRY_RUN)); then
        log "Would enable en_US.UTF-8, run locale-gen, and update /etc/locale.conf"
        return 0
    fi

    [[ -f /etc/locale.gen.bak ]] || cp -a /etc/locale.gen /etc/locale.gen.bak

    if grep -qE '^#[[:space:]]*en_US\.UTF-8 UTF-8' /etc/locale.gen; then
        sed -i -E 's/^#[[:space:]]*en_US\.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    elif ! grep -qE '^en_US\.UTF-8 UTF-8' /etc/locale.gen; then
        printf '%s\n' 'en_US.UTF-8 UTF-8' >>/etc/locale.gen
    fi

    locale-gen

    if [[ -f "$config" ]]; then
        backup_file "$config"
        if grep -qE '^[[:space:]]*LANG=' "$config"; then
            sed -i -E 's/^[[:space:]]*LANG=.*/LANG=en_US.UTF-8/' "$config"
        else
            printf '%s\n' 'LANG=en_US.UTF-8' >>"$config"
        fi
        return 0
    fi

    printf '%s\n' 'LANG=en_US.UTF-8' >"$config"
}

print_wsl_conf() {
    local user="$1"
    local hostname="$2"
    local systemd="$3"

    if ((systemd)); then
        printf '%s\n' '[boot]' 'systemd=true' ''
    fi

    cat <<EOF
[user]
default=$user

[interop]
appendWindowsPath=true

[automount]
enabled=true
options="metadata,umask=22,fmask=11"

[network]
hostname=$hostname
EOF
}

setup_wsl_conf() {
    local file="/etc/wsl.conf"
    local work

    if [[ -f "$file" ]]; then
        warn "$file already exists; merging required settings"
        if ((DRY_RUN)); then
            print_wsl_conf "$TARGET_USER" "$TARGET_HOSTNAME" "$ENABLE_SYSTEMD" >&2
            log "Would merge these settings into $file"
            return 0
        fi

        backup_file "$file"

        work="$(mktemp)"
        register_tmp "$work"
        cp -a "$file" "$work"

        ini_set_key "$work" user default "$TARGET_USER"
        # Preserve existing [interop] and [automount] choices; WSL defaults are
        # fine when those sections are absent.
        ini_set_key "$work" network hostname "$TARGET_HOSTNAME"
        if ((ENABLE_SYSTEMD)); then
            ini_set_key "$work" boot systemd true
        fi

        install -Dm644 "$work" "$file"
        log "Merged settings into $file"
        return 0
    fi

    log "Creating $file"
    if ((DRY_RUN)); then
        print_wsl_conf "$TARGET_USER" "$TARGET_HOSTNAME" "$ENABLE_SYSTEMD"
        return 0
    fi

    print_wsl_conf "$TARGET_USER" "$TARGET_HOSTNAME" "$ENABLE_SYSTEMD" >"$file"
    chmod 644 "$file"
}

while (($# > 0)); do
    case "$1" in
    --user)
        [[ $# -ge 2 ]] || die "--user requires an argument"
        TARGET_USER="$2"
        shift 2
        ;;
    --user=*)
        TARGET_USER="${1#*=}"
        shift
        ;;
    --hostname)
        [[ $# -ge 2 ]] || die "--hostname requires an argument"
        TARGET_HOSTNAME="$2"
        HOSTNAME_SET=1
        shift 2
        ;;
    --hostname=*)
        TARGET_HOSTNAME="${1#*=}"
        HOSTNAME_SET=1
        shift
        ;;
    --systemd)
        ENABLE_SYSTEMD=1
        shift
        ;;
    --dry-run)
        DRY_RUN=1
        shift
        ;;
    --check)
        CHECK_ONLY=1
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

if ((NON_INTERACTIVE)); then
    ASSUME_YES=1
fi

# Validate values supplied on the command line before the privilege and OS
# checks so a typo never reaches a prompt or a package transaction.
if [[ -n "$TARGET_USER" ]]; then
    validate_target_user
fi
if ((HOSTNAME_SET)); then
    validate_target_hostname
fi

if [[ -z "$TARGET_USER" ]] && { ((NON_INTERACTIVE)) || [[ ! -t 0 ]]; }; then
    die "no user specified; pass --user NAME"
fi

[[ $EUID -eq 0 ]] || die "run this script as root (sudo provisioning/arch/wsl-init.sh)"

# shellcheck source=/dev/null
[[ -r /etc/os-release ]] && source /etc/os-release
[[ "${ID:-}" == "arch" ]] || die "this script targets Arch Linux (found: ${ID:-unknown})"

if ! is_wsl; then
    die "this script must run inside WSL"
fi

if [[ -z "$TARGET_USER" ]]; then
    read -r -p "Linux username: " TARGET_USER
fi
validate_target_user

if ((HOSTNAME_SET == 0)) && ! ((NON_INTERACTIVE)) && [[ -t 0 ]]; then
    read -r -p "Machine name (hostname) [$TARGET_HOSTNAME]: " hostname_input
    [[ -z "$hostname_input" ]] || TARGET_HOSTNAME="$hostname_input"
fi
validate_target_hostname

require_cmd passwd

require_cmd pacman
require_cmd pacman-key
require_cmd useradd
require_cmd usermod
require_cmd locale-gen

if ! grep -q '^Server' /etc/pacman.d/mirrorlist 2>/dev/null; then
    warn "/etc/pacman.d/mirrorlist has no enabled mirrors; fix it if pacman fails"
fi

if ((CHECK_ONLY)); then
    if ! preflight_passwords; then
        exit 1
    fi
    log "Check complete: no blocking issues found."
    log "WSL initialization was not run; omit --check to apply it."
    exit 0
fi

preflight_passwords

ensure_keyring

log "Updating the system"
if ((ASSUME_YES)); then
    run_cmd pacman -Syu --noconfirm
else
    run_cmd pacman -Syu
fi

log "Installing sudo and git"
if ((ASSUME_YES)); then
    run_cmd pacman -S --needed --noconfirm sudo git
else
    run_cmd pacman -S --needed sudo git
fi

if ((DRY_RUN == 0)); then
    require_cmd visudo
fi

# Secure root right before creating the unprivileged login.
ensure_password root

if id -u "$TARGET_USER" >/dev/null 2>&1; then
    log "User $TARGET_USER already exists; ensuring wheel membership"
    run_cmd usermod -aG wheel "$TARGET_USER"
else
    log "Creating user $TARGET_USER"
    run_cmd useradd -m -G wheel -s /bin/bash "$TARGET_USER"
fi

ensure_password "$TARGET_USER"

write_sudoers
setup_locale
setup_wsl_conf

log "WSL initialization complete."
log "From Windows, run: wsl --shutdown"
log "Then reopen this distro as $TARGET_USER and run: ./provisioning/arch/bootstrap.sh --profile wsl"
if ((ENABLE_SYSTEMD)); then
    log "systemd was requested; ensure WSL is up to date ('wsl --update' from Windows)."
fi
