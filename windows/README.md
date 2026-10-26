# Windows

Intentionally empty for now.

Back to [the documentation index](../docs/README.md) or [the project README](../README.md).

This machine is expected to use WSL for Linux development, so the Windows side
only needs a small number of applications and a few host settings. When that is
actually needed, add:

- a curated WinGet manifest or a short list of package IDs
- optional Windows Terminal settings, copied with a backup
- optional `.wslconfig`

Do not add a second dotfiles manager here, and do not run the Linux bootstrap
from Windows.
