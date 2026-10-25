# Documentation

Focused references sit beside the main README:

| Document | What it covers |
| --- | --- |
| [Package catalog](packages.md) | All 61 tracked packages, with Native/WSL badges, per-file counts, the mise toolchains, and the install → record → audit loop. |
| [Tips and tricks](tips-and-tricks.md) | Fish, Git, chezmoi, mise, WSL, secrets, OpenCode, recovery, and a small maintenance rhythm. |
| [Authentication and SSH](auth.md) | Key, GitHub, gcloud, Tailscale, BWS, and MCP setup and troubleshooting. |
| [Decisions](decisions.md) | Tooling-language rationale, optional Git defaults, and the BWS private-key decision. |

![Native and WSL provisioning flow](assets/provisioning-flow.svg)

The package lists are install-only. The bootstrap adds missing packages and
never removes anything; use the audit to make drift visible.

## Environment badges

| Badge | Meaning |
| --- | --- |
| <img src="assets/badge-both.svg" alt="Both" height="20"> | Native Arch and WSL |
| <img src="assets/badge-native.svg" alt="Native" height="20"> | Native Arch + GNOME only |
| <img src="assets/badge-wsl.svg" alt="WSL" height="20"> | Arch inside WSL only |
| <img src="assets/badge-aur.svg" alt="AUR" height="18"> | Arch User Repository |

## Back to

- [Project README](../README.md)
