#!/usr/bin/env bash
#
# Audits GDScript files: parse/type checks, plus repository architecture seams.
#
# `godot --check-only -s <file>` runs the full GDScript analyser — it catches
# type mismatches and unknown identifiers, not just syntax — but always exits 0,
# so this wrapper scans its output for diagnostics and sets the status itself.
#
# Usage:  tools/check_scripts.sh [file.gd ...]
#
# With no arguments it checks every project script (the `check` target in the
# Makefile); with arguments, just those files — project-relative paths — which
# is what the post-edit hook (tools/check_gd_hook.sh) uses.
#
# Much faster than `make test` for "does what I just wrote compile?": it skips
# booting the scene tree and GUT.

set -uo pipefail

GODOT="${GODOT:-bin/Godot.app/Contents/MacOS/Godot}"

# Per-file line budgets, tighter than gdlintrc's repo-wide max-file-lines.
#
# gdlint takes one ceiling for the whole project, so the longest file sets
# everybody's — and the longest is the dev-only scenario driver. That left
# scenes/battle/battle.gd, the production file the ratchet was raised for in the
# first place, free to grow into its slack without tripping anything. A file
# listed here is held to its own length instead. scenes/menu/main_menu.gd joined
# it when COM-97 moved the widget kit out to UiKit: it stopped being the ceiling
# and would otherwise have inherited the driver's 271 lines of slack.
#
# Same rule as the gdlintrc ledger: the number is the file's current length, so
# adding to it means moving something out first, and it comes down whenever the
# file sheds a responsibility. Say in the commit which it was.
FILE_BUDGETS="
scenes/battle/battle.gd 1341
scenes/menu/main_menu.gd 1112
"

if [[ ! -x "$GODOT" ]]; then
	echo "check: Godot binary not found at $GODOT" >&2
	echo "check: see README.md for engine setup, or pass GODOT=<path>" >&2
	exit 1
fi

# Every project script, in a stable order. .claude/worktrees holds whole nested
# checkouts of this same repo; without excluding it every project file gets
# checked twice, once at a path Godot cannot resolve res:// imports for.
project_scripts() {
	find . -name '*.gd' \
		-not -path './.godot/*' \
		-not -path './addons/*' \
		-not -path './bin/*' \
		-not -path './.claude/*' |
		sort
}

# A `class_name` is a global identifier only because
# .godot/global_script_class_cache.cfg says so, and only an `--import` pass
# writes that file. A cache that predates a class — a fresh worktree, a deleted
# .godot, a branch switch — makes every file typing against it fail with
# "Identifier ... not declared in the current scope", which reads exactly like
# broken code: deleting the cache here fails 244 of 260 files (COM-112). So the
# names are compared before a single file is parsed, and `check` stays the
# read-only audit it claims to be — it names the command that fixes this rather
# than importing behind the caller's back.
CLASS_CACHE=".godot/global_script_class_cache.cfg"

declared_classes="$(project_scripts | xargs grep -hE '^class_name [A-Za-z_]' | awk '{print $2}' | sort -u)"
if [[ -f "$CLASS_CACHE" ]]; then
	cached_classes="$(sed -n 's/^"class": &"\([^"]*\)".*/\1/p' "$CLASS_CACHE" | sort -u)"
else
	cached_classes=""
fi
uncached="$(comm -23 <(printf '%s\n' "$declared_classes") <(printf '%s\n' "$cached_classes"))"
if [[ -n "$uncached" ]]; then
	missing="$(printf '%s\n' "$uncached" | wc -l | tr -d ' ')"
	first="$(printf '%s\n' "$uncached" | head -1)"
	echo "check: stale class cache — $missing class_name(s) the engine has not registered, e.g. $first" >&2
	echo "check: run 'make import' ($GODOT --headless --path . --import) and try again" >&2
	exit 1
fi

# Autoload singletons are global identifiers at runtime, but --check-only never
# instantiates them, so every use reads as "Identifier not found". Build an
# ignore pattern from the names project.godot actually registers — a typo'd
# singleton name still fails, because it won't be in this list.
autoloads="$(
	awk '/^\[autoload\]/ {inside = 1; next}
	     /^\[/ {inside = 0}
	     inside && /=/ {split($0, kv, "="); print kv[1]}' project.godot |
		paste -sd '|' -
)"
if [[ -n "$autoloads" ]]; then
	ignore="Identifier not found: ($autoloads)\$"
else
	ignore='a^' # matches nothing
fi

# A script that types against a class whose script uses an autoload inherits
# the problem one step removed: the dependency fails to compile for the reason
# above, and this file is then reported with "Failed to compile depended
# scripts", which names no identifier to match on.
#
# That cascade is only ignorable when the underlying autoload error is what
# caused it — and Godot prints both in the same output, so we can tell. A
# dependency that fails for a real reason prints that reason here too, and it
# survives the filter and fails the run.
cascade='Compile Error: Failed to compile depended scripts'

failed=0
checked=0

# bash 3.2 (macOS system bash) has no mapfile, so stream the paths instead.
while IFS= read -r file; do
	checked=$((checked + 1))
	# Strip the leading './' so reported paths line up with res:// paths.
	raw="$("$GODOT" --headless --path . --check-only -s "${file#./}" 2>&1)"
	output="$(grep -vE "$ignore" <<<"$raw")"
	if grep -qE "$ignore" <<<"$raw"; then
		output="$(grep -vE "$cascade" <<<"$output")"
	fi
	if grep -qE 'SCRIPT ERROR|Parse Error' <<<"$output"; then
		grep -E 'SCRIPT ERROR|Parse Error|^ +at:' <<<"$output"
		failed=$((failed + 1))
	fi
done < <(
	if (($#)); then
		printf '%s\n' "$@"
	else
		project_scripts
	fi
)

# Repository invariants. Kept in the full-project audit rather than a subset
# check: each is cross-file drift, so a run over the files somebody just edited
# is exactly the run that cannot see it.
if (($# == 0)); then
	while read -r path budget; do
		[[ -z "$path" ]] && continue
		lines="$(wc -l <"$path" | tr -d ' ')"
		if ((lines > budget)); then
			echo "check: $path is $lines lines, over its $budget-line budget" >&2
			failed=$((failed + 1))
		fi
	done <<<"$FILE_BUDGETS"

	# The live battle has one mutation seam: a new apply or validate anywhere
	# under scenes/battle is what this catches.
	live_applies="$(grep -rn --include='*.gd' -E '\.apply\([^)]*game[^)]*\)' scenes/battle || true)"
	apply_count="$(printf '%s\n' "$live_applies" | sed '/^$/d' | wc -l | tr -d ' ')"
	if [[ "$apply_count" != 1 || "$live_applies" != scenes/battle/battle_command_pipeline.gd:* ]]; then
		echo "check: expected one live apply in BattleCommandPipeline, found $apply_count" >&2
		printf '%s\n' "$live_applies" >&2
		failed=$((failed + 1))
	fi

	# Menu construction may query a fresh command to decide whether to offer a
	# row — a `<Command>.new(...).validate(game)` chain, excluded below. This
	# guards committed-command validation specifically, whatever the receiver
	# variable is named.
	live_validates="$(grep -rn --include='*.gd' -E '\.validate\([^)]*game[^)]*\)' scenes/battle |
		grep -vE '\.new\(.*\)\.validate\(' || true)"
	validate_count="$(printf '%s\n' "$live_validates" | sed '/^$/d' | wc -l | tr -d ' ')"
	if [[ "$validate_count" != 1 || "$live_validates" != scenes/battle/battle_command_pipeline.gd:* ]]; then
		echo "check: expected one live validate in BattleCommandPipeline, found $validate_count" >&2
		printf '%s\n' "$live_validates" >&2
		failed=$((failed + 1))
	fi

	# The balance pool is Python, so `make test` never reaches it. Its two pure
	# decisions — where a run may write, and what a resumed shard is keyed on —
	# are pinned by its own self-check, which needs no engine.
	if ! pool_check="$(tools/balance_pool.py --self-check 2>&1)"; then
		echo "check: tools/balance_pool.py --self-check failed" >&2
		printf '%s\n' "$pool_check" >&2
		failed=$((failed + 1))
	fi
fi

if ((failed > 0)); then
	echo "check: $failed failure(s) across $checked file(s)" >&2
	exit 1
fi

echo "check: $checked files OK"
