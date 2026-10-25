# Interactive shell environment.
if type -q nvim
    set -gx EDITOR nvim
else if type -q vim
    set -gx EDITOR vim
else
    set -gx EDITOR nano
end

set -gx VISUAL $EDITOR
set -gx PAGER less
set -gx MANPAGER "less -R"
set -gx LESS -R

# Bitwarden Secrets Manager account label used by functions/bws.fish.
set -gx BWS_ACCOUNT personal
