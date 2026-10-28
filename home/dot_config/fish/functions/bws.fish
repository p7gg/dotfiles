# Load the Bitwarden Secrets Manager access token from GNOME Keyring.
#
# Store the token with:
#   secret-tool store --label='BWS access token' service bws account personal
#
# The token is exported only for the bws process and its children. Run
# `./provisioning/arch/auth.sh` to store it interactively, or see the README for
# the manual commands.
function bws --wraps bws --description 'bws with access token from GNOME Keyring'
    set -l account personal
    if set -q BWS_ACCOUNT
        set account $BWS_ACCOUNT
    end

    if not type -q secret-tool
        echo "bws: secret-tool is not installed; run provisioning/arch/bootstrap.sh" >&2
        return 1
    end

    set -l token (secret-tool lookup service bws account $account 2>/dev/null | string collect)

    if test -z "$token"
        echo "bws: no access token in GNOME Keyring for account '$account'; if the keyring is locked run 'keyring-unlock', or run ./provisioning/arch/auth.sh --bws-account $account" >&2
        return 1
    end

    set -lx BWS_ACCESS_TOKEN $token
    command bws $argv
end
