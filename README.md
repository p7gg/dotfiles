# Dotfiles and machine provisioning

Personal Arch Linux configuration: chezmoi for user dotfiles, pacman/AUR for
system packages, OpenCode's verified npm release for the CLI, mise for
development toolchains, and fish as the interactive shell.

Supported targets:

| Target | Status | Provisioning entry point |
| --- | --- | --- |
| Arch Linux + GNOME (native) | Supported | `arch/bootstrap.sh --profile native` |
| Arch Linux in WSL | Supported | `arch/wsl-init.sh` as root, then `arch/bootstrap.sh --profile wsl` |
| Windows host | Placeholder | Nothing yet; see `windows/README.md` |

The bootstrap does **not** partition disks, install a bootloader, configure
encryption, install hardware drivers, or manage secrets. Those are separate
concerns.

## Documentation

- [Package catalog](docs/packages.md) — all 67 tracked packages (60 native,
  58 WSL) with Native/WSL badges, the bootstrap-managed OpenCode CLI, the 18
  optional Nerd Fonts, per-list counts, mise toolchains, and the install/record/
  audit loop.
- [Documentation index](docs/README.md) — task-based navigation for the docs.
- [Windows notes](windows/README.md) — the intentionally empty Windows side.
- [Tips and tricks](docs/tips-and-tricks.md) — fish, Git, chezmoi, mise, WSL,
  secrets, OpenCode, recovery, and local SVG illustrations.
- [Authentication and SSH](docs/auth.md) — key, GitHub, gcloud, Tailscale,
  BWS, and MCP setup and troubleshooting.
- [Decisions](docs/decisions.md) — tooling-language notes, optional Git
  defaults, and the BWS private-key decision.

## Safety

- Run `arch/bootstrap.sh` as your normal user, never as root.
- Run `arch/wsl-init.sh` as root, only inside WSL, once for the initial import.
  Rerun it with `--systemd` if you later enable systemd.
- An explicit `--profile` must match the current environment. Bootstrap refuses
  `native` inside WSL and `wsl` outside it before installing anything; use
  `--allow-profile-mismatch` only for deliberate cross-profile work.
- Start with `--check`, then `--dry-run`; dry-run previews `chezmoi diff`.
- Use `--non-interactive --name ... --email ...` for unattended provisioning.
- Use `arch/wsl-init.sh --check` to validate the one-time WSL root setup, and
  `arch/wsl-init.sh --non-interactive` only after setting root and user
  passwords; it fails before changes when a `passwd` prompt would be needed.
- Use `arch/auth.sh --check` to inspect authentication without changing it.
- Package reconciliation is install-only. The bootstrap never removes packages.
- The OpenCode CLI is installed from a verified npm tarball; remove an older
  pacman `opencode` package once by hand after the user binary is in place.
- AUR packages execute code at build time. The bootstrap builds `paru` from a
  pinned AUR commit; review other AUR packages before using `--yes`.
- `chezmoi init --apply` can overwrite existing dotfiles. On an existing machine,
  inspect `chezmoi diff` first.
- Do not commit private keys, tokens, or password-store data.

## Layout

```text
.
├── .chezmoiroot                  # tells chezmoi to read source state from home/
├── home/                         # chezmoi source state
│   ├── .chezmoi.toml.tmpl        # sourceDir, editor, and init prompts
│   ├── .chezmoiignore
│   ├── .chezmoiversion
│   ├── run_once_after_migrate-go-data.sh  # move legacy ~/go to ~/.go once
│   ├── dot_gitconfig.tmpl
│   ├── private_dot_ssh/
│   │   ├── private_authorized_keys
│   │   └── private_config.tmpl
│   └── dot_config/
│       ├── fish/
│       │   ├── config.fish
│       │   ├── conf.d/
│       │   └── functions/
│       │       ├── bws.fish
│       │       └── fzf-checkout.fish
│       ├── gh/config.yml
│       ├── git/
│       │   ├── ignore
│       │   └── work.inc.tmpl
│       ├── go/env.tmpl
│       ├── mimeapps.list
│       ├── mise/config.toml
│       ├── opencode/
│       │   ├── cli.json
│       │   └── opencode.json
│       ├── starship.toml
│       └── zed/settings.json
├── arch/
│   ├── bootstrap.sh              # user-level provisioning
│   ├── auth.sh                   # one-time SSH/gh/gcloud/tailscale/BWS/MCP auth
│   ├── completions.sh            # fish completion generation
│   ├── fonts.sh                  # interactive optional Nerd Font installer
│   ├── wsl-init.sh               # one-time WSL root setup
│   ├── audit.sh                  # package drift report
│   ├── vscode-server-env-setup.sh # Remote-WSL SSH agent bridge
│   ├── lib/common.sh             # shared shell helpers
│   ├── system/
│   │   ├── reflector.conf        # Brazil-prioritized mirrors
│   │   └── sshd-hardening.conf   # key-only SSH drop-in
│   └── packages/
│       ├── base.txt
│       ├── native.txt
│       ├── wsl.txt
│       ├── aur.txt
│       ├── aur-native.txt
│       ├── aur-wsl.txt
│       ├── fonts.txt             # optional Nerd Font catalog
│       └── audit-ignore.txt      # bootstrap/OS-layer audit allowlist
├── scripts/
│   ├── lint.sh                   # shared local/CI lint entry point
│   ├── fmt.sh
│   ├── test.sh
│   ├── check-docs.sh             # package counts, links, and local assets
│   └── doctor.sh
├── tests/
│   ├── render-templates.sh       # render every chezmoi template
│   ├── audit.bats
│   ├── auth.bats
│   ├── bootstrap.bats
│   ├── common.bats
│   ├── docs.bats
│   ├── fish.bats
│   ├── fonts.bats
│   ├── go.bats
│   ├── ssh.bats
│   ├── supply-chain.bats
│   └── wsl-init.bats
├── windows/
│   └── README.md
├── docs/
│   ├── README.md                 # documentation index
│   ├── auth.md                   # SSH/GitHub/gcloud/Tailscale/MCP auth
│   ├── packages.md               # complete package catalog
│   ├── tips-and-tricks.md        # shell/Git/WSL/secrets workflows
│   ├── decisions.md              # design notes moved out of the README
│   └── assets/                   # local SVG badges and illustrations
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

./arch/bootstrap.sh --profile native --check
./arch/bootstrap.sh --profile native --dry-run
./arch/bootstrap.sh --profile native
```

The first chezmoi run prompts for your name, personal email, and work email
when it cannot seed them from Git. Work email is optional; leave it blank on a
personal-only machine. The values are stored in `~/.config/chezmoi/chezmoi.toml`;
subsequent prompts are skipped. Use `chezmoi edit-config` to change them later.

For unattended provisioning, pass the data explicitly. `--non-interactive`
also implies `--yes` and disables chezmoi, mise, and font prompts, so use it
when no terminal is available:

```bash
./arch/bootstrap.sh --profile native --non-interactive \
  --name "Your Name" --email you@example.com --work-email you@work.example
```

After bootstrap, log out and back in so fish and mise are active. If
`pacman -Syu` installed a new kernel, reboot before relying on the updated
system.

`--profile` is validated against the environment: `native` is rejected inside
WSL and `wsl` is rejected outside it, before package or system changes. The
default is auto-detection, so normal runs never need the flag. Use
`--allow-profile-mismatch` only when deliberately inspecting or installing the
other profile; `--check` honors the same rule. The read-only audit is looser: it
warns about a mismatch instead of failing, so `./arch/audit.sh --profile wsl` can
still inspect a WSL list from another machine.

### Arch Linux in WSL

Use the Arch Wiki guide for the initial import:

<https://wiki.archlinux.org/title/Install_Arch_Linux_on_WSL>

The Windows side is intentionally not automated yet. After importing the Arch
image, open it as root. If the repo is not inside WSL yet, clone it on the
Windows side and run the script through `/mnt/c`:

```bash
sudo /mnt/c/Users/<you>/dotfiles/arch/wsl-init.sh \
  --user <your-linux-user> --hostname <machine-name> --systemd
```

Or install `git` manually in WSL, clone the repo inside WSL, and run the same
script from there. Omit `--hostname` to be prompted interactively for the machine
name, or accept the `arch-wsl` default. `wsl-init.sh` installs `git`, so after it
finishes and WSL restarts you can clone the repo inside the WSL filesystem for
normal use.

Validate the root setup first, then apply it:

```bash
sudo ./arch/wsl-init.sh --user <your-linux-user> --hostname <machine-name> --check
sudo ./arch/wsl-init.sh --user <your-linux-user> --hostname <machine-name>
```

`--check` performs the same root, WSL, argument, command, and password-prompt
checks without changing packages or files. `--non-interactive` implies `--yes`,
never prompts for a username or hostname, and refuses to continue when a
`passwd` prompt would be required. Set the passwords first for unattended runs:

```bash
sudo passwd root
sudo passwd <your-linux-user>
sudo ./arch/wsl-init.sh --user <your-linux-user> --hostname <machine-name> --non-interactive
```

A real run also refuses to reach an interactive password prompt when stdin is
not a terminal, before pacman or account changes begin.

Use `--systemd` for a normal service-managed WSL installation; this is also the
recommended path for Tailscale. The script backs up any existing `/etc/wsl.conf`
and merges the required settings instead of skipping the file.

`wsl-init.sh` handles:

- a machine-name (hostname) prompt when `--hostname` is omitted; the value is
  applied through `/etc/wsl.conf` after the WSL restart
- pacman keyring initialization if it is empty
- `pacman -Syu`
- installing `sudo` and `git`
- a root password prompt right before the user is created, if the root account
  is locked or has none; an existing root password is left unchanged
- creating the user and adding them to `wheel`
- a password prompt for the new user if the account is locked
- a sudoers drop-in for `wheel`
- `en_US.UTF-8` locale generation
- `/etc/wsl.conf` default user and hostname, optional systemd; new files get
  automount defaults, while existing interop/automount choices are preserved.
  The target user cannot be `root`, and an existing `/etc/locale.conf` is backed
  up and merged instead of overwritten

Then, from Windows:

```powershell
wsl --shutdown
```

Reopen the distro as your normal user, clone the repo inside the WSL
filesystem, and run:

```bash
./arch/bootstrap.sh --profile wsl --check
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

There are 67 tracked package names: 60 apply to the native profile and 58 to
WSL. The 51 shared names are 46 official packages plus 5 AUR packages; the
remaining 9 native-only and 7 WSL-only names are split by profile.

- `base.txt` — common CLI tools, fish, chezmoi, mise, git, Git tooling, atuin, tealdeer, dust/duf, kubectl, lint/test tooling, system maintenance, and build tools
- `native.txt` — native-only extras: `fwupd`, `restic`, `ufw`, `zellij`, and `gnome-tweaks`
- `wsl.txt` — CLI-only WSL additions, plus the `mesa`/`vulkan-dzn` drivers that
  enable hardware accelerated rendering through the Windows GPU
- `aur.txt` — AUR packages used by both profiles: GitButler CLI/GUI, `bws-bin`, `google-cloud-cli`, the GKE auth plugin, and `lefthook`
- `aur-native.txt` — native-only AUR packages: `brave-bin`,
  `opencode-desktop-bin`, `t3code-nightly-bin`, and `visual-studio-code-bin`
- `aur-wsl.txt` — WSL-only AUR packages: `wslu`
- `fonts.txt` — optional Nerd Fonts; nothing is installed unless you select it
  in the interactive font step

The OpenCode CLI is not in a package list. `arch/bootstrap.sh` installs it from
the verified OpenCode npm tarball into `~/.opencode/bin`; see
[OpenCode](#opencode).

See the [package catalog](docs/packages.md) for every package with its
environment badge, purpose, and configuration notes.

The native package list deliberately does **not** include the `gnome` group,
the kernel, firmware, microcode, or GPU drivers. Those belong to the OS
installation step and are machine-specific.

The AUR lists contain `bws-bin`, `gitbutler-bin`, `google-cloud-cli`, the GKE
auth plugin, `lefthook`, `brave-bin`, `opencode-desktop-bin`,
`t3code-nightly-bin`, `visual-studio-code-bin`, and `wslu`. The bootstrap
bootstraps `paru` when any AUR list is non-empty; its clone is checked out at the
reviewed commit in `PARU_COMMIT` in `arch/bootstrap.sh`, not at whatever is on
AUR master that day. Bump that pin deliberately when updating paru. On WSL, the
GitButler GUI requires WSLg.
`gitbutler-bin` includes both the GUI and the `but` CLI; do not add
`gitbutler-cli-bin`, because both packages own `/usr/bin/but`.
`visual-studio-code-bin`, `brave-bin`, `opencode-desktop-bin`, and
`t3code-nightly-bin` are installed only on the native profile.
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

The bootstrap runs `pacman -Syu`, initializes or repopulates the keyring when
needed, installs missing packages with `--needed`, bootstraps `paru` when either
`aur.txt` or `aur-<profile>.txt` contains packages, and then installs both AUR
lists.

To inspect drift without changing anything:

```bash
./arch/audit.sh --profile native            # full report
./arch/audit.sh --profile native --check    # exit 1 if tracked packages are missing
./arch/audit.sh --profile native --check --strict  # also fail on untracked packages
./arch/audit.sh --profile native --json     # machine-readable output
```

The audit expands a tracked package group when one is listed, so members do not
show up as false drift. `base-devel` is a meta package in current Arch, not a group, so
it is compared directly. Untracked packages from `arch/packages/audit-ignore.txt`
(for example the bootstrap's `paru` and `paru-debug`) are omitted from the
untracked sections.

On a desktop installed with GNOME, many GNOME/system packages will appear as
untracked by design: they belong to the OS/desktop layer, not these lists. The
default `--check` therefore only fails on missing tracked packages; use
`--strict` when you deliberately want to review the OS layer too.

Adding a package is a two-step operation: install it normally, then add its name
to the appropriate list. The bootstrap is not a package manager UI.

### Optional Nerd Fonts

Bootstrap ends the package phase with an interactive font selection. Nothing is
selected by default: enter numbers or ranges such as `1 3-5` to install only
those fonts, or press Enter to skip. Already installed fonts are marked in the
menu and are not reinstalled.

The catalog is `arch/packages/fonts.txt`; every entry comes from the official
`extra` repository. For non-interactive runs:

```bash
./arch/bootstrap.sh --profile native --no-fonts
./arch/bootstrap.sh --profile native --fonts all
./arch/bootstrap.sh --profile native --fonts "JetBrains Mono,Fira Code"
./arch/fonts.sh --list
./arch/fonts.sh --font "Zed Mono"
./arch/fonts.sh --all
```

`--fonts` also accepts catalog numbers and package names. The audit recognizes
installed fonts as tracked, but never reports unselected fonts as missing.

## System maintenance

The bootstrap applies:

- `pacman.conf`: `Color`, `ILoveCandy`, `ParallelDownloads = 5`, `CheckSpace`
- `arch/system/reflector.conf`: Brazil-only mirrors, HTTPS, latest 20, sorted by rate
- `paccache.timer` and `reflector.timer` on both profiles when systemd is active
- `fstrim.timer` and `fwupd-refresh.timer` on native only
- `ufw` on native: default deny incoming, allow outgoing, allow SSH and `tailscale0`.
  Add extra rules in `setup_firewall` or directly in `/etc/ufw`.
- `sshd` on both profiles: `sshd.service` is enabled and started when systemd is
  available, so SSH over the LAN or Tailscale works after provisioning. WSL
  still needs mirrored networking or a Windows port proxy for outside access.
- `sshd` key-only hardening: `arch/system/sshd-hardening.conf` is installed as
  `/etc/ssh/sshd_config.d/10-hardening.conf` after dotfiles are applied,
  validated with `sshd -t`, then reloaded. `~/.ssh/authorized_keys` is managed
  from `home/private_dot_ssh/private_authorized_keys`; without a key the step is
  skipped so password access is never lost.
- timestamped backups of managed system files: `pacman.conf`, `wsl.conf`, and
  `locale.conf` keep the newest 3 backups per file instead of accumulating
  forever. Override with `BACKUP_RETENTION=<count>` for a longer history.
- `arch-audit` for package vulnerability checks

Tailscale is installed on both profiles. Native enables `tailscaled.service`.
For WSL, use `wsl-init.sh --systemd` so `tailscaled.service` can be managed;
without systemd, bootstrap prints the manual `sudo tailscaled` setup and
`auth.sh` handles `tailscale up` once the daemon is running. If WSL cannot
create a TUN device, run `tailscaled --tun=userspace-networking` and use its
SOCKS/HTTP proxy for applications that need tailnet access.

Use `./arch/bootstrap.sh --no-system` to skip the pacman, reflector, timer,
firewall, sshd, and Tailscale changes, and `--no-hooks` to skip
`lefthook install`.

## Backups

`restic` is installed on native only. No repository, password, or timer is
configured automatically because those depend on your backup destination. Set
`RESTIC_REPOSITORY` and `RESTIC_PASSWORD_FILE`, then create the repository and a
timer.

## Git hooks and Just

`lefthook` is installed on both profiles and bootstrap runs `lefthook install`.
The pre-commit hook calls `scripts/lint.sh --staged` (Gitleaks, ShellCheck,
`shfmt`, fish syntax/format, actionlint, and Just formatting) plus
`git diff --cached --check`.

Useful recipes:

```bash
just --list
just check native          # validate prerequisites
just bootstrap native
just dry-run native
just audit-check native
just lint
just fmt
just test
just fonts --list
just fonts --all
just doctor
just auth-check
just auth
```

Atuin is installed in local-only mode for fish history; no sync login is
configured. Zellij is installed on native only.

Tooling-language rationale lives in [docs/decisions.md](docs/decisions.md).

## Fish

Fish is the interactive shell. `arch/bootstrap.sh` installs it and changes the
login shell with `chsh`; provisioning scripts remain Bash.

Chezmoi manages:

```text
~/.config/fish/config.fish
~/.config/fish/conf.d/*.fish
~/.config/fish/functions/*.fish
```

The config uses `set -gx` and `abbr --add --global` rather than universal
variables, so nothing important is hidden in `fish_variables`. Fish history and
fish variables are not tracked.

`ch` opens the `fzf-checkout` branch picker. Local branches come first,
remote-tracking branches follow, and picking a remote branch creates a local
branch with the same name that tracks it. With arguments, `ch` defers to
`git checkout`, so `ch <branch>` and `ch -b <branch>` keep working. The Git alias
`git ch` uses the same picker.

`~/.local/bin`, `~/.opencode/bin`, and `~/.go/bin` are prepended once, in that
order of precedence. `mise`, starship, fzf,
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

On machines that still have the old default `~/go`, the
`home/run_once_after_migrate-go-data.sh` script moves it to `~/.go` on the next
`chezmoi apply`, preserving the module cache. If `~/.go` already exists, it
leaves both directories in place and prints a warning.

AUR packages are built before dotfiles are applied, so the bootstrap passes the
same `GOPATH` to `paru`. Source builds such as `lefthook` write to `~/.go`
instead of creating `~/go`.

## Completions

Package-provided fish completions in `/usr/share/fish/vendor_completions.d`
load automatically. That covers tools such as `gh`, `yt-dlp`, `mise`,
`chezmoi`, `starship`, `zoxide`, `ripgrep`, `tailscale`, `just`, and `atuin`.

`arch/completions.sh` generates the rest into
`~/.config/fish/completions/`:

- `pnpm completion fish`
- npm's bundled `completion.fish`
- `bun completions`
- `but completions fish`
- `opencode --completions fish`

The bootstrap runs it after `mise install`. Rerun it after upgrading tools:

```bash
./arch/completions.sh
```

`gcloud` does not ship an official fish completion. `gitui`, `bws`, `ni`, and
`git-flow` do not provide one either.

## OpenCode

The OpenCode CLI is installed from OpenCode's npm release, not from pacman. The
bootstrap no longer pipes a remote installer into a shell: it reads the official
release metadata from `https://opencode.ai/update/api/latest/cli/npm`, downloads
the platform tarball from `registry.npmjs.org`, verifies the published `sha512`
integrity value, and only then installs `~/.opencode/bin/opencode`.

```bash
# What bootstrap does, without the remote-script pipe:
# metadata -> registry.npmjs.org tarball -> sha512 check -> extract package/bin
```

By default the CLI tracks the latest release on every provisioning run. Pin a
reviewed version when reproducibility matters:

```bash
OPENCODE_VERSION=2.1.4 ./arch/bootstrap.sh --profile wsl
```

Use `--no-opencode` to skip the step. If the release metadata or checksum is
missing or does not match, bootstrap fails instead of installing an unverified
binary. Fish adds `~/.opencode/bin` to `PATH` through
`home/dot_config/fish/conf.d/10-path.fish`; `just doctor` verifies that
`opencode` resolves there. Update manually with `opencode upgrade`, or rerun
bootstrap.

The pacman package `opencode` is no longer tracked. If an older machine still
has it, install the user-managed CLI first and then remove the package once so
stale system-wide copies and scripts do not keep using `/usr/bin/opencode`:

```bash
sudo pacman -Rns opencode
```

The desktop app is a separate native-only AUR package,
`opencode-desktop-bin` in `arch/packages/aur-native.txt`. It installs
`/usr/bin/opencode-desktop` and runs on system `electron44`; it does not replace
the `opencode` CLI.

Chezmoi tracks `~/.config/opencode/cli.json` with the current sidebar and diff
tree settings, and `~/.config/opencode/opencode.json` with the global MCP
servers:

- `linear` — Linear's remote MCP server at `https://mcp.linear.app/mcp` (OAuth)
- `jira` — Atlassian's remote MCP server for Jira, Confluence, and related
  products at `https://mcp.atlassian.com/v2/mcp` (OAuth)
- `context7` — Context7 documentation lookup at `https://mcp.context7.com/mcp`
  (no authentication required)

`arch/auth.sh` signs in to Linear and Jira through their OAuth flows. To
authenticate later, run `opencode mcp auth linear` or `opencode mcp auth jira`,
or use `/mcps` in OpenCode. Context7 works without an API key; set
`CONTEXT7_API_KEY` and add it as a `CONTEXT7_API_KEY` header in `opencode.json`
only if you want the higher rate limits.

OpenCode provider credentials and MCP OAuth tokens live outside the repo, and
`~/.config/opencode/service.json` is intentionally ignored because it contains a
local service password.

## Editor and app defaults

Chezmoi manages `~/.config/zed/settings.json` (keymap, fonts, telemetry off) and
`~/.config/mimeapps.list` for default application associations. The GitHub CLI
config is tracked as `~/.config/gh/config.yml`; `hosts.yml` stays untracked
because it is machine auth state and can contain an OAuth token.

## Authentication and SSH

Chezmoi configures SSH commit signing with one per-machine key, and work
projects under `~/Projects/work/` use the work email. `~/.ssh/authorized_keys`
is managed too: `home/private_dot_ssh/private_authorized_keys` lists the keys
allowed to log in, so a freshly provisioned host accepts them without a manual
`ssh-copy-id`. Inspect state first, then run the helper once:

```bash
./arch/auth.sh --check
./arch/auth.sh --generate-key
```

Tailscale device names double as SSH aliases: `ssh gabriel@laptop` resolves the
name from `tailscaled`'s peer list (`tailscale ip`) and proxies the session with
`tailscale nc`. Because it does not rely on the OS resolver, it also works when
local MagicDNS resolution is unavailable, such as on a WSL or
userspace-networking node whose resolver does not know the tailnet. Other
hostnames keep using the normal resolver. This is client-side only; the target
still needs `sshd` and an account for you.

The helper handles the SSH key, GitHub authentication/signing keys, gcloud and
application default credentials, Tailscale, the Bitwarden Secrets Manager token,
and the Linear/Jira MCP servers. See [docs/auth.md](docs/auth.md) for flags,
skip options, Cloud Source Repositories registration steps, and troubleshooting.

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
- `delta` as the Git pager and `git dt` as the difftastic alias when those
  tools are installed

Optional additions are listed in [docs/decisions.md](docs/decisions.md).

## Bitwarden Secrets Manager

`bws-bin` is tracked in `arch/packages/aur.txt`. The fish wrapper in
`home/dot_config/fish/functions/bws.fish` loads the token from GNOME Keyring
(native) or `pass` (WSL) and exports it only for the `bws` process. Run
`./arch/auth.sh` to store it, or see
[the secrets section in docs/tips-and-tricks.md](docs/tips-and-tricks.md#secrets-not-plaintext-at-rest)
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

`arch/auth.sh` initializes an empty store automatically when exactly one GPG
secret key exists; otherwise it prints the `pass init <gpg-key-id>` command to
run. When the helper asks whether to store the token, answer `y`; `pass` then
prompts twice, and you paste the machine-account access token (a long string
starting with `0.`) at both prompts. Input is hidden.

`--check` only verifies that the `pass` entry exists; it does not decrypt or
validate it. If a wrong value is stored, replace it directly:

```bash
pass insert -f bitwarden/bws-token
bws -o none project list
```

`bws -o none project list` exercises the token through the fish wrapper without
printing secrets. Use `pass rm bitwarden/bws-token` first if you want
`arch/auth.sh` to prompt for the token again.

## WSL defaults

WSL defaults:

- `[interop] appendWindowsPath` is `true`.
- `[boot] systemd` is `false` unless the distro image enables it.

`wsl-init.sh` writes `appendWindowsPath=true` into a new `/etc/wsl.conf` and
preserves an existing value. It only enables systemd when you pass `--systemd`.

- Leaving `appendWindowsPath=true` keeps Windows GUI integration convenient. If
  Windows `node.exe`, `git.exe`, or `python.exe` starts shadowing Linux/mise
  tools, set it to `false` deliberately and add explicit Windows helpers.
- To enable systemd, rerun `wsl-init.sh --systemd`, ensure WSL is updated, and run
  `wsl --shutdown` from Windows. The bootstrap detects `/run/systemd/system` and
  skips desktop services when systemd is unavailable.

## Day 2

If you copied the directory instead of cloning it, initialize the repository
once and add your remote before relying on `chezmoi update`:

```bash
git init -b main
git add .
git commit -m "Initial dotfiles"
git remote add origin <repo-url>
git push -u origin main
```

This section is for human bootstrap. Agent-driven changes should use GitButler
(`but`) for writes; see [AGENTS.md](AGENTS.md).

```bash
# Dotfiles
just --list
chezmoi diff
chezmoi apply --dry-run
chezmoi apply
chezmoi update

# Packages
just audit native
just audit-check native
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

# After changing repository files
just lint
just test
just dry-run native
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
- OpenCode provider credentials and MCP OAuth tokens
- Windows apps, WSL installation, Windows Terminal settings
- `/etc` broadly; the bootstrap only manages the pacman, reflector, firewall,
  and sshd files listed above, and `wsl-init.sh` handles the WSL-specific
  bootstrap files

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

CI uses an Arch container and the same entry points; update your local system
if you need its tool versions to match CI exactly. The test suite runs as a
regular user because the provisioning scripts refuse to run as root. It
executes the same entry points used locally:

```bash
just lint       # Bash syntax, ShellCheck, shfmt, fish, actionlint, Just, gitleaks
just test       # docs consistency, bats tests, and every chezmoi template render
just render     # template rendering only
lefthook run pre-commit
```

`just test` runs `scripts/check-docs.sh` first. It verifies the 67/60/58 package
counts in the README, docs, and provisioning SVG against `arch/packages/*.txt`,
and checks every relative Markdown link and local asset. `just lint` scans the
full repository and Git history; the pre-commit hook calls
`scripts/lint.sh --staged` so it only checks staged shell/fish files and scans
staged secrets.
