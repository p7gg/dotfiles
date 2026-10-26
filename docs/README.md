# Documentation

Start with the task you need instead of reading everything:

| I need to... | Read |
| --- | --- |
| Set up a native Arch + GNOME machine | [Project README — native bootstrap](../README.md#native-arch--gnome) |
| Set up Arch inside WSL | [Project README — WSL bootstrap](../README.md#arch-linux-in-wsl) |
| Add, remove, or audit a package | [Package catalog](packages.md) |
| Fix SSH, GitHub, gcloud, Tailscale, BWS, or MCP auth | [Authentication and SSH](auth.md) |
| Look up a shell, Git, chezmoi, mise, WSL, or secrets workflow | [Tips and tricks](tips-and-tricks.md) |
| Recover a broken shell or dotfiles | [Tips — recovery moves](tips-and-tricks.md#recovery-moves) |
| Understand a design choice | [Decisions and rationale](decisions.md) |
| See the Windows-side status | [Windows notes](../windows/README.md) |

## Reference documents

| Document | What it covers |
| --- | --- |
| [Package catalog](packages.md) | All 67 tracked packages plus the installer-managed OpenCode CLI and 18 optional Nerd Fonts, with Native/WSL badges, per-file counts, the mise toolchains, and the install → record → audit loop. |
| [Tips and tricks](tips-and-tricks.md) | Fish, Git, chezmoi, mise, WSL, secrets, OpenCode, recovery, and a small maintenance rhythm. |
| [Authentication and SSH](auth.md) | Key, GitHub, gcloud, Tailscale, BWS, and MCP setup and troubleshooting. |
| [Decisions](decisions.md) | Tooling-language rationale, optional Git defaults, and the BWS private-key decision. |

![Native and WSL provisioning flow](assets/provisioning-flow.svg)

## Source of truth

`arch/packages/*.txt` and the scripts are the source of truth. The counts and
tables in these docs are descriptive; update them when the lists change. The
package lists are install-only: bootstrap adds missing packages and never
removes anything, and the audit makes drift visible.

## Environment badges

| Badge | Meaning |
| --- | --- |
| <img src="assets/badge-both.svg" alt="Both" height="20"> | Native Arch and WSL |
| <img src="assets/badge-native.svg" alt="Native" height="20"> | Native Arch + GNOME only |
| <img src="assets/badge-wsl.svg" alt="WSL" height="20"> | Arch inside WSL only |
| <img src="assets/badge-aur.svg" alt="AUR" height="18"> | Arch User Repository |

## Back to

- [Project README](../README.md)
- [Validation commands](../README.md#validation)
