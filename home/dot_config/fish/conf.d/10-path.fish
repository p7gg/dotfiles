# User-local binaries take precedence, without duplicating PATH entries.
if not contains $HOME/.local/bin $PATH
    set -gx PATH $HOME/.local/bin $PATH
end
