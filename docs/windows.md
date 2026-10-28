# Windows

The Windows host is the layer that runs WSL and the terminal. It is not a
second dotfiles manager: only the small set of host tools and settings needed
by the Arch/WSL workflow is tracked here.

## Status

A read-only audit and a curated WinGet inventory are available. Nothing on the
Windows side is installed or changed by the repository yet. The audit checks
that WSL is installed and compares the installed WSL build with the latest
stable release.

## What is tracked

The audit compares the host against two lists:

- `provisioning/windows/packages/required.txt` — host tools the WSL workflow
  depends on. Missing required packages fail the audit.
- `provisioning/windows/packages/optional.txt` — desktop apps that mirror the
  Arch side. Missing optional packages are warnings.

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
| `Git.Git` | Optional | Windows-side Git and editor integration; WSL uses Linux Git. |
| `Docker.DockerDesktop` | Optional | Docker Desktop on Windows; not required by the Arch distro. |

WSL itself is a prerequisite, not a WinGet package here. The installed WSL
build may not exist in the WinGet source, so the audit checks `wsl --version`
and `wsl --list --verbose`; the documented update path is `wsl --update` from
Windows.

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

The audit never needs administrator rights. A future bootstrap will use normal
Windows UAC: run it from an elevated terminal, or let it relaunch itself and
approve the consent prompt on the desktop. WSL and the audit are already
reachable from WSL, but an elevated Windows child process does not share the WSL
shell's output; the bootstrap will log to a file so the result is visible.

The bootstrap will not reboot automatically. It will report when a reboot is
required, and the audit already warns about a pending reboot. WSL updates and
driver installs stay manual.

## From a fresh machine

The Windows host is prepared before the Arch import:

1. Install Windows and update it.
2. Install or update WSL from Windows (`wsl --update`).
3. Run the audit to see which required host tools are missing.
4. Install the required tools with WinGet; the installer is not automated yet.
5. Import Arch and run `provisioning/arch/wsl-init.sh` as root, then run
   `provisioning/arch/bootstrap.sh --profile wsl` as your user.
6. Run `just windows-audit` again from WSL.

The Linux bootstrap must not be run from Windows.

## What is not managed

- Disk partitioning, drivers, firmware, Windows updates, and WSL updates.
- Games, vendor utilities, and general application configuration.
- Windows Terminal settings, `.wslconfig`, and services; the audit only reports
  them.
- A second dotfiles manager or a Windows-side copy of the chezmoi state.

## Troubleshooting

- **The WSL wrapper cannot find PowerShell.** Enable WSL interop, or set
  `WINDOWS_POWERSHELL` to `pwsh.exe` or `powershell.exe`.
- **The script is blocked by the execution policy.** Run it with
  `-ExecutionPolicy Bypass`, as shown above.
- **`winget` is missing.** Install App Installer from the Microsoft Store.
- **The audit reports the SSH pipe but Bitwarden still prompts.** Check the
  Bitwarden authorization policy; `Always` blocks unattended commits. See
  [Authentication and SSH](auth.md#windows-ssh-agent-relay-wsl).
- **Terminal settings cannot be parsed.** Use PowerShell 7; Windows Terminal
  settings may contain comments that Windows PowerShell 5.1 cannot read.
- **A Terminal settings change did not appear.** Windows Terminal hot-reloads
  `settings.json`; if it still looks stale, reopen Terminal.

Back to [the documentation index](README.md) or [the project README](../README.md).
