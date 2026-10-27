# Browse ports with fzf.
#
# ss(8) supplies the socket table and fzf supplies the multi-select UI. Each row
# hides its port, PID, protocol, and process name in tab-separated fields, so
# the preview and actions can use them without parsing the display columns.
function ports --description 'Browse, copy, and kill ports with fzf'
    set -l show_all 0
    set -l assume_yes 0
    set -l query_parts

    set -l index 1
    while test $index -le (count $argv)
        set -l arg $argv[$index]
        switch $arg
            case -a --all
                set show_all 1
            case -y --yes
                set assume_yes 1
            case -h --help
                printf '%s\n' \
                    'Usage: ports [--all] [--yes] [query...]' \
                    '' \
                    'Browse TCP and UDP sockets with fzf. Tab marks multiple rows,' \
                    'Enter prints the selected ports, Ctrl-Y copies them, and Ctrl-K' \
                    'sends SIGTERM to the selected processes.' \
                    '' \
                    'Options:' \
                    '  -a, --all    include established and other non-listening sockets' \
                    '  -y, --yes    skip the SIGTERM confirmation' \
                    '  -h, --help   show this help' \
                    '' \
                    'Keys:' \
                    '  tab        mark another row' \
                    '  enter      print selected ports' \
                    '  ctrl-y     copy selected ports to the clipboard' \
                    '  ctrl-k     send SIGTERM to the selected processes' \
                    '  esc        cancel'
                return 0
            case --preview
                set -l preview_start (math $index + 1)
                set -l preview_pid_index (math $index + 2)
                set -l preview_proto_index (math $index + 3)
                set -l preview_port $argv[$preview_start]
                set -l preview_pid $argv[$preview_pid_index]
                set -l preview_proto $argv[$preview_proto_index]
                __ports_preview $preview_port $preview_pid $preview_proto
                return 0
            case --
                set -l rest (math $index + 1)
                if test $rest -le (count $argv)
                    set -a query_parts $argv[$rest..-1]
                end
                break
            case '-*'
                printf 'ports: unknown option: %s\n' $arg >&2
                return 2
            case '*'
                set -a query_parts $arg
        end
        set index (math $index + 1)
    end

    if not type -q fzf
        printf 'ports: fzf is not installed\n' >&2
        return 1
    end
    if not type -q ss
        printf 'ports: ss is not installed (install iproute2)\n' >&2
        return 1
    end

    set -l ss_args -H -n -p -t -u
    if test $show_all -eq 1
        set -a ss_args -a
    else
        set -a ss_args -l
    end

    set -l sockets (command ss $ss_args 2>/dev/null)
    set -l ss_status $status
    if test $ss_status -ne 0
        printf 'ports: ss failed\n' >&2
        return 1
    end
    if test (count $sockets) -eq 0
        if test $show_all -eq 1
            printf 'ports: no sockets found\n' >&2
        else
            printf 'ports: no listening ports found\n' >&2
        end
        return 0
    end

    set -l rows
    set -l pid_cache
    set -l user_cache

    for line in $sockets
        set -l fields (string split -n ' ' -- $line)
        if test (count $fields) -lt 5
            continue
        end

        set -l proto (string upper -- $fields[1])
        set -l state $fields[2]
        set -l local_address $fields[5]
        set -l processes
        if test (count $fields) -gt 6
            set processes (string join ' ' -- $fields[7..-1])
        end

        set -l address_parts (string split -r -m 1 ':' -- $local_address)
        if test (count $address_parts) -lt 2
            continue
        end
        set -l address $address_parts[1]
        set -l port $address_parts[2]
        if not string match -qr '^[0-9]+$' -- $port
            continue
        end

        if test "$address" = 0.0.0.0; or test "$address" = '*'
            set address all
        else if test "$address" = '[::]'; or test "$address" = '::'
            set address all6
        else
            set address (string replace -r '^\[(.*)\]$' '$1' -- $address)
        end

        set -l process_entries
        if test -n "$processes"
            for match in (string match -ar '\(\("[^"]+",pid=[0-9]+' -- $processes)
                set -l name (string replace -r '^\(\("([^"]+)",pid=[0-9]+$' '$1' -- $match)
                set -l pid (string replace -r '^.*pid=([0-9]+)$' '$1' -- $match)
                set -a process_entries (printf '%s\t%s' $pid $name)
            end
        end

        if test (count $process_entries) -eq 0
            set -a rows (printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' $port $proto $address $state - - '?')
            continue
        end

        for process in $process_entries
            set -l process_fields (string split \t -- $process)
            set -l pid $process_fields[1]
            set -l name $process_fields[2]

            set -l user -
            set -l cache_index (contains -i -- $pid $pid_cache)
            if test -n "$cache_index"
                set user $user_cache[$cache_index]
            else
                set user (command ps -o user= -p $pid 2>/dev/null | string trim)
                if test -z "$user"
                    set user '?'
                end
                set -a pid_cache $pid
                set -a user_cache $user
            end

            set -a rows (printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' $port $proto $address $state $user $pid $name)
        end
    end

    if test (count $rows) -eq 0
        printf 'ports: could not parse ss output\n' >&2
        return 1
    end

    set -l sorted (printf '%s\n' $rows | sort -n -k1,1 -k2,2 -k3,3)

    set -l address_width 8
    set -l user_width 4
    for row in $sorted
        set -l fields (string split \t -- $row)
        set -l address_length (string length -- $fields[3])
        if test $address_length -gt $address_width
            set address_width $address_length
        end
        set -l user_length (string length -- $fields[5])
        if test $user_length -gt $user_width
            set user_width $user_length
        end
    end
    if test $address_width -gt 26
        set address_width 26
    end
    if test $user_width -gt 12
        set user_width 12
    end

    set -l reset (printf '\e[0m')
    set -l bold (printf '\e[1m')
    set -l dim (printf '\e[2m')
    set -l green (printf '\e[32m')
    set -l yellow (printf '\e[33m')
    set -l blue (printf '\e[34m')
    set -l magenta (printf '\e[35m')
    set -l cyan (printf '\e[36m')
    set -l port_color (printf '\e[1;33m')

    set -l entries
    for row in $sorted
        set -l fields (string split \t -- $row)
        set -l port $fields[1]
        set -l proto $fields[2]
        set -l address $fields[3]
        set -l state $fields[4]
        set -l user $fields[5]
        set -l pid $fields[6]
        set -l name $fields[7]

        set -l proto_color $cyan
        if test "$proto" = UDP
            set proto_color $magenta
        end

        set -l state_color $dim
        switch $state
            case LISTEN
                set state_color $green
            case ESTAB
                set state_color $blue
            case UNCONN
                set state_color $yellow
        end

        set -l port_cell (string pad -w 5 -- $port)
        set -l proto_cell (string pad -r -w 3 -- $proto)
        set -l address_cell (string pad -r -w $address_width -- (string shorten -m $address_width -- $address))
        set -l state_cell (string pad -r -w 10 -- (string shorten -m 10 -- $state))
        set -l user_cell (string pad -r -w $user_width -- (string shorten -m $user_width -- $user))
        set -l pid_cell (string pad -w 7 -- $pid)

        set -l line (printf '%s%s%s %s%s%s  %s%s%s  %s%s%s  %s%s%s  %s%s%s  %s%s%s' \
            $proto_color $proto_cell $reset \
            $port_color $port_cell $reset \
            $dim $address_cell $reset \
            $state_color $state_cell $reset \
            $blue $user_cell $reset \
            $dim $pid_cell $reset \
            $bold $name $reset)

        set -a entries (printf '%s\t%s\t%s\t%s\t%s' $line $port $pid $proto $name)
    end

    set -l noun listeners
    if test $show_all -eq 1
        set noun sockets
    end
    set -l header (printf '\e[1m%d\e[0m %s  \e[2m·\e[0m  \e[2mtab\e[0m mark  \e[2menter\e[0m print  \e[2mctrl-y\e[0m copy  \e[2mctrl-k\e[0m kill' (count $entries) $noun)

    set -l fzf_options \
        --ansi \
        --multi \
        --delimiter='\t' \
        --with-nth=1 \
        --nth=1 \
        --tiebreak=index \
        --height=80% \
        --layout=reverse \
        --border=rounded \
        --border-label=' ports ' \
        --info=inline-right \
        --prompt='port> ' \
        --pointer='▸' \
        --marker='●' \
        --header-first \
        --header="$header" \
        --expect=ctrl-y,ctrl-k \
        --with-shell='fish -c' \
        --preview='ports --preview {2} {3} {4}' \
        --preview-label=' details ' \
        --preview-window='right,50%,border-left,wrap' \
        --color='pointer:cyan,marker:green,header:bright-black,prompt:cyan,spinner:cyan,info:bright-black,border:bright-black,label:cyan'

    set -l query
    if test (count $query_parts) -gt 0
        set query (string join ' ' -- $query_parts)
    end
    if test -n "$query"
        set -a fzf_options --query="$query"
    end

    set -l result (printf '%s\n' $entries | fzf $fzf_options)
    set -l pick_status $status
    if test $pick_status -ne 0
        return 130
    end

    set -l key
    set -l picked
    for line in $result
        if test -z "$line"
            continue
        end
        if test -z "$key"; and contains -- $line ctrl-y ctrl-k
            set key $line
            continue
        end
        set -a picked $line
    end

    set -l selected_ports
    set -l selected_pids
    for line in $picked
        set -l clean (string replace -ar '\x1b\[[0-9;]*m' '' -- $line)
        set -l fields (string split \t -- $clean)
        if test (count $fields) -lt 3
            continue
        end
        set -a selected_ports $fields[2]
        if test "$fields[3]" != -
            set -a selected_pids $fields[3]
        end
    end

    if test (count $selected_ports) -gt 0
        set selected_ports (printf '%s\n' $selected_ports | sort -n -u)
    end
    if test (count $selected_pids) -gt 0
        set selected_pids (printf '%s\n' $selected_pids | sort -n -u)
    end
    if test (count $selected_ports) -eq 0
        printf 'ports: no ports selected\n' >&2
        return 130
    end

    if test -z "$key"
        printf '%s\n' $selected_ports
        return 0
    end

    switch $key
        case ctrl-y
            set -l copied 0
            if test $copied -eq 0; and type -q wl-copy
                printf '%s\n' $selected_ports | command wl-copy
                and set copied 1
            end
            if test $copied -eq 0; and type -q xclip
                printf '%s\n' $selected_ports | command xclip -selection clipboard
                and set copied 1
            end
            if test $copied -eq 0; and type -q xsel
                printf '%s\n' $selected_ports | command xsel --clipboard --input
                and set copied 1
            end
            if test $copied -eq 0; and type -q pbcopy
                printf '%s\n' $selected_ports | command pbcopy
                and set copied 1
            end
            if test $copied -eq 0; and type -q clip.exe
                printf '%s\n' $selected_ports | command clip.exe
                and set copied 1
            end

            if test $copied -eq 1
                printf 'ports: copied %d port(s)\n' (count $selected_ports) >&2
            else
                printf 'ports: no clipboard tool found; printing instead\n' >&2
            end
            printf '%s\n' $selected_ports
            return 0
        case ctrl-k
            if test (count $selected_pids) -eq 0
                printf 'ports: selected ports have no visible process\n' >&2
                printf 'ports: other users processes need root to signal\n' >&2
                return 1
            end

            if test $assume_yes -eq 0
                printf 'Send SIGTERM to %d process(es) [%s]? [y/N] ' \
                    (count $selected_pids) (string join ', ' -- $selected_pids) >&2
                read -l answer
                if not string match -qir '^y(es)?$' -- $answer
                    printf 'ports: cancelled\n' >&2
                    return 130
                end
            end

            set -l failures 0
            for pid in $selected_pids
                if test "$pid" -le 1; or test "$pid" = "$fish_pid"
                    printf 'ports: refusing to signal pid %s\n' $pid >&2
                    set failures (math $failures + 1)
                    continue
                end
                if command kill -TERM $pid 2>/dev/null
                    printf 'ports: sent SIGTERM to pid %s\n' $pid >&2
                else
                    printf 'ports: could not signal pid %s (permission denied?)\n' $pid >&2
                    set failures (math $failures + 1)
                end
            end
            if test $failures -gt 0
                return 1
            end
            return 0
        case '*'
            printf 'ports: unexpected action: %s\n' $key >&2
            return 1
    end
end

function __ports_preview --description 'Render a ports fzf preview'
    set -l port $argv[1]
    set -l pid $argv[2]
    set -l proto $argv[3]

    set -l reset (printf '\e[0m')
    set -l bold (printf '\e[1m')
    set -l dim (printf '\e[2m')
    set -l green (printf '\e[32m')
    set -l yellow (printf '\e[33m')
    set -l magenta (printf '\e[35m')
    set -l cyan (printf '\e[36m')

    set -l label ":$port"
    if test -n "$proto"
        set label "$label/"(string lower -- $proto)
    end
    printf '%s%s%s\n\n' $bold $label $reset

    if test -n "$pid"; and test "$pid" != -
        set -l fields (command ps -o pid=,ppid=,user=,stat=,pcpu=,pmem=,etime= -p $pid 2>/dev/null | string split -n ' ')
        if test (count $fields) -ge 7
            set -l arguments (command ps -o args= -p $pid 2>/dev/null | string trim)
            printf '%sprocess%s\n' $bold $reset
            printf '  %s%-8s%s %s\n' $dim pid $reset $fields[1]
            printf '  %s%-8s%s %s\n' $dim parent $reset $fields[2]
            printf '  %s%-8s%s %s%s%s\n' $dim user $reset $yellow $fields[3] $reset
            printf '  %s%-8s%s %s\n' $dim state $reset $fields[4]
            printf '  %s%-8s%s %s%%\n' $dim cpu $reset $fields[5]
            printf '  %s%-8s%s %s%%\n' $dim memory $reset $fields[6]
            printf '  %s%-8s%s %s\n' $dim uptime $reset $fields[7]
            printf '  %s%-8s%s %s\n' $dim command $reset (string shorten -m 100 -- "$arguments")
        else
            printf '%sprocess%s\n' $bold $reset
            printf '  %sno process information available%s\n' $dim $reset
            printf '  %sother users processes need root privileges%s\n' $dim $reset
        end
    else
        printf '%sprocess%s\n' $bold $reset
        printf '  %sno process information available%s\n' $dim $reset
        printf '  %sother users processes need root privileges%s\n' $dim $reset
    end

    printf '\n%ssocket%s\n' $bold $reset
    set -l sockets (command ss -H -tuanp "sport = :$port" 2>/dev/null)
    if test (count $sockets) -eq 0
        printf '  %sno socket rows%s\n' $dim $reset
        return 0
    end

    for line in $sockets
        set -l fields (string split -n ' ' -- $line)
        if test (count $fields) -lt 5
            continue
        end
        set -l socket_proto (string upper -- $fields[1])
        set -l socket_state $fields[2]
        set -l local_address $fields[5]
        set -l peer_address -
        if test (count $fields) -ge 6
            set peer_address $fields[6]
        end

        set -l proto_color $cyan
        if test "$socket_proto" = UDP
            set proto_color $magenta
        end
        set -l state_color $dim
        if test "$socket_state" = LISTEN
            set state_color $green
        else if test "$socket_state" = ESTAB
            set state_color $cyan
        end

        printf '  %s%-3s%s %s%-10s%s %s%s%s\n' \
            $proto_color $socket_proto $reset \
            $state_color $socket_state $reset \
            $dim $local_address $reset

        if test "$peer_address" != '0.0.0.0:*'; and test "$peer_address" != '[::]:*'; and test "$peer_address" != '*:*'
            printf '      %s→ %s%s\n' $dim $peer_address $reset
        end
    end
end
