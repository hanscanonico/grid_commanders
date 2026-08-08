#!/usr/bin/env bash
#
# The determinism gate (balance plan D1). Plays one pinned Balance Lab match and
# byte-diffs its report against the golden committed under
# tests/fixtures/determinism/.
#
# D1's merge bar for touching the shared match loop is "a fixed-seed byte-diff of
# both reports". That was a procedure nobody could run: reports/ is gitignored,
# so there was no committed side to diff against. This is that side, small enough
# to run on every change — one map, one seed, no command log, about a second.
#
# The golden is committed, so it has to reproduce on a machine that is not the
# one that wrote it — and it does so by construction rather than by luck: the
# seed is pinned, so no hash-derived one enters, and nothing under core/ or ai/
# calls a transcendental, so every number in the pair comes out of integer and
# IEEE-754 double arithmetic any platform reproduces.
#
# Usage:  tools/check_determinism.sh [--refresh]
#
# `--refresh` (make determinism REFRESH=1) rewrites the golden. A rules, data or
# planner change is *supposed* to move this match; the diff it prints first is
# what that change did to one, and refreshing is how the change is accepted.

set -uo pipefail

# Every path below is repo-relative, and OUT_DIR is rm -rf'd — run from
# anywhere else and that either fells a stranger's reports/determinism or
# silently no-ops. cd to the repo root derived from $0, not
# CLAUDE_PROJECT_DIR (that's a hook-only variable and this script isn't one).
cd "$(dirname "$0")/.." || exit 1

GODOT="${GODOT:-bin/Godot.app/Contents/MacOS/Godot}"

GOLDEN_DIR="tests/fixtures/determinism"
OUT_DIR="reports/determinism"

# The match, stated in full rather than leaning on any default: a default that
# moves must move this line too, or the golden would change with nothing in the
# diff to say why.
SIM_ARGS=(--map=clash --seed=1000 --days=20 --no-commands "--out=$OUT_DIR")

# The artifacts of that run that are a pure function of (map, seed, side specs).
# timeline.csv is not one of them and report.html re-renders it: both carry
# planning_ms, the planner's wall clock — BalanceMatchRecorder's
# NONDETERMINISTIC_COLUMNS is the authority on which column that is. The
# timeline's numbers still reach the diff, because summary.json aggregates them.
ARTIFACTS=(matches.csv summary.json)

refresh=0
if [[ ${1:-} == "--refresh" ]]; then
	refresh=1
elif (($#)); then
	echo "determinism: unknown argument '$1' (only --refresh)" >&2
	exit 2
fi

if [[ ! -x "$GODOT" ]]; then
	echo "determinism: Godot binary not found at $GODOT" >&2
	echo "determinism: see README.md for engine setup, or pass GODOT=<path>" >&2
	exit 1
fi

rm -rf "$OUT_DIR"
if ! log="$("$GODOT" --headless --path . -s res://tools/run_balance_sim.gd -- "${SIM_ARGS[@]}" 2>&1)"; then
	echo "$log" >&2
	echo "determinism: the pinned match did not play" >&2
	exit 1
fi

if ((refresh)); then
	mkdir -p "$GOLDEN_DIR"
	for file in "${ARTIFACTS[@]}"; do
		cp "$OUT_DIR/$file" "$GOLDEN_DIR/$file"
	done
	echo "determinism: refreshed the golden (${ARTIFACTS[*]})"
	exit 0
fi

moved=0
for file in "${ARTIFACTS[@]}"; do
	if [[ ! -f "$GOLDEN_DIR/$file" ]]; then
		echo "determinism: no golden $file — regenerate with 'make determinism REFRESH=1'" >&2
		moved=$((moved + 1))
	elif ! diff -u "$GOLDEN_DIR/$file" "$OUT_DIR/$file"; then
		moved=$((moved + 1))
	fi
done

if ((moved > 0)); then
	echo "determinism: $moved golden file(s) moved — the pinned match plays differently." >&2
	echo "determinism: read the diff. If the change is deliberate, 'make determinism REFRESH=1'." >&2
	exit 1
fi

echo "determinism: golden reproduced (${ARTIFACTS[*]})"
