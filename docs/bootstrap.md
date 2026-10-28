# Bootstrapping a machine

Provisioning entry points live under `provisioning/arch/`. The bootstrap assumes
an existing Arch install and never partitions disks, installs a bootloader,
configures encryption, or manages hardware drivers. See the
[project README](../README.md#safety) for the safety rules that apply to every
run.

## Native Arch + GNOME

Install Arch and GNOME first using the normal installation guide or
`archinstall`. Make sure your user is in `wheel`, sudo works, and the network is
up. The bootstrap assumes the desktop environment already exists.

```bash
# Git is needed to clone the repo; install it first if the base system is minimal.
sudo pacman -S --needed git

git clone <repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles

./provisioning/arch/bootstrap.sh --profile native --check
./provisioning/arch/bootstrap.sh --profile native --dry-run
./provisioning/arch/bootstrap.sh --profile native
```

The first chezmoi run prompts for your name, personal email, and work email
when it cannot seed them from Git. Work email is optional; leave it blank on a
personal-only machine. The values are stored in
`~/.config/chezmoi/chezmoi.toml`; subsequent prompts are skipped. Use
`chezmoi edit-config` to change them later.

For unattended provisioning, pass the data explicitly. `--non-interactive`
also implies `--yes` and disables chezmoi, mise, and font prompts, so use it
when no terminal is available:

```bash
./provisioning/arch/bootstrap.sh --profile native --non-interactive \
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
warns about a mismatch instead of failing, so
`./provisioning/arch/audit.sh --profile wsl` can still inspect a WSL list from
another machine.

## Arch Linux in WSL

Use the Arch Wiki guide for the initial import:

<https://wiki.archlinux.org/title/Install_Arch_Linux_on_WSL>

The Windows side is intentionally not automated yet. After importing the Arch
image, open it as root. If the repo is not inside WSL yet, clone it on the
Windows side and run the script through `/mnt/c`:

```bash
sudo /mnt/c/Users/<you>/dotfiles/provisioning/arch/wsl-init.sh \
  --user <your-linux-user> --hostname <machine-name> --systemd
```

Or install `git` manually in WSL, clone the repo inside WSL, and run the same
script from there. Omit `--hostname` to be prompted interactively for the machine
name, or accept the `arch-wsl` default. `wsl-init.sh` installs `git`, so after it
finishes and WSL restarts you can clone the repo inside the WSL filesystem for
normal use.

Validate the root setup first, then apply it:

```bash
sudo ./provisioning/arch/wsl-init.sh --user <your-linux-user> --hostname <machine-name> --check
sudo ./provisioning/arch/wsl-init.sh --user <your-linux-user> --hostname <machine-name>
```

`--check` performs the same root, WSL, argument, command, and password-prompt
checks without changing packages or files. `--non-interactive` implies `--yes`,
never prompts for a username or hostname, and refuses to continue when a
`passwd` prompt would be required. Set the passwords first for unattended runs:

```bash
sudo passwd root
sudo passwd <your-linux-user>
sudo ./provisioning/arch/wsl-init.sh --user <your-linux-user> --hostname <machine-name> --non-interactive
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
./provisioning/arch/bootstrap.sh --profile wsl --check
./provisioning/arch/bootstrap.sh --profile wsl --dry-run
./provisioning/arch/bootstrap.sh --profile wsl
```

Bootstrap also installs `socat` and starts `ssh-agent-bridge.service`, which
relays the Windows Bitwarden SSH agent into WSL via `npiperelay.exe`. The
Windows OpenSSH Authentication Agent service must be disabled so Bitwarden can
own the pipe. Install Bitwarden Desktop and `npiperelay` on Windows first; see
[Windows SSH agent relay](auth.md#windows-ssh-agent-relay-wsl).

It also installs `gnome-keyring` (from `base.txt`) and creates the WSL `Login`
keyring with a blank password, so the Secret Service works without a PAM login.
GitButler and the `bws` wrapper use it; see
[GNOME Keyring](auth.md#gnome-keyring-both-profiles) for the tradeoff and how to
choose a passphrase instead. Bootstrap never replaces an existing keyring; a
passphrase-protected keyring stays locked after each WSL start until you run
`keyring-unlock`.

Keep the repo inside WSL, not on `/mnt/c`, for sensible permissions, file modes,
and Git performance.

### WSL defaults

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

## Windows host

The Windows host has a read-only audit and a curated WinGet inventory; it does
not install packages or change settings yet. Run it from WSL:

```bash
just windows-audit
```

Or run the PowerShell script directly from a Windows checkout:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\provisioning\windows\audit.ps1
```

See [Windows notes](windows.md) for the boundary, tracked packages, and manual
steps. The Windows side is prepared before `wsl-init.sh`; the Linux bootstrap
still runs inside WSL.

## System maintenance

The bootstrap applies:

- `pacman.conf`: `Color`, `ILoveCandy`, `ParallelDownloads = 5`, `CheckSpace`
- `provisioning/arch/system/reflector.conf`: Brazil-only mirrors, HTTPS, latest
  20, sorted by rate
- `paccache.timer` and `reflector.timer` on both profiles when systemd is active
- `fstrim.timer` and `fwupd-refresh.timer` on native only
- `ufw` on native: default deny incoming, allow outgoing, allow SSH and
  `tailscale0`. Add extra rules in `setup_firewall` or directly in `/etc/ufw`.
- `sshd` on both profiles: `sshd.service` is enabled and started when systemd is
  available, so SSH over the LAN or Tailscale works after provisioning. WSL
  still needs mirrored networking or a Windows port proxy for outside access.
- `sshd` key-only hardening:
  `provisioning/arch/system/sshd-hardening.conf` is installed as
  `/etc/ssh/sshd_config.d/10-hardening.conf` after dotfiles are applied,
  validated with `sshd -t`, then reloaded. `~/.ssh/authorized_keys` is managed
  from `home/private_dot_ssh/private_authorized_keys`; without a key the step is
  skipped so password access is never lost.
- timestamped backups of managed system files: `pacman.conf`, `wsl.conf`, and
  `locale.conf` keep the newest 3 backups per file instead of accumulating
  forever. Override with `BACKUP_RETENTION=<count>` for a longer history.
- `arch-audit` is installed for manual package vulnerability checks

Tailscale is installed on both profiles. Native enables `tailscaled.service`.
For WSL, use `wsl-init.sh --systemd` so `tailscaled.service` can be managed;
without systemd, bootstrap prints the manual `sudo tailscaled` setup and
`auth.sh` handles `tailscale up` once the daemon is running. If WSL cannot
create a TUN device, run `tailscaled --tun=userspace-networking` and use its
SOCKS/HTTP proxy for applications that need tailnet access.

Use `./provisioning/arch/bootstrap.sh --no-system` to skip the pacman, reflector,
timer, firewall, sshd, and Tailscale changes, and `--no-hooks` to skip
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
just verify
just fonts --list
just fonts --all
just doctor
just auth-check
just auth
just windows-audit
```

The profile examples use `native`; on WSL use `wsl` instead, or omit the profile
and let it auto-detect. Atuin is installed in local-only mode for fish history;
no sync login is configured. Zellij is installed on native only.

Tooling-language rationale lives in [decisions.md](decisions.md).

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
(`but`) for writes; see [AGENTS.md](../AGENTS.md).

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
./provisioning/arch/bootstrap.sh --profile native
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

## Next

- [Package catalog](packages.md) — the install, record, and audit loop.
- [Authentication and SSH](auth.md) — one-time machine credentials.
- [Tips and tricks](tips-and-tricks.md) — recovery and maintenance rhythm.
- [Back to the documentation index](README.md)
- [Back to the project README](../README.md)
