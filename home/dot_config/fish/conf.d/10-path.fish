# User-local binaries take precedence, without duplicating PATH entries.
for dir in $HOME/.local/bin $HOME/.go/bin
    if not contains $dir $PATH
        set -gx PATH $dir $PATH
    end
end
