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

# Fall back to PATH only when neither standard location matched, so unusual
# installs (mise, /opt, Homebrew) still work without slowing the common case.
if test $editor = nano
    if type -q nvim
        set editor nvim
    else if type -q vim
        set editor vim
    end
end

set -q EDITOR; or set -gx EDITOR $editor
set -q VISUAL; or set -gx VISUAL $EDITOR
set -q PAGER; or set -gx PAGER less
set -q MANPAGER; or set -gx MANPAGER "less -R"
set -q LESS; or set -gx LESS -R

# Bitwarden Secrets Manager account label used by functions/bws.fish.
# Keep an explicitly configured account (for example, from a local config).
if not set -q BWS_ACCOUNT
    set -gx BWS_ACCOUNT personal
end
