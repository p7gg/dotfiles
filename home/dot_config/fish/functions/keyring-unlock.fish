# Unlock the passphrase-protected GNOME login keyring.
#
# WSL has no PAM login, so a keyring protected by a passphrase stays locked
# after the distro starts. This stops the systemd-managed daemon, starts a
# daemon with the keyring unlocked, and leaves it running for this WSL session.
function keyring-unlock --description 'Unlock the GNOME login keyring'
    if not set -q WSL_DISTRO_NAME
        if not grep -qi microsoft /proc/version 2>/dev/null
            echo "keyring-unlock: this helper is for WSL; native GNOME unlocks at login" >&2
            return 1
        end
    end

    if not type -q gnome-keyring-daemon
        echo "keyring-unlock: gnome-keyring-daemon is not installed; run provisioning/arch/bootstrap.sh" >&2
        return 1
    end

    if not type -q gdbus
        echo "keyring-unlock: gdbus is not installed (glib2); run provisioning/arch/bootstrap.sh" >&2
        return 1
    end

    set -l runtime_dir /run/user/(id -u)
    if set -q XDG_RUNTIME_DIR
        set runtime_dir $XDG_RUNTIME_DIR
    end
    set -l control_dir $runtime_dir/keyring

    set -l state (gdbus call --session --dest org.freedesktop.secrets \
        --object-path /org/freedesktop/secrets/collection/login \
        --method org.freedesktop.DBus.Properties.Get \
        org.freedesktop.Secret.Collection Locked 2>/dev/null)

    if string match -q '*false*' -- "$state"
        echo "GNOME Keyring is already unlocked"
        return 0
    end

    read -s -P 'GNOME Keyring passphrase: ' passphrase
    echo
    if test -z "$passphrase"
        echo "keyring-unlock: empty passphrase" >&2
        return 1
    end

    # --unlock must be the only daemon starting, so stop the socket-activated
    # service before asking the daemon to take over with the unlocked keyring.
    if type -q systemctl
        systemctl --user stop gnome-keyring-daemon.service gnome-keyring-daemon.socket >/dev/null 2>&1
    end
    if type -q pkill
        pkill -x gnome-keyring-d >/dev/null 2>&1
    end

    # Wait for the old daemon to release org.freedesktop.secrets before the
    # unlocked daemon tries to take the name.
    for attempt in (seq 1 20)
        if not pgrep -x gnome-keyring-d >/dev/null 2>&1
            break
        end
        sleep 0.5
    end

    mkdir -p $control_dir
    chmod 700 $control_dir

    # Pass the passphrase through a private file in the tmpfs runtime dir. A
    # fish pipeline keeps the write end open in this process, which makes the
    # daemon wait for EOF until the shell exits.
    set -l pass_file (mktemp -p $runtime_dir keyring-pass.XXXXXX) 2>/dev/null
    or begin
        echo "keyring-unlock: could not create a temporary passphrase file" >&2
        return 1
    end
    /usr/bin/printf '%s' "$passphrase" >$pass_file
    set -e passphrase

    set -l rc 0
    gnome-keyring-daemon --unlock --daemonize --control-directory=$control_dir <$pass_file >/dev/null 2>&1
    or set rc $status
    rm -f $pass_file

    if test $rc -ne 0
        echo "keyring-unlock: could not start the keyring daemon" >&2
        return 1
    end

    # --daemonize returns before the new daemon owns the bus; poll briefly.
    set -l state ""
    for attempt in (seq 1 30)
        set state (gdbus call --session --dest org.freedesktop.secrets \
            --object-path /org/freedesktop/secrets/collection/login \
            --method org.freedesktop.DBus.Properties.Get \
            org.freedesktop.Secret.Collection Locked 2>/dev/null)
        string match -q '*false*' -- "$state"
        and break
        sleep 0.5
    end

    if not string match -q '*false*' -- "$state"
        echo "keyring-unlock: the passphrase did not unlock the keyring" >&2
        return 1
    end

    echo "GNOME Keyring unlocked for this WSL session"
end
