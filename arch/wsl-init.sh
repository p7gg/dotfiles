#!/usr/bin/env bash
#
# One-time root initialization for Arch Linux inside WSL.
#
# Follow https://wiki.archlinux.org/title/Install_Arch_Linux_on_WSL for the
# initial import. This script only handles the post-import system setup that
# must run as root. Run arch/bootstrap.sh as the normal user afterwards.

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=arch/lib/common.sh
source "$REPO_ROOT/arch/lib/common.sh"

TARGET_USER="${SUDO_USER:-}"
TARGET_HOSTNAME="arch-wsl"
HOSTNAME_SET=0
ENABLE_SYSTEMD=0
DRY_RUN=0
ASSUME_YES=0
ROOT_RUNNER=run_cmd
export ROOT_RUNNER

trap 'on_error' ERR
trap cleanup_tmp EXIT

usage() {
    cat <<'EOF'
Usage: sudo arch/wsl-init.sh [options]

Options:
  --user NAME        Linux user to create/configure (default: SUDO_USER)
  --hostname NAME    Machine name for WSL (default: arch-wsl; prompted when omitted)
  --systemd          Enable systemd in /etc/wsl.conf
  --dry-run          Print actions without changing anything
  --yes              Pass --noconfirm to pacman
  -h, --help         Show this help

Run this inside WSL, as root, once after importing the Arch image. Then run
`wsl --shutdown` from Windows and reopen the distro. The target user must not be
root; create or name a normal Linux user instead.

The machine name (hostname) is prompted when --hostname is omitted and a
terminal is attached. The root password is set right before the target user is
created, if the root account is locked or has none. An existing root password is
left unchanged.
EOF
}

ensure_password() {
    local user="$1"
    local status

    if ! id -u "$user" >/dev/null 2>&1; then
        if ((DRY_RUN)); then
            log "Would set a password for $user"
            return 0
        fi
        die "cannot set a password: user does not exist: $user"
    fi

    status="$(LC_ALL=C passwd -S "$user" | awk '{print $2}')"
    if [[ "$status" == "P" ]]; then
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
    local backup

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
        backup="${config}.bak.$(date +%Y%m%d%H%M%S)"
        cp -a "$config" "$backup"
        log "Backed up $config to $backup"
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
    local backup work

    if [[ -f "$file" ]]; then
        warn "$file already exists; merging required settings"
        if ((DRY_RUN)); then
            print_wsl_conf "$TARGET_USER" "$TARGET_HOSTNAME" "$ENABLE_SYSTEMD" >&2
            log "Would merge these settings into $file"
            return 0
        fi

        backup="${file}.bak.$(date +%Y%m%d%H%M%S)"
        cp -a "$file" "$backup"
        log "Backed up $file to $backup"

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
    --yes)
        ASSUME_YES=1
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

[[ $EUID -eq 0 ]] || die "run this script as root (sudo arch/wsl-init.sh)"

# shellcheck source=/dev/null
[[ -r /etc/os-release ]] && source /etc/os-release
[[ "${ID:-}" == "arch" ]] || die "this script targets Arch Linux (found: ${ID:-unknown})"

if ! is_wsl; then
    die "this script must run inside WSL"
fi

if [[ -z "$TARGET_USER" ]]; then
    if [[ -t 0 ]]; then
        read -r -p "Linux username: " TARGET_USER
    else
        die "no user specified; pass --user NAME"
    fi
fi

[[ -n "$TARGET_USER" ]] || die "username must not be empty"
[[ "$TARGET_USER" != "root" ]] ||
    die "refusing to use root as the WSL default user; pass --user NAME"
[[ "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "invalid username: $TARGET_USER"

if ((HOSTNAME_SET == 0)) && [[ -t 0 ]]; then
    read -r -p "Machine name (hostname) [$TARGET_HOSTNAME]: " hostname_input
    [[ -z "$hostname_input" ]] || TARGET_HOSTNAME="$hostname_input"
fi

[[ "$TARGET_HOSTNAME" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] ||
    die "invalid hostname: $TARGET_HOSTNAME"

require_cmd passwd

require_cmd pacman
require_cmd pacman-key
require_cmd useradd
require_cmd usermod
require_cmd locale-gen

if ! grep -q '^Server' /etc/pacman.d/mirrorlist 2>/dev/null; then
    warn "/etc/pacman.d/mirrorlist has no enabled mirrors; fix it if pacman fails"
fi

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
log "Then reopen this distro as $TARGET_USER and run: ./arch/bootstrap.sh --profile wsl"
if ((ENABLE_SYSTEMD)); then
    log "systemd was requested; ensure WSL is up to date ('wsl --update' from Windows)."
fi
