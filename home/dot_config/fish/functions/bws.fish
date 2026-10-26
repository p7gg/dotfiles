# Load the Bitwarden Secrets Manager access token from a local secret store.
#
# Native GNOME: token is stored in GNOME Keyring:
#   secret-tool store --label='BWS access token' service bws account personal
#
# WSL: token is stored in pass:
#   pass insert bitwarden/bws-token
#
# --bws-account only selects the GNOME Keyring label on native systems. WSL
# always reads the single pass entry at bitwarden/bws-token.
#
# The token is exported only for the bws process and its children. Run
# `./arch/auth.sh` to store it interactively, or see the README for the manual
# commands.
function bws --wraps bws --description 'bws with access token from keyring'
    set -l account personal
    if set -q BWS_ACCOUNT
        set account $BWS_ACCOUNT
    end

    set -l token
    set -l token_store native
    if set -q WSL_DISTRO_NAME
        set token_store wsl
        if not type -q pass
            echo "bws: pass is not installed; run arch/bootstrap.sh --profile wsl" >&2
            return 1
        end
        set token (pass show bitwarden/bws-token 2>/dev/null | string collect)
    else
        if not type -q secret-tool
            echo "bws: secret-tool is not installed; install libsecret via arch/bootstrap.sh" >&2
            return 1
        end
        set token (secret-tool lookup service bws account $account 2>/dev/null | string collect)
    end

    if test -z "$token"
        if test "$token_store" = wsl
            echo "bws: no access token in pass at bitwarden/bws-token; run ./arch/auth.sh or: pass insert bitwarden/bws-token" >&2
        else
            echo "bws: no access token stored in GNOME Keyring for account '$account'; run ./arch/auth.sh --bws-account $account" >&2
        end
        return 1
    end

    set -lx BWS_ACCESS_TOKEN $token
    command bws $argv
end
