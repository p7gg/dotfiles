if status is-interactive; and tty -s
    # Helps GPG/pass pinentry find the correct terminal.
    set -gx GPG_TTY (tty)
end
