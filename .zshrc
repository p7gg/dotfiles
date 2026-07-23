# zinit ========================================================================

### setup
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
[ ! -d $ZINIT_HOME ] && mkdir -p "$(dirname $ZINIT_HOME)"
[ ! -d $ZINIT_HOME/.git ] && git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
source "${ZINIT_HOME}/zinit.zsh"

# plugins
zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-history-substring-search
zinit light zsh-users/zsh-completions
zinit light zdharma-continuum/fast-syntax-highlighting

# completions
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit
zinit cdreplay -q

# .zsh =========================================================================

for file in ~/.zsh/*.zsh; do
    source "$file"
done

# aliases ======================================================================

alias gensecret='openssl rand -base64 32'
alias ls='eza --icons'
alias ll='eza -lh --icons --git'
alias la='eza -lah --icons --git'
alias tree='eza --tree --icons'
alias cat='bat --style=auto'
alias cl='clear'
alias pn='pnpm'
alias lz='lazygit'
alias g='git'
alias grep='rg --color=auto'
alias diff='diff --color=auto'
alias df='df -h'
alias ..='cd ..'
alias ...='cd ../..'

# keybindings ==================================================================

# Ctrl+Right -> move forward one word (^[[1;5C is the terminal escape code)
bindkey '^[[1;5C' forward-word

# Ctrl+Left -> move backward one word (^[[1;5D is the terminal escape code)
bindkey '^[[1;5D' backward-word

# Ctrl+F -> fzf file picker (no hidden files)
bindkey '^F' _fzf_file_no_hidden

# Up/Down -> history search by substring (^[[A/^[[B are up/down arrow escape codes)
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# history ======================================================================

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_FIND_NO_DUPS

# shell behavior ======================================================================

setopt AUTOCD
setopt NOBEEP
setopt NUMERIC_GLOB_SORT  # sort file10 after file9, not after file1

# completion styling ===========================================================

# Enable interactive completion menu selection
zstyle ':completion:*' menu select

# Make completion case-insensitive
# Example: "doc" can complete to "Documents"
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'  # lowercase input matches upper and lower

# Reuse ls completions for eza (avoids defining a separate completion function)
compdef eza=ls