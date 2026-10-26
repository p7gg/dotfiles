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
already has an SSH agent through gnome-keyring. On WSL the helper enables the
`ssh-agent.socket` user unit, so systemd starts an agent on first use at
`$XDG_RUNTIME_DIR/ssh-agent.socket`.
Fish exports that path in new shells and runs `ssh-add` when the agent has no
keys, so a protected key prompts once per boot. There is no socket cache to go
stale across restarts. The helper also installs
`~/.vscode-server/server-env-setup`, which gives the Remote-WSL server the same
socket and asks for the passphrase through a WSLg dialog when no terminal has
loaded the key yet.

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
