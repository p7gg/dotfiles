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

# shellcheck source=arch/lib/common.sh
source "$REPO_ROOT/arch/lib/common.sh"

PROFILE="auto"
DRY_RUN=0
ASSUME_YES=0
NON_INTERACTIVE=0
CHECK_ONLY=0
DO_PACKAGES=1
DO_FONTS=1
DO_OPENCODE=1
DO_DOTFILES=1
DO_MISE=1
DO_SERVICES=1
DO_SHELL=1
DO_COMPLETIONS=1
DO_SYSTEM=1
DO_HOOKS=1
FONT_SELECTION="${FONT_SELECTION:-}"
CHEZMOI_NAME="${CHEZMOI_NAME:-}"
CHEZMOI_EMAIL="${CHEZMOI_EMAIL:-}"
CHEZMOI_WORK_EMAIL="${CHEZMOI_WORK_EMAIL:-}"
ROOT_RUNNER=run_sudo
export ROOT_RUNNER

trap 'on_error' ERR
trap cleanup_tmp EXIT

usage() {
    cat <<'EOF'
Usage: arch/bootstrap.sh [options]

Options:
  --profile native|wsl  Target profile (default: auto-detect)
  --dry-run             Print actions without changing anything
  --check               Validate prerequisites without changing anything
  --yes                 Pass --noconfirm to pacman/paru where supported
  --name NAME           Set the chezmoi name when initializing a new config
  --email EMAIL         Set the chezmoi email when initializing a new config
  --work-email EMAIL    Set the optional work email
  --non-interactive     Fail instead of prompting for missing chezmoi data
  --no-packages         Skip pacman/AUR package installation
  --fonts LIST          Install selected Nerd Fonts without prompting; LIST is
                        all or a comma-separated list of numbers, packages, or
                        display names (implies the fonts step)
  --no-fonts            Skip the optional Nerd Fonts step
  --no-opencode         Skip installing/updating the OpenCode CLI
  --no-dotfiles         Skip chezmoi init/apply
  --no-mise             Skip `mise install`
  --no-completions      Skip fish completion generation
  --no-system           Skip pacman/reflector/timer/firewall/Tailscale setup
  --no-hooks            Skip `lefthook install`
  --no-services         Skip enabling desktop systemd services
  --no-shell            Do not change the login shell to fish
  -h, --help            Show this help

Run this as your normal user. Use `sudo ./arch/wsl-init.sh` for the one-time
WSL root setup.
EOF
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
    run_cmd "${args[@]}" "${pkgs[@]}"
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

    (
        local tmp
        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT

        run_cmd git clone --depth=1 https://aur.archlinux.org/paru.git "$tmp/paru"
        (cd -- "$tmp/paru" && run_cmd makepkg -si)
    )

    hash -r
    command -v paru >/dev/null 2>&1 || die "paru installation did not produce a paru executable"
}

install_packages() {
    local profile="$1"

    validate_package_lists \
        "$REPO_ROOT/arch/packages/base.txt" \
        "$REPO_ROOT/arch/packages/${profile}.txt" \
        "$REPO_ROOT/arch/packages/aur.txt" \
        "$REPO_ROOT/arch/packages/aur-${profile}.txt" ||
        die "fix the invalid package lists before installing"

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

setup_opencode() {
    local install_url="https://opencode.ai/v2/install"
    local opencode_bin="$HOME/.opencode/bin/opencode"
    local version

    if pacman -Q opencode >/dev/null 2>&1; then
        warn "pacman package 'opencode' is still installed; remove it once with: sudo pacman -Rns opencode"
    fi

    if ((DRY_RUN)); then
        log "Would install/update OpenCode from $install_url into $HOME/.opencode/bin"
        log "Would run: curl -fsSL $install_url | bash -s -- --no-modify-path"
        return 0
    fi

    require_cmd curl

    log "Installing/updating OpenCode with the official installer"
    curl -fsSL "$install_url" | bash -s -- --no-modify-path ||
        die "OpenCode installation failed; retry: curl -fsSL $install_url | bash"

    [[ -x "$opencode_bin" ]] ||
        die "OpenCode installer did not create $opencode_bin"

    version="$("$opencode_bin" --version 2>/dev/null | tail -n 1 || true)"
    log "OpenCode installed at $opencode_bin${version:+ ($version)}"
}

setup_fonts() {
    local script="$REPO_ROOT/arch/fonts.sh"
    local -a args=()

    if [[ ! -x "$script" ]]; then
        warn "font script not found or not executable: $script"
        return 0
    fi

    if [[ -n "$FONT_SELECTION" ]]; then
        if [[ "${FONT_SELECTION,,}" == "none" ]]; then
            log "No optional fonts selected"
            return 0
        fi

        if [[ "${FONT_SELECTION,,}" == "all" ]]; then
            args+=(--all)
        else
            args+=(--font "$FONT_SELECTION")
        fi

        if ((DRY_RUN)); then
            if [[ "${FONT_SELECTION,,}" == "all" ]]; then
                log "Would install all optional Nerd Fonts"
            else
                log "Would install selected optional fonts: $FONT_SELECTION"
            fi
            return 0
        fi

        ((ASSUME_YES)) && args+=(--yes)
        log "Installing selected optional fonts"
        run_optional "$script" "${args[@]}" ||
            warn "optional font installation failed; rerun ./arch/fonts.sh with the same selection"
        return 0
    fi

    if ((DRY_RUN)); then
        log "Would prompt for optional Nerd Fonts; available fonts:"
        "$script" --list || warn "could not list optional fonts"
        log "Use --fonts all or --fonts LIST to select fonts non-interactively."
        return 0
    fi

    if ((NON_INTERACTIVE)) || [[ ! -t 0 ]]; then
        log "Skipping optional Nerd Fonts; pass --fonts all|LIST or run ./arch/fonts.sh"
        return 0
    fi

    log "Selecting optional Nerd Fonts"
    run_optional "$script" ||
        warn "optional font installation failed; rerun ./arch/fonts.sh"
}

chezmoi_config_path() {
    printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/chezmoi.toml"
}

toml_quote() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

# Pre-seed chezmoi data so a new machine can be provisioned without a TTY.
# An existing config is never overwritten here.
seed_chezmoi_config() {
    local config name email work_email tmp

    config="$(chezmoi_config_path)"
    [[ -f "$config" ]] && return 0

    name="${CHEZMOI_NAME:-$(git config --global --get user.name 2>/dev/null || true)}"
    email="${CHEZMOI_EMAIL:-$(git config --global --get user.email 2>/dev/null || true)}"
    work_email="${CHEZMOI_WORK_EMAIL:-}"

    if [[ -z "$name" || -z "$email" ]]; then
        if ((NON_INTERACTIVE)); then
            die "non-interactive init needs --name and --email, or git user.name/user.email"
        fi
        return 0
    fi

    if ((DRY_RUN)); then
        log "Would seed chezmoi data in $config"
        return 0
    fi

    mkdir -p "$(dirname "$config")"
    tmp="$(mktemp "${config}.XXXXXX")"
    register_tmp "$tmp"
    {
        printf '[data]\n'
        printf '    name = %s\n' "$(toml_quote "$name")"
        printf '    email = %s\n' "$(toml_quote "$email")"
        printf '    work_email = %s\n' "$(toml_quote "$work_email")"
    } >"$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$config"
    log "Seeded chezmoi data in $config"
}

configure_chezmoi_source() {
    local config backup escaped tmp

    config="$(chezmoi_config_path)"
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

    if grep -qF "sourceDir = \"$escaped\"" "$config" ||
        grep -qF "sourceDir = \"$escaped/home\"" "$config"; then
        log "chezmoi sourceDir already points at $REPO_ROOT"
        return 0
    fi

    backup="${config}.bak.$(date +%Y%m%d%H%M%S)"
    cp -a "$config" "$backup"
    log "Backed up $config to $backup"

    tmp="$(mktemp "${config}.XXXXXX")"
    register_tmp "$tmp"
    {
        printf 'sourceDir = "%s"\n\n' "$escaped"
        grep -vE '^[[:space:]]*sourceDir[[:space:]]*=' "$config" || true
    } >"$tmp"

    if ! chezmoi --config "$tmp" source-path >/dev/null 2>&1; then
        rm -f "$tmp"
        die "generated chezmoi config is invalid; original kept at $config"
    fi

    mv "$tmp" "$config"
    chmod 600 "$config"
    log "Configured chezmoi sourceDir=$REPO_ROOT"
}

apply_dotfiles() {
    if ((DRY_RUN)); then
        log "Would run: chezmoi init --apply --source $REPO_ROOT"
        seed_chezmoi_config
        if command -v chezmoi >/dev/null 2>&1 && [[ -f "$(chezmoi_config_path)" ]]; then
            log "Dotfile preview:"
            chezmoi diff --source "$REPO_ROOT" || warn "chezmoi diff failed"
        else
            log "chezmoi is not initialized yet; the first real run will prompt or use seeded data"
        fi
        return 0
    fi

    require_cmd chezmoi

    seed_chezmoi_config
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
    run_cmd mise install
}

setup_completions() {
    local script="$REPO_ROOT/arch/completions.sh"

    if [[ ! -x "$script" ]]; then
        warn "completion script not found: $script"
        return 0
    fi

    log "Generating fish completions"
    if ! run_optional "$script"; then
        warn "completion generation failed; rerun ./arch/completions.sh after fixing the cause"
    fi
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
            run_optional sudo systemctl start "${svc}.service" ||
                warn "could not start ${svc}.service"
            continue
        fi

        log "Enabling ${svc}.service"
        run_optional sudo systemctl enable --now "${svc}.service" ||
            warn "could not enable ${svc}.service"
    done
}

configure_pacman() {
    local conf="/etc/pacman.conf"
    local failed=0

    if [[ ! -f "$conf" ]]; then
        warn "pacman config not found: $conf"
        return 0
    fi

    if grep -qE '^Color$' "$conf" &&
        grep -qE '^ILoveCandy$' "$conf" &&
        grep -qE '^ParallelDownloads[[:space:]]*=[[:space:]]*5$' "$conf" &&
        grep -qE '^CheckSpace$' "$conf"; then
        log "pacman.conf options already configured"
        return 0
    fi

    backup_file "$conf"

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

    if ((DRY_RUN)); then
        log "Would update pacman.conf options"
        return 0
    fi

    if command -v pacman-conf >/dev/null 2>&1 &&
        ! pacman-conf --config "$conf" >/dev/null 2>&1; then
        if [[ -n "${BACKUP_PATH:-}" && -f "${BACKUP_PATH:-}" ]]; then
            root_run cp -a "$BACKUP_PATH" "$conf"
            warn "restored $conf from $BACKUP_PATH"
        fi
        die "pacman.conf failed validation"
    fi

    grep -qE '^Color$' "$conf" || failed=1
    grep -qE '^ILoveCandy$' "$conf" || failed=1
    grep -qE '^ParallelDownloads[[:space:]]*=[[:space:]]*5$' "$conf" || failed=1
    grep -qE '^CheckSpace$' "$conf" || failed=1

    if ((failed)); then
        if [[ -n "${BACKUP_PATH:-}" && -f "${BACKUP_PATH:-}" ]]; then
            root_run cp -a "$BACKUP_PATH" "$conf"
            warn "restored $conf from $BACKUP_PATH"
        fi
        die "pacman.conf postcondition check failed"
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
        run_optional sudo systemctl start "$timer" || warn "could not start $timer"
        return 0
    fi

    log "Enabling $timer"
    run_optional sudo systemctl enable --now "$timer" || warn "could not enable $timer"
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
        run_optional sudo systemctl start reflector.service || warn "reflector refresh failed"
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

    log "Ensuring ufw default policies and rules"
    # Enforce the policies even when ufw is already enabled. Adding the rules is
    # idempotent, so a pre-existing permissive configuration is corrected too.
    # Add extra allow rules here (or in /etc/ufw) as needed.
    run_sudo ufw default deny incoming
    run_sudo ufw default allow outgoing
    run_sudo ufw allow 22/tcp
    run_optional sudo ufw allow in on tailscale0 ||
        warn "could not add Tailscale interface rule"
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
            run_optional sudo systemctl start tailscaled.service ||
                warn "could not start tailscaled.service"
        else
            log "Enabling tailscaled.service"
            run_optional sudo systemctl enable --now tailscaled.service ||
                warn "could not start tailscaled.service"
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
        cd "$REPO_ROOT" && run_optional lefthook install
    ) || warn "could not install lefthook hooks"
}

check_environment() {
    local status=0

    if [[ $EUID -eq 0 ]]; then
        warn "run this as your normal user, not root"
        status=1
    fi

    if [[ "${ID:-}" != "arch" ]]; then
        warn "this script targets Arch Linux (found: ${ID:-unknown})"
        status=1
    fi

    if ! command -v pacman >/dev/null 2>&1; then
        warn "pacman not found"
        status=1
    fi

    if ((DO_PACKAGES || DO_SYSTEM || DO_SERVICES || DO_SHELL)); then
        if ! command -v sudo >/dev/null 2>&1; then
            warn "sudo not found; required by the enabled package/system/shell steps"
            status=1
        fi
    fi

    if ((DO_DOTFILES)) && ! command -v chezmoi >/dev/null 2>&1; then
        warn "chezmoi not found; required by the dotfiles step"
        status=1
    fi

    if ((DO_MISE)) && ! command -v mise >/dev/null 2>&1; then
        warn "mise not found; required by the toolchain step"
        status=1
    fi

    if ((DO_OPENCODE)); then
        if ! command -v curl >/dev/null 2>&1; then
            warn "curl not found; required by the OpenCode installer"
            status=1
        fi
        if ! command -v tar >/dev/null 2>&1; then
            warn "tar not found; required by the OpenCode installer"
            status=1
        fi
    fi

    if ((DO_HOOKS)) && ! command -v lefthook >/dev/null 2>&1; then
        warn "lefthook not found; Git hooks will be skipped"
    fi

    if ((DO_COMPLETIONS)) && [[ ! -x "$REPO_ROOT/arch/completions.sh" ]]; then
        warn "completion script is not executable: arch/completions.sh"
        status=1
    fi

    if ((DO_PACKAGES)); then
        validate_package_lists \
            "$REPO_ROOT/arch/packages/base.txt" \
            "$REPO_ROOT/arch/packages/${PROFILE}.txt" \
            "$REPO_ROOT/arch/packages/aur.txt" \
            "$REPO_ROOT/arch/packages/aur-${PROFILE}.txt" ||
            status=1
    fi

    if ((DO_FONTS)); then
        if [[ ! -x "$REPO_ROOT/arch/fonts.sh" ]]; then
            warn "font script is not executable: arch/fonts.sh"
            status=1
        fi
        validate_font_catalog "$REPO_ROOT/arch/packages/fonts.txt" || status=1
    fi

    if [[ "$PROFILE" == "native" ]] && is_wsl; then
        warn "native profile selected inside WSL; desktop packages may not be appropriate"
    elif [[ "$PROFILE" == "wsl" ]] && ! is_wsl; then
        warn "wsl profile selected outside WSL"
    fi

    if ((status == 0)); then
        log "Check complete: no blocking issues found."
    else
        warn "Check found blocking issues."
    fi

    return "$status"
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
    --check)
        CHECK_ONLY=1
        shift
        ;;
    --yes)
        ASSUME_YES=1
        shift
        ;;
    --name)
        [[ $# -ge 2 ]] || die "--name requires an argument"
        CHEZMOI_NAME="$2"
        shift 2
        ;;
    --name=*)
        CHEZMOI_NAME="${1#*=}"
        shift
        ;;
    --email)
        [[ $# -ge 2 ]] || die "--email requires an argument"
        CHEZMOI_EMAIL="$2"
        shift 2
        ;;
    --email=*)
        CHEZMOI_EMAIL="${1#*=}"
        shift
        ;;
    --work-email)
        [[ $# -ge 2 ]] || die "--work-email requires an argument"
        CHEZMOI_WORK_EMAIL="$2"
        shift 2
        ;;
    --work-email=*)
        CHEZMOI_WORK_EMAIL="${1#*=}"
        shift
        ;;
    --non-interactive)
        NON_INTERACTIVE=1
        shift
        ;;
    --no-packages)
        DO_PACKAGES=0
        shift
        ;;
    --fonts)
        [[ $# -ge 2 ]] || die "--fonts requires an argument"
        FONT_SELECTION="$2"
        DO_FONTS=1
        shift 2
        ;;
    --fonts=*)
        FONT_SELECTION="${1#*=}"
        DO_FONTS=1
        shift
        ;;
    --no-fonts)
        DO_FONTS=0
        shift
        ;;
    --no-opencode)
        DO_OPENCODE=0
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
    --no-hooks)
        DO_HOOKS=0
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

if [[ "$PROFILE" == "auto" ]]; then
    PROFILE="$(detect_profile)"
fi

case "$PROFILE" in
native | wsl) ;;
*) die "invalid profile: $PROFILE (expected native or wsl)" ;;
esac

if ((CHECK_ONLY)); then
    check_environment
    exit $?
fi

require_cmd pacman

needs_sudo=0
if ((DO_PACKAGES || DO_SERVICES || DO_SHELL || DO_SYSTEM)); then
    needs_sudo=1
fi

if ((DRY_RUN == 0 && needs_sudo)); then
    require_cmd sudo
    log "Requesting sudo access"
    sudo -v || die "sudo access is required for package/service/shell changes"
fi

if [[ "$PROFILE" == "native" ]] && is_wsl; then
    warn "native profile selected inside WSL; desktop packages may not be appropriate"
elif [[ "$PROFILE" == "wsl" ]] && ! is_wsl; then
    warn "wsl profile selected outside WSL"
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
    if ((DO_FONTS)); then
        setup_fonts
    else
        log "Skipping optional fonts"
    fi
else
    log "Skipping packages"
    if ((DO_FONTS)); then
        log "Skipping optional fonts because packages are disabled"
    fi
fi

if ((DO_OPENCODE)); then
    setup_opencode
else
    log "Skipping OpenCode CLI"
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

if ((DO_HOOKS)); then
    setup_hooks
else
    log "Skipping Git hooks"
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

if ((DRY_RUN)); then
    log "Dry run complete; no changes were made."
else
    log "Bootstrap complete."
fi
if ((DRY_RUN == 0 && DO_DOTFILES)); then
    log "Next: ./arch/auth.sh --check  (inspect SSH, GitHub, gcloud, Tailscale, BWS, and MCP state)"
    log "      ./arch/auth.sh --generate-key  (apply missing authentication)"
fi
if ((DRY_RUN == 0 && DO_SHELL)); then
    log "Log out and back in (or start a new shell) to pick up fish and mise."
fi
