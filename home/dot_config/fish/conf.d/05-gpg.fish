if status is-interactive; and tty -s
    # Helps GPG pinentry find the correct terminal.
    set -gx GPG_TTY (tty)
end
