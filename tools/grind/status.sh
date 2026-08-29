#!/usr/bin/env bash
#
# Where the grind box is right now.
#
#   tools/grind/status.sh [--watch]     (or: make grind-status)
#
# The digest is written after a job; this is for while one is running. It reads
# the artifacts the supervisor and the instruments already write —
# `reports/grind/state.json`, the pool's `status.txt`, each search's own
# `tools/arena_status.sh` — and says what is being played, since when, and what
# is still queued. It plays nothing and writes nothing.
#
# --watch redraws every 10s until interrupted; macOS ships no watch(1).
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
STATE="$ROOT/reports/grind/state.json"
WATCH=""
for arg in "$@"; do
	case "$arg" in
	--watch) WATCH=1 ;;
	*)
		echo "grind-status: unknown flag '$arg'" >&2
		exit 2
		;;
	esac
done

draw() {
	if [ ! -f "$STATE" ]; then
		echo "grind-status: no run yet — start one with \`make grind\`" >&2
		return 1
	fi
	local job phase
	python3 - "$STATE" <<'PY'
import json, sys, time

state = json.load(open(sys.argv[1]))
started = int(state.get("started") or 0)
elapsed = int(time.time()) - started if started else 0
print("host     %s" % state.get("host", "?"))
print("commit   %s" % state.get("sha", "?"))
print("pass     %s" % state.get("pass", "?"))
print("phase    %s" % state.get("phase", "?"))
print("job      %s%s" % (state.get("job") or "(none)", " for %ds" % elapsed if started else ""))
print("queued   %s" % (", ".join(state.get("queue", [])) or "-"))
PY
	job=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("job") or "")' "$STATE")
	phase=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("phase") or "")' "$STATE")
	[ "$phase" = running ] || return 0
	printf '\n--- %s ---\n' "$job"
	case "$job" in
	arena-search-*)
		# The search has a status reader of its own; a second one here would be a
		# second opinion about how far a campaign has got.
		(cd "$ROOT" && tools/arena_status.sh "reports/ai_arena/search/${job#arena-search-}")
		;;
	balance-pool-*)
		cat "$ROOT/reports/balance_pool/grind_${job#balance-pool-}/status.txt" 2>/dev/null ||
			echo "(no shard has reported yet)"
		;;
	*)
		local log
		log=$(ls -t "$ROOT/reports/grind/logs/$job"-*.log 2>/dev/null | head -1)
		if [ -n "$log" ]; then
			grep -v '^[[:space:]]*$' "$log" | tail -5
		else
			echo "(no log yet)"
		fi
		;;
	esac
}

if [ -n "$WATCH" ]; then
	while true; do
		clear
		draw
		printf '\nrefreshing every 10s — ctrl-c to stop\n'
		sleep 10
	done
else
	draw
fi
