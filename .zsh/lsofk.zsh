# Kill processes on given ports
lsofk() {
	local pids

	pids=$(
		lsof -nP -iTCP -sTCP:LISTEN |
			awk 'NR > 1 {
				split($9, parts, ":")
				port = parts[length(parts)]
				printf "%-6s %-8s %s\n", port, $2, $1
			}' |
			sort -n |
			fzf \
				-m \
				--header='PORT   PID      COMMAND' \
				--preview 'ps -fp {2}' |
			awk '{ print $2 }'
	)

	[ -z "$pids" ] && return 0

	echo "$pids" | xargs kill
}