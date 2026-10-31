# Tooling and defaults

What chezmoi and bootstrap put on a machine, beyond packages and system files.
For package lists, see the [catalog](packages.md); for credentials, see
[authentication](auth.md).

## Fish

Fish is the interactive shell. `provisioning/arch/bootstrap.sh` installs it and
changes the login shell with `chsh`; provisioning scripts remain Bash.

Chezmoi manages:

```text
~/.config/fish/config.fish
~/.config/fish/conf.d/*.fish
~/.config/fish/functions/*.fish
```

The config uses `set -gx` and `abbr --add --global` rather than universal
variables, so nothing important is hidden in `fish_variables`. Fish history and
fish variables are not tracked.

`ch` opens the `fzf-checkout` branch picker. Local branches come first,
remote-tracking branches follow, and picking a remote branch creates a local
branch with the same name that tracks it. With arguments, `ch` defers to
`git checkout`, so `ch <branch>` and `ch -b <branch>` keep working. The Git alias
`git ch` uses the same picker.

`ports` opens the port browser. It reads `ss(8)` and lists TCP and UDP sockets
with their protocol, port, address, state, user, and process. `Tab` marks
multiple rows, `Enter` prints the selected port numbers, `Ctrl-Y` copies them to
the clipboard, and `Ctrl-K` sends `SIGTERM` to the selected processes after a
confirmation. The preview pane shows process details and the matching socket.
`ports --all` includes established connections, and `ports 8080` starts with a
pre-filled search.

`~/.local/bin`, `~/.opencode/bin`, and `~/.go/bin` are prepended once, in that
order of precedence. `mise`, starship, fzf, zoxide, and atuin are activated only
in interactive shells. Atuin is local-only; no sync login is set up.

## mise

Global toolchains live in `~/.config/mise/config.toml`:

- Node.js (latest global; pin project versions in each `mise.toml`)
- Bun
- pnpm
- `npm:@antfu/ni`
- `github:gittower/git-flow-next`, version 2.1.0, renamed to `git-flow`

Project-specific versions belong in each project's `mise.toml`, not in the
global config. After bootstrap:

```bash
mise install
mise ls
```

## Go

Go keeps its module cache and installed binaries in `~/.go` instead of the
default `~/go`. The location is set in `~/.config/go/env` via
`home/dot_config/go/env.tmpl`, so it applies in every shell and to tools that
invoke the `go` command. `~/.go/bin` is added to `PATH` by fish.

AUR packages are built before dotfiles are applied, so the bootstrap passes the
same `GOPATH` to `paru`. Source builds such as `lefthook` write to `~/.go`
instead of creating `~/go`.

## Completions

Package-provided fish completions in `/usr/share/fish/vendor_completions.d`
load automatically. That covers tools such as `gh`, `yt-dlp`, `mise`,
`chezmoi`, `starship`, `zoxide`, `ripgrep`, `tailscale`, `just`, and `atuin`.

`provisioning/arch/tools/completions.sh` generates the rest into
`~/.config/fish/completions/`:

- `pnpm completion fish`
- npm's bundled `completion.fish`
- `bun completions`
- `but completions fish`
- `opencode --completions fish`

The bootstrap runs it after `mise install`. Rerun it after upgrading tools:

```bash
./provisioning/arch/tools/completions.sh
```

`gcloud` does not ship an official fish completion. `gitui`, `bws`, `ni`, and
`git-flow` do not provide one either.

## OpenCode

The OpenCode CLI is installed from OpenCode's npm release, not from pacman.
Bootstrap reads the official release metadata from
`https://opencode.ai/update/api/latest/cli/npm`, downloads the platform tarball
from `registry.npmjs.org`, verifies the published `sha512` integrity value, and
only then installs `~/.opencode/bin/opencode`. When the installed version
already matches the target, it skips the download and reinstall.

```bash
# What bootstrap does, without the remote-script pipe:
# metadata -> registry.npmjs.org tarball -> sha512 check -> extract package/bin
```

By default the CLI tracks the latest release. Pin a reviewed version when
reproducibility matters:

```bash
OPENCODE_VERSION='<version>' ./provisioning/arch/bootstrap.sh --profile wsl
```

Use `--no-opencode` to skip the step. If the release metadata or checksum is
missing or does not match, bootstrap fails instead of installing an unverified
binary. Fish adds `~/.opencode/bin` to `PATH` through
`home/dot_config/fish/conf.d/10-path.fish`; `just doctor` verifies that
`opencode` resolves there. Update manually with `opencode upgrade`, or rerun
bootstrap.

The desktop app is a separate native-only AUR package,
`opencode-desktop-bin` in `provisioning/arch/packages/aur-native.txt`. It installs
`/usr/bin/opencode-desktop` and runs on the system Electron runtime; it does not
replace the `opencode` CLI.

Chezmoi tracks `~/.config/opencode/cli.json` with the current sidebar and diff
tree settings, and `~/.config/opencode/opencode.json` with the global MCP
servers. MCP servers are scoped to the projects that need them:

- `~/.config/opencode/opencode.json` — `context7` at
  `https://mcp.context7.com/mcp` and `gh_grep` at `https://mcp.grep.app` (both
  without authentication). They are available in every project.
- `~/Projects/opencode.json` — `linear`, at `https://mcp.linear.app/mcp`
  (OAuth), for personal projects.
- `~/Projects/work/opencode.json` — `jira`, at
  `https://mcp.atlassian.com/v2/mcp` (OAuth), and `linear` explicitly disabled,
  for work projects.

OpenCode merges configs from ancestor directories, so personal projects inherit
Linear from `~/Projects/opencode.json`. Work projects inherit that file too and
then override the `linear` server with `disabled: true` in the work config.

`provisioning/arch/auth.sh` signs in to Linear from `~/Projects` and Jira from
`~/Projects/work` through their OAuth flows. To authenticate later, run
`(cd ~/Projects && opencode mcp auth linear)` or
`(cd ~/Projects/work && opencode mcp auth jira)`, or use `/mcps` in OpenCode.
Context7 and `gh_grep` work without an API key. The tracked `opencode.json`
already sends `CONTEXT7_API_KEY` from the environment when it is set; export the
variable only if you want the higher rate limits.

OpenCode provider credentials and MCP OAuth tokens live outside the repo, and
`~/.config/opencode/service.json` is intentionally ignored because it contains a
local service password.

### Agents and context

T3 Code always runs the primary `build` agent (or `plan` in plan mode); it does
not expose OpenCode's agent picker. This setup keeps OpenCode's default agents
and does not install a custom subagent roster or orchestration instruction, so
`build` and `plan` behave like vanilla OpenCode.

The only additions are the `context7` and `gh_grep` MCP servers above and the
`reflect` skill below.

Global agent skills are tracked from `~/.agents/skills` and
`~/.agents/.skill-lock.json` under `home/dot_agents`. The lock records the source
repository and content hash for each skill; the skill folders are tracked so a
new machine can restore them with `chezmoi apply` without network access.

To update skills, run `just skills` (or `npx skills update -g` followed by
`chezmoi add ~/.agents`), review `chezmoi diff`, and commit the result. To add a
skill, run `npx skills add <owner/repo> -g -a opencode -s <skill>` and add it
the same way. Project-local skills under a repository's `.agents/skills` are not
managed by chezmoi; work repositories ignore those folders.

The custom `reflect` skill lives in `~/.config/opencode/skills/reflect/` and is
exposed as `/reflect`. It reviews recent work for repeated friction and proposes
the smallest reusable improvement; `--sessions` reads the local OpenCode session
database. It is adapted from the `oh-my-opencode-slim` reflect skill (MIT).

## Git defaults

Beyond SSH signing (see [authentication](auth.md)), the tracked Git config
enables:

- `rerere.enabled` and `rerere.autoupdate`
- `merge.conflictStyle = zdiff3`
- `diff.algorithm = histogram`
- `status.showUntrackedFiles = all`
- `commit.verbose = true`
- `fetch.writeCommitGraph = true`
- `column.ui = auto` and `branch.sort = -committerdate`
- `pull.rebase`, `rebase.autoStash`, `rebase.updateRefs`, and
  `push.autoSetupRemote`
- `delta` as the Git pager and `git dt` as the difftastic alias when those
  tools are installed

## Editor and application defaults

Chezmoi manages `~/.config/zed/settings.json` (keymap, fonts, telemetry off) and
`~/.config/mimeapps.list` for default application associations. The GitHub CLI
config is tracked as `~/.config/gh/config.yml`; `hosts.yml` stays untracked
because it is machine auth state and can contain an OAuth token.

## Next

- [Bootstrapping a machine](bootstrap.md) — install order and system changes.
- [Authentication and SSH](auth.md) — keys, GitHub, gcloud, Tailscale, BWS, MCP.
- [Back to the documentation index](README.md)
- [Back to the project README](../README.md)
