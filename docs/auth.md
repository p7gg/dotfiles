# Authentication and SSH

Chezmoi configures SSH commit signing globally with
`~/.ssh/id_ed25519.pub`. It also changes `user.email` under
`~/Projects/work/` through `~/.config/git/work.inc`, populated from the
`work_email` prompt during `chezmoi init`.

Personal GitHub and work Google Cloud Source Repositories both use the same
per-machine SSH key. On native Arch the private key lives in `~/.ssh` and is
loaded by GNOME Keyring; on WSL the same key is stored in the Bitwarden Password
Manager vault and served by the Bitwarden agent:

- `github.com` for personal repositories and `gh`
- `source.developers.google.com:2022` for work Cloud Source Repositories,
  with `User` set to the work email

GNOME Keyring is also the Secret Service on both profiles; on WSL it runs only
the secrets component, so the SSH agent remains Bitwarden. See
[GNOME Keyring](#gnome-keyring-both-profiles).

If you prefer stronger isolation, use separate personal/work keys and adjust the
two `Host` entries; Bitwarden can hold both, but its agent has no per-request key
selection, so use `IdentityFile`/`IdentitiesOnly` to choose the offered key.

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
- verify the key is available from the session agent or the Bitwarden agent
- authenticate `gh` for personal GitHub with the SSH Git protocol
- add the key to personal GitHub for both authentication and signing
- authenticate `gcloud` and application default credentials
- authenticate Tailscale when the daemon is running
- offer to store the Bitwarden Secrets Manager token in GNOME Keyring
- authenticate the Linear MCP server from `~/Projects` and the Jira MCP server
  from `~/Projects/work` with OAuth
- print the key fingerprint and the Cloud Source Repositories registration URL

The helper skips MCP sign-in when a server is already connected. Use
`--skip-mcp`, `--skip-linear`, or `--skip-jira` to skip those steps; Context7
needs no sign-in. Use `--skip-bws` to leave the BWS token setup manual, and
`--bws-account NAME` if your keyring label is not `personal`. For non-interactive
runs, pass `--email` and `--non-interactive`; steps that need a browser or TTY
are reported instead of prompted for. Native GNOME already has an SSH agent
through gnome-keyring. On WSL, the Windows **Bitwarden Password Manager** desktop
app is the agent; GNOME Keyring runs only its secrets component there, and the
`bws` Secrets Manager CLI is not an SSH agent. The private key lives in the
Bitwarden vault, not in the WSL filesystem.
Fish exports the relay socket in new shells, and the helper installs
`~/.vscode-server/server-env-setup` so the Remote-WSL server inherits it.

Processes that do not start from fish (the T3 and OpenCode servers, systemd user
scopes) do not inherit `SSH_AUTH_SOCK`. On WSL, `~/.ssh/config` therefore points
`IdentityAgent` at the relay socket, so `ssh` and Git's transport find the agent
without the variable.

`IdentityAgent` does not cover commit signing. Git and GitButler sign by running
`ssh-keygen -Y sign`, and `ssh-keygen` does not read `~/.ssh/config`; it only
consults `SSH_AUTH_SOCK`. `gpg.ssh.program` therefore points at
`~/.local/bin/git-ssh-sign.sh`, which exports the relay socket when it is
missing and, when no terminal is attached, fails instead of prompting.

### Windows SSH agent relay (WSL)

The agent is the **Bitwarden Password Manager desktop app** on Windows. Enable
**Settings → App settings (all accounts) → Enable SSH agent**, then set **Ask
for authorization when using SSH agent**:

- `Always` asks on every request. It will block T3/OpenCode commits.
- `Remember until vault is locked` asks once per session and is the recommended
  balance.
- `Never` signs silently while the vault is unlocked; use it only for unattended
  agent commits or if you accept that any WSL process can sign.

The Windows OpenSSH Authentication Agent service must be disabled so Bitwarden
can own `\\.\pipe\openssh-ssh-agent`:

```powershell
Set-Service -Name ssh-agent -StartupType Disabled
Stop-Service -Name ssh-agent
```

Bootstrap installs `socat` and enables the `ssh-agent-bridge.service` user unit.
The unit runs `~/.local/bin/ssh-agent-bridge`, which finds `npiperelay.exe` on
the Windows side and exposes the pipe at `$XDG_RUNTIME_DIR/ssh-agent.sock`
(mode `0600`). Install npiperelay once from Windows:

```powershell
winget install --id albertony.npiperelay -e
```

The relay is per-connection: when Bitwarden is closed or the Windows pipe is
unavailable, the client fails fast instead of waiting on a PowerShell child.
When the vault is locked, Bitwarden prompts locally to unlock it. Check the
relay with:

```bash
systemctl --user status ssh-agent-bridge.service
SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.sock" ssh-add -l
ssh-add.exe -l
```

Import the key into Bitwarden once (Vault → New → SSH key → **Import**), then
remove the private key from WSL and keep `~/.ssh/id_ed25519.pub` for
`user.signingkey` and `allowed_signers`. `ssh-add` cannot add or remove keys in
Bitwarden; the vault is the source of truth.

Windows Hello unlock is optional: **File → Settings → Security → Unlock with
Windows Hello**. It only appears when Windows Hello is enabled at the OS level,
and some builds do not support biometric unlock.

The ArchWiki's PAM Windows Hello setup is separate: it authenticates `sudo` and
other PAM services through Windows Hello. It does not expose an SSH agent, load
a key, or affect commit signing.

While the relay is active, every WSL process that can reach the socket can ask
Bitwarden to sign with every key the agent offers. Set the authorization policy
deliberately, keep work and personal keys separate, and do not enable
`ForwardAgent` for untrusted hosts.

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

### SSH multiplexing

`ControlMaster` keeps one connection per `%C` hash. The socket lives under
`$XDG_RUNTIME_DIR`, so a WSL restart or logout clears it. If a master is left
behind — or is still alive after its original client is gone — SSH can report
`PERMISSION_DENIED` or `ControlSocket ... already exists` for every remote.
Close a specific master with `ssh -O exit <host>`, or remove the sockets when no
SSH session is active:

```bash
ssh -O exit git@github.com
rm -f "$XDG_RUNTIME_DIR"/ssh-control-* ~/.ssh/control-*
```

Cloud Source Repositories opts out of multiplexing (`ControlMaster no`,
`ControlPath none`) because its SSH endpoint returns `PERMISSION_DENIED` when a
persisted master outlives its client.

If you prefer to manage authentication yourself, use the individual commands
above; the helper only automates them. It exits nonzero when a required
component is missing or a requested authentication step is incomplete; use
`--skip-gh`, `--skip-gcloud`, `--skip-tailscale`, `--skip-mcp`,
`--skip-bws`, `--skip-linear`, or `--skip-jira` for intentional skips.

## Commit signing troubleshooting

A commit that waits for a passphrase, or an agent that disables signing to avoid
the prompt, usually means `ssh-keygen` could not reach an agent. Check the
configuration and the relay:

```bash
git config --show-origin --get gpg.format
git config --show-origin --get user.signingkey
git config --show-origin --get gpg.ssh.program
systemctl --user status ssh-agent-bridge.service
SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/ssh-agent.sock" ssh-add -l
```

`gpg.ssh.program` should point at `~/.local/bin/git-ssh-sign.sh`, and
`ssh-add -l` should list the key from Bitwarden. If it is empty, unlock
Bitwarden, confirm the SSH key item is in the active account, and check the
relay:

```bash
journalctl --user -u ssh-agent-bridge.service -n 50 --no-pager
ssh-add.exe -l
```

On Windows, the OpenSSH Authentication Agent service must be stopped and
disabled so Bitwarden owns the pipe:

```powershell
Get-Service ssh-agent
```

If the relay unit is not running, start it:

```bash
systemctl --user enable --now ssh-agent-bridge.service
```

Bitwarden has no `ssh-add` key management. Do not try to load a private key into
it from WSL; import the key into the vault instead.

GitButler has its own override, `gitbutler.signCommits`, which takes precedence
over `commit.gpgsign`. If `git commit` signs but `but commit` does not, check the
local value and remove the override (or set it to `true`):

```bash
git config --show-origin --get gitbutler.signCommits
```

Do not work around signing failures with `commit.gpgsign=false`,
`gitbutler.signCommits=false`, or by temporarily disabling signing; that leaves
unsigned commits and hides the real problem.

## GNOME Keyring (both profiles)

Both profiles install `gnome-keyring` and `libsecret`; `secret-tool` talks to
the Secret Service at `org.freedesktop.secrets`. GitButler, `bws`, and other
libsecret clients use the same store on native Arch and WSL.

- **Native GNOME** starts the daemon at login and unlocks the `Login` keyring
  through `pam_gnome_keyring`. It also provides the SSH agent.
- **WSL** has no PAM login. Bootstrap creates a `Login` keyring with a blank
  password by default, so the socket-activated daemon unlocks it automatically.
  It runs only the secrets component, so the Windows Bitwarden agent stays the
  SSH agent.

A blank keyring is convenient but not meaningfully encrypted at rest: the WSL
VHDX plus the Windows account are the protection boundary. For at-rest
protection, set a passphrase with `seahorse` (optional, not tracked) and unlock
the keyring once per WSL session:

```bash
keyring-unlock
```

The `keyring-unlock` fish function stops the socket-activated daemon, starts one
with the keyring unlocked, and leaves it running. A passphrase-protected keyring
stays locked after the distro starts, so run `keyring-unlock` again after
`wsl --shutdown` or a reboot. Bootstrap only creates a keyring when it is
missing, so it will not overwrite your passphrase.

The ArchWiki's PAM Windows Hello setup (`pam_wsl_hello`, package
`wsl-hello-sudo-bin`) is for authenticating `sudo`. It does not unlock a keyring:
WSL has no PAM login, and Windows Hello supplies no password to
`pam_gnome_keyring`. Do not add it for this.

Check the service and a canary item:

```bash
systemctl --user status gnome-keyring-daemon.service
printf 'test' | secret-tool store --label='canary' service dotfiles account canary
secret-tool lookup service dotfiles account canary
secret-tool clear service dotfiles account canary
```

## Bitwarden Secrets Manager

`bws-bin` is tracked in `provisioning/arch/packages/aur.txt`. The fish wrapper in
`home/dot_config/fish/functions/bws.fish` loads the token from GNOME Keyring on
both profiles and exports it only for the `bws` process. Run
`provisioning/arch/auth.sh` to store it, or see
[the secrets section in tips-and-tricks.md](tips-and-tricks.md#secrets-keyring-not-shell-exports)
for the manual commands and operational notes.

`--bws-account NAME` selects the keyring account label (default: `personal`) on
both profiles.

If the keyring is locked (a passphrase-protected WSL keyring after a restart),
run `keyring-unlock` first. Otherwise `secret-tool` opens the graphical keyring
prompt.

Store or replace the token manually:

```bash
secret-tool store --label='BWS access token' service bws account personal
secret-tool lookup service bws account personal   # prints the secret
```

`secret-tool store` prompts twice and hides input. Paste the machine-account
access token (a long string starting with `0.`) at both prompts. `--check` only
verifies that an item exists; it does not decrypt or validate it.

If a wrong value is stored, replace it with the same `secret-tool store` command,
then verify through the wrapper:

```bash
bws -o none project list
```

`bws -o none project list` exercises the token without printing it. Use
`secret-tool clear service bws account personal` first if you want
`provisioning/arch/auth.sh` to prompt for the token again.

## Back to

- [Documentation index](README.md)
- [Project README](../README.md)
