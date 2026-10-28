# Dotfiles and machine provisioning

Personal Arch Linux configuration: chezmoi for user dotfiles, pacman/AUR for
system packages, OpenCode's verified npm release for the CLI, mise for
development toolchains, and fish as the interactive shell.

Supported targets:

| Target | Status | Provisioning entry point |
| --- | --- | --- |
| Arch Linux + GNOME (native) | Supported | `provisioning/arch/bootstrap.sh --profile native` |
| Arch Linux in WSL | Supported | `provisioning/arch/wsl-init.sh` as root, then `provisioning/arch/bootstrap.sh --profile wsl` |
| Windows host | Placeholder | Nothing yet; see [Windows notes](docs/windows.md) |

The bootstrap does **not** partition disks, install a bootloader, configure
encryption, install hardware drivers, or manage secrets. Those are separate
concerns.

## Documentation

Start with the task you need:

| I need to... | Read |
| --- | --- |
| Set up a machine | [Bootstrapping](docs/bootstrap.md) |
| Add, remove, or audit a package | [Package catalog](docs/packages.md) |
| Fix SSH, GitHub, gcloud, Tailscale, BWS, or MCP auth | [Authentication and SSH](docs/auth.md) |
| Check shell, editor, OpenCode, or Git defaults | [Tooling and defaults](docs/tooling.md) |
| Look up a shell, Git, chezmoi, WSL, or secrets workflow | [Tips and tricks](docs/tips-and-tricks.md) |
| Understand a design choice | [Decisions](docs/decisions.md) |
| See every document | [Documentation index](docs/README.md) |

## Safety

- Run `provisioning/arch/bootstrap.sh` as your normal user, never as root.
- Run `provisioning/arch/wsl-init.sh` as root, only inside WSL, once for the
  initial import. Rerun it with `--systemd` if you later enable systemd.
- An explicit `--profile` must match the current environment. Bootstrap refuses
  `native` inside WSL and `wsl` outside it before installing anything; use
  `--allow-profile-mismatch` only for deliberate cross-profile work.
- Start with `--check`, then `--dry-run`; dry-run previews `chezmoi diff`.
- Use `--non-interactive --name ... --email ...` for unattended provisioning.
- Use `provisioning/arch/wsl-init.sh --check` to validate the one-time WSL root
  setup, and `--non-interactive` only after setting root and user passwords; it
  fails before changes when a `passwd` prompt would be needed.
- Use `provisioning/arch/auth.sh --check` to inspect authentication without
  changing it.
- Package reconciliation is install-only. The bootstrap never removes packages.
- The OpenCode CLI is installed from a verified npm tarball; remove an older
  pacman `opencode` package once by hand after the user binary is in place.
- AUR packages execute code at build time. The bootstrap builds `paru` from a
  pinned AUR commit; review other AUR packages before using `--yes`.
- `chezmoi init --apply` can overwrite existing dotfiles. On an existing machine,
  inspect `chezmoi diff` first.
- Do not commit private keys, tokens, or keyring data.

## Quick start

### Native Arch + GNOME

Install Arch and GNOME first, then:

```bash
sudo pacman -S --needed git
git clone <repo-url> ~/Projects/dotfiles
cd ~/Projects/dotfiles

./provisioning/arch/bootstrap.sh --profile native --check
./provisioning/arch/bootstrap.sh --profile native --dry-run
./provisioning/arch/bootstrap.sh --profile native
```

After bootstrap, log out and back in so fish and mise are active. See
[Bootstrapping](docs/bootstrap.md#native-arch--gnome) for the chezmoi prompts,
unattended runs, and profile validation.

### Arch Linux in WSL

Run `provisioning/arch/wsl-init.sh` as root once, restart WSL, then run
`provisioning/arch/bootstrap.sh --profile wsl`. The full import, password,
systemd, and validation flow is in
[Bootstrapping — WSL](docs/bootstrap.md#arch-linux-in-wsl).

## Layout

```text
home/                  chezmoi source state; mirrors the home directory
provisioning/arch/     Arch/WSL bootstrap, package lists, system files
  bootstrap.sh         user-level provisioning
  wsl-init.sh          one-time WSL root setup
  auth.sh              SSH, GitHub, gcloud, Tailscale, BWS, MCP auth
  audit.sh             package drift report
  tools/               optional font installer and completion generator
  lib/common.sh        shared shell helpers
  system/              pacman, reflector, sshd, and WSL support files
  packages/            tracked package lists and the font catalog
docs/                  task-oriented documentation
scripts/               developer entry points (lint, fmt, test, doctor)
tests/                 bats suites plus docs and template checks
```

`.chezmoiroot` points chezmoi at `home/`, so provisioning scripts, docs, and
tooling stay outside the managed home directory.

## Packages

There are 67 tracked package names: 61 apply to the native profile and 58 to
WSL. The lists live in `provisioning/arch/packages/` and split shared, native,
and WSL packages across official and AUR files. The bootstrap also manages the
OpenCode CLI outside those lists, and offers 18 optional Nerd Fonts that nothing
installs unless selected.

Adding a package is a two-step operation: install it normally, then add its name
to the appropriate list. The bootstrap adds missing packages and never removes
anything, and the audit makes drift visible:

```bash
./provisioning/arch/audit.sh --profile native            # full report
./provisioning/arch/audit.sh --profile native --check    # fail if tracked packages are missing
./provisioning/arch/audit.sh --profile native --strict   # also fail on untracked packages
```

See the [package catalog](docs/packages.md) for every package with its
environment badge, purpose, and configuration notes.

## Validation

The same entry points run locally and in CI:

```bash
just lint       # Bash syntax, ShellCheck, shfmt, fish, actionlint, Just, gitleaks
just test       # docs consistency, bats tests, and every chezmoi template render
just render     # template rendering only
lefthook run pre-commit
```

`just test` runs the docs checker first. It verifies the 67/61/58 package counts
against `provisioning/arch/packages/*.txt` and checks every relative Markdown
link and local asset.

## What is not managed

- Disk partitioning, LUKS, bootloader, `fstab`, `crypttab`
- Kernel, firmware, CPU microcode, GPU drivers
- Hostname, timezone, locale on native installs
- GNOME/dconf, browser profiles, app caches
- Private SSH keys, GPG keys, Bitwarden tokens, keyring contents
- Restic repository/password and backup schedule
- Tailscale account authentication and ACLs
- OpenCode provider credentials and MCP OAuth tokens
- Windows apps, WSL installation, Windows Terminal settings
- `/etc` broadly; the bootstrap only manages the pacman, reflector, firewall,
  and sshd files listed in [Bootstrapping](docs/bootstrap.md#system-maintenance),
  and `wsl-init.sh` handles the WSL-specific bootstrap files

If you later need reproducible desktop packages, add a `desktop.txt` list. If you
later target multiple machines with different GPUs, add a host-specific overlay.
Do not add that complexity before it is needed.
