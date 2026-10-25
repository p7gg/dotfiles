#!/usr/bin/env bash
#
# Provision an existing Arch Linux user environment.
#
# This script intentionally does not partition disks, install a bootloader,
# configure encryption, or manage hardware-specific packages. Those belong to
# the OS installation step.
#
# Run as your normal user, not as root.

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

PROFILE="auto"
DRY_RUN=0
ASSUME_YES=0
DO_PACKAGES=1
DO_DOTFILES=1
DO_MISE=1
DO_SERVICES=1
DO_SHELL=1
DO_COMPLETIONS=1
DO_SYSTEM=1

usage() {
    cat <<'EOF'
Usage: arch/bootstrap.sh [options]

Options:
  --profile native|wsl  Target profile (default: auto-detect)
  --dry-run             Print actions without changing anything
  --yes                 Pass --noconfirm to pacman/paru where supported
  --no-packages         Skip pacman/AUR package installation
  --no-dotfiles         Skip chezmoi init/apply
  --no-mise             Skip `mise install`
  --no-completions      Skip fish completion generation
  --no-system           Skip pacman/reflector/firewall/tailscale setup
  --no-services         Skip enabling desktop systemd services
  --no-shell            Do not change the login shell to fish
  -h, --help            Show this help

Run this as your normal user. Use `sudo ./arch/wsl-init.sh` for the one-time
WSL root setup.
EOF
}

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

on_error() {
    local status=$?
    printf 'error: bootstrap failed at line %s (status %s)\n' "$1" "$status" >&2
}

trap 'on_error "$LINENO"' ERR

run() {
    printf '+'
    printf ' %q' "$@"
    printf '\n'
    if ((DRY_RUN == 0)); then
        "$@"
    fi
}

run_sudo() {
    run sudo "$@"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
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

ensure_keyring() {
    local key_count

    key_count="$(pacman-key --list-keys 2>/dev/null | grep -c '^pub' || true)"

    if ((key_count == 0)); then
        warn "pacman keyring is empty; initializing it (common on fresh WSL images)"
        run_sudo pacman-key --init
        run_sudo pacman-key --populate archlinux
        return 0
    fi

    if ((key_count < 2)); then
        warn "pacman keyring has no Arch packager keys; populating it"
        run_sudo pacman-key --populate archlinux
        return 0
    fi

    log "pacman keyring already initialized"
}

pacman_install_file() {
    local file="$1"
    local -a pkgs=()
    local -a args=(pacman -S --needed)

    mapfile -t pkgs < <(filter_packages "$file")
    ((${#pkgs[@]} > 0)) || return 0

    if ((ASSUME_YES)); then
        args+=(--noconfirm)
    fi

    log "Installing native packages from ${file#"$REPO_ROOT/"}"
    run_sudo "${args[@]}" "${pkgs[@]}"
}

paru_install_file() {
    local file="$1"
    local -a pkgs=()
    local -a args=(paru -S --needed)

    mapfile -t pkgs < <(filter_packages "$file")
    ((${#pkgs[@]} > 0)) || return 0

    if ((ASSUME_YES)); then
        args+=(--noconfirm)
    fi

    log "Installing AUR packages from ${file#"$REPO_ROOT/"}"
    run "${args[@]}" "${pkgs[@]}"
}

ensure_paru() {
    local profile="$1"
    local file
    local has_aur=0

    command -v paru >/dev/null 2>&1 && return 0

    for file in "$REPO_ROOT/arch/packages/aur.txt" "$REPO_ROOT/arch/packages/aur-${profile}.txt"; do
        if list_has_packages "$file"; then
            has_aur=1
            break
        fi
    done

    if ((has_aur == 0)); then
        log "No AUR packages listed; skipping paru bootstrap"
        return 0
    fi

    require_cmd git
    require_cmd makepkg

    log "Bootstrapping paru from the AUR"
    if ((DRY_RUN)); then
        log "Would clone https://aur.archlinux.org/paru.git and run makepkg -si"
        return 0
    fi

    local tmp
    tmp="$(mktemp -d)"
    git clone --depth=1 https://aur.archlinux.org/paru.git "$tmp/paru"
    (cd "$tmp/paru" && makepkg -si)
    rm -rf "$tmp"

    command -v paru >/dev/null 2>&1 || die "paru installation did not produce a paru executable"
}

install_packages() {
    local profile="$1"

    ensure_keyring

    log "Updating the system before installing packages"
    if ((ASSUME_YES)); then
        run_sudo pacman -Syu --noconfirm
    else
        run_sudo pacman -Syu
    fi

    pacman_install_file "$REPO_ROOT/arch/packages/base.txt"
    pacman_install_file "$REPO_ROOT/arch/packages/${profile}.txt"

    ensure_paru "$profile"
    paru_install_file "$REPO_ROOT/arch/packages/aur.txt"
    paru_install_file "$REPO_ROOT/arch/packages/aur-${profile}.txt"
}

configure_chezmoi_source() {
    local config="$HOME/.config/chezmoi/chezmoi.toml"
    local escaped tmp

    if ((DRY_RUN)); then
        log "Would set sourceDir=$REPO_ROOT in $config"
        return 0
    fi

    if [[ ! -f "$config" ]]; then
        warn "chezmoi config not found at $config; cannot set sourceDir"
        return 0
    fi

    escaped="${REPO_ROOT//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"

    tmp="$(mktemp "${config}.XXXXXX")"
    {
        printf 'sourceDir = "%s"\n\n' "$escaped"
        grep -vE '^[[:space:]]*sourceDir[[:space:]]*=' "$config" || true
    } >"$tmp"
    mv "$tmp" "$config"
    chmod 600 "$config"

    log "Configured chezmoi sourceDir=$REPO_ROOT"
}

apply_dotfiles() {
    if ((DRY_RUN)); then
        log "Would run: chezmoi init --apply --source $REPO_ROOT"
        configure_chezmoi_source
        return 0
    fi

    require_cmd chezmoi

    log "Applying dotfiles with chezmoi"
    chezmoi init --apply --source "$REPO_ROOT"
    configure_chezmoi_source
}

setup_shell() {
    local user fish_path current_shell

    if ! command -v fish >/dev/null 2>&1; then
        if ((DRY_RUN)); then
            log "Would install fish and set it as the login shell"
            return 0
        fi
        die "fish is not installed"
    fi

    user="$(id -un)"
    fish_path="$(command -v fish)"
    current_shell="$(getent passwd "$user" | cut -d: -f7)"

    if [[ "$current_shell" == "$fish_path" ]]; then
        log "Login shell already set to $fish_path"
        return 0
    fi

    log "Setting login shell for $user to $fish_path"
    run_sudo chsh -s "$fish_path" "$user"
}

setup_mise() {
    if ! command -v mise >/dev/null 2>&1; then
        if ((DRY_RUN)); then
            log "Would install mise and run: mise install"
            return 0
        fi
        die "mise is not installed"
    fi

    if [[ ! -f "$HOME/.config/mise/config.toml" ]]; then
        warn "mise config not found; run without --no-dotfiles before mise install"
        return 0
    fi

    log "Installing mise toolchains"
    run mise install
}

setup_completions() {
    local script="$REPO_ROOT/arch/completions.sh"

    if [[ ! -x "$script" ]]; then
        warn "completion script not found: $script"
        return 0
    fi

    log "Generating fish completions"
    run "$script"
}

setup_services() {
    local profile="$1"
    local svc

    if [[ "$profile" != "native" ]]; then
        log "Skipping desktop services for profile $profile"
        return 0
    fi

    if [[ ! -d /run/systemd/system ]]; then
        warn "systemd is not running; skipping desktop service setup"
        return 0
    fi

    for svc in gdm NetworkManager bluetooth power-profiles-daemon; do
        if ! systemctl cat "${svc}.service" >/dev/null 2>&1; then
            warn "systemd unit not found: ${svc}.service"
            continue
        fi

        if systemctl is-active --quiet "${svc}.service" 2>/dev/null; then
            log "${svc}.service already active"
            continue
        fi

        if systemctl is-enabled --quiet "${svc}.service" 2>/dev/null; then
            log "Starting ${svc}.service"
            run_sudo systemctl start "${svc}.service" || warn "could not start ${svc}.service"
            continue
        fi

        log "Enabling ${svc}.service"
        run_sudo systemctl enable --now "${svc}.service" || warn "could not enable ${svc}.service"
    done
}

configure_pacman() {
    local conf="/etc/pacman.conf"

    if [[ ! -f "$conf" ]]; then
        warn "pacman config not found: $conf"
        return 0
    fi

    if ! grep -qE '^Color$' "$conf"; then
        if grep -qE '^#Color$' "$conf"; then
            run_sudo sed -i 's/^#Color$/Color/' "$conf"
        else
            run_sudo sed -i '/^\[options\]/a Color' "$conf"
        fi
    fi

    if ! grep -qE '^ILoveCandy$' "$conf"; then
        run_sudo sed -i '/^Color$/a ILoveCandy' "$conf"
    fi

    if grep -qE '^#?ParallelDownloads' "$conf"; then
        run_sudo sed -i -E 's/^#?ParallelDownloads.*/ParallelDownloads = 5/' "$conf"
    else
        run_sudo sed -i '/^ILoveCandy$/a ParallelDownloads = 5' "$conf"
    fi

    if grep -qE '^#CheckSpace$' "$conf"; then
        run_sudo sed -i 's/^#CheckSpace$/CheckSpace/' "$conf"
    elif ! grep -qE '^CheckSpace$' "$conf"; then
        run_sudo sed -i '/^ParallelDownloads/a CheckSpace' "$conf"
    fi

    log "pacman.conf options updated"
}

configure_reflector() {
    local src="$REPO_ROOT/arch/system/reflector.conf"

    if [[ ! -f "$src" ]]; then
        warn "reflector config not found: $src"
        return 0
    fi

    log "Installing Brazil-prioritized reflector config"
    run_sudo install -Dm644 "$src" /etc/xdg/reflector/reflector.conf
}

enable_timer() {
    local timer="$1"

    if [[ ! -d /run/systemd/system ]]; then
        warn "systemd is not running; skipping $timer"
        return 0
    fi

    if ! systemctl cat "$timer" >/dev/null 2>&1; then
        warn "systemd timer not found: $timer"
        return 0
    fi

    if systemctl is-active --quiet "$timer" 2>/dev/null; then
        log "$timer already active"
        return 0
    fi

    if systemctl is-enabled --quiet "$timer" 2>/dev/null; then
        log "Starting $timer"
        run_sudo systemctl start "$timer" || warn "could not start $timer"
        return 0
    fi

    log "Enabling $timer"
    run_sudo systemctl enable --now "$timer" || warn "could not enable $timer"
}

setup_timers() {
    local profile="$1"

    if [[ ! -d /run/systemd/system ]]; then
        warn "systemd is not running; skipping maintenance timers"
        return 0
    fi

    enable_timer paccache.timer
    enable_timer reflector.timer

    if [[ "$profile" == "native" ]]; then
        enable_timer fstrim.timer
        enable_timer fwupd-refresh.timer
    fi

    if command -v reflector >/dev/null 2>&1; then
        log "Refreshing the Brazil-prioritized mirrorlist"
        run_sudo systemctl start reflector.service || warn "reflector refresh failed"
    fi
}

setup_firewall() {
    local profile="$1"

    if [[ "$profile" != "native" ]]; then
        log "Skipping ufw for profile $profile"
        return 0
    fi

    if ! command -v ufw >/dev/null 2>&1; then
        warn "ufw is not installed; skipping firewall setup"
        return 0
    fi

    if [[ -r /etc/ufw/ufw.conf ]] && grep -q '^ENABLED=yes' /etc/ufw/ufw.conf; then
        log "ufw is already enabled; ensuring SSH and Tailscale rules"
        run_sudo ufw allow 22/tcp
        run_sudo ufw allow in on tailscale0 || warn "could not add Tailscale interface rule"
        return 0
    fi

    log "Configuring ufw"
    # Add additional allow rules here (or in /etc/ufw) as needed.
    run_sudo ufw default deny incoming
    run_sudo ufw default allow outgoing
    run_sudo ufw allow 22/tcp
    run_sudo ufw allow in on tailscale0 || warn "could not add Tailscale interface rule"
    run_sudo ufw --force enable
}

setup_tailscale() {
    local profile="$1"

    if ! command -v tailscale >/dev/null 2>&1; then
        warn "tailscale is not installed; skipping tailscaled setup"
        return 0
    fi

    if [[ -d /run/systemd/system ]]; then
        if ! systemctl cat tailscaled.service >/dev/null 2>&1; then
            warn "tailscaled.service not found"
            return 0
        fi

        if systemctl is-active --quiet tailscaled.service 2>/dev/null; then
            log "tailscaled.service is running"
        elif systemctl is-enabled --quiet tailscaled.service 2>/dev/null; then
            log "Starting tailscaled.service"
            run_sudo systemctl start tailscaled.service || warn "could not start tailscaled.service"
        else
            log "Enabling tailscaled.service"
            run_sudo systemctl enable --now tailscaled.service || warn "could not start tailscaled.service"
        fi
        return 0
    fi

    if [[ "$profile" == "wsl" ]] || is_wsl; then
        warn "WSL has no systemd here; start Tailscale manually with:"
        warn "  sudo tailscaled >/tmp/tailscaled.log 2>&1 &"
        warn "  sudo tailscale up"
        warn "Alternatively, rerun arch/wsl-init.sh --systemd and restart WSL."
    else
        warn "systemd is not running; cannot enable tailscaled"
    fi
}

setup_hooks() {
    if ! command -v lefthook >/dev/null 2>&1; then
        warn "lefthook is not installed; skipping Git hooks"
        return 0
    fi

    if ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        warn "not a Git repository; skipping lefthook install"
        return 0
    fi

    log "Installing lefthook Git hooks"
    (
        cd "$REPO_ROOT" && run lefthook install
    ) || warn "could not install lefthook hooks"
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
    --dry-run)
        DRY_RUN=1
        shift
        ;;
    --yes)
        ASSUME_YES=1
        shift
        ;;
    --no-packages)
        DO_PACKAGES=0
        shift
        ;;
    --no-dotfiles)
        DO_DOTFILES=0
        shift
        ;;
    --no-mise)
        DO_MISE=0
        shift
        ;;
    --no-completions)
        DO_COMPLETIONS=0
        shift
        ;;
    --no-system)
        DO_SYSTEM=0
        shift
        ;;
    --no-services)
        DO_SERVICES=0
        shift
        ;;
    --no-shell)
        DO_SHELL=0
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

[[ $EUID -ne 0 ]] || die "do not run this script as root; run it as your user"

# shellcheck source=/dev/null
[[ -r /etc/os-release ]] && source /etc/os-release
[[ "${ID:-}" == "arch" ]] || die "this script targets Arch Linux (found: ${ID:-unknown})"

require_cmd pacman
require_cmd sudo

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

if ((DRY_RUN == 0 && (DO_PACKAGES || DO_SERVICES || DO_SHELL || DO_SYSTEM))); then
    log "Requesting sudo access"
    sudo -v || die "sudo access is required for package/service/shell changes"
fi

log "Repository: $REPO_ROOT"
log "Profile:    $PROFILE"
log "Dry run:    $DRY_RUN"

if ((DO_SYSTEM)); then
    configure_pacman
else
    log "Skipping pacman configuration"
fi

if ((DO_PACKAGES)); then
    install_packages "$PROFILE"
else
    log "Skipping packages"
fi

if ((DO_SYSTEM)); then
    configure_reflector
    setup_timers "$PROFILE"
    setup_firewall "$PROFILE"
    setup_tailscale "$PROFILE"
else
    log "Skipping system maintenance"
fi

if ((DO_DOTFILES)); then
    apply_dotfiles
else
    log "Skipping dotfiles"
fi

if ((DO_SYSTEM)); then
    setup_hooks
fi

if ((DO_SHELL)); then
    setup_shell
else
    log "Skipping login shell setup"
fi

if ((DO_MISE)); then
    setup_mise
else
    log "Skipping mise install"
fi

if ((DO_COMPLETIONS)); then
    setup_completions
else
    log "Skipping completions"
fi

if ((DO_SERVICES)); then
    setup_services "$PROFILE"
else
    log "Skipping services"
fi

log "Bootstrap complete."
if ((DRY_RUN == 0 && DO_DOTFILES)); then
    log "Next: ./arch/auth.sh --generate-key  (SSH, personal GitHub, gcloud, Tailscale, BWS, Linear/Jira MCP)"
fi
if ((DRY_RUN == 0 && DO_SHELL)); then
    log "Log out and back in (or start a new shell) to pick up fish and mise."
fi
