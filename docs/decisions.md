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
