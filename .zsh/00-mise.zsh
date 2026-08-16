# mise activation — resolve mise whether system-installed or from the mise.run installer (~/.local/bin)
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate zsh)"
elif [ -x "${HOME}/.local/bin/mise" ]; then
    eval "$("${HOME}/.local/bin/mise" activate zsh)"
fi
