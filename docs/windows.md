# Windows

The Windows host is the layer that runs WSL and the terminal. It is not a
second dotfiles manager: only the host tools and chosen desktop apps needed by
the Arch/WSL workflow are tracked here.

## Status

A read-only audit and an install-only WinGet bootstrap are available. The
bootstrap installs missing packages only; it never uninstalls or upgrades
anything. The audit checks that WSL is installed and compares the installed WSL
build with the latest stable release.

## What is tracked

The audit compares the host against two lists:

- `provisioning/windows/packages/required.txt` — host tools the WSL workflow
  depends on. Missing required packages fail the audit.
- `provisioning/windows/packages/optional/` — desktop apps and utilities worth
  reproducing on a fresh machine, split into `apps.txt`, `games.txt`, and
  `hardware.txt`. Missing optional packages are warnings.

### Windows package inventory

| Package ID | Class | Purpose |
| --- | --- | --- |
| `Microsoft.WindowsTerminal` | Required | Terminal host for the `archlinux` WSL profile. |
| `Microsoft.PowerShell` | Required | PowerShell 7 host for the Windows scripts. |
| `Bitwarden.Bitwarden` | Required | Password Manager and the SSH agent that signs commits from WSL. |
| `albertony.npiperelay` | Required | Exposes the Windows SSH agent pipe to WSL. |
| `Brave.Brave` | Optional | Browser tracked on the native Arch side. |
| `Microsoft.VisualStudioCode` | Optional | Editor tracked on the native Arch side. |
| `SST.OpenCodeDesktop` | Optional | OpenCode desktop app tracked on the native Arch side. |
| `T3Tools.T3Code` | Optional | T3 Code tracked on the native Arch side. |
| `Docker.DockerDesktop` | Optional | Docker Desktop on Windows; not required by the Arch distro. |
| `Microsoft.PowerToys` | Optional | Windows utilities. |
| `OctasoftLtd.WSLUI` | Optional | WSL management GUI. |
| `Discord.Discord` | Optional | Chat. |
| `LinearOrbit.Linear` | Optional | Issue tracking. |
| `Mozilla.Thunderbird` | Optional | Email. |
| `Spotify.Spotify` | Optional | Music streaming. |
| `Stremio.Stremio.Beta` | Optional | Media center. |
| `Blizzard.BattleNet` | Optional | Battle.net game launcher. |
| `ElectronicArts.EADesktop` | Optional | EA game launcher. |
| `EpicGames.EpicGamesLauncher` | Optional | Epic Games launcher. |
| `Valve.Steam` | Optional | Steam game launcher. |
| `Devolutions.UniGetUI` | Optional | GUI front-end for WinGet; provisioning still uses WinGet directly. |
| `memstechtips.Winhance` | Optional | Windows tweaking utility; review its changes before applying. |
| `Guru3D.Afterburner` | Optional | GPU tuning utility. |
| `Guru3D.RTSS` | Optional | GPU overlay and statistics. |
| `NZXT.CAM` | Optional | NZXT hardware utility. |

WSL itself is a prerequisite, not a WinGet package here. The installed WSL
build may not exist in the WinGet source, so the audit checks `wsl --version`
and `wsl --list --verbose`; the documented update path is `wsl --update` from
Windows.

All tracked WinGet IDs resolve with
`winget show --id <id> -e --source winget`. Add a package only after that check
passes.

`Tw93.Mole` is installed on the current host but is not available from the
WinGet source, so it is not part of the inventory. Install it manually or add a
supported source before tracking it.

`Spotify.Spotify` is installed from the Store on this host; the WinGet ID is the
one a fresh machine would use, so the audit may report it as missing here.

## Run the audit

From WSL, inside the repository:

```bash
just windows-audit
```

From Windows, from a repository checkout:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\provisioning\windows\audit.ps1
```

Windows PowerShell 5.1 also runs the audit, but it cannot parse Windows Terminal
settings that contain JSONC comments; the audit reports that as a warning. The
WSL wrapper prefers `pwsh.exe` and falls back to `powershell.exe`.

Use `-Strict` to treat warnings as failures:

```bash
just windows-audit -Strict
```

The WSL update check calls the GitHub releases API. Pass `-NoUpdateCheck` to
keep the audit offline:

```bash
just windows-audit -NoUpdateCheck
```

The audit is read-only. It does not install packages, change services, edit
Terminal settings, or write `.wslconfig`. WinGet may refresh its local source
metadata while answering queries.

## Run the bootstrap

The bootstrap installs missing required packages by default. Validate first,
then preview, then install:

```bash
just windows-check          # prerequisites and package lists only
just windows-dry-run        # print the WinGet commands
just windows-bootstrap      # install missing required packages
```

Optional categories are opt-in:

```bash
just windows-bootstrap -Optional apps
just windows-bootstrap -Optional apps,games
just windows-bootstrap -Optional all
```

Use `-Yes` for unattended runs. When run through the WSL wrapper, the
confirmation prompt happens in the WSL terminal; `-Yes` skips it. The bootstrap
skips packages that are already installed and never removes or upgrades
anything. If an installer needs its UI, rerun with `-NoSilent`. If a reboot is
pending, the bootstrap refuses to start unless `-Force` is passed.

From Windows, run the PowerShell script directly:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\provisioning\windows\bootstrap.ps1 -Check
pwsh -NoProfile -ExecutionPolicy Bypass -File .\provisioning\windows\bootstrap.ps1 -DryRun
pwsh -NoProfile -ExecutionPolicy Bypass -File .\provisioning\windows\bootstrap.ps1
```

## What the audit checks

- Windows build and architecture (Windows 11 is the documented target).
- Pending reboots.
- WinGet and the tracked package IDs.
- WSL installation, version, latest stable release, and default distro; WSL 2
  is expected.
- `.wslconfig` values when the file exists.
- Windows Terminal settings: default profile, default font, color scheme.
- The `ssh-agent` service state and the `openssh-ssh-agent` pipe.
- The `npiperelay.exe` path used by the WSL relay.

## Manual steps

These are intentionally not automated because they involve credentials, a
running GUI application, or a Windows-side choice:

1. Enable the SSH agent in Bitwarden: **Settings → App settings (all accounts)
   → Enable SSH agent**. See
   [Authentication and SSH](auth.md#windows-ssh-agent-relay-wsl).
2. Disable the Windows OpenSSH Authentication Agent service so Bitwarden can own
   the pipe:

   ```powershell
   Set-Service -Name ssh-agent -StartupType Disabled
   Stop-Service -Name ssh-agent
   ```

3. Set a Nerd Font in Windows Terminal if you want icons and consistent glyphs:
   **Settings → Profiles → Defaults → Appearance → Font face**.
4. Keep WSL current with `wsl --update` from Windows. The audit warns when the
   installed build is behind the latest stable release, but the update itself
   stays manual.

## Elevation and reboots

Neither the audit nor `-Check`/`-DryRun` needs administrator rights. Run a real
bootstrap as your normal user: WinGet requests UAC for installers that need
machine-scope elevation, and the consent prompt appears on the desktop. If a
package fails because it needs elevation and the prompt cannot appear, rerun the
bootstrap from an elevated terminal.

The bootstrap will not reboot automatically. It refuses to start with a pending
reboot unless `-Force` is passed, then re-checks and reports when a reboot is
required after installing. WSL updates and driver installs stay manual.

## From a fresh machine

The Windows host is prepared before the Arch import:

1. Install Windows and update it.
2. Install or update WSL from Windows (`wsl --update`).
3. Run `just windows-audit` to see which required host tools are missing.
4. Run `just windows-check`, then `just windows-dry-run`, then
   `just windows-bootstrap`. Add `-Optional apps` if you want the optional
   application set.
5. Import Arch and run `provisioning/arch/wsl-init.sh` as root, then run
   `provisioning/arch/bootstrap.sh --profile wsl` as your user.
6. Run `just windows-audit` again from WSL.

The Linux bootstrap must not be run from Windows.

## What is not managed

- Disk partitioning, drivers, firmware, Windows updates, and WSL updates.
- Games themselves, vendor utilities, and general application configuration.
- Windows Terminal settings, `.wslconfig`, and services; the audit only reports
  them.
- A second dotfiles manager or a Windows-side copy of the chezmoi state.

The bootstrap installs missing WinGet packages from the tracked lists; it does
not remove or upgrade them.

## Troubleshooting

- **The WSL wrapper cannot find PowerShell.** Enable WSL interop, or set
  `WINDOWS_POWERSHELL` to `pwsh.exe` or `powershell.exe`.
- **The script is blocked by the execution policy.** Run it with
  `-ExecutionPolicy Bypass`, as shown above.
- **`winget` is missing.** Install App Installer from the Microsoft Store.
- **A package installer needs its UI.** Rerun the bootstrap with `-NoSilent`.
- **The bootstrap refuses to start.** A reboot is pending; reboot first, or
  pass `-Force` if you deliberately want to continue.
- **The audit reports the SSH pipe but Bitwarden still prompts.** Check the
  Bitwarden authorization policy; `Always` blocks unattended commits. See
  [Authentication and SSH](auth.md#windows-ssh-agent-relay-wsl).
- **Terminal settings cannot be parsed.** Use PowerShell 7; Windows Terminal
  settings may contain comments that Windows PowerShell 5.1 cannot read.
- **A Terminal settings change did not appear.** Windows Terminal hot-reloads
  `settings.json`; if it still looks stale, reopen Terminal.

Back to [the documentation index](README.md) or [the project README](../README.md).
