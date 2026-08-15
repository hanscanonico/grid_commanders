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
ARTIFACTS=(matches.csv summary.json)

# Artifacts that are that function once their wall-clock columns are cut. The
# timeline is per turn, so it is what catches a change that moves the middle of
# the match and still lands on the same winner, day and end-state totals.
# report.html stays out of both lists because it re-renders these same numbers.
STRIPPED_ARTIFACTS=(timeline.csv)

# BalanceMatchRecorder's NONDETERMINISTIC_COLUMNS is the authority on which
# columns those are; this is that list, spelled where the gate can read it.
TIMELINE_STRIPPED_COLUMNS=(planning_ms)

# Emits $1 without its TIMELINE_STRIPPED_COLUMNS fields, and fails naming the
# column when the header does not carry one: a renamed column must be loud,
# because silently stripping nothing would diff the wall clock and silently
# stripping the wrong index would hide a real move.
#
# Cutting fields with awk -F, is safe because no timeline field can hold a
# comma — the unit tallies join with ';' (BalanceMatchRecorder._tally_text).
strip_columns() {
	local src="$1" dest="$2"
	local column index
	local -a cut=()
	for column in "${TIMELINE_STRIPPED_COLUMNS[@]}"; do
		index="$(awk -F, -v want="$column" 'NR == 1 { for (i = 1; i <= NF; i++) if ($i == want) { print i; exit } }' "$src")"
		if [[ -z $index ]]; then
			echo "determinism: $src has no '$column' column — TIMELINE_STRIPPED_COLUMNS is stale" >&2
			return 1
		fi
		cut+=("$index")
	done
	awk -F, -v cutlist="$(
		IFS=,
		echo "${cut[*]}"
	)" '
		BEGIN { n = split(cutlist, c, ","); for (i = 1; i <= n; i++) skip[c[i]] = 1 }
		{
			out = ""
			sep = ""
			for (i = 1; i <= NF; i++) {
				if (i in skip) continue
				out = out sep $i
				sep = FS
			}
			print out
		}
	' "$src" >"$dest"
}

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
	for file in "${STRIPPED_ARTIFACTS[@]}"; do
		strip_columns "$OUT_DIR/$file" "$GOLDEN_DIR/$file" || exit 1
	done
	echo "determinism: refreshed the golden (${ARTIFACTS[*]} ${STRIPPED_ARTIFACTS[*]})"
	exit 0
fi

moved=0

# $1 is the golden's name, $2 the played side to hold it to.
diff_golden() {
	if [[ ! -f "$GOLDEN_DIR/$1" ]]; then
		echo "determinism: no golden $1 — regenerate with 'make determinism REFRESH=1'" >&2
		moved=$((moved + 1))
	elif ! diff -u "$GOLDEN_DIR/$1" "$2"; then
		moved=$((moved + 1))
	fi
}

for file in "${ARTIFACTS[@]}"; do
	diff_golden "$file" "$OUT_DIR/$file"
done
for file in "${STRIPPED_ARTIFACTS[@]}"; do
	strip_columns "$OUT_DIR/$file" "$OUT_DIR/stripped-$file" || exit 1
	diff_golden "$file" "$OUT_DIR/stripped-$file"
done

if ((moved > 0)); then
	echo "determinism: $moved golden file(s) moved — the pinned match plays differently." >&2
	echo "determinism: read the diff. If the change is deliberate, 'make determinism REFRESH=1'." >&2
	exit 1
fi

echo "determinism: golden reproduced (${ARTIFACTS[*]} ${STRIPPED_ARTIFACTS[*]})"
