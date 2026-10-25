# Load the Bitwarden Secrets Manager access token from a local secret store.
#
# Native GNOME: token is stored in GNOME Keyring:
#   secret-tool store --label='BWS access token' service bws account personal
#
# WSL: token is stored in pass:
#   pass insert bitwarden/bws-token
#
# The token is exported only for the bws process and its children.
function bws --wraps bws --description 'bws with access token from keyring'
    set -l account personal
    if set -q BWS_ACCOUNT
        set account $BWS_ACCOUNT
    end

    set -l token
    if set -q WSL_DISTRO_NAME
        if type -q pass
            set token (pass show bitwarden/bws-token 2>/dev/null)
        end
    else
        if type -q secret-tool
            set token (secret-tool lookup service bws account $account 2>/dev/null)
        end
    end

    if test -z "$token"
        echo "bws: could not load access token (see README)" >&2
        return 1
    end

    set -lx BWS_ACCESS_TOKEN $token
    command bws $argv
end
