# Dotfiles and machine provisioning

Personal Arch Linux configuration: chezmoi for user dotfiles, pacman/AUR for
system packages, mise for development toolchains, and fish as the interactive
shell.

Supported targets:

| Target | Status | Provisioning entry point |
| --- | --- | --- |
| Arch Linux + GNOME (native) | Supported | `arch/bootstrap.sh --profile native` |
| Arch Linux in WSL | Supported | `arch/wsl-init.sh` as root, then `arch/bootstrap.sh --profile wsl` |
| Windows host | Placeholder | Nothing yet; see `windows/README.md` |

The bootstrap does **not** partition disks, install a bootloader, configure
encryption, install hardware drivers, or manage secrets. Those are separate
concerns.

## Safety

- Run `arch/bootstrap.sh` as your normal user, never as root.
- Run `arch/wsl-init.sh` as root, only inside WSL, only once after importing the
  Arch image.
- Start with `--dry-run`.
- Package reconciliation is install-only. The bootstrap never removes packages.
- AUR packages execute code at build time. Review them before using `--yes`.
- `chezmoi init --apply` can overwrite existing dotfiles. On an existing machine,
  inspect `chezmoi diff` first.
- Do not commit private keys, tokens, or password-store data.

## Layout

```text
.
├── .chezmoiroot                  # tells chezmoi to read source state from home/
├── home/                         # chezmoi source state
│   ├── .chezmoi.toml.tmpl        # init prompts: name, personal/work email
│   ├── .chezmoiignore
│   ├── .chezmoiversion
│   ├── dot_gitconfig.tmpl
│   ├── private_dot_ssh/private_config.tmpl
│   └── dot_config/
│       ├── fish/
│       │   ├── config.fish
│       │   ├── conf.d/
│       │   └── functions/bws.fish
│       ├── gh/config.yml
│       ├── git/
│       │   ├── ignore
│       │   └── work.inc.tmpl
│       ├── go/env.tmpl
│       ├── mimeapps.list
│       ├── mise/config.toml
│       ├── opencode/cli.json
│       ├── starship.toml
│       └── zed/settings.json
├── arch/
│   ├── bootstrap.sh              # user-level provisioning
│   ├── auth.sh                   # one-time SSH/gh/gcloud/tailscale auth
│   ├── completions.sh            # fish completion generation
│   ├── wsl-init.sh               # one-time WSL root setup
│   ├── audit.sh                  # package drift report
│   ├── system/reflector.conf     # Brazil-prioritized mirrors
│   └── packages/
│       ├── base.txt
│       ├── native.txt
│       ├── wsl.txt
│       ├── aur.txt
│       ├── aur-native.txt
│       └── aur-wsl.txt
├── windows/
│   └── README.md
├── .github/workflows/ci.yml
├── .editorconfig
├── .gitattributes
├── .lefthook.yml
├── justfile
└── README.md
```

`.chezmoiroot` is essential: without it, chezmoi would treat `arch/`,
`windows/`, and `home/` itself as things to create in your home directory.
Because the source state root is `home/`, `chezmoi cd` opens that directory; the
provisioning scripts remain one level up in `arch/`.

## Bootstrap

### Native Arch + GNOME

Install Arch and GNOME first using the normal installation guide or
`archinstall`. Make sure your user is in `wheel`, sudo works, and the network is
up. The bootstrap assumes the desktop environment already exists.

```bash
# Git is needed to clone the repo; install it first if the base system is minimal.
sudo pacman -S --needed git

git clone <repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles

./arch/bootstrap.sh --profile native --dry-run
./arch/bootstrap.sh --profile native
```

The first chezmoi run prompts for your name, personal email, and work email.
They are stored in
`~/.config/chezmoi/chezmoi.toml`; subsequent prompts are skipped. (`--yes` only
affects pacman/paru confirmation prompts; it does not bypass chezmoi's init
prompts.) Use `chezmoi edit-config` to change them later.

After bootstrap, log out and back in so fish and mise are active. If
`pacman -Syu` installed a new kernel, reboot before relying on the updated
system.

### Arch Linux in WSL

Use the Arch Wiki guide for the initial import:

<https://wiki.archlinux.org/title/Install_Arch_Linux_on_WSL>

The Windows side is intentionally not automated yet. After importing the Arch
image, open it as root. If the repo is not inside WSL yet, clone it on the
Windows side and run the script through `/mnt/c`:

```bash
sudo /mnt/c/Users/<you>/dotfiles/arch/wsl-init.sh --user <your-linux-user> --systemd
```

Or install `git` manually in WSL, clone the repo inside WSL, and run the same
script from there. `wsl-init.sh` installs `git`, so after it finishes and WSL
restarts you can clone the repo inside the WSL filesystem for normal use.

Use `--systemd` for a normal service-managed WSL installation; this is also the
recommended path for Tailscale. The script backs up any existing `/etc/wsl.conf`
and merges the required settings instead of skipping the file.

`wsl-init.sh` handles:

- pacman keyring initialization if it is empty
- `pacman -Syu`
- installing `sudo` and `git`
- creating the user and adding them to `wheel`
- a password prompt if the account is locked
- a sudoers drop-in for `wheel`
- `en_US.UTF-8` locale generation
- `/etc/wsl.conf` default user and hostname, optional systemd; new files get
  automount defaults, while existing interop/automount choices are preserved

Then, from Windows:

```powershell
wsl --shutdown
```

Reopen the distro as your normal user, clone the repo inside the WSL
filesystem, and run:

```bash
./arch/bootstrap.sh --profile wsl --dry-run
./arch/bootstrap.sh --profile wsl
```

Keep the repo inside WSL, not on `/mnt/c`, for sensible permissions, file modes,
and Git performance.

### Windows host

Nothing is provisioned yet. `windows/README.md` is a placeholder. When needed,
this should be a small curated WinGet list plus optional Windows Terminal
settings, not a second dotfiles manager.

## Package model

Tracked lists live in `arch/packages/`:

- `base.txt` — common CLI tools, fish, chezmoi, mise, git, Git tooling, atuin, tealdeer, dust/duf, kubectl, system maintenance, and build tools
- `native.txt` — native-only extras: `fwupd`, `restic`, `ufw`, `zellij`, and `gnome-tweaks`
- `wsl.txt` — CLI-only WSL additions
- `aur.txt` — AUR packages used by both profiles: GitButler CLI/GUI, `bws-bin`, `google-cloud-cli`, the GKE auth plugin, and `lefthook`
- `aur-native.txt` — native-only AUR packages: `t3code-nightly-bin` and `visual-studio-code-bin`
- `aur-wsl.txt` — WSL-only AUR packages: `wslu`

The native package list deliberately does **not** include the `gnome` group,
the kernel, firmware, microcode, or GPU drivers. Those belong to the OS
installation step and are machine-specific.

`google-cloud-cli`, `bws-bin`, `gitbutler-bin`, and
`t3code-nightly-bin` are in the AUR; the bootstrap bootstraps `paru` when any
AUR list is non-empty. On WSL, the GitButler GUI requires WSLg.
`gitbutler-bin` includes both the GUI and the `but` CLI; do not add
`gitbutler-cli-bin`, because both packages own `/usr/bin/but`.
`visual-studio-code-bin` is installed only on the native profile.
`yt-dlp` is installed without `ffmpeg`; add `ffmpeg` if you need stream merging
or audio extraction.

`restic` is native-only and is installed without a repository or password. Set
those up separately before enabling a backup timer. `tailscale` is installed on
both profiles; WSL without systemd needs the manual `tailscaled` command shown
by bootstrap.

To reconcile:

```bash
./arch/bootstrap.sh --profile native
```

The bootstrap runs `pacman -Syu`, initializes the keyring only if it is empty,
installs missing packages with `--needed`, bootstraps `paru` when either
`aur.txt` or `aur-<profile>.txt` contains packages, and then installs both AUR
lists.

To inspect drift without changing anything:

```bash
./arch/audit.sh --profile native
./arch/audit.sh --profile wsl --check
```

The audit expands package groups such as `gnome` so group members do not show up
as false drift. `base-devel` is a meta package in current Arch, not a group, so
it is compared directly. The audit reports installed-but-untracked packages too;
add or remove them deliberately rather than regenerating the lists blindly.

On a desktop installed with GNOME, many GNOME/system packages will appear as
untracked by design: they belong to the OS/desktop layer, not these lists.

Adding a package is a two-step operation: install it normally, then add its name
to the appropriate list. The bootstrap is not a package manager UI.

## System maintenance

The bootstrap applies:

- `pacman.conf`: `Color`, `ILoveCandy`, `ParallelDownloads = 5`, `CheckSpace`
- `arch/system/reflector.conf`: Brazil-only mirrors, HTTPS, latest 20, sorted by rate
- `paccache.timer` and `reflector.timer` on both profiles when systemd is active
- `fstrim.timer` and `fwupd-refresh.timer` on native only
- `ufw` on native: default deny incoming, allow outgoing, allow SSH and `tailscale0`.
  Add extra rules in `setup_firewall` or directly in `/etc/ufw`.
- `arch-audit` for package vulnerability checks

Tailscale is installed on both profiles. Native enables `tailscaled.service`.
For WSL, use `wsl-init.sh --systemd` so `tailscaled.service` can be managed;
without systemd, bootstrap prints the manual `sudo tailscaled` setup and
`auth.sh` handles `tailscale up` once the daemon is running. If WSL cannot
create a TUN device, run `tailscaled --tun=userspace-networking` and use its
SOCKS/HTTP proxy for applications that need tailnet access.

Use `./arch/bootstrap.sh --no-system` to skip the pacman/reflector/timer/
firewall/Tailscale/hook changes.

## Backups

`restic` is installed on native only. No repository, password, or timer is
configured automatically because those depend on your backup destination. Set
`RESTIC_REPOSITORY` and `RESTIC_PASSWORD_FILE`, then create the repository and a
timer.

## Git hooks and Just

`lefthook` is installed on both profiles and bootstrap runs `lefthook install`.
The pre-commit hook runs Gitleaks, ShellCheck, `shfmt -d`, fish syntax/format
checks, and `git diff --cached --check`.

Useful recipes:

```bash
just --list
just bootstrap native
just dry-run native
just audit native
just completions
just auth
```

Atuin is installed in local-only mode for fish history; no sync login is
configured. Zellij is installed on native only.

### Rust alternatives

A few notes on the requested tools:

- `gitui` is Rust and is the tracked Git TUI. `lazygit` is the Go alternative.
- `gitbutler` and its `but` CLI are Rust.
- New Rust additions: `zellij`, `atuin`, `tealdeer`, `dust`, `git-delta`,
  `difftastic`, `git-absorb`, and `just`.
- Go tools include `gitleaks`, `lefthook`, `kubectl`, `restic`, `tailscale`,
  and `duf`. `ufw` and `google-cloud-cli` are Python.
- `github-cli` (Go), `google-cloud-cli` (Python), `opencode`,
  `t3code-nightly-bin`, and `yt-dlp` (Python) have no drop-in Rust replacements.
- `starship`, `mise`, `bat`, `eza`, `fd`, `ripgrep`, and `zoxide` are already
  written in Rust. `fzf` is Go; `skim` is a Rust alternative, but not a drop-in
  for the current fish integration.
- `fish` is C++; `nushell` is Rust but not fish-compatible.

## Fish

Fish is the interactive shell. `arch/bootstrap.sh` installs it and changes the
login shell with `chsh`; provisioning scripts remain Bash.

Chezmoi manages:

```text
~/.config/fish/config.fish
~/.config/fish/conf.d/*.fish
~/.config/fish/functions/bws.fish
```

The config uses `set -gx` and `abbr --add --global` rather than universal
variables, so nothing important is hidden in `fish_variables`. Fish history and
fish variables are not tracked.

`~/.local/bin` and `~/.go/bin` are prepended once. `mise`, starship, fzf,
zoxide, and atuin are activated only in interactive shells. Atuin is local-only;
no sync login is set up.

## mise

Global toolchains live in `~/.config/mise/config.toml`:

- Node.js (latest global; pin project versions in each `mise.toml`)
- Bun
- pnpm
- `npm:@antfu/ni`
- `github:gittower/git-flow-next`, version 2.1.0, renamed to `git-flow`

Project-specific versions belong in each project's `mise.toml`, not in the
global config. After bootstrap:

```bash
mise install
mise ls
```

## Go

Go keeps its module cache and installed binaries in `~/.go` instead of the
default `~/go`. The location is set in `~/.config/go/env` via
`home/dot_config/go/env.tmpl`, so it applies in every shell and to tools that
invoke the `go` command. `~/.go/bin` is added to `PATH` by fish.

## Completions

Package-provided fish completions in `/usr/share/fish/vendor_completions.d`
load automatically. That covers tools such as `gh`, `opencode`, `yt-dlp`,
`mise`, `chezmoi`, `starship`, `zoxide`, `ripgrep`, `tailscale`, `just`, and
`atuin`.

`arch/completions.sh` generates the rest into
`~/.config/fish/completions/`:

- `pnpm completion fish`
- npm's bundled `completion.fish`
- `bun completions`
- `but completions fish`

The bootstrap runs it after `mise install`. Rerun it after upgrading tools:

```bash
./arch/completions.sh
```

`gcloud` does not ship an official fish completion. `gitui`, `bws`, `ni`, and
`git-flow` do not provide one either.

## OpenCode

Chezmoi tracks `~/.config/opencode/cli.json` with the current sidebar and diff
tree settings. OpenCode provider credentials live outside the repo, and
`~/.config/opencode/service.json` is intentionally ignored because it contains a
local service password.

## Editor and app defaults

Chezmoi manages `~/.config/zed/settings.json` (keymap, fonts, telemetry off) and
`~/.config/mimeapps.list` for default application associations. The GitHub CLI
config is tracked as `~/.config/gh/config.yml`; `hosts.yml` stays untracked
because it is machine auth state and can contain an OAuth token.

## Authentication and SSH

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
two `Host` entries and `arch/auth.sh`; this setup intentionally keeps it simple
with one key.

Run the interactive auth helper once per machine:

```bash
./arch/auth.sh --generate-key
```

It will:

- generate a per-machine ed25519 key if one does not exist
- load it into an ssh-agent
- authenticate `gh` for personal GitHub with the SSH Git protocol
- add the key to personal GitHub for both authentication and signing
- authenticate `gcloud` and application default credentials
- authenticate Tailscale when the daemon is running
- print the public key and the Cloud Source Repositories registration URL

Native GNOME already has an SSH agent through gnome-keyring. In WSL the helper
starts one and writes `~/.ssh/agent.env`; fish sources that file in new shells.

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
  The helper runs `gh auth login --git-protocol ssh --web`.
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
`--skip-gh`, `--skip-gcloud`, or `--skip-tailscale` for intentional skips.

## Git defaults

Beyond SSH signing, the tracked Git config enables:

- `rerere.enabled` and `rerere.autoupdate`
- `merge.conflictStyle = zdiff3`
- `diff.algorithm = histogram`
- `status.showUntrackedFiles = all`
- `commit.verbose = true`
- `fetch.writeCommitGraph = true`
- `column.ui = auto` and `branch.sort = -committerdate`
- `pull.rebase`, `rebase.autoStash`, `rebase.updateRefs`, and
  `push.autoSetupRemote`
- `delta` as the Git pager and `git dt` as the difftastic alias

Optional additions worth considering later: `feature.manyFiles = true` for
large repositories, `diff.renames = copies`, and `push.followTags = true`.
I would avoid `merge.ff = only` unless every repo enforces linear history.

## Bitwarden Secrets Manager

`bws` is not in the official Arch repositories. `bws-bin` is tracked in
`arch/packages/aur.txt` and installed by bootstrap through `paru`.

The token is loaded by the fish wrapper in
`home/dot_config/fish/functions/bws.fish`, not by a plaintext file.

### Native GNOME

GNOME Keyring is the native desktop secret service. Store the machine-account
token interactively:

```bash
secret-tool store --label='BWS access token' service bws account personal
```

Then `bws` works through the wrapper and the token is not exported globally. It
is only available to the `bws` process and its children.

### WSL

GNOME Keyring is normally not running in WSL. Use `pass` instead. Generate a
GPG key first if you do not have one, then initialize the store:

```bash
gpg --full-generate-key
pass init <gpg-key-id>
pass insert bitwarden/bws-token
```

The same fish wrapper reads `pass show bitwarden/bws-token` when
`WSL_DISTRO_NAME` is set.

### Notes

- Use a read-only machine account token scoped to one project, with rotation.
- Environment variables are visible to same-user processes. The goal here is
  “not plaintext at rest,” not process isolation. Use `bws run` for application
  secrets instead of exporting everything into your shell.
- Do not wire BWS into `chezmoi apply`. Chezmoi’s Bitwarden functions target the
  Bitwarden password manager, not Secrets Manager, and every apply should not
  require an unlocked token and network access.
- `~/.config/bws/state` is an encrypted session cache, not a replacement for
  protecting the access token.

### Should the private SSH key go in BWS?

Technically BWS can store any secret, including a private key. In practice I
would not do it:

- BWS is a secret store, not an SSH agent. To use the key you have to materialize
  it somewhere, so it ends up in a file or process memory anyway.
- The BWS machine token becomes a second credential that can retrieve the key.
  Losing it is now equivalent to losing the key.
- Every signing operation would depend on BWS availability and token access.

Use a per-machine SSH key instead, add its public half to GitHub and Cloud
Source Repositories, and keep an encrypted backup in your password manager or on
a hardware token. If you absolutely must store it in BWS, fetch it into
`$XDG_RUNTIME_DIR` with mode `0600`, add it to the agent, and delete it
immediately; do not keep a permanent copy in the repo or home directory.

## WSL defaults

WSL defaults:

- `[interop] appendWindowsPath` is `true`.
- `[boot] systemd` is `false` unless the distro image enables it.

This repo does not change either automatically.

- Leaving `appendWindowsPath=true` keeps Windows GUI integration convenient. If
  Windows `node.exe`, `git.exe`, or `python.exe` starts shadowing Linux/mise
  tools, set it to `false` deliberately and add explicit Windows helpers.
- To enable systemd, rerun `wsl-init.sh --systemd`, ensure WSL is updated, and run
  `wsl --shutdown` from Windows. The bootstrap detects `/run/systemd/system` and
  skips desktop services when systemd is unavailable.

## Day 2

The bootstrap does not create a Git repository. Initialize the repo once and add
your remote before relying on `chezmoi update`:

```bash
git init -b main
git add .
git commit -m "Initial dotfiles"
git remote add origin <repo-url>
git push -u origin main
```

```bash
# Dotfiles
just --list
chezmoi diff
chezmoi apply --dry-run
chezmoi apply
chezmoi update

# Packages
just audit native
./arch/bootstrap.sh --profile native
arch-audit

# Toolchains
mise install
mise upgrade
mise outdated

# Services
sudo tailscale status
sudo systemctl list-timers --all

# System updates (explicit, not hidden inside chezmoi)
sudo pacman -Syu
paru -Sua

# After changing arch/bootstrap.sh or package lists
./arch/bootstrap.sh --profile native --dry-run
```

The repo is intentionally not automatically updating packages during
`chezmoi apply`. Keep upgrades explicit.

## What is not managed

- Disk partitioning, LUKS, bootloader, `fstab`, `crypttab`
- Kernel, firmware, CPU microcode, GPU drivers
- Hostname, timezone, locale on native installs
- GNOME/dconf, browser profiles, app caches
- Private SSH keys, GPG keys, Bitwarden tokens, password stores
- Restic repository/password and backup schedule
- Tailscale account authentication and ACLs
- OpenCode provider credentials
- Windows apps, WSL installation, Windows Terminal settings
- `/etc` generally; `wsl-init.sh` only handles the WSL-specific bootstrap files

If you later need reproducible desktop packages, add a `desktop.txt` list. If you
later target multiple machines with different GPUs, add a host-specific overlay.
Do not add that complexity before it is needed.

## Recovery

- If a shell config breaks fish, start Bash with `bash --noprofile` or
  `command fish` from another terminal.
- `chezmoi diff` shows what would change; `chezmoi apply --dry-run --verbose`
  previews an apply.
- Revert dotfile changes with Git in the repo, then run `chezmoi apply`.
- If a system upgrade breaks something, use a btrfs snapshot if available, or
  boot an Arch ISO and chroot.
- If `chezmoi` cannot find the source, check `sourceDir` in
  `~/.config/chezmoi/chezmoi.toml`; the bootstrap sets it to this repo.
- If pacman reports invalid signatures, refresh the keyring with
  `sudo pacman-key --refresh-keys` or re-populate the `archlinux` keyring. Do not
  leave the system in a `pacman -Sy`-only state.

## Validation

CI runs Bash syntax checks, ShellCheck, fish syntax/format checks, `shfmt`, and
Gitleaks. Locally:

```bash
find . -name '*.sh' -print0 | xargs -0 -n1 bash -n
find . -name '*.sh' -print0 | xargs -0 shfmt -d
find home -name '*.fish' -print0 | xargs -0 -n1 fish --no-execute
find home -name '*.fish' -print0 | xargs -0 -n1 fish_indent --check
gitleaks detect --source . --redact --verbose
lefthook run pre-commit
```
