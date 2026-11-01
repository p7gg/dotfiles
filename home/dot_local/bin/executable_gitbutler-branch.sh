#!/usr/bin/env bash
#
# Starship segment for GitButler-managed repositories.
#
# Runs only when the checkout is managed by GitButler: the `gitbutler` data
# directory exists and either HEAD is parked on a `gitbutler/*` branch
# (workspace mode) or `refs/heads/gitbutler/target` exists (single-branch
# mode). Everywhere else it prints nothing and starship's own [git_branch]
# keeps rendering the branch. In workspace mode [git_branch] ignores
# `gitbutler/workspace`, so this module is the only branch segment there.
#
# Output is plain text apart from bold SGR codes around the branch ids, so
# starship still owns the colour and style.
#
#   ⧓ gs:feat ⇡2 › at:feat-part-2 ⇡ | br:hotfix   two stacks, the first chained
#   ⧓ workspace                                   managed repo, nothing applied
#   ⧓ gs:feat ⇡2 ⇣1                               target is one commit ahead
#   ⧓ ?                                           `but status --json` failed
#
# Each branch is prefixed with the two-letter id from `but status --json`
# (bold), the same id `but status` prints and other commands accept, e.g.
# `but merge gs`. The prefix is dropped when the JSON carries no id.
#
# Markers:
#   ⇡N  commits on the branch, nothing pushed yet (exact count)
#   ⇡   some commits are unpushed (--json has no exact count for this case)
#   ⇡!  unpushed commits were rewritten, a force push is needed
#   ⇣N  the target has N commits the workspace base lacks (`but pull`)
#
# `but status --json` takes tens of milliseconds, so starship.toml sets
# ignore_timeout for this module and the call is bounded here instead.

set -u
set -o pipefail

SYMBOL="⧓"
FAILED="?"
TIMEOUT="${BUT_TIMEOUT:-1}"

# Branches in one stack are chained with › (newest first, like `but status`);
# stacks are separated with |. Branch status is the only signal `but` gives for
# unpushed work, so a count is shown only when every commit is unpushed.
# The program is deliberately single-quoted: Bash must not expand jq variables.
# shellcheck disable=SC2016
JQ='
  def mark:
    (.commits | length) as $n
    | if $n == 0 then ""
      elif .branchStatus == "completelyUnpushed" then " ⇡\($n)"
      elif .branchStatus == "unpushedCommitsRequiringForce" then " ⇡!"
      elif .branchStatus == "unpushedCommits" then " ⇡"
      else "" end;
  def with_id:
    (.cliId // "") as $id
    | if $id == "" then .name
      else "\u001b[1m" + $id + "\u001b[22m:" + .name
      end;
  [ .stacks[]?
    | [ .branches[]? | select(.name != null and .name != "") | with_id + mark ]
    | select(length > 0)
    | join(" › ")
  ] as $stacks
  | (if ($stacks | length) == 0 then "workspace" else ($stacks | join(" | ")) end)
    + (if (.upstreamState.behind // 0) > 0
       then " ⇣" + (.upstreamState.behind | tostring)
       else "" end)
'

stacks_text() {
    local text
    text="$(
        if command -v timeout >/dev/null 2>&1; then
            timeout "$TIMEOUT" but status --json 2>/dev/null
        else
            but status --json 2>/dev/null
        fi | jq -r "$JQ" 2>/dev/null
    )" || text=""
    printf '%s' "${text:-$FAILED}"
}

# A repository is managed once GitButler has initialized its workspace:
# either HEAD points at a workspace branch, or `but` has recorded a target
# (which is what it does the first time a branch is applied). The data
# directory alone is not enough: opening a repository in the app once leaves
# one behind.
managed() {
    git show-ref --verify --quiet refs/heads/gitbutler/target && return 0
    case "$1" in
    refs/heads/gitbutler/*) return 0 ;;
    esac
    return 1
}

main() {
    local head gbdir

    head="$(git symbolic-ref --quiet HEAD 2>/dev/null)" || head=""
    gbdir="$(git rev-parse --git-path gitbutler 2>/dev/null)" || gbdir=""

    if [ -z "$gbdir" ] || [ ! -d "$gbdir" ]; then
        # A gitbutler/* branch without workspace data, for example a clone
        # that only has the branch. Print the branch name because [git_branch]
        # ignores it, but do not pretend this is a workspace.
        case "$head" in
        refs/heads/gitbutler/*) printf '%s' "${head#refs/heads/}" ;;
        esac
        return 0
    fi

    managed "$head" || return 0

    printf '%s %s' "$SYMBOL" "$(stacks_text)"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main
fi
