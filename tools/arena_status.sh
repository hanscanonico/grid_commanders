#!/usr/bin/env bash
# Live status for a running (or finished) `tools/arena_search.py` run.
#
#   tools/arena_status.sh [run-dir] [--watch]
#
# A search campaign is hours to days of headless matches, and its own output is
# a log that only speaks at wave boundaries. This reads the artifacts the run
# already writes — the pool's status line, each block's search.json — and says
# where it is now. It plays nothing, writes nothing and is safe to run against a
# live run: every read is of a file the driver has already closed.
#
# --watch redraws every 10s until interrupted; macOS ships no watch(1).
set -uo pipefail

ARENA_ROOT="reports/ai_arena"
RUN=""
WATCH=""
for arg in "$@"; do
	case "$arg" in
	--watch) WATCH=1 ;;
	*) RUN="$arg" ;;
	esac
done

# With no directory named, the newest run under reports/ai_arena/ — which is the
# one somebody is most likely watching. Refuse out loud rather than reporting an
# invented default as missing.
if [ -z "$RUN" ]; then
	RUN=$(ls -dt "$ARENA_ROOT"/*/ 2>/dev/null | head -1)
	RUN="${RUN%/}"
	if [ -z "$RUN" ]; then
		echo "arena-status: no run under $ARENA_ROOT — name one, or start one with \`make arena-search\`" >&2
		exit 1
	fi
fi

draw() {
	local run=$1
	if [ ! -d "$run" ]; then
		echo "arena-status: no run at $run" >&2
		return 1
	fi
	printf '=== %s ===\n' "$run"

	# Scoped to THIS run: a second campaign in another directory is somebody
	# else's, and reporting a finished run as live is the one lie that matters.
	local out="${run#reports/}"
	if pgrep -f "arena_search.py.*--out=(reports/)?$out" >/dev/null 2>&1; then
		printf 'state    RUNNING (%s godot workers)\n' \
			"$(pgrep -f "run_ai_arena.gd.*$out" 2>/dev/null | wc -l | tr -d ' ')"
	else
		printf 'state    not running\n'
	fi

	local status="$run/pool/status.txt"
	[ -f "$status" ] && printf 'pool     %s\n' "$(cat "$status")"

	# Per block: how many waves have finished, and the incumbent's score.
	printf '\n%-14s %6s  %-9s %s\n' block waves score dials-moved-from-base
	local block search
	for block in "$run"/*/; do
		search="$block/search.json"
		[ -f "$search" ] || continue
		python3 - "$search" "$(basename "$block")" <<'PY'
import json, signal, sys

signal.signal(signal.SIGPIPE, signal.SIG_DFL)  # piping to head is not an error
path, name = sys.argv[1], sys.argv[2]
try:
	d = json.load(open(path))
except (OSError, ValueError):
	sys.exit(0)  # mid-write; the next redraw catches it
waves = d.get("waves", [])
best = max((c["training"] for w in waves for c in w.get("candidates", [])), default=None)
inc = d.get("incumbent", {})
first = waves[0]["incumbent"] if waves else {}
moved = ", ".join(
	"%s %s->%s" % (k, first[k], v) for k, v in inc.items() if k in first and first[k] != v
)
score = "%+.3f" % best if best is not None else "-"  # a best of 0.0 is a score, not a gap
print("%-14s %6d  %-9s %s" % (name, len(waves), score, moved or "-"))
PY
	done
	printf '\n(held-out replay runs after a block finishes its waves)\n'
}

if [ -n "$WATCH" ]; then
	while true; do
		clear
		draw "$RUN"
		printf '\nrefreshing every 10s — ctrl-c to stop\n'
		sleep 10
	done
else
	draw "$RUN"
fi
