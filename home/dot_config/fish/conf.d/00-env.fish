# Interactive shell environment. Check the usual install locations directly;
# `type -q` walks the whole PATH, which is noticeably slow when WSL appends the
# Windows PATH.
set -l editor nano
for candidate in $HOME/.local/bin/nvim /usr/local/bin/nvim /usr/bin/nvim
    if test -x $candidate
        set editor nvim
        break
    end
end
if test $editor = nano
    for candidate in $HOME/.local/bin/vim /usr/local/bin/vim /usr/bin/vim
        if test -x $candidate
            set editor vim
            break
        end
    end
end
set -gx EDITOR $editor

set -gx VISUAL $EDITOR
set -gx PAGER less
set -gx MANPAGER "less -R"
set -gx LESS -R

# Bitwarden Secrets Manager account label used by functions/bws.fish.
# Keep an explicitly configured account (for example, from a local config).
if not set -q BWS_ACCOUNT
    set -gx BWS_ACCOUNT personal
end
