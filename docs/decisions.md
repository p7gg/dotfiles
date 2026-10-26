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
  `arch/bootstrap.sh` instead of whatever is on AUR master at provisioning time.
  Bump that pin deliberately, after reviewing the PKGBUILD.

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

## Private SSH key in Bitwarden Secrets Manager?

Technically BWS can store any secret, including a private key. In practice, do
not do it:

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

## Back to

- [Documentation index](README.md)
- [Project README](../README.md)
