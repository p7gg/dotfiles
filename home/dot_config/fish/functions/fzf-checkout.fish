# Interactively switch Git branches with fzf.
#
# Local branches are listed first, followed by remote-tracking branches. Picking
# a remote branch creates a local branch with the same name and sets it to track
# that remote. Remote branches that already have a local branch with the same
# name are omitted to avoid duplicate entries.
#
# With arguments, fall back to `git checkout` so `ch <branch>` and flag-based
# use still work.
function fzf-checkout --description 'Interactively switch Git branches with fzf'
    if test (count $argv) -gt 0
        command git checkout $argv
        return
    end

    if not type -q fzf
        echo 'fzf-checkout: fzf is not installed' >&2
        return 1
    end

    if not command git rev-parse --is-inside-work-tree >/dev/null 2>&1
        echo 'fzf-checkout: not inside a Git work tree' >&2
        return 1
    end

    # Remote names can contain slashes, so pick the longest matching remote for
    # each remote-tracking ref instead of assuming the first path component.
    set -l remotes (command git remote)
    set -l local_names
    set -l entries

    for line in (command git for-each-ref \
        --sort=-committerdate \
        --format='%(refname:short)%09%(committerdate:relative)' \
        refs/heads)
        set -l fields (string split \t -- $line)
        set -a local_names $fields[1]
        set -a entries (printf '\e[32mlocal\e[0m\t%s\t\e[2m%s\e[0m\t' $fields[1] $fields[2])
    end

    for line in (command git for-each-ref \
        --sort=-committerdate \
        --format='%(refname:short)%09%(committerdate:relative)' \
        refs/remotes)
        set -l fields (string split \t -- $line)
        set -l ref $fields[1]
        set -l remote
        for candidate in $remotes
            if string match -q -- "$candidate/*" $ref
                if test -z "$remote"; or test (string length -- $candidate) -gt (string length -- $remote)
                    set remote $candidate
                end
            end
        end
        test -n "$remote"; or continue

        set -l name (string replace -- "$remote/" '' $ref)
        test "$name" = HEAD; and continue
        contains -- $name $local_names; and continue

        set -a entries (printf '\e[34mremote\e[0m\t%s\t\e[2m%s\e[0m\t%s' $ref $fields[2] $name)
    end

    if test (count $entries) -eq 0
        echo 'fzf-checkout: no branches found' >&2
        return 1
    end

    set -l current (command git branch --show-current 2>/dev/null)
    set -l header 'enter: switch  |  esc: cancel'
    if test -n "$current"
        set header "current: $current  |  $header"
    else
        set header "current: detached HEAD  |  $header"
    end

    set -l fzf_options \
        --ansi \
        --delimiter='\t' \
        --nth=1,2 \
        --with-nth=1,2,3 \
        --height=60% \
        --layout=reverse \
        --header-first \
        --border=rounded \
        --info=inline-right \
        --prompt='switch> ' \
        --pointer='▸' \
        --header="$header" \
        --preview="git --no-pager log --color=always --graph --pretty='%C(auto)%h%C(auto)%d %s %C(dim)(%ar)' -20 {2}" \
        --preview-window='right,55%,border-left,wrap'

    set -l picked (printf '%s\n' $entries | fzf $fzf_options)
    set -l pick_status $status
    if test $pick_status -ne 0; or test -z "$picked"
        return 130
    end

    # fzf normally strips ANSI codes from picked lines; strip defensively so a
    # different fzf version cannot turn the type field into a failed match.
    set -l fields (string split \t -- (string replace -ar '\x1b\[[0-9;]*m' '' -- $picked))
    set -l kind (string trim -- $fields[1])

    switch $kind
        case local
            command git switch -- $fields[2]
        case remote
            # The fourth field carries the local branch name computed while
            # building the list. It is hidden from the picker by --with-nth.
            # Use --create=<name> and -- so branch names starting with "-" are
            # never interpreted as git options.
            command git switch --track --create=$fields[4] -- $fields[2]
        case '*'
            echo "fzf-checkout: unexpected selection: $picked" >&2
            return 1
    end
end
