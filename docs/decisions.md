# Decisions and rationale

Short design notes that are useful context but do not belong in the quick-start
README.

## Tooling language choices

A few notes on the requested tools:

- `gitui` is Rust and is the tracked Git TUI. `lazygit` is the Go alternative.
- `gitbutler` and its `but` CLI are Rust.
- Rust additions include `zellij`, `atuin`, `tealdeer`, `dust`, `git-delta`,
  `difftastic`, `git-absorb`, and `just`.
- Go tools include `gitleaks`, `lefthook`, `kubectl`, `restic`, `tailscale`,
  and `duf`. `ufw` and `google-cloud-cli` are Python.
- `github-cli` (Go), `google-cloud-cli` (Python), `opencode`,
  `t3code-nightly-bin`, and `yt-dlp` (Python) have no drop-in Rust replacements.
- `starship`, `mise`, `bat`, `eza`, `fd`, `ripgrep`, and `zoxide` are already
  written in Rust. `fzf` is Go; `skim` is a Rust alternative, but not a drop-in
  for the current fish integration.
- `fish` is C++; `nushell` is Rust but not fish-compatible.

## Explicit profile mismatches

Bootstrap treats an explicit `--profile` that contradicts the environment as a
blocking error: installing desktop packages in WSL, or WSL drivers on a desktop,
is almost always a mistake. Auto-detection remains the default, and
`--allow-profile-mismatch` is the narrow escape hatch for deliberate
cross-profile work. The audit only warns about the same mismatch because it is
read-only; inspecting another profile's drift is a legitimate use.

## Supply-chain pins

Two bootstrap steps execute code that is not covered by pacman's package
signatures:

- The OpenCode CLI is downloaded from OpenCode's npm release metadata and the
  tarball's published `sha512` integrity is verified before extraction. Set
  `OPENCODE_VERSION` to pin a release; `--no-opencode` skips it.
- `paru` is built from the AUR at the `PARU_COMMIT` value in
  `provisioning/arch/bootstrap.sh` instead of whatever is on AUR master at
  provisioning time. Bump that pin deliberately, after reviewing the PKGBUILD.

Upstream OpenCode uses npm's registry integrity metadata rather than a detached
installer signature. This repo verifies the published `sha512` integrity over
HTTPS but does not verify npm's registry signing keys; an optional
`OPENCODE_VERSION` pin adds reproducibility. Failing closed is intentional: a
missing or mismatched checksum stops bootstrap rather than installing an
unverified binary.

## Optional Git defaults

Worth considering later: `feature.manyFiles = true` for large repositories,
`diff.renames = copies`, and `push.followTags = true`. Avoid `merge.ff = only`
unless every repository enforces linear history.

## GNOME Keyring on both profiles

Native Arch already uses GNOME Keyring for the desktop and the SSH agent. WSL
used `pass` only because it has no PAM login to unlock a keyring; that split
doubled the secret paths and made the `bws` wrapper behave differently per
profile. Both profiles now install `gnome-keyring` and talk to the Secret Service
through `secret-tool`.

On WSL the login keyring is created with a blank password so the daemon can
unlock it without a login password. That is a deliberate tradeoff: the keyring
file is not meaningfully encrypted at rest, and the WSL VHDX plus the Windows
account are the boundary. A password-protected keyring is still possible, but it
must be unlocked once per WSL boot. Windows Hello PAM is not a solution: it
authenticates `sudo` and supplies no password to `pam_gnome_keyring`.

## Private SSH key in Bitwarden

Bitwarden has two different products:

- **Secrets Manager** (`bws`) is a secret store, not an SSH agent. Do not put the
  private key there: using it requires materializing the key somewhere, and the
  machine token becomes a second credential that can retrieve it.
- **Password Manager** has an SSH agent. It keeps the key in the vault, exposes
  the OpenSSH agent protocol on Windows, and prompts for authorization. That is
  the supported way to avoid a private key file on disk.

This repo uses the Password Manager agent **on WSL**; native Arch keeps the key
file and GNOME Keyring. On Windows, Bitwarden owns
`\\.\pipe\openssh-ssh-agent`; on WSL, `socat` + `npiperelay` expose that pipe as
`$XDG_RUNTIME_DIR/ssh-agent.sock`. Keep only the public key in WSL for
`user.signingkey` and `allowed_signers`, and keep an encrypted backup of the
private key outside the laptop.

If you absolutely must store the key in BWS, fetch it into `$XDG_RUNTIME_DIR`
with mode `0600`, add it to an agent, and delete it immediately; do not keep a
permanent copy in the repo or home directory.

## Back to

- [Documentation index](README.md)
- [Project README](../README.md)
