#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    TEST_TMP="$(mktemp -d)"
    TEST_BIN="$TEST_TMP/bin"
    mkdir -p "$TEST_BIN"

    export SS_FIXTURE_FILE="$TEST_TMP/ss-fixture"
    export SS_ARGS_FILE="$TEST_TMP/ss-args"
    export PS_ARGS_FILE="$TEST_TMP/ps-args"
    export FZF_INPUT="$TEST_TMP/fzf-input"
    export FZF_ARGS_FILE="$TEST_TMP/fzf-args"
    export KILL_ARGS_FILE="$TEST_TMP/kill-args"

    cat >"$SS_FIXTURE_FILE" <<'EOF'
tcp LISTEN 0 4096 127.0.0.1:8080 0.0.0.0:* users:(("node",pid=111,fd=20))
tcp LISTEN 0 128 [::]:22 [::]:* users:(("sshd",pid=222,fd=3))
udp UNCONN 0 0 0.0.0.0:5353 0.0.0.0:* users:(("avahi-daemon",pid=333,fd=12))
tcp LISTEN 0 511 127.0.0.1:3000 0.0.0.0:* users:(("bun",pid=444,fd=8))
EOF

    cat >"$TEST_BIN/ss" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${SS_ARGS_FILE:?}"
port=
for argument in "$@"; do
    if [[ "$argument" == "sport = :"* ]]; then
        port="${argument##*:}"
    fi
done
if [[ -n "$port" ]]; then
    grep -F ":$port " "$SS_FIXTURE_FILE" | head -n 1 || true
else
    cat "$SS_FIXTURE_FILE"
fi
EOF

    cat >"$TEST_BIN/ps" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${PS_ARGS_FILE:?}"
case "$*" in
    *"pid=,ppid="*)
        echo "111 1 gabriel Sl 0.4 1.2 02:14:03"
        ;;
    *"args="*)
        echo "/usr/bin/node server.js"
        ;;
    *"user="*)
        case "$*" in
            *"-p 333"*) echo root ;;
            *) echo gabriel ;;
        esac
        ;;
    *)
        echo "111 1 gabriel Sl 0.4 1.2 02:14:03"
        ;;
esac
EOF

    cat >"$TEST_BIN/fzf" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >"${FZF_ARGS_FILE:?}"
cat >"${FZF_INPUT:?}"

if [[ -n "${FZF_ACTION:-}" ]]; then
    printf '%s\n' "$FZF_ACTION"
fi

if [[ -n "${FZF_PORTS:-}" ]]; then
    awk -v ports="$FZF_PORTS" '
        BEGIN {
            count = split(ports, wanted, " ")
            for (i = 1; i <= count; i++) {
                want[wanted[i]] = 1
            }
        }
        {
            split($0, fields, "\t")
            if (fields[2] in want) {
                print $0
            }
        }
    ' "$FZF_INPUT"
fi
EOF

    cat >"$TEST_BIN/kill" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${KILL_ARGS_FILE:?}"
EOF

    chmod +x "$TEST_BIN/ss" "$TEST_BIN/ps" "$TEST_BIN/fzf" "$TEST_BIN/kill"

    unset FZF_ACTION FZF_PORTS
    export PATH="$TEST_BIN:$PATH"
    export REPO_ROOT
}

teardown() {
    rm -rf "$TEST_TMP"
}

@test "prints the selected port" {
    export FZF_PORTS=8080

    run fish -c "source '$REPO_ROOT/home/dot_config/fish/functions/ports.fish'; ports"

    [ "$status" -eq 0 ]
    [ "$output" = "8080" ]
    grep -q "node" "$FZF_INPUT"
    grep -q "gabriel" "$FZF_INPUT"
}

@test "multi-select prints each port once in numeric order" {
    export FZF_PORTS="8080 3000 8080"

    run fish -c "source '$REPO_ROOT/home/dot_config/fish/functions/ports.fish'; ports"

    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "3000" ]
    [ "${lines[1]}" = "8080" ]
}

@test "default mode asks ss for listening sockets" {
    export FZF_PORTS=8080

    run fish -c "source '$REPO_ROOT/home/dot_config/fish/functions/ports.fish'; ports"

    [ "$status" -eq 0 ]
    grep -q -- "-l" "$SS_ARGS_FILE"
    ! grep -q -- "-a" "$SS_ARGS_FILE"
}

@test "--all asks ss for every socket" {
    export FZF_PORTS=22

    run fish -c "source '$REPO_ROOT/home/dot_config/fish/functions/ports.fish'; ports --all"

    [ "$status" -eq 0 ]
    grep -q -- "-a" "$SS_ARGS_FILE"
    ! grep -q -- "-l" "$SS_ARGS_FILE"
}

@test "preview shows process and socket details" {
    run fish -c "source '$REPO_ROOT/home/dot_config/fish/functions/ports.fish'; ports --preview 8080 111 TCP"

    [ "$status" -eq 0 ]
    [[ "$output" == *"process"* ]]
    [[ "$output" == *"gabriel"* ]]
    [[ "$output" == *"/usr/bin/node server.js"* ]]
    [[ "$output" == *"127.0.0.1:8080"* ]]
}

@test "--yes sends SIGTERM to every selected pid" {
    export FZF_ACTION=ctrl-k
    export FZF_PORTS="8080 3000"

    run fish -c "source '$REPO_ROOT/home/dot_config/fish/functions/ports.fish'; ports --yes"

    [ "$status" -eq 0 ]
    grep -q -- "-TERM 111" "$KILL_ARGS_FILE"
    grep -q -- "-TERM 444" "$KILL_ARGS_FILE"
}
