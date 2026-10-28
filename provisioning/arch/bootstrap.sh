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

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=provisioning/arch/lib/common.sh
source "$REPO_ROOT/provisioning/arch/lib/common.sh"

PROFILE="auto"
DRY_RUN=0
ASSUME_YES=0
NON_INTERACTIVE=0
CHECK_ONLY=0
ALLOW_PROFILE_MISMATCH=0
DO_PACKAGES=1
DO_FONTS=1
DO_OPENCODE=1
DO_WSL_SSH_AGENT=1
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
OPENCODE_VERSION="${OPENCODE_VERSION:-}"
# Pin the paru build to a reviewed AUR commit instead of executing whatever
# happens to be on master at provisioning time. Bump it deliberately when
# updating paru.
PARU_COMMIT="${PARU_COMMIT:-329be2113c590046cb29858c23d9b96a8d7bd586}"
ROOT_RUNNER=run_sudo
export ROOT_RUNNER

trap 'on_error' ERR
trap cleanup_tmp EXIT

usage() {
    cat <<'EOF'
Usage: provisioning/arch/bootstrap.sh [options]

Options:
  --profile native|wsl  Target profile (default: auto-detect)
  --allow-profile-mismatch
                        Permit an explicit profile that does not match the
                        current environment (native inside WSL or wsl outside
                        WSL); bootstrap otherwise refuses to continue
  --dry-run             Print actions without changing anything
  --check               Validate prerequisites without changing anything
  --yes                 Pass --noconfirm to pacman/paru/makepkg where supported
  --name NAME           Set the chezmoi name when initializing a new config
  --email EMAIL         Set the chezmoi email when initializing a new config
  --work-email EMAIL    Set the optional work email
  --non-interactive     Never prompt (implies --yes); fail if data is missing
  --no-packages         Skip pacman/AUR package installation
  --fonts LIST          Install selected Nerd Fonts without prompting; LIST is
                        all, none, or a comma-separated list of numbers,
                        packages, or display names (implies the fonts step)
  --no-fonts            Skip the optional Nerd Fonts step
  --no-opencode         Skip installing/updating the OpenCode CLI
  --no-wsl-ssh-agent    Skip the Windows SSH agent relay (WSL only)
  --no-dotfiles         Skip chezmoi init/apply
  --no-mise             Skip `mise install`
  --no-completions      Skip fish completion generation
  --no-system           Skip pacman/reflector/timer/firewall/sshd/Tailscale setup
  --no-hooks            Skip `lefthook install`
  --no-services         Skip desktop systemd services and WSL keyring setup
  --no-shell            Do not change the login shell to fish
  -h, --help            Show this help

Environment:
  OPENCODE_VERSION      Pin the OpenCode CLI version (default: latest)
  PARU_COMMIT           AUR paru commit to build (default: reviewed pin)
  BACKUP_RETENTION      Timestamped backups to keep per managed file (default: 3)

Run this as your normal user. Use `sudo ./provisioning/arch/wsl-init.sh` for the one-time
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
    # AUR packages such as lefthook build with Go before dotfiles are applied.
    # Point those builds at the same GOPATH the managed go/env file will set.
    run_cmd env GOPATH="$HOME/.go" "${args[@]}" "${pkgs[@]}"
}

ensure_paru() {
    local profile="$1"
    local file
    local has_aur=0

    command -v paru >/dev/null 2>&1 && return 0

    for file in "$REPO_ROOT/provisioning/arch/packages/aur.txt" "$REPO_ROOT/provisioning/arch/packages/aur-${profile}.txt"; do
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

    [[ "$PARU_COMMIT" =~ ^[0-9a-f]{40}$ ]] ||
        die "PARU_COMMIT must be a 40-character lowercase Git commit"

    log "Bootstrapping paru from the AUR at pinned commit $PARU_COMMIT"
    if ((DRY_RUN)); then
        log "Would clone https://aur.archlinux.org/paru.git, check out $PARU_COMMIT, and run makepkg -si"
        return 0
    fi

    (
        local tmp
        local -a makepkg_args=(makepkg -si)
        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT

        ((ASSUME_YES)) && makepkg_args+=(--noconfirm)
        run_cmd git clone https://aur.archlinux.org/paru.git "$tmp/paru"
        run_cmd git -C "$tmp/paru" checkout --detach "$PARU_COMMIT"
        (cd -- "$tmp/paru" && run_cmd "${makepkg_args[@]}")
    )

    hash -r
    command -v paru >/dev/null 2>&1 || die "paru installation did not produce a paru executable"
}

install_packages() {
    local profile="$1"

    validate_package_lists \
        "$REPO_ROOT/provisioning/arch/packages/base.txt" \
        "$REPO_ROOT/provisioning/arch/packages/${profile}.txt" \
        "$REPO_ROOT/provisioning/arch/packages/aur.txt" \
        "$REPO_ROOT/provisioning/arch/packages/aur-${profile}.txt" ||
        die "fix the invalid package lists before installing"

    ensure_keyring

    log "Updating the system before installing packages"
    if ((ASSUME_YES)); then
        run_sudo pacman -Syu --noconfirm
    else
        run_sudo pacman -Syu
    fi

    pacman_install_file "$REPO_ROOT/provisioning/arch/packages/base.txt"
    pacman_install_file "$REPO_ROOT/provisioning/arch/packages/${profile}.txt"

    ensure_paru "$profile"
    paru_install_file "$REPO_ROOT/provisioning/arch/packages/aur.txt"
    paru_install_file "$REPO_ROOT/provisioning/arch/packages/aur-${profile}.txt"
}

opencode_target() {
    local os="$1"
    local arch="$2"
    local target

    [[ "$os" == "Linux" ]] || return 1

    case "$arch" in
    x86_64 | amd64)
        target="linux-x64"
        if ! grep -qwi avx2 /proc/cpuinfo 2>/dev/null; then
            target="${target}-baseline"
        fi
        ;;
    aarch64 | arm64)
        target="linux-arm64"
        ;;
    *)
        return 1
        ;;
    esac

    if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
        target="${target}-musl"
    fi

    printf '%s\n' "$target"
}

json_string_field() {
    local json="$1"
    local field="$2"

    sed -n "s/.*\"${field}\":\"\([^\"]*\)\".*/\1/p" <<<"$json" | head -n 1
}

# Fetch over HTTPS only, including redirects, so a downgrade to plain HTTP is
# rejected before any download is trusted.
curl_https() {
    curl -fsSL --proto '=https' --tlsv1.2 "$@"
}

fetch_opencode_package() {
    local scope="$1"
    local target="$2"
    local version="$3"
    local package url

    package="${scope}/cli-${target}"
    url="https://registry.npmjs.org/${package//\//%2f}/${version}"
    if curl_https "$url" 2>/dev/null; then
        return 0
    fi

    # Older releases used the @opencode-ai scope. Keep the same fallback the
    # official installer uses for a pinned pre-rename version.
    package="@opencode-ai/cli-${target}"
    url="https://registry.npmjs.org/${package//\//%2f}/${version}"
    curl_https "$url"
}

setup_opencode() {
    local opencode_bin="$HOME/.opencode/bin/opencode"
    local latest_metadata package_name package_scope metadata version target
    local tarball integrity download_tmp installed_version

    if pacman -Q opencode >/dev/null 2>&1; then
        warn "pacman package 'opencode' is still installed; remove it once with: sudo pacman -Rns opencode"
    fi

    target="$(opencode_target "$(uname -s)" "$(uname -m)")" ||
        die "OpenCode does not publish a Linux package for $(uname -s)/$(uname -m)"

    if ((DRY_RUN)); then
        version="${OPENCODE_VERSION:-latest}"
        log "Would install/update OpenCode ${version} from the npm tarball into $HOME/.opencode/bin"
        log "Would verify the tarball's sha512 integrity before installing"
        return 0
    fi

    require_cmd curl
    require_cmd tar
    require_cmd sha512sum
    require_cmd base64
    require_cmd od

    latest_metadata="$(curl_https https://opencode.ai/update/api/latest/cli/npm)" ||
        die "could not read the OpenCode release metadata; skip with --no-opencode"
    package_name="$(json_string_field "$latest_metadata" package)"
    package_scope="${package_name%/cli}"
    version="${OPENCODE_VERSION:-$(json_string_field "$latest_metadata" version)}"
    version="${version#v}"

    [[ "$package_name" =~ ^@[A-Za-z0-9._-]+/cli$ ]] ||
        die "unexpected OpenCode package metadata: ${package_name:-<missing>}"
    [[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] ||
        die "unexpected OpenCode version: ${version:-<missing>}"

    log "Installing/updating OpenCode ${version} from the verified npm tarball"
    metadata="$(fetch_opencode_package "$package_scope" "$target" "$version")" ||
        die "OpenCode ${version} is not available for ${target}; skip with --no-opencode"
    tarball="$(json_string_field "$metadata" tarball)"
    integrity="$(json_string_field "$metadata" integrity)"

    [[ "$tarball" == https://registry.npmjs.org/* ]] ||
        die "unexpected OpenCode tarball URL: ${tarball:-<missing>}"
    [[ -n "$integrity" ]] ||
        die "OpenCode registry metadata has no sha512 checksum; skip with --no-opencode"

    download_tmp="$(mktemp -d)"
    register_tmp_dir "$download_tmp"

    curl_https -o "$download_tmp/opencode.tgz" "$tarball" ||
        die "could not download the OpenCode tarball"
    verify_sha512_integrity "$download_tmp/opencode.tgz" "$integrity" ||
        die "OpenCode tarball checksum verification failed"
    tar -xzf "$download_tmp/opencode.tgz" -C "$download_tmp"
    [[ -f "$download_tmp/package/bin/opencode" ]] ||
        die "OpenCode tarball did not contain package/bin/opencode"

    install -Dm755 "$download_tmp/package/bin/opencode" "$opencode_bin"

    [[ -x "$opencode_bin" ]] ||
        die "OpenCode installation did not create $opencode_bin"

    installed_version="$("$opencode_bin" --version 2>/dev/null | tail -n 1 || true)"
    log "OpenCode installed at $opencode_bin${installed_version:+ ($installed_version)}"
}

find_wsl_npiperelay() {
    local candidate winprofile

    if [[ -n "${NPIPERELAY:-}" && -x "${NPIPERELAY:-}" ]]; then
        printf '%s\n' "$NPIPERELAY"
        return 0
    fi

    if command -v npiperelay.exe >/dev/null 2>&1; then
        command -v npiperelay.exe
        return 0
    fi

    if command -v cmd.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
        winprofile="$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r\n')"
        if [[ -n "$winprofile" ]]; then
            winprofile="$(wslpath -u "$winprofile" 2>/dev/null || true)"
            candidate="${winprofile}/bin/npiperelay.exe"
            if [[ -x "$candidate" ]]; then
                printf '%s\n' "$candidate"
                return 0
            fi
        fi
    fi

    for candidate in /mnt/c/Users/*/AppData/Local/Microsoft/WinGet/Packages/albertony.npiperelay_*/npiperelay.exe; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

check_wsl_ssh_agent_prereqs() {
    local npiperelay

    if [[ "$PROFILE" != "wsl" ]]; then
        log "Skipping the Windows SSH agent relay for profile $PROFILE"
        return 0
    fi

    if ! command -v socat >/dev/null 2>&1; then
        warn "socat is not installed; the SSH agent relay will not start"
        return 0
    fi

    if ! npiperelay="$(find_wsl_npiperelay)"; then
        warn "npiperelay.exe was not found on the Windows side"
        warn "  install it from PowerShell: winget install --id albertony.npiperelay -e"
        return 0
    fi

    log "Windows SSH agent relay prerequisites are present: socat, $npiperelay"
    log "The Windows Bitwarden SSH agent must be enabled and own the openssh-ssh-agent pipe"
}

setup_fonts() {
    local script="$REPO_ROOT/provisioning/arch/tools/fonts.sh"
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
            warn "optional font installation failed; rerun ./provisioning/arch/tools/fonts.sh with the same selection"
        return 0
    fi

    if ((DRY_RUN)); then
        log "Would prompt for optional Nerd Fonts; available fonts:"
        "$script" --list || warn "could not list optional fonts"
        log "Use --fonts all or --fonts LIST to select fonts non-interactively."
        return 0
    fi

    if ((NON_INTERACTIVE)) || [[ ! -t 0 ]]; then
        log "Skipping optional Nerd Fonts; pass --fonts all|LIST or run ./provisioning/arch/tools/fonts.sh"
        return 0
    fi

    log "Selecting optional Nerd Fonts"
    run_optional "$script" ||
        warn "optional font installation failed; rerun ./provisioning/arch/tools/fonts.sh"
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
    local config name email work_email tmp value

    config="$(chezmoi_config_path)"
    [[ -f "$config" ]] && return 0

    name="${CHEZMOI_NAME:-$(git config --global --get user.name 2>/dev/null || true)}"
    email="${CHEZMOI_EMAIL:-$(git config --global --get user.email 2>/dev/null || true)}"
    work_email="${CHEZMOI_WORK_EMAIL:-}"

    for value in "$name" "$email" "$work_email"; do
        [[ "$value" != *[[:cntrl:]]* ]] ||
            die "chezmoi data must not contain control characters"
    done

    if [[ -z "$name" || -z "$email" ]]; then
        if ((DRY_RUN)); then
            log "Would prompt for missing chezmoi data (or require --name and --email)"
            return 0
        fi
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
    local config backup escaped tmp actual expected

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

    expected="$(cd -- "$REPO_ROOT/home" && pwd -P)"
    actual="$(chezmoi --config "$config" source-path 2>/dev/null || true)"

    if [[ "$actual" == "$expected" ]]; then
        log "chezmoi sourceDir already points at $expected"
        chmod 600 "$config"
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

    local -a chezmoi_args=(init --apply --source "$REPO_ROOT")
    ((NON_INTERACTIVE)) && chezmoi_args=(--no-tty "${chezmoi_args[@]}")

    log "Applying dotfiles with chezmoi"
    chezmoi "${chezmoi_args[@]}"
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

    local -a args=(mise install)
    ((ASSUME_YES)) && args+=(-y)

    log "Installing mise toolchains"
    run_cmd "${args[@]}"
}

setup_completions() {
    local script="$REPO_ROOT/provisioning/arch/tools/completions.sh"

    if [[ ! -x "$script" ]]; then
        warn "completion script not found: $script"
        return 0
    fi

    log "Generating fish completions"
    if ! run_optional "$script"; then
        warn "completion generation failed; rerun ./provisioning/arch/tools/completions.sh after fixing the cause"
    fi
}

ensure_systemd_unit() {
    local unit="$1"
    local active=0 enabled=0

    systemctl is-active --quiet "$unit" 2>/dev/null && active=1
    systemctl is-enabled --quiet "$unit" 2>/dev/null && enabled=1

    if ((enabled == 0)); then
        log "Enabling $unit"
        run_optional sudo systemctl enable "$unit" || warn "could not enable $unit"
    fi

    if ((active == 0)); then
        log "Starting $unit"
        run_optional sudo systemctl start "$unit" || warn "could not start $unit"
    elif ((enabled)); then
        log "$unit is enabled and active"
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

        ensure_systemd_unit "${svc}.service"
    done
}

enable_wsl_ssh_agent_service() {
    local unit="ssh-agent-bridge.service"
    local unit_file="$HOME/.config/systemd/user/$unit"
    local socket="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh-agent.sock"

    [[ "$PROFILE" == "wsl" ]] || return 0
    ((DO_WSL_SSH_AGENT)) || return 0

    if ! command -v socat >/dev/null 2>&1; then
        warn "socat is not installed; skipping $unit"
        return 0
    fi

    if ! find_wsl_npiperelay >/dev/null 2>&1; then
        warn "npiperelay.exe is not installed; skipping $unit"
        warn "  install it from PowerShell: winget install --id albertony.npiperelay -e"
        return 0
    fi

    if ((DRY_RUN)); then
        log "Would enable and start $unit"
        return 0
    fi

    if [[ ! -f "$unit_file" ]]; then
        warn "systemd user unit not found: $unit_file; apply dotfiles first"
        return 0
    fi

    if [[ ! -d /run/systemd/system ]] ||
        ! systemctl --user show-environment >/dev/null 2>&1; then
        warn "no systemd user manager; the Windows SSH agent relay will not start automatically"
        return 0
    fi

    if command -v powershell.exe >/dev/null 2>&1; then
        if powershell.exe -NoProfile -NonInteractive -Command \
            "(Get-Service ssh-agent -ErrorAction SilentlyContinue).Status" \
            2>/dev/null | grep -qi running; then
            warn "Windows OpenSSH agent is running; skipping $unit"
            warn "  disable it so Bitwarden can own the pipe:"
            warn "  Set-Service ssh-agent -StartupType Disabled; Stop-Service ssh-agent"
            return 0
        fi
    fi

    if ! systemctl --user enable --now "$unit" >/dev/null 2>&1; then
        warn "could not enable $unit; check: systemctl --user status $unit"
        return 0
    fi

    # The relay is now the only agent on WSL; stop the stock agent so a second
    # empty agent cannot shadow it.
    if systemctl --user is-enabled --quiet ssh-agent.socket 2>/dev/null; then
        systemctl --user disable --now ssh-agent.socket >/dev/null 2>&1 ||
            warn "could not disable the unused ssh-agent.socket"
    fi
    systemctl --user stop ssh-agent.service >/dev/null 2>&1 || true

    log "Windows SSH agent relay is active at $socket"
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
    local src="$REPO_ROOT/provisioning/arch/system/reflector.conf"
    local dest="/etc/xdg/reflector/reflector.conf"

    if [[ ! -f "$src" ]]; then
        warn "reflector config not found: $src"
        return 0
    fi

    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
        log "Reflector config already up to date"
        return 0
    fi

    log "Installing Brazil-prioritized reflector config"
    run_sudo install -Dm644 "$src" "$dest"
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

    ensure_systemd_unit "$timer"
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

setup_sshd() {
    local profile="$1"

    if ! command -v sshd >/dev/null 2>&1; then
        warn "sshd is not installed; skipping SSH server setup"
        return 0
    fi

    if [[ ! -d /run/systemd/system ]]; then
        warn "systemd is not running; cannot enable sshd"
        if [[ "$profile" == "wsl" ]] || is_wsl; then
            warn "  rerun provisioning/arch/wsl-init.sh --systemd to manage sshd.service"
        fi
        return 0
    fi

    ensure_systemd_unit sshd.service

    if [[ "$profile" == "wsl" ]]; then
        log "WSL: sshd listens inside the distro; external SSH needs mirrored"
        log "networking or a Windows port proxy for port 22."
    fi
}

sshd_hardening_effective() {
    local effective

    effective="$(sudo sshd -T 2>/dev/null)" || return 1
    grep -qx 'passwordauthentication no' <<<"$effective" &&
        grep -qx 'kbdinteractiveauthentication no' <<<"$effective" &&
        grep -qx 'permitrootlogin no' <<<"$effective" &&
        grep -qx 'pubkeyauthentication yes' <<<"$effective"
}

setup_sshd_hardening() {
    local src="$REPO_ROOT/provisioning/arch/system/sshd-hardening.conf"
    local dest="/etc/ssh/sshd_config.d/10-hardening.conf"
    local backup=""

    if ! command -v sshd >/dev/null 2>&1; then
        log "sshd is not installed; skipping key-only hardening"
        return 0
    fi

    if [[ ! -f "$src" ]]; then
        warn "sshd hardening config not found: $src"
        return 0
    fi

    # Key-only auth would lock out a host without a usable public key, so leave
    # password auth alone until an authorized key is in place.
    if ! has_authorized_key "${HOME:-}/.ssh/authorized_keys"; then
        warn "no usable key in ${HOME:-~}/.ssh/authorized_keys; skipping key-only hardening"
        warn "  add one to home/private_dot_ssh/private_authorized_keys or run ssh-copy-id"
        return 0
    fi

    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
        if ((DRY_RUN)); then
            log "Would verify the effective sshd hardening"
        elif sshd_hardening_effective; then
            log "sshd key-only hardening is up to date"
        else
            warn "sshd hardening file exists but is not effective; check other sshd_config.d files"
        fi
        return 0
    fi

    log "Installing sshd key-only hardening"

    if ((DRY_RUN)); then
        run_sudo install -Dm644 "$src" "$dest"
        log "Would validate with sshd -t, verify with sshd -T, and reload sshd.service"
        return 0
    fi

    if [[ -f "$dest" ]]; then
        backup="$(mktemp)"
        if ! sudo install -m 600 -o "$(id -u)" -g "$(id -g)" "$dest" "$backup"; then
            warn "could not back up $dest; leaving sshd config unchanged"
            rm -f "$backup"
            return 0
        fi
    fi

    if ! sudo install -Dm644 "$src" "$dest"; then
        warn "could not install $dest; leaving sshd config unchanged"
        rm -f "$backup"
        return 0
    fi

    if ! sudo sshd -t; then
        warn "sshd rejected the hardening config; restoring the previous one"
        if [[ -n "$backup" ]]; then
            run_optional sudo install -Dm644 "$backup" "$dest" ||
                warn "could not restore $dest"
        else
            run_optional sudo rm -f "$dest" ||
                warn "could not remove $dest"
        fi
        rm -f "$backup"
        return 0
    fi

    if ! sshd_hardening_effective; then
        warn "sshd accepts the config but the effective settings differ; restoring the previous one"
        if [[ -n "$backup" ]]; then
            run_optional sudo install -Dm644 "$backup" "$dest" ||
                warn "could not restore $dest"
        else
            run_optional sudo rm -f "$dest" ||
                warn "could not remove $dest"
        fi
        rm -f "$backup"
        return 0
    fi

    rm -f "$backup"

    if systemctl is-active --quiet sshd.service 2>/dev/null; then
        run_optional sudo systemctl reload sshd.service ||
            warn "could not reload sshd.service"
    else
        log "sshd.service is not running; hardening applies on next start"
    fi
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

        ensure_systemd_unit tailscaled.service
        return 0
    fi

    if [[ "$profile" == "wsl" ]] || is_wsl; then
        warn "WSL has no systemd here; start Tailscale manually with:"
        warn "  sudo tailscaled >/tmp/tailscaled.log 2>&1 &"
        warn "  sudo tailscale up"
        warn "Alternatively, rerun provisioning/arch/wsl-init.sh --systemd and restart WSL."
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

    if ((DO_SYSTEM)) && command -v sshd >/dev/null 2>&1; then
        if ((DO_DOTFILES)) &&
            has_authorized_key "$REPO_ROOT/home/private_dot_ssh/private_authorized_keys"; then
            :
        elif ! has_authorized_key "${HOME:-}/.ssh/authorized_keys"; then
            warn "no SSH authorized keys; sshd key-only hardening will be skipped"
        fi
    fi

    if ((DO_DOTFILES)) && ! command -v chezmoi >/dev/null 2>&1; then
        if ((DO_PACKAGES)); then
            warn "chezmoi not found; the package step will install it"
        else
            warn "chezmoi not found; required by the dotfiles step"
            status=1
        fi
    fi

    if ((DO_MISE)) && ! command -v mise >/dev/null 2>&1; then
        if ((DO_PACKAGES)); then
            warn "mise not found; the package step will install it"
        else
            warn "mise not found; required by the toolchain step"
            status=1
        fi
    fi

    if ((DO_SHELL)) && ! command -v fish >/dev/null 2>&1; then
        if ((DO_PACKAGES)); then
            warn "fish not found; the package step will install it"
        else
            warn "fish not found; required by the login-shell step"
            status=1
        fi
    fi

    if ((DO_OPENCODE)); then
        if ! command -v curl >/dev/null 2>&1; then
            if ((DO_PACKAGES)); then
                warn "curl not found; the package step will install it"
            else
                warn "curl not found; required by the OpenCode download"
                status=1
            fi
        fi
        for cmd in tar sha512sum base64 od; do
            if ! command -v "$cmd" >/dev/null 2>&1; then
                warn "$cmd not found; required by the verified OpenCode install (part of the base system)"
                status=1
            fi
        done
    fi

    if ((DO_WSL_SSH_AGENT)) && [[ "$PROFILE" == "wsl" ]]; then
        if ! command -v socat >/dev/null 2>&1; then
            if ((DO_PACKAGES)); then
                warn "socat not found; the package step will install it"
            else
                warn "socat not found; required by the SSH agent relay"
                status=1
            fi
        fi
        if ! find_wsl_npiperelay >/dev/null 2>&1; then
            warn "npiperelay.exe not found; install it from PowerShell: winget install --id albertony.npiperelay -e"
            status=1
        fi
    fi

    if ((DO_HOOKS)) && ! command -v lefthook >/dev/null 2>&1; then
        warn "lefthook not found; Git hooks will be skipped"
    fi

    if ((DO_COMPLETIONS)) && [[ ! -x "$REPO_ROOT/provisioning/arch/tools/completions.sh" ]]; then
        warn "completion script is not executable: provisioning/arch/tools/completions.sh"
        status=1
    fi

    if ((DO_PACKAGES)); then
        validate_package_lists \
            "$REPO_ROOT/provisioning/arch/packages/base.txt" \
            "$REPO_ROOT/provisioning/arch/packages/${PROFILE}.txt" \
            "$REPO_ROOT/provisioning/arch/packages/aur.txt" \
            "$REPO_ROOT/provisioning/arch/packages/aur-${PROFILE}.txt" ||
            status=1
    fi

    if ((DO_FONTS)); then
        if [[ ! -x "$REPO_ROOT/provisioning/arch/tools/fonts.sh" ]]; then
            warn "font script is not executable: provisioning/arch/tools/fonts.sh"
            status=1
        fi
        validate_font_catalog "$REPO_ROOT/provisioning/arch/packages/fonts.txt" || status=1
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
    --allow-profile-mismatch)
        ALLOW_PROFILE_MISMATCH=1
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
    --no-wsl-ssh-agent)
        DO_WSL_SSH_AGENT=0
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

# Unattended provisioning must not stop at a pacman/paru confirmation prompt.
if ((NON_INTERACTIVE)); then
    ASSUME_YES=1
fi

if [[ "$PROFILE" == "auto" ]]; then
    PROFILE="$(detect_profile)"
fi

case "$PROFILE" in
native | wsl) ;;
*) die "invalid profile: $PROFILE (expected native or wsl)" ;;
esac

if mismatch_reason="$(profile_mismatch "$PROFILE")"; then
    if ((ALLOW_PROFILE_MISMATCH)); then
        warn "$mismatch_reason; continuing because --allow-profile-mismatch was passed"
    else
        die "$mismatch_reason; refusing to install packages for the wrong profile (pass --allow-profile-mismatch only for intentional cross-profile work)"
    fi
fi

[[ $EUID -ne 0 ]] || die "do not run this script as root; run it as your user"

# shellcheck source=/dev/null
[[ -r /etc/os-release ]] && source /etc/os-release
[[ "${ID:-}" == "arch" ]] || die "this script targets Arch Linux (found: ${ID:-unknown})"

if ((CHECK_ONLY)); then
    if check_environment; then
        exit 0
    else
        exit 1
    fi
fi

require_cmd pacman

needs_sudo=0
if ((DO_PACKAGES || DO_SERVICES || DO_SHELL || DO_SYSTEM)); then
    needs_sudo=1
fi

if ((DRY_RUN == 0 && needs_sudo)); then
    require_cmd sudo
    log "Requesting sudo access"
    if ((NON_INTERACTIVE)); then
        sudo -n -v || die "sudo credentials are required; run 'sudo -v' first or run interactively"
    else
        sudo -v || die "sudo access is required for package/service/shell changes"
    fi
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

if ((DO_WSL_SSH_AGENT)); then
    check_wsl_ssh_agent_prereqs
else
    log "Skipping the Windows SSH agent relay"
fi

if ((DO_SYSTEM)); then
    configure_reflector
    setup_timers "$PROFILE"
    setup_firewall "$PROFILE"
    setup_sshd "$PROFILE"
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
    enable_wsl_ssh_agent_service
fi

# Run after dotfiles so a managed ~/.ssh/authorized_keys exists before password
# auth is disabled.
if ((DO_SYSTEM)); then
    setup_sshd_hardening
else
    log "Skipping sshd hardening"
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
    if ! ensure_login_keyring; then
        warn "GNOME Keyring is not ready; run ./provisioning/arch/auth.sh"
    fi
else
    log "Skipping services"
fi

if ((DRY_RUN)); then
    log "Dry run complete; no changes were made."
else
    log "Bootstrap complete."
fi
if ((DRY_RUN == 0 && DO_DOTFILES)); then
    log "Next: ./provisioning/arch/auth.sh --check  (inspect SSH, GitHub, gcloud, Tailscale, BWS, and MCP state)"
    log "      ./provisioning/arch/auth.sh --generate-key  (apply missing authentication)"
fi
if ((DRY_RUN == 0 && DO_SHELL)); then
    log "Log out and back in (or start a new shell) to pick up fish and mise."
fi
