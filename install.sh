#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="${HOME}/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

info()  { printf "\033[1;34m➜\033[0m %s\n" "$1"; }
ok()    { printf "\033[1;32m✓\033[0m %s\n" "$1"; }
warn()  { printf "\033[1;33m⚠\033[0m %s\n" "$1"; }

# ── Symlink helpers ──────────────────────────────────────────────────────

link_file() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ] || [ -L "$dst" ]; then
        if [ "$(readlink "$dst")" = "$src" ]; then
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

# ── Phase 0: Install pacman prerequisites ───────────────────────────────

phase0() {
    # Arch: everything the dotfiles and mise builds need, before any setup.
    if ! command -v pacman >/dev/null 2>&1; then
        return
    fi

    info "installing pacman prerequisites..."

    # nano = $EDITOR in .zshenv; xdg-utils = desktop integration; pacman-contrib = rankmirrors/checkupdates
    local pkgs=(zsh git curl openssl lsof unzip xz base-devel nano xdg-utils pacman-contrib)
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
    if command -v yay >/dev/null 2>&1; then
        ok "yay already installed"
    else
        info "installing yay (AUR helper)..."
        local build_dir
        build_dir="$(mktemp -d)"
        git clone https://aur.archlinux.org/yay.git "$build_dir/yay"
        (cd "$build_dir/yay" && makepkg -si --noconfirm)
        rm -rf "$build_dir"
        ok "yay installed"
    fi

    # Brave browser (AUR prebuilt binary package)
    if pacman -Q brave-bin >/dev/null 2>&1; then
        ok "brave already installed"
    else
        info "installing brave..."
        yay -S --needed --noconfirm brave-bin
        ok "brave installed"
    fi
}

# ── Phase 1: Symlink dotfiles ───────────────────────────────────────────-

phase1() {
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

    # Personal scripts → ~/.local/bin
    mkdir -p "${HOME}/.local/bin"
    for script in "${DOTFILES}"/bin/*; do
        [ -f "$script" ] && link_file "$script" "${HOME}/.local/bin/$(basename "$script")"
    done
}

# ── Phase 2: Install system dependencies ─────────────────────────────────

phase2() {
    info "checking system prerequisites..."

    local missing=()
    command -v zsh  >/dev/null 2>&1 || missing+=(zsh)
    command -v git  >/dev/null 2>&1 || missing+=(git)
    command -v curl >/dev/null 2>&1 || missing+=(curl)

    if [ ${#missing[@]} -gt 0 ]; then
        warn "install missing packages: ${missing[*]}"
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update || true
            sudo apt-get install -y "${missing[@]}"
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y "${missing[@]}"
        elif command -v brew >/dev/null 2>&1; then
            brew install "${missing[@]}"
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm "${missing[@]}"
        else
            warn "unsupported package manager — install manually: ${missing[*]}"
        fi
    fi
    ok "prerequisites satisfied"

    if ! command -v mise >/dev/null 2>&1; then
        info "installing mise..."
        curl -fsSL https://mise.run | sh
        export PATH="${HOME}/.local/bin:${PATH}"
    else
        ok "mise already installed"
    fi

    if ! command -v opencode >/dev/null 2>&1; then
        info "installing opencode..."
        curl -fsSL https://opencode.ai/install | bash
    else
        ok "opencode already installed"
    fi

    info "installing mise tools (this will take a while)..."
    mise install --yes
    ok "mise tools installed"
}

# ── Phase 3: Post-install configuration ──────────────────────────────────

phase3() {
    info "post-install configuration..."

    local zsh_path
    zsh_path="$(command -v zsh || true)"
    if [ -n "$zsh_path" ] && [ "$SHELL" != "$zsh_path" ]; then
        warn "setting default shell to zsh..."
        chsh -s "$zsh_path"
        ok "default shell changed — log out and back in to take effect"
    else
        ok "default shell is already zsh"
    fi

    local gh_path
    gh_path="$(command -v gh 2>/dev/null || mise which gh 2>/dev/null || true)"
    if [ -n "$gh_path" ]; then
        local cred_line='helper = !gh auth git-credential'
        if grep -qF "$cred_line" "${HOME}/.gitconfig" 2>/dev/null; then
            ok "git credential helper already using 'gh' directly"
        else
            warn "patching git credential helper in ~/.gitconfig"
            sed -i 's|helper = !/.*/gh auth git-credential|helper = !gh auth git-credential|' "${HOME}/.gitconfig"
        fi
    fi

    local opencode_sh="${HOME}/.zsh/opencode.zsh"
    if [ -f "$opencode_sh" ] && grep -q '/home/gabriel/' "$opencode_sh" 2>/dev/null; then
        warn "patching hardcoded path in .zsh/opencode.zsh"
        sed -i 's|/home/gabriel/|${HOME}/|g' "$opencode_sh"
    fi

    if ! git config user.name >/dev/null 2>&1 || ! git config user.email >/dev/null 2>&1; then
        warn "git user not configured — set name & email:"
        warn "  git config --global user.name \"Your Name\""
        warn "  git config --global user.email \"you@example.com\""
    else
        ok "git user configured: $(git config user.name) <$(git config user.email)>"
    fi

    if [ ! -d "$HOME/.zsh/completions/_mise" ]; then
        info "generating mise completions... (will complete on next zsh login)"
        mkdir -p "$HOME/.zsh/completions"
        mise completion zsh > "$HOME/.zsh/completions/_mise" 2>/dev/null || true
    fi
}

# ── Phase 4: Print summary ──────────────────────────────────────────────

summary() {
    printf "\n"
    info "install complete!"
    printf "  \033[1mNotes:\033[0m\n"
    printf "  • Start \033[1mzsh\033[0m — .zshrc will auto-install zinit and plugins\n"
    printf "  • Set git user if prompted above\n"
    printf "  • Restart your terminal or run: \033[1mexec zsh\033[0m\n"
    [ -d "$BACKUP_DIR" ] && printf "  • Existing dotfiles backed up to: \033[33m%s\033[0m\n" "$BACKUP_DIR"
}

# ── Main ─────────────────────────────────────────────────────────────────

phase0
phase1
phase2
phase3
summary
