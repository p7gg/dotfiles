# Authentication and SSH

Chezmoi configures SSH commit signing globally with
`~/.ssh/id_ed25519.pub`. It also changes `user.email` under
`~/Projects/work/` through `~/.config/git/work.inc`, populated from the
`work_email` prompt during `chezmoi init`.

Personal GitHub and work Google Cloud Source Repositories both use the same
per-machine SSH key:

- `github.com` for personal repositories and `gh`
- `source.developers.google.com:2022` for work Cloud Source Repositories,
  with `User` set to the work email

If you prefer stronger isolation, use separate personal/work keys and adjust the
two `Host` entries and `provisioning/arch/auth.sh`; this setup intentionally keeps it simple
with one key.

Inspect authentication without changing anything:

```bash
./provisioning/arch/auth.sh --check
```

Run the interactive auth helper once per machine:

```bash
./provisioning/arch/auth.sh --generate-key
```

It will:

- generate a per-machine ed25519 key if one does not exist
- load it into an ssh-agent
- authenticate `gh` for personal GitHub with the SSH Git protocol
- add the key to personal GitHub for both authentication and signing
- authenticate `gcloud` and application default credentials
- authenticate Tailscale when the daemon is running
- offer to store the Bitwarden Secrets Manager token in GNOME Keyring or `pass`
- authenticate the Linear and Jira MCP servers in OpenCode with OAuth
- print the key fingerprint and the Cloud Source Repositories registration URL

The helper skips MCP sign-in when a server is already connected. Use
`--skip-mcp`, `--skip-linear`, or `--skip-jira` to skip those steps; Context7
needs no sign-in. Use `--skip-bws` to leave the BWS token setup manual, and
`--bws-account NAME` if your native keyring label is not `personal` (WSL always
uses the single `pass` entry `bitwarden/bws-token`, so the flag has no effect
there). For non-interactive runs, pass `--email` and `--non-interactive`; steps
that need a browser or TTY are reported instead of prompted for. Native GNOME
already has an SSH agent through gnome-keyring. On WSL, bootstrap installs the
Windows bridge described below and the helper loads the key there; the stock
`ssh-agent.socket` unit is not used, so there is exactly one agent per Windows
session. Fish exports the bridge socket in new shells and runs `ssh-add` when
the agent is empty, so a protected key prompts once per Windows boot. There is
no socket cache to go stale across restarts. The helper also installs
`~/.vscode-server/server-env-setup`, which gives the Remote-WSL server the same
socket and asks for the passphrase through a WSLg dialog when no terminal has
loaded the key yet.

Processes that do not start from fish (the T3 and OpenCode servers, systemd user
scopes) do not inherit `SSH_AUTH_SOCK`. On WSL, `~/.ssh/config` therefore points
`IdentityAgent` at the bridge socket, so `ssh` and Git's transport find the key
without the variable.

`IdentityAgent` does not cover commit signing. Git and GitButler sign by running
`ssh-keygen -Y sign`, and `ssh-keygen` does not read `~/.ssh/config`; it only
consults `SSH_AUTH_SOCK`. Without that variable it falls back to the
passphrase-protected private key and opens an askpass dialog that a T3 or
OpenCode session cannot see, so the commit appears to hang. `gpg.ssh.program`
therefore points at `~/.local/bin/git-ssh-sign.sh`, which exports the bridge
socket when it is missing and, when no terminal is attached, fails instead of
prompting.

### Windows SSH agent bridge (WSL)

Bootstrap installs `wsl2-ssh-agent` into `~/.local/bin` from a pinned upstream
release after verifying its SHA-256, and enables the
`wsl2-ssh-agent.service` user unit. The bridge forwards the agent protocol to
the Windows OpenSSH Authentication Agent, so one key works in Windows and WSL,
and it survives WSL restarts.

Prerequisites, once per Windows machine: install the OpenSSH Client optional
feature and start its agent service from an elevated PowerShell:

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
Set-Service -Name ssh-agent -StartupType Automatic
Start-Service ssh-agent
```

The socket is `$XDG_RUNTIME_DIR/wsl2-ssh-agent.sock`. Fish exports it, and
`~/.ssh/config` points `IdentityAgent` at it for processes that do not inherit
the variable. Bootstrap enables the unit only when the Windows `ssh-agent`
service is running. Load the key into the Windows agent once per Windows login;
from WSL, so the private key stays in the WSL filesystem:

```bash
SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/wsl2-ssh-agent.sock" ssh-add ~/.ssh/id_ed25519
```

The ArchWiki's PAM Windows Hello setup is separate: it authenticates `sudo` and
other PAM services through Windows Hello. It does not expose an SSH agent, load
a key, or affect commit signing.

The bridge runs PowerShell in the background and adds a small delay to the
first agent operation after it starts. While it is active, every WSL process
can use every key held by the Windows agent: keep only the per-machine key
there, and do not load work or security-key credentials you would not expose to
WSL.

Work Cloud Source Repositories setup is partly manual because Google does not
provide a CLI command to register an SSH key for Cloud Source Repositories.
The helper prints the steps:

1. Run `gcloud auth login` (the helper does this).
2. Open <https://source.cloud.google.com/user/ssh_keys>.
3. Register the contents of `~/.ssh/id_ed25519.pub`.
4. Clone with SSH:
   ```bash
   git clone ssh://<work-email>@source.developers.google.com:2022/p/PROJECT_ID/r/REPO_NAME
   ```

Notes:

- `gh` itself authenticates with OAuth, but personal Git operations use SSH.
  The helper requests `admin:public_key` and `admin:ssh_signing_key` explicitly
  so it can register both the authentication and signing keys.
- `gcloud` CLI authentication is **OAuth, not SSH**. `gcloud source repos clone`
  uses that OAuth path. The SSH key is for the direct `git clone ssh://...`
  path and for Compute Engine VM access.
- The helper also configures application default credentials via
  `gcloud auth application-default login`, which is what Terraform and Google
  client libraries use.
- Tailscale is authenticated with `tailscale up` when its daemon is running.
  On WSL without systemd, start it manually first:
  ```bash
  sudo tailscaled >/tmp/tailscaled.log 2>&1 &
  sudo tailscale up
  ```
  With WSL systemd enabled, bootstrap can enable `tailscaled.service` directly.
- `~/.ssh/config` resolves Tailscale peer names from `tailscaled`'s peer list
  and proxies them with `tailscale nc`, so `ssh user@laptop` works without
  local MagicDNS resolution. This is a client-side alias only; the destination
  still needs a normal `sshd` and user account, and it does not enable the
  Tailscale SSH server.
- `gcloud compute config-ssh` is for Compute Engine VMs, not Cloud Source
  Repositories.
- Commits and tags are signed by default. Personal GitHub commits can show as
  verified after the key is registered as a signing key. Work commits use the
  work email and the same signing key; Cloud Source Repositories does not use
  GitHub's verification flow. The helper also writes
  `~/.config/git/allowed_signers`, so local `git log --show-signature`
  verification works for both identities.
- Useful checks:

```bash
ssh-add -l
gh auth status
git config --show-origin --get gpg.format
git config --show-origin --get user.signingkey
gcloud auth list
ssh -T git@github.com
ssh -p 2022 -T <work-email>@source.developers.google.com
```

If you prefer to manage authentication yourself, use the individual commands
above; the helper only automates them. It exits nonzero when a required
component is missing or a requested authentication step is incomplete; use
`--skip-gh`, `--skip-gcloud`, `--skip-tailscale`, `--skip-mcp`,
`--skip-bws`, `--skip-linear`, or `--skip-jira` for intentional skips.

## Commit signing troubleshooting

A commit that waits for a passphrase, or an agent that disables signing to avoid
the prompt, usually means `ssh-keygen` could not reach an agent. Check the
configuration and the bridge:

```bash
git config --show-origin --get gpg.format
git config --show-origin --get user.signingkey
git config --show-origin --get gpg.ssh.program
systemctl --user status wsl2-ssh-agent.service
SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/wsl2-ssh-agent.sock" ssh-add -l
```

`gpg.ssh.program` should point at `~/.local/bin/git-ssh-sign.sh`, and
`ssh-add -l` should list the key. If the agent is empty, load the key from a
terminal:

```bash
SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/wsl2-ssh-agent.sock" ssh-add ~/.ssh/id_ed25519
```

If the bridge unit is not running, start it:

```bash
systemctl --user enable --now wsl2-ssh-agent.service
```

GitButler has its own override, `gitbutler.signCommits`, which takes precedence
over `commit.gpgsign`. If `git commit` signs but `but commit` does not, check the
local value and remove the override (or set it to `true`):

```bash
git config --show-origin --get gitbutler.signCommits
```

Do not work around signing failures with `commit.gpgsign=false`,
`gitbutler.signCommits=false`, or by temporarily disabling signing; that leaves
unsigned commits and hides the real problem.

## Bitwarden Secrets Manager

`bws-bin` is tracked in `provisioning/arch/packages/aur.txt`. The fish wrapper in
`home/dot_config/fish/functions/bws.fish` loads the token from GNOME Keyring
(native) or `pass` (WSL) and exports it only for the `bws` process. Run
`provisioning/arch/auth.sh` to store it, or see
[the secrets section in tips-and-tricks.md](tips-and-tricks.md#secrets-not-plaintext-at-rest)
for the manual commands and operational notes.

`--bws-account NAME` selects the GNOME Keyring label on native systems only. WSL
always reads the single `pass` entry at `bitwarden/bws-token`, so the wrapper's
WSL error message does not suggest `--bws-account`.

On WSL, `pass` also needs a GPG key and an initialized password store. If you do
not have a key yet:

```bash
gpg --full-generate-key
gpg --list-secret-keys --keyid-format=long
pass init <gpg-key-id>
```

`provisioning/arch/auth.sh` initializes an empty store automatically when exactly
one GPG secret key exists; otherwise it prints the `pass init <gpg-key-id>`
command to run. When the helper asks whether to store the token, answer `y`;
`pass` then prompts twice, and you paste the machine-account access token (a long
string starting with `0.`) at both prompts. Input is hidden.

`--check` only verifies that the `pass` entry exists; it does not decrypt or
validate it. If a wrong value is stored, replace it directly:

```bash
pass insert -f bitwarden/bws-token
bws -o none project list
```

`bws -o none project list` exercises the token through the fish wrapper without
printing secrets. Use `pass rm bitwarden/bws-token` first if you want
`provisioning/arch/auth.sh` to prompt for the token again.

## Back to

- [Documentation index](README.md)
- [Project README](../README.md)
