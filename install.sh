#!/usr/bin/env bash
set -euo pipefail

# Usage: ./install.sh [phase ...]   (default: all phases)
#   Phases: system link tools extras config auth
#   Example: ./install.sh link config        # only re-link + re-configure
# Env skips: SKIP_TAILSCALE=1 SKIP_AUTH=1 SKIP_MISE_TOOLS=1 SKIP_EXTRAS=1

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="${HOME}/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
SKIP_TAILSCALE="${SKIP_TAILSCALE:-0}"
SKIP_AUTH="${SKIP_AUTH:-0}"
SKIP_MISE_TOOLS="${SKIP_MISE_TOOLS:-0}"
SKIP_EXTRAS="${SKIP_EXTRAS:-0}"

info()  { printf "\033[1;34m➜\033[0m %s\n" "$1"; }
ok()    { printf "\033[1;32m✓\033[0m %s\n" "$1"; }
warn()  { printf "\033[1;33m⚠\033[0m %s\n" "$1"; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

# Prompt a yes/no question (default: No). Returns 0 for yes, 1 for no.
# Usage: if ask_yes_no "Install foo?"; then ...; fi
ask_yes_no() {
    local prompt="$1" answer
    printf "%s [y/N] " "$prompt" >&2
    read -r answer </dev/tty || return 1
    case "$answer" in
        [Yy]|[Yy][Ee][Ss]) return 0 ;;
        *) return 1 ;;
    esac
}

# ── Symlink helpers ──────────────────────────────────────────────────────

link_file() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        # -m canonicalises without requiring existence; 2>/dev/null covers
        # regular files, where readlink would otherwise fail.
        if [ "$(readlink -m "$dst" 2>/dev/null)" = "$(readlink -m "$src")" ]; then
            ok "exists: ${dst#$HOME/}"
            return
        fi
        mkdir -p "$BACKUP_DIR"
        mv "$dst" "$BACKUP_DIR/"
        warn "backed up: ${dst#$HOME/}"
    fi
    ln -sf "$src" "$dst"
    ok "linked:  ${dst#$HOME/}"
}

link_dir() {
    local src="$1" dst="$2"
    if [ -d "$dst" ] && [ ! -L "$dst" ]; then
        mkdir -p "$BACKUP_DIR"
        mv "$dst" "$BACKUP_DIR/"
        warn "backed up: ${dst#$HOME/}"
    fi
    link_file "$src" "$dst"
}

# ── Phase: system (distro prerequisites + AUR helper + tailscale) ───────

phase_system() {
    # Arch: everything the dotfiles and mise builds need, before any setup.
    if has_cmd pacman; then
        info "installing pacman prerequisites..."

        # nano = $EDITOR in .zshenv; xdg-utils = desktop integration; pacman-contrib = rankmirrors/checkupdates
        # git-lfs = required by .gitconfig [filter "lfs"]; difftastic (difft) = used by `git dlog` alias
        local pkgs=(zsh git git-lfs curl openssl lsof unzip xz base-devel nano xdg-utils pacman-contrib difftastic)
        local missing=()
        local p
        for p in "${pkgs[@]}"; do
            pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p")
        done

        if [ ${#missing[@]} -gt 0 ]; then
            sudo pacman -S --needed --noconfirm "${missing[@]}"
        else
            ok "all pacman prerequisites present"
        fi

        # AUR helper (builds from source — needs the base-devel/git just installed)
        if has_cmd yay; then
            ok "yay already installed"
        else
            info "installing yay (AUR helper)..."
            local build_dir
            build_dir="$(mktemp -d)"
            trap 'rm -rf "$build_dir"' EXIT
            git clone https://aur.archlinux.org/yay.git "$build_dir/yay"
            (cd "$build_dir/yay" && makepkg -si --noconfirm)
            rm -rf "$build_dir"
            trap - EXIT
            ok "yay installed"
        fi
    fi

    install_tailscale
}

# Tailscale: runs on any distro (called from system phase).
# Arch → official repo package, AUR prebuilt binary as fallback.
# Other distros → upstream installer (supports apt/yum/zypper-based systems).
install_tailscale() {
    if [ "$SKIP_TAILSCALE" = "1" ]; then
        info "skipping tailscale (SKIP_TAILSCALE=1)"
        return
    fi
    if has_cmd tailscale; then
        ok "tailscale already installed"
    elif has_cmd pacman; then
        info "installing tailscale..."
        if pacman -Si tailscale >/dev/null 2>&1; then
            sudo pacman -S --needed --noconfirm tailscale
        else
            has_cmd yay || { warn "yay required for tailscale-bin — skipping"; return; }
            yay -S --needed --noconfirm tailscale-bin
        fi
        ok "tailscale installed"
    elif has_cmd curl; then
        info "installing tailscale (upstream installer)..."
        curl -fsSL https://tailscale.com/install.sh | sh \
            || { warn "tailscale installer failed — see https://tailscale.com/docs/install/linux"; return; }
        ok "tailscale installed"
    else
        warn "curl not found — cannot install tailscale, see https://tailscale.com/docs/install/linux"
        return
    fi

    # tailscaled must be running before `tailscale up` (auth phase) can work.
    if has_cmd tailscale && has_cmd systemctl; then
        if systemctl is-active --quiet tailscaled 2>/dev/null; then
            ok "tailscaled already running"
        else
            info "enabling tailscaled..."
            sudo systemctl enable --now tailscaled || warn "could not start tailscaled — run: sudo systemctl enable --now tailscaled"
        fi
    fi
}

# ── Phase: link dotfiles ─────────────────────────────────────────────────

phase_link() {
    info "symlinking dotfiles..."

    link_file "${DOTFILES}/.zshrc"       "${HOME}/.zshrc"
    link_file "${DOTFILES}/.zshenv"      "${HOME}/.zshenv"
    link_file "${DOTFILES}/.gitconfig"   "${HOME}/.gitconfig"
    link_file "${DOTFILES}/.gitignore"   "${HOME}/.gitignore"
    link_file "${DOTFILES}/starship.toml" "${HOME}/.config/starship.toml"
    link_file "${DOTFILES}/.config/mise/config.toml" "${HOME}/.config/mise/config.toml"
    link_dir  "${DOTFILES}/.zsh"         "${HOME}/.zsh"
    link_dir  "${DOTFILES}/.agents"      "${HOME}/.agents"
    link_dir  "${DOTFILES}/.config/opencode" "${HOME}/.config/opencode"

    # NOTE: the repo .gitconfig uses `helper = !gh auth git-credential`
    # (PATH-resolved, no hardcoded home dir) and sets
    # core.excludesFile = ~/.gitignore, so no post-link sed patching needed.
    # Generated files under symlinked dirs (e.g. .zsh/completions/_mise)
    # are covered by scoped .gitignore files in the repo — never sed through
    # a symlink, it would mutate the repo source.

    # Personal scripts → ~/.local/bin
    mkdir -p "${HOME}/.local/bin"
    shopt -s nullglob
    for script in "${DOTFILES}"/bin/*; do
        [ -f "$script" ] && link_file "$script" "${HOME}/.local/bin/$(basename "$script")"
    done
    shopt -u nullglob
}

# ── Phase: system dependencies (mise, opencode, tools) ───────────────────

phase_tools() {
    info "checking system prerequisites..."

    local missing=()
    has_cmd zsh  || missing+=(zsh)
    has_cmd git  || missing+=(git)
    has_cmd curl || missing+=(curl)

    if [ ${#missing[@]} -gt 0 ]; then
        warn "install missing packages: ${missing[*]}"
        if has_cmd apt-get; then
            sudo apt-get update || true
            sudo apt-get install -y "${missing[@]}"
        elif has_cmd dnf; then
            sudo dnf install -y "${missing[@]}"
        elif has_cmd brew; then
            brew install "${missing[@]}"
        elif has_cmd pacman; then
            sudo pacman -S --needed --noconfirm "${missing[@]}"
        else
            warn "unsupported package manager — install manually: ${missing[*]}"
        fi
    fi
    ok "prerequisites satisfied"

    if ! has_cmd mise; then
        info "installing mise..."
        curl -fsSL https://mise.run | sh
        export PATH="${HOME}/.local/bin:${PATH}"
    else
        ok "mise already installed"
    fi
    # mise shims (gh, codex, cmdc, …) for the rest of this script.
    export PATH="${HOME}/.local/share/mise/shims:${PATH}"

    if ! has_cmd opencode; then
        info "installing opencode..."
        curl -fsSL https://opencode.ai/install | bash
        export PATH="${HOME}/.opencode/bin:${PATH}"
    else
        ok "opencode already installed"
    fi

    if [ "$SKIP_MISE_TOOLS" = "1" ]; then
        info "skipping mise tools (SKIP_MISE_TOOLS=1)"
        return
    fi
    info "installing mise tools (this will take a while)..."
    # Run from $HOME so mise resolves the symlinked global config
    # (~/.config/mise/config.toml) regardless of the caller's CWD.
    (cd "$HOME" && mise trust >/dev/null 2>&1 || true; mise install --yes)
    ok "mise tools installed"
}

# ── Phase: optional extra packages (interactive, Arch/AUR only) ─────────

phase_extras() {
    if [ "$SKIP_EXTRAS" = "1" ]; then
        info "skipping extras (SKIP_EXTRAS=1)"
        return
    fi
    if ! has_cmd pacman; then
        info "skipping extras (not an Arch system — AUR packages unavailable)"
        return
    fi
    if ! has_cmd yay; then
        warn "skipping extras (yay not found — run system phase first)"
        return
    fi
    if [ ! -t 0 ]; then
        warn "non-interactive shell — skipping extras, install manually:"
        warn "  yay -S --needed t3code-nightly-bin brave-bin visual-studio-code-bin"
        warn "  yay -S --needed ttf-cascadia-code-nerd ttf-cascadia-mono-nerd ttf-firacode-nerd otf-firamono-nerd otf-geist-mono-nerd ttf-hack-nerd otf-hasklig-nerd ttf-ibmplex-mono-nerd ttf-jetbrains-mono-nerd ttf-meslo-nerd otf-monaspace-nerd ttf-noto-nerd ttf-roboto-mono-nerd ttf-sourcecodepro-nerd ttf-space-mono-nerd ttf-ubuntu-nerd ttf-ubuntu-mono-nerd ttf-zed-mono-nerd"
        warn "  or rerun: ./install.sh extras"
        return
    fi
    info "optional extras (already-installed packages are skipped)..."

    # format: "pkg|Human-readable label"
    local extras=(
        "t3code-nightly-bin|T3 Code nightly (desktop control surface for coding agents)"
        "brave-bin|Brave browser (binary release)"
        "visual-studio-code-bin|Visual Studio Code (official binary release)"
        "ghostty|Ghostty terminal (GPU-accelerated)"
        "docker|Docker engine (containers)"
        "docker-compose|Docker Compose (multi-container orchestration)"
        "wl-clipboard|Clipboard tools for Wayland (wl-copy/wl-paste)"
        "xclip|Clipboard tool for X11 (xclip)"
    )

    local entry pkg label
    for entry in "${extras[@]}"; do
        pkg="${entry%%|*}"
        label="${entry#*|}"
        if pacman -Q "$pkg" >/dev/null 2>&1; then
            ok "$pkg already installed"
            continue
        fi
        if ask_yes_no "Install ${label} [${pkg}]?"; then
            info "installing $pkg..."
            yay -S --needed --noconfirm "$pkg" \
                || { warn "$pkg install failed — rerun: yay -S $pkg"; continue; }
            ok "$pkg installed"
        else
            info "skipping $pkg"
        fi
    done

    # Docker post-setup (idempotent): daemon socket + user group membership.
    # Only runs when the docker package is present (installed just now or earlier).
    if pacman -Q docker >/dev/null 2>&1; then
        if has_cmd systemctl; then
            if systemctl is-enabled --quiet docker.socket 2>/dev/null; then
                ok "docker.socket already enabled"
            else
                info "enabling docker.socket..."
                sudo systemctl enable --now docker.socket \
                    || warn "could not enable docker.socket — run: sudo systemctl enable --now docker.socket"
            fi
        fi
        local docker_user
        docker_user="$(id -un)"
        if id -nG "$docker_user" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
            ok "user already in docker group"
        else
            info "adding $docker_user to docker group (log out and back in to take effect)..."
            sudo usermod -aG docker "$docker_user" \
                || warn "could not add $docker_user to docker group — run: sudo usermod -aG docker $docker_user"
        fi
    fi

    # Nerd Fonts bundle — one opt-in gate for the whole set (default: No).
    # Maps to the 18 zips in the screenshot; all are official extra packages.
    local nerd_fonts=(
        ttf-cascadia-code-nerd
        ttf-cascadia-mono-nerd
        ttf-firacode-nerd
        otf-firamono-nerd
        otf-geist-mono-nerd
        ttf-hack-nerd
        otf-hasklig-nerd
        ttf-ibmplex-mono-nerd
        ttf-jetbrains-mono-nerd
        ttf-meslo-nerd
        otf-monaspace-nerd
        ttf-noto-nerd
        ttf-roboto-mono-nerd
        ttf-sourcecodepro-nerd
        ttf-space-mono-nerd
        ttf-ubuntu-nerd
        ttf-ubuntu-mono-nerd
        ttf-zed-mono-nerd
    )
    local missing_fonts=()
    local f
    for f in "${nerd_fonts[@]}"; do
        pacman -Q "$f" >/dev/null 2>&1 || missing_fonts+=("$f")
    done
    if [ ${#missing_fonts[@]} -eq 0 ]; then
        ok "all nerd fonts already installed"
    elif ask_yes_no "Install Nerd Fonts bundle [${#missing_fonts[@]} of ${#nerd_fonts[@]} missing]?"; then
        info "installing nerd fonts..."
        yay -S --needed --noconfirm "${missing_fonts[@]}" \
            || { warn "nerd fonts install failed — rerun: yay -S ${missing_fonts[*]}"; return; }
        has_cmd fc-cache && fc-cache -f >/dev/null 2>&1 || true
        ok "nerd fonts installed"
    else
        info "skipping nerd fonts"
    fi
}

# ── Phase: post-install configuration ────────────────────────────────────

phase_config() {
    info "post-install configuration..."

    local zsh_path
    zsh_path="$(command -v zsh || true)"
    if [ -n "$zsh_path" ] && [ "$SHELL" != "$zsh_path" ]; then
        warn "setting default shell to zsh..."
        chsh -s "$zsh_path" || warn "chsh failed — run manually: chsh -s $zsh_path"
        ok "default shell changed — log out and back in to take effect"
    else
        ok "default shell is already zsh"
    fi

    if ! git config user.name >/dev/null 2>&1 || ! git config user.email >/dev/null 2>&1; then
        warn "git user not configured — set name & email:"
        warn "  git config --global user.name \"Your Name\""
        warn "  git config --global user.email \"you@example.com\""
    else
        ok "git user configured: $(git config user.name) <$(git config user.email)>"
    fi

    # .gitconfig declares an LFS filter — hooks must be registered per user.
    if has_cmd git-lfs; then
        if git lfs install >/dev/null 2>&1; then
            ok "git-lfs hooks installed"
        else
            warn "git lfs install failed — rerun: git lfs install"
        fi
    else
        warn "git-lfs not found — skipping (run system phase first)"
    fi

    if [ ! -f "$HOME/.zsh/completions/_mise" ]; then
        info "generating mise completions... (will complete on next zsh login)"
        mkdir -p "$HOME/.zsh/completions"
        mise completion zsh > "$HOME/.zsh/completions/_mise" 2>/dev/null || true
    else
        ok "mise completions already generated"
    fi
}

# ── Phase: auth logins (status-checked, interactive only) ────────────────

phase_auth() {
    if [ "$SKIP_AUTH" = "1" ]; then
        info "skipping auth logins (SKIP_AUTH=1)"
        return
    fi
    if [ ! -t 0 ]; then
        warn "non-interactive shell — skipping auth logins, run manually:"
        warn "  gh auth login && gcloud auth login && codex login"
        warn "  opencode auth login --provider zen && opencode auth login --provider opencode"
        warn "  sudo tailscale up && cmdc login"
        return
    fi
    info "checking auth status (already-logged-in services are skipped)..."

    # gh — git credential helper depends on this.
    if has_cmd gh; then
        if gh auth status >/dev/null 2>&1; then
            ok "gh already logged in"
        else
            warn "logging into gh..."
            gh auth login || warn "gh login failed — rerun: gh auth login"
        fi
    else
        warn "gh not found — skipping (run tools phase first)"
    fi

    # gcloud — user login + application-default credentials.
    if has_cmd gcloud; then
        if gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
            ok "gcloud already logged in"
        else
            warn "logging into gcloud..."
            gcloud auth login || warn "gcloud login failed — rerun: gcloud auth login"
        fi
        if gcloud auth application-default print-access-token >/dev/null 2>&1; then
            ok "gcloud application-default credentials present"
        else
            warn "setting up gcloud application-default credentials..."
            gcloud auth application-default login || warn "rerun: gcloud auth application-default login"
        fi
    else
        warn "gcloud not found — skipping (run tools phase first)"
    fi

    # codex — `login status` exits 0 when credentials are present.
    if has_cmd codex; then
        if codex login status >/dev/null 2>&1; then
            ok "codex already logged in"
        else
            warn "logging into codex..."
            codex login || warn "codex login failed — rerun: codex login"
        fi
    else
        warn "codex not found — skipping (run tools phase first)"
    fi

    # opencode providers: zen + opencode-go + custom litellm from
    # opencode.json, plus openai and commandcode.
    if has_cmd opencode; then
        local providers=(zen opencode litellm openai commandcode)
        local list auth_file
        list="$(opencode auth list 2>/dev/null || true)"
        auth_file="${HOME}/.local/share/opencode/auth.json"
        local p
        for p in "${providers[@]}"; do
            # Exact-key match on auth.json first: a substring grep on
            # `auth list` would false-positive ("opencode" matches "OpenCode Zen").
            if { [ -f "$auth_file" ] && grep -q "\"${p}\"" "$auth_file"; } \
                || printf '%s' "$list" | grep -qi "\<${p}\>"; then
                ok "opencode provider '$p' already authenticated"
            else
                warn "logging into opencode provider '$p'..."
                opencode auth login --provider "$p" || warn "rerun: opencode auth login --provider $p"
            fi
        done
    else
        warn "opencode not found — skipping (run tools phase first)"
    fi

    # opencode remote MCPs (jira, linear) use browser OAuth on first use,
    # stored in ~/.local/share/opencode/mcp-auth.json. No CLI login exists.
    local mcp_auth="${HOME}/.local/share/opencode/mcp-auth.json"
    if [ -f "$mcp_auth" ] && grep -qi "atlassian\|linear" "$mcp_auth" 2>/dev/null; then
        ok "opencode MCP auth present (jira/linear)"
    else
        warn "opencode MCPs (jira/linear) need one-time browser OAuth:"
        warn "  run 'opencode' once and accept the MCP auth prompts"
    fi

    # tailscale — daemon must be running (enabled in system phase).
    if [ "$SKIP_TAILSCALE" = "1" ]; then
        info "skipping tailscale login (SKIP_TAILSCALE=1)"
    elif has_cmd tailscale; then
        if tailscale status >/dev/null 2>&1; then
            ok "tailscale already connected ($(tailscale ip 2>/dev/null | head -n 1))"
        else
            warn "connecting tailscale (browser SSO)..."
            sudo tailscale up || warn "rerun: sudo tailscale up"
        fi
    else
        warn "tailscale not found — skipping (run system phase first)"
    fi

    # command-code — binary is `cmd` on Linux, `cmdc` on native Windows.
    local cmd_bin=""
    local c
    for c in cmdc cmd command-code; do
        if has_cmd "$c"; then cmd_bin="$c"; break; fi
    done
    if [ -z "$cmd_bin" ]; then
        warn "command-code not found — skipping (run tools phase first)"
    elif [ -n "${COMMAND_CODE_API_KEY:-}" ] || [ -f "${HOME}/.commandcode/auth.json" ] || "$cmd_bin" status >/dev/null 2>&1; then
        ok "command-code already logged in"
    else
        warn "logging into command-code..."
        "$cmd_bin" login || warn "rerun: $cmd_bin login"
    fi
}

# ── Summary ──────────────────────────────────────────────────────────────

summary() {
    printf "\n"
    info "install complete!"
    printf "  \033[1mNotes:\033[0m\n"
    printf "  • Start \033[1mzsh\033[0m — .zshrc will auto-install zinit and plugins\n"
    printf "  • Set git user if prompted above\n"
    printf "  • Auth: rerun './install.sh auth' any time to (re)check logins\n"
    printf "  • Extras: rerun './install.sh extras' to (re)check optional packages\n"
    printf "  • Tailscale status: \033[1mtailscale status\033[0m\n"
    printf "  • Restart your terminal or run: \033[1mexec zsh\033[0m\n"
    [ -d "$BACKUP_DIR" ] && printf "  • Existing dotfiles backed up to: \033[33m%s\033[0m\n" "$BACKUP_DIR"
}

# ── Main ─────────────────────────────────────────────────────────────────

usage() {
    printf "Usage: %s [phase ...]\n" "$0"
    printf "Phases: system link tools extras config auth (default: all)\n"
}

main() {
    local phases=()
    if [ $# -eq 0 ]; then
        phases=(system link tools extras config auth)
    else
        local a
        for a in "$@"; do
            case "$a" in
                system|link|tools|extras|config|auth) phases+=("$a") ;;
                -h|--help) usage; return 0 ;;
                *) printf "unknown phase: %s\n" "$a" >&2; usage >&2; return 1 ;;
            esac
        done
    fi
    local ph
    for ph in "${phases[@]}"; do
        "phase_${ph}"
    done
    summary
}

main "$@"
