# gh is installed by the tools phase — skip completion on fresh shells before that.
command -v gh >/dev/null 2>&1 && eval "$(gh completion -s zsh)"