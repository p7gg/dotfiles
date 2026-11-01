#!/usr/bin/env bats

# The segment is a starship custom module that shells out to `but status
# --json`. These tests stub `but` so they do not need a real GitButler
# workspace, and drive the detection with a throwaway git repository.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SEGMENT="$REPO_ROOT/home/dot_local/bin/executable_gitbutler-branch.sh"
    TEST_TMP="$(mktemp -d)"

    command -v jq >/dev/null || skip "jq is not installed"
    command -v git >/dev/null || skip "git is not installed"

    REPO="$TEST_TMP/repo"
    git init -q -b main "$REPO"

    # Put a fake `but` first on PATH. It prints $BUT_FIXTURE, or exits with
    # $BUT_EXIT when that is set.
    mkdir -p "$TEST_TMP/bin"
    cat >"$TEST_TMP/bin/but" <<'FAKE'
#!/usr/bin/env bash
if [ -n "${BUT_EXIT:-}" ]; then
    exit "$BUT_EXIT"
fi
cat "${BUT_FIXTURE:-/dev/null}"
FAKE
    chmod +x "$TEST_TMP/bin/but"
    export PATH="$TEST_TMP/bin:$PATH"

    cd "$REPO" || return 1
}

teardown() {
    rm -rf "$TEST_TMP"
}

# fixture writes the `but status --json` output that the fake `but` returns.
fixture() {
    cat >"$TEST_TMP/but.json"
    export BUT_FIXTURE="$TEST_TMP/but.json"
}

# managed marks the repository as a GitButler workspace: a data directory plus
# HEAD parked on the synthetic workspace branch.
managed() {
    mkdir -p "$REPO/.git/gitbutler"
    git symbolic-ref HEAD refs/heads/gitbutler/workspace
}

# single_branch marks a repository that GitButler manages while a normal branch
# is checked out (its single-branch mode): no workspace ref, but a target ref.
single_branch() {
    mkdir -p "$REPO/.git/gitbutler"
    git -c user.email=test@example.com -c user.name=Test \
        commit -q --allow-empty -m base
    git update-ref refs/heads/gitbutler/target HEAD
}

@test "prints nothing outside a git repository" {
    cd "$TEST_TMP" || return 1

    run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "prints nothing in a plain git repository" {
    run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "prints nothing when only a leftover gitbutler directory exists" {
    mkdir -p "$REPO/.git/gitbutler"

    run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "prints the branch when the gitbutler directory is missing" {
    git symbolic-ref HEAD refs/heads/gitbutler/workspace

    run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = "gitbutler/workspace" ]
}

@test "renders stacks in single-branch mode" {
    single_branch
    fixture <<'JSON'
{"stacks":[
  {"cliId":"g0","branches":[
    {"name":"feat","commits":[{"commitId":"a"}],
     "upstreamCommits":[],"branchStatus":"completelyUnpushed"}
  ]}
]}
JSON

    run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = "⧓ feat ⇡1" ]
}

@test "marks the checked-out branch and shows ids only in single-branch mode" {
    single_branch
    fixture <<'JSON'
{"stacks":[
  {"cliId":"g0","branches":[
    {"cliId":"gs","name":"main","commits":[{"commitId":"a"}],
     "upstreamCommits":[],"branchStatus":"completelyUnpushed"},
    {"cliId":"at","name":"feat-part-2","commits":[{"commitId":"b"}],
     "upstreamCommits":[],"branchStatus":"completelyUnpushed"}
  ]}
]}
JSON

    run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = $'⧓ \e[1m▸gs\e[22m ⇡1 › \e[1mat\e[22m ⇡1' ]
}

@test "marks a checked-out branch without an id" {
    single_branch
    fixture <<'JSON'
{"stacks":[
  {"cliId":"g0","branches":[
    {"name":"main","commits":[{"commitId":"a"}],
     "upstreamCommits":[],"branchStatus":"completelyUnpushed"}
  ]}
]}
JSON

    run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = $'⧓ \e[1m▸\e[22m ⇡1' ]
}

@test "renders an empty workspace" {
    managed
    fixture <<'JSON'
{"uncommittedChanges":[],"stacks":[],"mergeBase":null,"upstreamState":null}
JSON

    run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = "⧓ workspace" ]
}

@test "renders one stack with an unpushed commit count" {
    managed
    fixture <<'JSON'
{"stacks":[
  {"cliId":"g0","branches":[
    {"name":"feat","commits":[{"commitId":"a"},{"commitId":"b"}],
     "upstreamCommits":[],"branchStatus":"completelyUnpushed"}
  ]}
]}
JSON

    run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = "⧓ feat ⇡2" ]
}

@test "renders several stacks separated by a pipe" {
    managed
    fixture <<'JSON'
{"stacks":[
  {"cliId":"g0","branches":[
    {"name":"feat","commits":[{"commitId":"a"}],
     "upstreamCommits":[],"branchStatus":"completelyUnpushed"}
  ]},
  {"cliId":"h0","branches":[
    {"name":"hotfix","commits":[],"upstreamCommits":[],
     "branchStatus":"completelyUnpushed"}
  ]}
]}
JSON

    run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = "⧓ feat ⇡1 | hotfix" ]
}

@test "prefixes branches with their but CLI id" {
    managed
    fixture <<'JSON'
{"stacks":[
  {"cliId":"g0","branches":[
    {"cliId":"gs","name":"feat","commits":[{"commitId":"a"}],
     "upstreamCommits":[],"branchStatus":"completelyUnpushed"}
  ]}
]}
JSON

    run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = $'⧓ \e[1mgs\e[22m:feat ⇡1' ]
}

@test "chains branches inside one stack" {
    managed
    fixture <<'JSON'
{"stacks":[
  {"cliId":"g0","branches":[
    {"cliId":"at","name":"feat-part-2","commits":[{"commitId":"c"}],
     "upstreamCommits":[],"branchStatus":"unpushedCommits"},
    {"cliId":"gs","name":"feat","commits":[{"commitId":"a"},{"commitId":"b"}],
     "upstreamCommits":[],"branchStatus":"completelyUnpushed"}
  ]}
]}
JSON

    run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = $'⧓ \e[1mat\e[22m:feat-part-2 ⇡ › \e[1mgs\e[22m:feat ⇡2' ]
}

@test "does not invent a count for partially pushed branches" {
    managed
    fixture <<'JSON'
{"stacks":[
  {"cliId":"g0","branches":[
    {"name":"feat","commits":[{"commitId":"a"},{"commitId":"b"},
     {"commitId":"c"},{"commitId":"d"}],"upstreamCommits":[],
     "branchStatus":"unpushedCommits"}
  ]}
]}
JSON

    run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = "⧓ feat ⇡" ]
}

@test "marks rewritten unpushed commits as needing a force push" {
    managed
    fixture <<'JSON'
{"stacks":[
  {"cliId":"g0","branches":[
    {"name":"feat","commits":[{"commitId":"a"}],"upstreamCommits":[],
     "branchStatus":"unpushedCommitsRequiringForce"}
  ]}
]}
JSON

    run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = "⧓ feat ⇡!" ]
}

@test "hides the marker once a branch is pushed" {
    managed
    fixture <<'JSON'
{"stacks":[
  {"cliId":"g0","branches":[
    {"name":"feat","commits":[{"commitId":"a"},{"commitId":"b"}],
     "upstreamCommits":[],"branchStatus":"nothingToPush"}
  ]}
]}
JSON

    run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = "⧓ feat" ]
}

@test "shows how far the target is ahead of the workspace base" {
    managed
    fixture <<'JSON'
{"stacks":[
  {"cliId":"g0","branches":[
    {"name":"feat","commits":[{"commitId":"a"}],"upstreamCommits":[],
     "branchStatus":"completelyUnpushed"}
  ]}
],"upstreamState":{"behind":2}}
JSON

    run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = "⧓ feat ⇡1 ⇣2" ]
}

@test "skips branches without a name" {
    managed
    fixture <<'JSON'
{"stacks":[
  {"cliId":"g0","branches":[
    {"name":"","commits":[{"commitId":"a"}],"upstreamCommits":[],
     "branchStatus":"completelyUnpushed"},
    {"name":"good","commits":[{"commitId":"b"}],"upstreamCommits":[],
     "branchStatus":"completelyUnpushed"}
  ]}
]}
JSON

    run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = "⧓ good ⇡1" ]
}

@test "reports a failed but read" {
    managed
    fixture </dev/null
    export BUT_EXIT=1

    run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = "⧓ ?" ]
}

@test "reports empty output from but as a failure" {
    managed
    fixture </dev/null

    run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = "⧓ ?" ]
}

@test "reports malformed json as a failure" {
    managed
    fixture <<'JSON'
{"stacks": [ this is not json
JSON

    run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = "⧓ ?" ]
}

@test "reports a hung but as a failure" {
    command -v timeout >/dev/null || skip "timeout is not installed"

    managed
    cat >"$TEST_TMP/bin/but" <<'FAKE'
#!/usr/bin/env bash
sleep 5
FAKE
    chmod +x "$TEST_TMP/bin/but"

    BUT_TIMEOUT=0.2 run bash "$SEGMENT"

    [ "$status" -eq 0 ]
    [ "$output" = "⧓ ?" ]
}
