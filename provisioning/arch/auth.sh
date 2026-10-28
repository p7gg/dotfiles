#!/usr/bin/env bash
#
# Interactive SSH/personal GitHub/gcloud/Tailscale/BWS/OpenCode MCP
# authentication helper.
#
# This does not run during bootstrap. Run it once per machine after the
# packages and dotfiles are applied.

set -Eeuo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=provisioning/arch/lib/common.sh
source "$REPO_ROOT/provisioning/arch/lib/common.sh"

KEY="${HOME}/.ssh/id_ed25519"
GENERATE_KEY=0
CHECK_ONLY=0
DRY_RUN=0
NON_INTERACTIVE=0
SKIP_GH=0
SKIP_GCLOUD=0
SKIP_TAILSCALE=0
SKIP_BWS=0
SKIP_LINEAR=0
SKIP_JIRA=0
AUTH_INCOMPLETE=0
AUTH_EMAIL="${AUTH_EMAIL:-}"
BWS_ACCOUNT="${BWS_ACCOUNT:-personal}"
if [[ -x "$HOME/.opencode/bin/opencode" ]]; then
    OPENCODE_BIN="$HOME/.opencode/bin/opencode"
else
    OPENCODE_BIN="$(command -v opencode 2>/dev/null || true)"
fi
ROOT_RUNNER=run_sudo
export ROOT_RUNNER

trap 'on_error' ERR

usage() {
    cat <<'EOF'
Usage: provisioning/arch/auth.sh [options]

Options:
  --check             Report missing authentication without changing anything
  --dry-run           Print actions without changing anything
  --generate-key      Generate ~/.ssh/id_ed25519 if it does not exist (on WSL,
                      import it into the Bitwarden vault, then remove the private
                      half from WSL)
  --email EMAIL       Email address for the SSH key comment
  --non-interactive   Skip steps that need a browser or TTY; report them instead
  --skip-gh           Do not configure or authenticate the GitHub CLI
  --skip-gcloud       Do not configure or authenticate the gcloud CLI
  --skip-tailscale    Do not authenticate Tailscale
  --skip-bws          Do not set up the Bitwarden Secrets Manager token
  --bws-account NAME  GNOME Keyring account label for the BWS token
                      (default: personal)
  --skip-linear       Do not authenticate the Linear MCP server
  --skip-jira         Do not authenticate the Jira MCP server
  --skip-mcp          Do not authenticate the Linear or Jira MCP servers
  -h, --help          Show this help

What this does:
  - ensures the per-machine SSH public key is available
  - uses the Windows Bitwarden agent relay (WSL) or the session agent
  - authenticates `gh` for personal GitHub and uploads the key
  - uploads the same key as a GitHub signing key
  - authenticates `gcloud` and application default credentials
  - authenticates Tailscale when its daemon is running
  - offers to store the Bitwarden Secrets Manager token in GNOME Keyring
  - authenticates the Linear and Jira MCP servers in OpenCode
  - prints Cloud Source Repositories SSH registration instructions for work

SSH commit signing is configured by chezmoi. Work projects under
~/Projects/work/ use the work email from the chezmoi data and the same SSH key.
EOF
}

mcp_list_output() {
    "$OPENCODE_BIN" mcp list 2>/dev/null
}

mcp_matches() {
    local output="$1" name="$2" state="$3"
    grep -Eq "(^|[[:space:]])${name}[[:space:]]+${state}([[:space:]]|$)" <<<"$output"
}

authenticate_mcp() {
    local name="$1" label="$2" output
    local state_text

    if ! output="$(mcp_list_output)"; then
        warn "$label MCP status check failed; run: opencode mcp list"
        AUTH_INCOMPLETE=1
        return
    fi

    if mcp_matches "$output" "$name" "connected"; then
        log "$label MCP is already connected"
        return
    fi

    if mcp_matches "$output" "$name" "needs authentication"; then
        state_text="needs authentication"
    else
        state_text="not waiting for authentication"
    fi

    if ((DRY_RUN || NON_INTERACTIVE)); then
        warn "$label MCP $state_text; run: opencode mcp auth $name"
        AUTH_INCOMPLETE=1
        return
    fi

    if [[ "$state_text" != "needs authentication" ]]; then
        warn "$label MCP is $state_text; check: opencode mcp list"
        AUTH_INCOMPLETE=1
        return
    fi

    log "Authenticating $label MCP in OpenCode (a browser window will open)"
    if ! "$OPENCODE_BIN" mcp auth "$name"; then
        warn "$label MCP authentication failed; retry: opencode mcp auth $name"
        AUTH_INCOMPLETE=1
        return
    fi

    if output="$(mcp_list_output)" && mcp_matches "$output" "$name" "connected"; then
        log "$label MCP connected"
    else
        warn "$label MCP is still not connected; check: opencode mcp list"
        AUTH_INCOMPLETE=1
    fi
}

bws_token_shape_ok() {
    local token="$1"

    # Machine-account access tokens are long and start with "0.".
    [[ "$token" == 0.* && ${#token} -ge 40 ]]
}

bws_token_present() {
    # `secret-tool search` exits 0 even when nothing matches, so inspect the
    # output for an item path. Search reports locked items without unlocking.
    command -v secret-tool >/dev/null 2>&1 &&
        secret-tool search --all service bws account "$BWS_ACCOUNT" 2>/dev/null |
        grep -q '^\['
}

legacy_pass_token_present() {
    local store_dir="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
    [[ -f "$store_dir/bitwarden/bws-token.gpg" ]]
}

store_bws_token() {
    local stored

    if ! command -v secret-tool >/dev/null 2>&1; then
        warn "secret-tool is not installed; run provisioning/arch/bootstrap.sh"
        return 1
    fi
    log "Storing the BWS access token in GNOME Keyring"
    log "Paste the token at both prompts (input is hidden)"
    if ! secret-tool store --label='BWS access token' service bws account "$BWS_ACCOUNT"; then
        warn "could not store the BWS token in GNOME Keyring"
        return 1
    fi
    if ! stored="$(secret-tool lookup service bws account "$BWS_ACCOUNT" 2>/dev/null)" ||
        ! bws_token_shape_ok "$stored"; then
        warn "the value in GNOME Keyring does not look like a BWS access token"
        warn "replace it with: secret-tool store --label='BWS access token' service bws account $BWS_ACCOUNT"
        return 1
    fi
}

gh_key_exists() {
    local endpoint="$1" key="$2"
    gh api --paginate "$endpoint" --jq '.[].key' 2>/dev/null | grep -Fxq "$key"
}

gh_has_scopes() {
    local status
    status="$(gh auth status --hostname github.com 2>&1 || true)"
    [[ "$status" == *"admin:public_key"* && "$status" == *"admin:ssh_signing_key"* ]]
}

ensure_gh_key() {
    local type="$1" endpoint="$2" title_suffix="$3" label="$4"

    if gh_key_exists "$endpoint" "$public_key"; then
        log "$label SSH key is already registered on GitHub"
        return 0
    fi

    if ((DRY_RUN)); then
        warn "$label SSH key is not registered on GitHub; would upload it"
        AUTH_INCOMPLETE=1
        return 1
    fi

    if gh ssh-key add "${KEY}.pub" \
        --title "$(uname -n)-${title_suffix}" --type "$type"; then
        log "$label SSH key registered on GitHub"
    else
        warn "could not register the $label SSH key on GitHub"
        AUTH_INCOMPLETE=1
        return 1
    fi
}

while (($# > 0)); do
    case "$1" in
    --check)
        CHECK_ONLY=1
        DRY_RUN=1
        shift
        ;;
    --dry-run)
        DRY_RUN=1
        shift
        ;;
    --generate-key)
        GENERATE_KEY=1
        shift
        ;;
    --email)
        [[ $# -ge 2 ]] || die "--email requires an argument"
        AUTH_EMAIL="$2"
        shift 2
        ;;
    --email=*)
        AUTH_EMAIL="${1#*=}"
        shift
        ;;
    --non-interactive)
        NON_INTERACTIVE=1
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
    --skip-bws)
        SKIP_BWS=1
        shift
        ;;
    --bws-account)
        [[ $# -ge 2 ]] || die "--bws-account requires an argument"
        BWS_ACCOUNT="$2"
        shift 2
        ;;
    --bws-account=*)
        BWS_ACCOUNT="${1#*=}"
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

for cmd in git ssh-keygen uname; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        warn "required command not found: $cmd"
        AUTH_INCOMPLETE=1
    fi
done

if ((DRY_RUN == 0)); then
    umask 077
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
fi

email="${AUTH_EMAIL:-$(git config --global --get user.email 2>/dev/null || true)}"
if [[ -z "$email" ]]; then
    if ((NON_INTERACTIVE || DRY_RUN)) || [[ ! -t 0 ]]; then
        warn "no email for the SSH key comment; pass --email or set git user.email"
        AUTH_INCOMPLETE=1
    else
        read -r -p "Email address for the SSH key comment: " email
    fi
fi
if [[ -z "$email" ]] && ((DRY_RUN == 0)); then
    die "an email address is required for the SSH key comment"
fi
if [[ -n "$email" && "$email" =~ [[:space:]] ]]; then
    die "email address must not contain whitespace"
fi

have_key=0
have_pub=0
if [[ -f "$KEY" ]]; then
    have_key=1
fi
if [[ -f "${KEY}.pub" ]]; then
    have_pub=1
fi

if ((have_key == 0 && have_pub == 0)); then
    if ((GENERATE_KEY)); then
        if ((DRY_RUN || NON_INTERACTIVE)); then
            warn "SSH key is missing; rerun interactively with --generate-key"
            AUTH_INCOMPLETE=1
        else
            log "Generating a new ed25519 SSH key at $KEY"
            ssh-keygen -t ed25519 -a 100 -C "${email:-$USER}" -f "$KEY"
            have_key=1
        fi
    else
        warn "SSH key not found: ${KEY}.pub (rerun with --generate-key or restore your key)"
        AUTH_INCOMPLETE=1
    fi
fi

if ((have_key)); then
    if ((DRY_RUN == 0)); then
        chmod 600 "$KEY"
    fi

    if [[ ! -f "${KEY}.pub" ]]; then
        if ((DRY_RUN || NON_INTERACTIVE)); then
            warn "public key is missing: ${KEY}.pub; rerun interactively to derive it"
            AUTH_INCOMPLETE=1
        else
            log "Deriving public key from $KEY"
            ssh-keygen -y -f "$KEY" >"${KEY}.pub"
            chmod 644 "${KEY}.pub"
        fi
    fi
fi

[[ -f "${KEY}.pub" ]] && have_pub=1

public_key=""
if ((have_pub)); then
    public_key="$(awk '{print $1, $2}' "${KEY}.pub")"
fi

if ((have_pub)) && ! command -v ssh-add >/dev/null 2>&1; then
    warn "ssh-add is not installed; cannot inspect the ssh-agent"
    AUTH_INCOMPLETE=1
fi

# Make local `git log --show-signature` verification work for both identities.
work_email="$(git config --file "$HOME/.config/git/work.inc" --get user.email 2>/dev/null || true)"
if ((have_pub)) && [[ -n "$email" ]]; then
    if ((DRY_RUN)); then
        log "Would update $HOME/.config/git/allowed_signers"
    else
        mkdir -p "$HOME/.config/git"
        {
            printf '%s %s\n' "$email" "$public_key"
            [[ -n "$work_email" ]] && printf '%s %s\n' "$work_email" "$public_key"
        } >"$HOME/.config/git/allowed_signers"
        chmod 644 "$HOME/.config/git/allowed_signers"
    fi
fi

if ((have_pub)) && command -v ssh-add >/dev/null 2>&1; then
    agent_socket=""
    agent_ready=0
    agent_exported=0

    if is_wsl; then
        # The Windows Bitwarden agent owns the key; the relay only exposes its
        # pipe as a Unix socket.
        relay_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        agent_socket="$relay_dir/ssh-agent.sock"

        if [[ ! -S "$agent_socket" ]]; then
            if ((DRY_RUN)); then
                warn "Windows SSH agent relay is not running; would run: systemctl --user enable --now ssh-agent-bridge.service"
                AUTH_INCOMPLETE=1
            elif ! command -v systemctl >/dev/null 2>&1 ||
                ! systemctl --user show-environment >/dev/null 2>&1; then
                warn "Windows SSH agent relay is not running; start ssh-agent-bridge manually"
                AUTH_INCOMPLETE=1
            elif systemctl --user enable --now ssh-agent-bridge.service >/dev/null 2>&1; then
                log "Started ssh-agent-bridge.service"
            else
                warn "could not start ssh-agent-bridge.service; run provisioning/arch/bootstrap.sh"
                AUTH_INCOMPLETE=1
            fi
        fi

        if [[ -S "$agent_socket" ]]; then
            previous_socket="${SSH_AUTH_SOCK:-}"
            export SSH_AUTH_SOCK="$agent_socket"
            unset SSH_AGENT_PID
            agent_ready=1
            if [[ "$previous_socket" != "$agent_socket" ]]; then
                agent_exported=1
            fi
        fi
    elif [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
        # Native systems use the session agent, normally GNOME Keyring.
        agent_socket="$SSH_AUTH_SOCK"
        agent_status=0
        ssh-add -l >/dev/null 2>&1 || agent_status=$?
        if [[ "$agent_status" -eq 0 || "$agent_status" -eq 1 ]]; then
            agent_ready=1
        fi
    else
        warn "no SSH agent in this session; start one (GNOME Keyring provides it)"
        AUTH_INCOMPLETE=1
    fi

    key_fingerprint="$(ssh-keygen -lf "${KEY}.pub" | awk '{print $2}')"
    if ((agent_ready)); then
        agent_keys="$(ssh-add -l 2>/dev/null || true)"
        if grep -qF "$key_fingerprint" <<<"$agent_keys"; then
            log "SSH key is available from the agent"
        elif is_wsl; then
            warn "SSH key is not available from the Bitwarden agent"
            warn "  import the matching private key into Bitwarden, unlock the vault, and approve the request"
            AUTH_INCOMPLETE=1
        elif ((have_key == 0)); then
            warn "SSH private key is missing; the native agent cannot load it"
            AUTH_INCOMPLETE=1
        elif ((DRY_RUN)); then
            warn "SSH key is not loaded; would run: ssh-add $KEY"
            AUTH_INCOMPLETE=1
        elif ((NON_INTERACTIVE)) || [[ ! -t 0 ]]; then
            warn "SSH key is not loaded; run 'ssh-add $KEY' in a terminal"
            AUTH_INCOMPLETE=1
        elif ! ssh-add "$KEY"; then
            warn "could not load $KEY into the ssh-agent"
            AUTH_INCOMPLETE=1
        fi
    fi

    if is_wsl; then
        vscode_setup="$HOME/.vscode-server/server-env-setup"
        if cmp -s "$REPO_ROOT/provisioning/arch/system/vscode-server-env-setup.sh" "$vscode_setup"; then
            log "$vscode_setup is up to date"
        elif ((DRY_RUN)); then
            log "Would install $vscode_setup for the VS Code Remote-WSL server"
        else
            install -Dm644 "$REPO_ROOT/provisioning/arch/system/vscode-server-env-setup.sh" "$vscode_setup"
            log "Installed $vscode_setup for the VS Code Remote-WSL server"
        fi
    fi

    log "SSH key fingerprint: $key_fingerprint"
    if ((agent_exported)); then
        log "SSH agent socket: $SSH_AUTH_SOCK (new fish shells pick it up automatically)"
        log "For the current fish shell: set -gx SSH_AUTH_SOCK '$SSH_AUTH_SOCK'"
    fi
fi

if ((SKIP_GH == 0)); then
    if ! command -v gh >/dev/null 2>&1; then
        warn "gh is not installed; run provisioning/arch/bootstrap.sh and rerun this script"
        AUTH_INCOMPLETE=1
    elif ! gh auth status --hostname github.com >/dev/null 2>&1; then
        if ((DRY_RUN || NON_INTERACTIVE)); then
            warn "GitHub CLI is not authenticated; run: gh auth login"
            AUTH_INCOMPLETE=1
        else
            log "Authenticating GitHub CLI with the SSH Git protocol"
            if ! gh auth login --hostname github.com --git-protocol ssh --web \
                --scopes admin:public_key,admin:ssh_signing_key; then
                warn "GitHub CLI authentication failed"
                AUTH_INCOMPLETE=1
            fi
        fi
    elif ! gh_has_scopes; then
        if ((DRY_RUN || NON_INTERACTIVE)); then
            warn "GitHub CLI token is missing admin:public_key or admin:ssh_signing_key"
            AUTH_INCOMPLETE=1
        else
            log "Refreshing GitHub CLI scopes for SSH key management"
            if ! gh auth refresh --hostname github.com \
                --scopes admin:public_key,admin:ssh_signing_key; then
                warn "could not refresh GitHub CLI scopes"
                AUTH_INCOMPLETE=1
            fi
        fi
    else
        log "GitHub CLI is already authenticated with the required scopes"
    fi

    if command -v gh >/dev/null 2>&1; then
        if gh auth status --hostname github.com >/dev/null 2>&1; then
            if [[ -n "$public_key" ]]; then
                ensure_gh_key authentication user/keys auth "authentication" || true
                ensure_gh_key signing user/ssh_signing_keys signing "signing" || true
            else
                warn "cannot register the GitHub SSH key without a public key"
                AUTH_INCOMPLETE=1
            fi
        fi
    fi
fi

if ((SKIP_GCLOUD == 0)); then
    if ! command -v gcloud >/dev/null 2>&1; then
        warn "gcloud is not installed; run provisioning/arch/bootstrap.sh and rerun this script"
        AUTH_INCOMPLETE=1
    else
        active_account="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1 || true)"
        if [[ -z "$active_account" ]]; then
            if ((DRY_RUN || NON_INTERACTIVE)); then
                warn "gcloud is not authenticated; run: gcloud auth login"
                AUTH_INCOMPLETE=1
            else
                log "Authenticating gcloud (OAuth; SSH is not used for gcloud CLI auth)"
                if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
                    gcloud auth login --no-launch-browser || AUTH_INCOMPLETE=1
                else
                    gcloud auth login || AUTH_INCOMPLETE=1
                fi
            fi
        else
            log "gcloud is already authenticated as $active_account"
        fi

        if [[ -z "$(gcloud auth application-default print-access-token 2>/dev/null || true)" ]]; then
            if ((DRY_RUN || NON_INTERACTIVE)); then
                warn "gcloud application default credentials are missing; run: gcloud auth application-default login"
                AUTH_INCOMPLETE=1
            else
                log "Configuring gcloud application default credentials"
                if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
                    gcloud auth application-default login --no-launch-browser ||
                        AUTH_INCOMPLETE=1
                else
                    gcloud auth application-default login || AUTH_INCOMPLETE=1
                fi
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
        warn "tailscale is not installed; run provisioning/arch/bootstrap.sh and rerun this script"
        AUTH_INCOMPLETE=1
    elif ! command -v jq >/dev/null 2>&1; then
        warn "jq is not installed; cannot inspect Tailscale state"
        AUTH_INCOMPLETE=1
    elif [[ ! -S /var/run/tailscale/tailscaled.sock && ! -S /run/tailscale/tailscaled.sock ]]; then
        AUTH_INCOMPLETE=1
        if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
            log "Tailscale daemon is not running in WSL. Start it with:"
            log "  sudo tailscaled >/tmp/tailscaled.log 2>&1 &"
            log "Then rerun: ./provisioning/arch/auth.sh --skip-gh --skip-gcloud"
            log "Or enable systemd in WSL and rerun bootstrap."
        else
            warn "tailscaled is not running; start it with: sudo systemctl start tailscaled"
        fi
    else
        if ! tailscale_state="$(tailscale status --json 2>/dev/null | jq -r '.BackendState // empty')"; then
            warn "could not read Tailscale state"
            AUTH_INCOMPLETE=1
            tailscale_state=""
        fi

        if [[ "$tailscale_state" == "Running" ]]; then
            log "Tailscale is already connected"
        elif ((DRY_RUN || NON_INTERACTIVE)); then
            warn "Tailscale is not connected (state: ${tailscale_state:-unknown}); run: sudo tailscale up"
            AUTH_INCOMPLETE=1
        else
            log "Authenticating Tailscale (current state: ${tailscale_state:-unknown})"
            run_optional sudo tailscale up || AUTH_INCOMPLETE=1
        fi

        if ((DRY_RUN || NON_INTERACTIVE)); then
            log "Would ensure Tailscale operator is $(id -un)"
        elif ! run_optional sudo tailscale set --operator="$(id -un)"; then
            warn "could not set Tailscale operator"
            AUTH_INCOMPLETE=1
        fi
    fi
fi

if ((SKIP_BWS == 0)); then
    if ! command -v bws >/dev/null 2>&1; then
        warn "bws is not installed; run provisioning/arch/bootstrap.sh and rerun this script"
        AUTH_INCOMPLETE=1
    elif ! command -v secret-tool >/dev/null 2>&1; then
        warn "secret-tool is not installed; run provisioning/arch/bootstrap.sh"
        AUTH_INCOMPLETE=1
    elif ! ensure_login_keyring; then
        warn "the GNOME Keyring login keyring is not ready; run provisioning/arch/bootstrap.sh"
        AUTH_INCOMPLETE=1
    elif bws_token_present; then
        log "Bitwarden Secrets Manager token is already stored (replace: secret-tool store --label='BWS access token' service bws account $BWS_ACCOUNT)"
    elif legacy_pass_token_present; then
        warn "legacy pass entry found at ${PASSWORD_STORE_DIR:-$HOME/.password-store}/bitwarden/bws-token.gpg"
        warn "migrate it with:"
        warn "  pass show bitwarden/bws-token | secret-tool store --label='BWS access token' service bws account $BWS_ACCOUNT"
        warn "  pass rm -f bitwarden/bws-token"
        AUTH_INCOMPLETE=1
    elif ((DRY_RUN || NON_INTERACTIVE)) || [[ ! -t 0 ]]; then
        warn "BWS token is not stored; rerun interactively or see README: Bitwarden Secrets Manager"
        AUTH_INCOMPLETE=1
    else
        read -r -p "Store the Bitwarden Secrets Manager access token now? [y/N] " bws_answer
        if [[ "$bws_answer" =~ ^[Yy]$ ]]; then
            if store_bws_token; then
                log "Bitwarden Secrets Manager token stored"
            else
                warn "could not store the BWS token; see README: Bitwarden Secrets Manager"
                AUTH_INCOMPLETE=1
            fi
        else
            log "Skipping BWS token setup; see README: Bitwarden Secrets Manager"
        fi
    fi
fi

if ((SKIP_LINEAR == 0 || SKIP_JIRA == 0)); then
    if [[ -z "$OPENCODE_BIN" ]]; then
        warn "opencode is not installed; run provisioning/arch/bootstrap.sh and rerun this script"
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
    if ((CHECK_ONLY)); then
        log "Authentication check incomplete; review the warnings above."
    else
        log "Authentication setup incomplete; review the warnings above."
    fi
    exit 1
fi

if ((CHECK_ONLY)); then
    log "Authentication check complete."
elif ((DRY_RUN)); then
    log "Authentication dry run complete; no changes were made."
else
    log "Authentication setup complete."
    log "Commit signing is enabled globally by chezmoi; work email applies under ~/Projects/work/."
fi
