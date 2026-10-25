#!/usr/bin/env bash
#
# Interactive SSH/personal GitHub/gcloud/Tailscale/OpenCode MCP authentication
# helper.
#
# This does not run during bootstrap. Run it once per machine after the
# packages and dotfiles are applied.

set -Eeuo pipefail

KEY="${HOME}/.ssh/id_ed25519"
GENERATE_KEY=0
SKIP_GH=0
SKIP_GCLOUD=0
SKIP_TAILSCALE=0
SKIP_LINEAR=0
SKIP_JIRA=0
AUTH_INCOMPLETE=0

usage() {
    cat <<'EOF'
Usage: arch/auth.sh [options]

Options:
  --generate-key     Generate ~/.ssh/id_ed25519 if it does not exist
  --key PATH         Use a different private key path
  --skip-gh          Do not configure or authenticate the GitHub CLI
  --skip-gcloud      Do not configure or authenticate the gcloud CLI
  --skip-tailscale   Do not authenticate Tailscale
  --skip-linear      Do not authenticate the Linear MCP server
  --skip-jira        Do not authenticate the Jira MCP server
  --skip-mcp         Do not authenticate the Linear or Jira MCP servers
  -h, --help         Show this help

What this does:
  - ensures a per-machine SSH key exists
  - starts/reuses an ssh-agent and loads the key
  - authenticates `gh` for personal GitHub and uploads the key
  - uploads the same key as a GitHub signing key
  - authenticates `gcloud` and application default credentials
  - authenticates Tailscale when its daemon is running
  - authenticates the Linear and Jira MCP servers in OpenCode
  - prints Cloud Source Repositories SSH registration instructions for work

SSH commit signing is configured by chezmoi. Work projects under
~/Projects/work/ use the work email from the chezmoi data and the same SSH key.
EOF
}

log() {
    printf '%s\n' "$*"
}

warn() {
    printf 'warning: %s\n' "$*" >&2
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

on_error() {
    local status=$?
    printf 'error: auth setup failed at line %s (status %s)\n' "$1" "$status" >&2
}

trap 'on_error "$LINENO"' ERR

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

mcp_list_output() {
    opencode mcp list 2>/dev/null || true
}

mcp_matches() {
    local output="$1" name="$2" state="$3"
    grep -Eq "(^|[[:space:]])${name}[[:space:]]+${state}([[:space:]]|$)" <<<"$output"
}

authenticate_mcp() {
    local name="$1" label="$2" output
    output="$(mcp_list_output)"
    if mcp_matches "$output" "$name" "connected"; then
        log "$label MCP is already connected"
        return
    fi
    if ! mcp_matches "$output" "$name" "needs authentication"; then
        warn "$label MCP is not waiting for authentication; check: opencode mcp list"
        AUTH_INCOMPLETE=1
        return
    fi

    log "Authenticating $label MCP in OpenCode (a browser window will open)"
    if ! opencode mcp auth "$name"; then
        warn "$label MCP authentication failed; retry: opencode mcp auth $name"
        AUTH_INCOMPLETE=1
        return
    fi

    output="$(mcp_list_output)"
    if mcp_matches "$output" "$name" "connected"; then
        log "$label MCP connected"
    else
        warn "$label MCP is still not connected; check: opencode mcp list"
        AUTH_INCOMPLETE=1
    fi
}

while (($# > 0)); do
    case "$1" in
    --generate-key)
        GENERATE_KEY=1
        shift
        ;;
    --key)
        [[ $# -ge 2 ]] || die "--key requires an argument"
        KEY="$2"
        shift 2
        ;;
    --key=*)
        KEY="${1#*=}"
        shift
        ;;
    --skip-gh)
        SKIP_GH=1
        shift
        ;;
    --skip-gcloud)
        SKIP_GCLOUD=1
        shift
        ;;
    --skip-tailscale)
        SKIP_TAILSCALE=1
        shift
        ;;
    --skip-linear)
        SKIP_LINEAR=1
        shift
        ;;
    --skip-jira)
        SKIP_JIRA=1
        shift
        ;;
    --skip-mcp)
        SKIP_LINEAR=1
        SKIP_JIRA=1
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        die "unknown option: $1 (try --help)"
        ;;
    esac
done

[[ $EUID -ne 0 ]] || die "run this as your user, not root"
KEY="${KEY/#\~/$HOME}"

require_cmd git
require_cmd ssh-keygen
require_cmd ssh-add
require_cmd uname

umask 077
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

email="$(git config --global --get user.email 2>/dev/null || true)"
if [[ -z "$email" ]]; then
    read -r -p "Email address for the SSH key comment: " email
fi
[[ -n "$email" ]] || die "an email address is required for the key comment"

if [[ ! -f "$KEY" ]]; then
    if ((GENERATE_KEY)); then
        log "Generating a new ed25519 SSH key at $KEY"
        ssh-keygen -t ed25519 -a 100 -C "$email" -f "$KEY"
    else
        die "SSH key not found: $KEY (rerun with --generate-key or restore your key)"
    fi
fi

chmod 600 "$KEY"

if [[ ! -f "${KEY}.pub" ]]; then
    log "Deriving public key from $KEY"
    ssh-keygen -y -f "$KEY" >"${KEY}.pub"
fi
chmod 644 "${KEY}.pub"

# Make local `git log --show-signature` verification work for both identities.
work_email="$(git config --file "$HOME/.config/git/work.inc" --get user.email 2>/dev/null || true)"
public_key="$(awk '{print $1, $2}' "${KEY}.pub")"
mkdir -p "$HOME/.config/git"
{
    [[ -n "$email" ]] && printf '%s %s\n' "$email" "$public_key"
    [[ -n "$work_email" ]] && printf '%s %s\n' "$work_email" "$public_key"
} >"$HOME/.config/git/allowed_signers"
chmod 644 "$HOME/.config/git/allowed_signers"

agent_started=0
if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
    eval "$(ssh-agent -s)" >/dev/null
    agent_started=1
else
    agent_status=0
    ssh-add -l >/dev/null 2>&1 || agent_status=$?
    if [[ "$agent_status" -eq 2 ]]; then
        eval "$(ssh-agent -s)" >/dev/null
        agent_started=1
    fi
fi

if ((agent_started)); then
    {
        printf "set -gx SSH_AUTH_SOCK '%s'\n" "$SSH_AUTH_SOCK"
        printf "set -gx SSH_AGENT_PID '%s'\n" "${SSH_AGENT_PID:-}"
    } >"$HOME/.ssh/agent.env"
    chmod 600 "$HOME/.ssh/agent.env"
fi

log "Loading $KEY into the ssh-agent"
ssh-add "$KEY"

log "SSH key fingerprint: $(ssh-keygen -lf "${KEY}.pub" | awk '{print $2}')"
if ((agent_started)); then
    log "A new ssh-agent was started; new fish shells will load ~/.ssh/agent.env."
    log "For the current fish shell, run: source ~/.ssh/agent.env"
fi

if ((SKIP_GH == 0)); then
    if ! command -v gh >/dev/null 2>&1; then
        warn "gh is not installed; run arch/bootstrap.sh and rerun this script"
        AUTH_INCOMPLETE=1
    else
        if ! gh auth status >/dev/null 2>&1; then
            log "Authenticating GitHub CLI with the SSH Git protocol"
            gh auth login --hostname github.com --git-protocol ssh --web
        else
            log "GitHub CLI is already authenticated"
        fi

        log "Ensuring GitHub has this key for authentication and signing"
        gh ssh-key add "${KEY}.pub" --title "$(uname -n)-auth" --type authentication ||
            warn "authentication key may already be registered"
        gh ssh-key add "${KEY}.pub" --title "$(uname -n)-signing" --type signing ||
            warn "signing key may already be registered"

        if ! gh auth status >/dev/null 2>&1; then
            warn "GitHub CLI authentication is still failing"
            AUTH_INCOMPLETE=1
        fi
    fi
fi

if ((SKIP_GCLOUD == 0)); then
    if ! command -v gcloud >/dev/null 2>&1; then
        warn "gcloud is not installed; run arch/bootstrap.sh and rerun this script"
        AUTH_INCOMPLETE=1
    else
        active_account="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1 || true)"
        if [[ -z "$active_account" ]]; then
            log "Authenticating gcloud (OAuth; SSH is not used for gcloud CLI auth)"
            if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
                gcloud auth login --no-launch-browser
            else
                gcloud auth login
            fi
        else
            log "gcloud is already authenticated as $active_account"
        fi

        if [[ -z "$(gcloud auth application-default print-access-token 2>/dev/null || true)" ]]; then
            log "Configuring gcloud application default credentials"
            if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
                gcloud auth application-default login --no-launch-browser
            else
                gcloud auth application-default login
            fi
        else
            log "gcloud application default credentials already configured"
        fi

        log "For Compute Engine VM SSH access, use: gcloud compute config-ssh"

        log "Work repositories (Cloud Source Repositories) use a registered SSH key."
        log "Register ${KEY}.pub at: https://source.cloud.google.com/user/ssh_keys"
        log "SSH clone URL: ssh://${work_email:-<work-email>}@source.developers.google.com:2022/p/PROJECT/r/REPO"
        log "The gcloud CLI itself uses OAuth; 'gcloud source repos clone' is the OAuth-based clone path."
    fi
fi

if ((SKIP_TAILSCALE == 0)); then
    if ! command -v tailscale >/dev/null 2>&1; then
        warn "tailscale is not installed; run arch/bootstrap.sh and rerun this script"
        AUTH_INCOMPLETE=1
    elif [[ ! -S /var/run/tailscale/tailscaled.sock && ! -S /run/tailscale/tailscaled.sock ]]; then
        AUTH_INCOMPLETE=1
        if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
            log "Tailscale daemon is not running in WSL. Start it with:"
            log "  sudo tailscaled >/tmp/tailscaled.log 2>&1 &"
            log "Then rerun: ./arch/auth.sh --skip-gh --skip-gcloud"
            log "Or enable systemd in WSL and rerun bootstrap."
        else
            warn "tailscaled is not running; start it with: sudo systemctl start tailscaled"
        fi
    else
        tailscale_state="$(tailscale status --json 2>/dev/null | jq -r '.BackendState // empty' 2>/dev/null || true)"
        if [[ "$tailscale_state" == "Running" ]]; then
            log "Tailscale is already connected"
        else
            log "Authenticating Tailscale (current state: ${tailscale_state:-unknown})"
            sudo tailscale up
        fi

        if ! sudo tailscale set --operator="$USER"; then
            warn "could not set Tailscale operator"
            AUTH_INCOMPLETE=1
        fi
    fi
fi

if ((SKIP_LINEAR == 0 || SKIP_JIRA == 0)); then
    if ! command -v opencode >/dev/null 2>&1; then
        warn "opencode is not installed; run arch/bootstrap.sh and rerun this script"
        AUTH_INCOMPLETE=1
    else
        if ((SKIP_LINEAR == 0)); then
            authenticate_mcp linear "Linear"
        fi
        if ((SKIP_JIRA == 0)); then
            authenticate_mcp jira "Jira"
        fi
    fi
fi

if ((AUTH_INCOMPLETE)); then
    log "Authentication setup incomplete; review the warnings above."
    exit 1
fi

log "Authentication setup complete."
log "Commit signing is enabled globally by chezmoi; work email applies under ~/Projects/work/."
