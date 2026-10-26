if status is-interactive
    abbr --add --global g git
    abbr --add --global gs 'git status --short --branch'
    abbr --add --global gd 'git diff'
    abbr --add --global gl 'git log --oneline --graph --decorate -20'
    abbr --add --global ch fzf-checkout
    abbr --add --global ll 'ls -lah'
    abbr --add --global oc 'opencode'
end
