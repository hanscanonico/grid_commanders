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

# Sourced before the cd: $0 may be a relative path, and it is the caller's
# working directory that makes it resolve.
source "$(dirname "$0")/lib/require_godot.sh" || exit 1

# Every path below (project.godot, .godot/*, the res://-relative scripts
# themselves) is repo-relative — run from anywhere else and the sweep
# silently checks nothing. cd to the repo root derived from $0, not
# CLAUDE_PROJECT_DIR (that's a hook-only variable and this script isn't one).
cd "$(dirname "$0")/.." || exit 1

GODOT="${GODOT:-bin/Godot.app/Contents/MacOS/Godot}"

# Per-file line budgets, tighter than gdlintrc's repo-wide max-file-lines.
#
# gdlint takes one ceiling for the whole project, so the longest file sets
# everybody's and every shorter file gets that file's slack for free. The
# ceiling has been the dev-only scenario driver's and is scenes/battle/battle.gd's
# again today; either way, a file listed here is held to its own length instead.
# scenes/menu/main_menu.gd joined it when COM-97 moved the widget kit out to
# UiKit: it stopped being the ceiling and would otherwise have inherited the
# driver's 271 lines of slack.
#
# Same rule as the gdlintrc ledger: the number is the file's current length, so
# adding to it means moving something out first, and it comes down whenever the
# file sheds a responsibility. Say in the commit which it was.
#
# battle.gd 1341 -> 1411 over the merge: MC4's aimed Command Power took it to
# 1395 on main — the POWER_TARGETING state and the four small functions the aim,
# the repaint and the firing take — and R answering from rest took it to 1411.
# Nothing there is loose; every targeting state and every board lens is Battle's
# by the same rule, so the budget follows the file rather than the file being
# trimmed to it.
#
# 1411 -> 1415: the campaign layer's one seam. `conclude_command` is where a
# committed command settles, so asking the mission whether it is over belongs
# here and nowhere else. The runtime itself was kept out — CampaignSession owns
# it, and Battle holds no mission field — so the four lines are the branch and
# its reason, with nothing loose left to move.
#
# CD2 held that 1415 rather than raising it: the objective vocabulary gave the
# scene two more campaign moments (the mission capture's launch, the tally's
# opening board), and all three go through BattleCampaign, which owns this
# battle's whole campaign side. Battle still holds no mission field.
#
# 1415 -> 1396: CD3's scripted events wanted three lines here — the firing seam
# in conclude_command, the opening board's own firing, and the speech card handed
# to the animator — so scenes/battle/battle_recording.gd came out first. How this
# match records itself (which slot, what the menu calls it, and now which mission
# a recorded beat resolves against) is not flow, and the mission ids the header
# gained would otherwise have been two more lines in _ready.
#
# main_menu.gd 1112 -> 1148: the Campaign route. The flow itself was moved out
# first — MenuCampaignFlow owns the two panels and the walk between them, which
# is 80 of the 116 lines it arrived as — and what is left is the button, the
# collaborator, its two capture poses and the resume call. Which war a player is
# in is a different question from which board and how much fog, so the split is
# the responsibility rather than the line count; nothing loose is left to move.
#
# battle.gd 1396 -> 1397: the music wire-in. A scene states its theme in one
# line of _ready (Music.play) and the Music autoload owns everything else;
# there is nothing to extract from a single call.
# battle.gd 1397 -> 1399: O raises and lowers the campaign mission card. The two
# lines are the branch in the input chain, beside T's and R's, and nothing else
# here changed — the card owns whether it is up, the panel's own signal lights the
# top bar's chip, and Battle holds no mission state to extract.
# battle.gd 1399 -> 1402: the ambient-beat capture pin. Freezing the two-frame
# wall clock for a capture is one assignment beside the hint pin, for the same
# reason; UnitSprite owns the beat, so there is nothing here to extract. The
# raise records a merge that landed without it and left this gate red.
#
# battle.gd 1402 -> 1438: Auto mode, the pause menu's Auto row. The flow itself
# came out first — scenes/battle/battle_auto.gd (BattleAuto) owns the submenu
# and the two turn-handoff cases, the same split BattleExit and BattleAiRunner
# already are. What is left in Battle is the two new fields the row reads
# (`auto_tiers`, `difficulty_db`, each with the reason it lives here and not on
# BuiltMatch or BattleSetup alone), `last_human_team` losing its underscore so
# BattleAuto can write it the same way it already writes `ai_teams` and
# `auto_tiers`, and one small public method, `start_ai_turn`, that BattleAuto
# and `_begin_turn` now share — genuinely Battle's, since a collaborator
# reaching past it into `_ai_runner` directly would be a second opinion on
# state only Battle may hold. Nothing loose is left to move.
#
# main_menu.gd 1148 -> 1150: the picker cell's army count. Two lines inside
# _map_cell_name — the only place a cell's label is composed — saying "· 3P" or
# "· 4P" on the boards that seat more than a duel, so a four-army board is
# tellable from the list rather than one selection at a time. There is nothing
# to extract from an append to a string the same function already builds.
#
# battle.gd 1438 -> 1437: the Sound row, which pays for itself. How a device
# preference is worded is Settings' — it owns the preference — so `speed_row_label`
# and `cycle_speed` and their volume twins moved there, the pause menu's two rows
# and the two banners confirming them now read one string apiece, and Battle is
# left with the branch and nothing else. The file is a line shorter than before.
#
# main_menu.gd 1150 -> 1159: the `menu_four_seats` capture, the one frame that
# shows a board's "· NP" mark and a seat strip past two rows. Which board that
# is is the capture driver's answer, handed the shelf the way `posed_slot` is
# handed it, so what is left here is the pose itself and `_show_map` — the
# select-then-settle dance `--menu-map` already did inline, now shared by both
# rather than written twice.
#
# battle.gd 1437 -> 1429 and main_menu.gd 1159 -> 1121: per-seat difficulty
# (COM-225), which both files pay for by giving work back to the collaborator
# that owns it. Building a planner is choosing a profile, which is all a tier is,
# so `_build_planners` moved into BattleSetup beside `per_team_difficulty` and
# Battle takes the dictionary it hands back; and how well the computer plays is
# per seat now, so the panel's one Difficulty segment is the seat strip's chip and
# the menu keeps no tier state at all.
#
# battle.gd 1429 -> 1420: the mission's objective marks, which pay for themselves.
# What stayed here is the wiring — the node handed to the overlays and one call on
# the fog pass — because which squares are marked is BattleCampaign's answer and
# how they are drawn is ObjectiveMarks'. The two lines that bought are the capture
# chips' fog gate going to BattleOverlays, which owns the transient paint and was
# already handed the drawer: Battle was filtering a table it then handed straight
# over, and CapturePips stays as dumb as it was.
#
# battle.gd 1420 -> 1423: the pause menu's Briefing row, and the extraction came
# first as this file's convention asks. Which words a re-read says and what the
# board does while they are up is BattleCampaign._say_briefing's, holding the card
# until it is dismissed is BattleAnimator's, and what is left here is the three
# lines of the dispatch branch itself.
#
# battle.gd 1423 -> 1415: E ends the turn, and the extraction paid for it twice
# over. `_is_confirm_press` was a pure static answer over an InputEvent asked at
# two transition boundaries, which is exactly TransitionInput's question, so it
# moved there and is now checked without a scene. What the key costs here is the
# two-line dispatch arm, gated on the same BattleLegend.commands_board the bottom
# bar's button reads.
#
# Three more files enter at their current length, for the reason the two above
# are here: each is comfortably under the ceiling, so today nothing at all would
# say if it doubled.
#
# core/save_codec.gd 1332: the second door onto the board, where a silent bug is
# a corrupted or wrongly accepted save rather than a wrong pixel. Its header is
# the format's version ledger, so a version bump legitimately buys lines here —
# the budget moves with it, and the commit says which version it was.
#
# ai/ai_unit_action_planner.gd 1074: every scored candidate competes for one
# AIUnitPlan, which is why combat, capture, dive, join, supply and withdrawal
# live together — but a new capability is a new `_consider_*`, and the plans it
# answers to say each one arrives as a scored candidate rather than as a branch
# grown inside an existing one.
#
# 1074 -> 1099 for the three dials against the milling, which are deliberately
# *not* three new candidates: an engageable goal, a capture priced against the
# fire it walks into and a flat rank inside a firing band are each one term
# inside a judgement this file already makes, and a fourth `_consider_*` for any
# of them would be a second opinion competing with the one it belongs to. What
# each costs is a branch and its reason.
#
# scenes/battle/battle_scenario_driver.gd 985: dev-only, and held to its length
# because it held the ceiling once already and paid COM-94's cut-in split to get
# out of it. A scenario belongs in its own Battle*Scenario class, and what stays
# here is the dispatch arm that reaches it.
# battle_scenario_driver.gd 985 -> 990: the victory verdict's driven read-back.
# #271 measured the budget in its own worktree while #272 grew the file in a
# sibling one, so the two merged red; the raise records the merge that landed
# without it. The five lines are the read-back's dispatch, owned here like every
# scenario's.
#
# battle.gd 1415 -> 1402: the board's pointer. A finger's pan, pinch and tap had
# nowhere to land in a file at its budget, so the mouse half went out with them —
# scenes/battle/board_pointer.gd owns where a pointing device lands on the board
# now, and scenes/battle/touch_gestures.gd is the Node-free recogniser under it.
# What stayed is the one dispatch arm, beside the zoom's.
#
# Four extractions have since landed and each left its budget line alone, one
# PR owning this file at the time; these are those four measured back down to
# what the files are now. A ratchet left slack is a ratchet not ratcheting.
#
# ai/ai_unit_action_planner.gd 1099 -> 665: the fallback advance. ai/ai_advance.gd
# owns the goal a unit walks to, the column it keeps station with and the capture
# claims its fellows stake; what stays here is plan_next, the _consider_* family
# and the refuge.
#
# scenes/menu/main_menu.gd 1121 -> 896: the map picker (COM-38). The roster, the
# selection, the cells and the words are one piece of state, so they are
# scenes/menu/map_picker.gd's the way the seating is SeatStrip's, and the menu
# asks it.
#
# core/save_codec.gd 1332 -> 1106: the questions that need the board.
# core/save_board_check.gd is the seam this file already named — board_error, the
# home-HQ board check, the cell and turn/winner reads and the carriage check —
# and SaveCodec.board_error forwards to it.
#
# scenes/battle/battle_scenario_driver.gd 990 -> 737: the Command Power family.
# scenes/battle/battle_power_scenario.gd takes the eleven power modes and their
# consts, the way BattleFeedbackScenario and BattleMissionScenario already do,
# and the driver keeps one dispatch arm.
#
# A second wave has since landed under the same rule, and these two entries are
# it measured back down to what the files are now.
#
# battle.gd 1402 -> 1196: five splits nobody claimed the slack from.
# scenes/battle/battle_power_flow.gd owns the aimed power's whole flow, and
# scenes/battle/battle_handoff.gd the hot-seat blackout; the commit-and-settle
# sequence every unit action was spelling out is now one `_run_command`; the
# legend, the perspective and the camera are asked rather than re-decided; and
# scenes/battle/battle_targeting.gd owns picking a target. What stays is the
# scene's own state machine.
#
# battle_scenario_driver.gd 737 -> 705: scenes/battle/battle_scenario.gd, the
# base class the driven scenarios share, took the staging every one of them was
# repeating. The driver still keeps only the dispatch arms.
#
# A third wave leaves the last three entries here measured back down to what the
# files are now, so every budget is again exactly its file.
#
# main_menu.gd 896 -> 778: the Continue slot and the capture flags.
# scenes/menu/continue_slot.gd owns whether a saved match may be resumed and the
# words that say so, and the menu's --capture handling went to
# scenes/menu/menu_capture_driver.gd, which was already the class driving the
# menu's captures.
#
# save_codec.gd 1106 -> 1094: the unit index. Unit.indices_of is the one answer
# to which entries of a decoded list a command names, so the codec asks it
# instead of walking the list itself.
#
# battle_scenario_driver.gd 705 -> 668: the failure flag, _fail, _fail_if and
# band_error, all of which the driver and its own scenario classes were each
# declaring. They are BattleScenario's now; the driver keeps _check_in_band, the
# reporting wrapper.
# battle.gd 1196 -> 1195: `match_over()`, the one answer to whether the match is
# finished — the board's winner or the campaign's verdict — and the extraction
# paid for it. The victory lockup's Rematch and Main Menu buttons were wired in
# Battle and guarded through BattleOutcome, so half of each action lived on
# either side; BattleOutcome.bind_screen owns all three of its buttons now, the
# way it already owned Watch Replay.
# main_menu.gd 778 -> 777: Speed and the three toggles are one row now (COM-258).
# The height the second row and its rule were spending went to the map picker,
# which is the control this page exists for.
#
# main_menu.gd 777 -> 785: the Map Editor button (COM-263). A ghost row in the
# action stack, its press, its scene path and its field — the whole of the menu's
# share of the editor, since everything the editor does is the editor's own
# scene. Paid for honestly rather than by thinning a neighbour: there is nothing
# left on this page whose removal would be a simplification rather than a loss.
# battle.gd 1195 -> 1192: the keys that reach a computer turn are the runner's
# now (COM-267). Battle held an arm that answered three of them and refused the
# zoom ladder, which moves the camera and no unit; BattleAiRunner.handle_input is
# that arm, beside the pause it already owns, and the move paid for the ladder.
# battle.gd 1192 -> 1196: the animation-frames plan's S7 board moments. Three
# collaborators the animator now poses — DeathBlast, DamageCallout, and
# CapturePips for its flip flash — wired the way muzzle_flash already was, and
# BattleView.property_flipped connected the way fire_pressed and
# end_turn_pressed already are.
# battle.gd 1196 -> 1194: a launch with no match to play. The whole of what the
# scene does then is scenes/battle/battle_launch_failure.gd's now — the capture
# run's quit as well as the card that gives the player a way off a disabled
# board — so the branch here is the disable and one call, two lines shorter than
# the quit it replaced.
FILE_BUDGETS="
scenes/battle/battle.gd 1194
scenes/menu/main_menu.gd 785
core/save_codec.gd 1094
ai/ai_unit_action_planner.gd 665
scenes/battle/battle_scenario_driver.gd 668
"

require_godot check

# Every project script, in a stable order, NUL-separated so a path with a
# space or newline in it survives every pipeline below. .claude/worktrees
# holds whole nested checkouts of this same repo; without excluding it every
# project file gets checked twice, once at a path Godot cannot resolve res://
# imports for.
project_scripts() {
	find . -name '*.gd' \
		-not -path './.godot/*' \
		-not -path './addons/*' \
		-not -path './bin/*' \
		-not -path './.claude/*' \
		-print0 |
		sort -z
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

declared_classes="$(project_scripts | xargs -0 grep -hE '^class_name [A-Za-z_]' | awk '{print $2}' | sort -u)"
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

# Where a file's diagnostics are parked. Percent-encoded, so the key is
# one-to-one with the path: a file with a '%' in its name cannot land on
# another file's report.
report_path() {
	local key="${1//%/%25}"
	printf '%s' "$REPORTS/${key//\//%2F}"
}

# One engine boot per file, sharing nothing, so the files are checked in
# parallel. xargs starts a fresh shell per file, which is why the worker is an
# exported function over an exported environment rather than an inline body.
check_one() {
	local file="$1"
	local raw output
	# Strip the leading './' so reported paths line up with res:// paths.
	raw="$("$GODOT" --headless --path . --check-only -s "${file#./}" 2>&1)"
	output="$(grep -vE "$ignore" <<<"$raw")"
	if grep -qE "$ignore" <<<"$raw"; then
		output="$(grep -vE "$cascade" <<<"$output")"
	fi
	if grep -qE 'SCRIPT ERROR|Parse Error' <<<"$output"; then
		grep -E 'SCRIPT ERROR|Parse Error|^ +at:' <<<"$output" >"$(report_path "$file")"
		return 1
	fi
	return 0
}
export -f check_one report_path
export GODOT ignore cascade

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
REPORTS="$WORK/reports"
export REPORTS
mkdir -p "$REPORTS"

# bash 3.2 (macOS system bash) has no mapfile, so stream the paths through a
# file instead — read twice, once to check and once to report. NUL-delimited,
# matching project_scripts, so a path with a space survives both passes.
queue="$WORK/queue"
if (($#)); then
	printf '%s\0' "$@" >"$queue"
else
	project_scripts >"$queue"
fi

xargs -0 -P "${CHECK_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc)}" -n1 \
	bash -c 'check_one "$0"' <"$queue"

# A count kept inside a worker would die with the worker's own process, so
# the failures are read back off disk — in queue order, so a parallel run says
# exactly what a serial one said and two failures never interleave.
while IFS= read -r -d '' file; do
	checked=$((checked + 1))
	report="$(report_path "$file")"
	[[ -f "$report" ]] || continue
	cat "$report"
	failed=$((failed + 1))
done <"$queue"

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

	# The simulation/presentation split: nothing under core/ or ai/ may reach for
	# a Node, a scene or the tree. The pattern matches only spellings that can
	# mean nothing else — the bare word "Node" is prose in a dozen comments here,
	# and a lint that cries wolf gets switched off.
	layering="$(grep -rnE 'get_node\(|get_tree\(|\bSceneTree\b|\.tscn|res://scenes/|extends Node' core ai --include='*.gd' || true)"
	if [[ -n "$layering" ]]; then
		echo "check: core/ and ai/ are Node-free — the sim may not reach into the scene tree" >&2
		printf '%s\n' "$layering" >&2
		failed=$((failed + 1))
	fi

	# Determinism: combat luck is a seeded stream threaded through the sim, so a
	# global roll is a match that cannot be replayed. Excluding a leading dot is
	# what lets `rng.randf(...)` — the seeded stream, the correct call — through.
	global_rng="$(grep -rnE '(^|[^.A-Za-z_])(randf|randf_range|randi|randi_range|randomize)\(' core ai --include='*.gd' || true)"
	if [[ -n "$global_rng" ]]; then
		echo "check: core/ and ai/ are RNG-free — roll a seeded rng, never the global one" >&2
		printf '%s\n' "$global_rng" >&2
		failed=$((failed + 1))
	fi

	# Pacing can never move an outcome, a save or a replay (game-speed plan, D1),
	# so the sim may not import GameSpeed or read Settings. Requiring a word
	# boundary keeps `ProjectSettings.` — a path, not a preference — silent.
	pacing="$(grep -rnE '(^|[^A-Za-z_])(GameSpeed|Settings)\.' core ai --include='*.gd' || true)"
	if [[ -n "$pacing" ]]; then
		echo "check: core/ and ai/ may not read GameSpeed or Settings — pacing is presentation" >&2
		printf '%s\n' "$pacing" >&2
		failed=$((failed + 1))
	fi

	# A leading underscore is this repo's word for "private to its file", so a
	# class reached for through one is either an API nobody named as such or a
	# helper somebody should not be calling. Matching a call on a PascalCase
	# receiver keeps `self._helper()` and a plain `_helper()` — the ordinary
	# private calls — out of it.
	private_reach="$(grep -rnoE '\b[A-Z][A-Za-z0-9]*\._[a-z_][a-z0-9_]*\(' core ai scenes tools --include='*.gd' || true)"
	if [[ -n "$private_reach" ]]; then
		echo "check: a \`_\`-prefixed member is private to its file — promote it or stop reaching for it" >&2
		printf '%s\n' "$private_reach" >&2
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

	# Same for the arena search driver, whose pure half is the search itself —
	# the lattice a proposal snaps to, the compass around an incumbent, and the
	# step that contracts. The space it searches is GDScript and the suite holds
	# that; this is the arithmetic laid over it.
	if ! search_check="$(tools/arena_search.py --self-check 2>&1)"; then
		echo "check: tools/arena_search.py --self-check failed" >&2
		printf '%s\n' "$search_check" >&2
		failed=$((failed + 1))
	fi

	# And for the grind box's digest, whose pure half is the reading it takes off
	# each instrument's artifact. The box itself plays matches for days; this is
	# the part a gate can hold, over the fixtures in tests/fixtures/grind/.
	if ! digest_check="$(tools/grind/digest.py --self-check 2>&1)"; then
		echo "check: tools/grind/digest.py --self-check failed" >&2
		printf '%s\n' "$digest_check" >&2
		failed=$((failed + 1))
	fi

	# A detector with no fixture is a detector nobody can trust: a false positive
	# sends the reader looking at a doctrine that was playing correctly. Every
	# finding kind the analyser can report is a key of ReplayAnalysis.SEVERITY, so
	# that constant is the roster a new detector joins and this is what holds it to
	# naming itself in a suite.
	finding_kinds="$(
		sed -n '/^const SEVERITY/,/^}/p' tools/replay/replay_analysis.gd |
			grep -oE '^[[:space:]]*"[^"]+"' | tr -d '[:blank:]"'
	)"
	if [[ -z "$finding_kinds" ]]; then
		echo "check: read no finding kinds from ReplayAnalysis.SEVERITY — has it moved?" >&2
		failed=$((failed + 1))
	fi
	while read -r kind; do
		[[ -z "$kind" ]] && continue
		if ! grep -q "\"$kind\"" tests/unit/test_replay_*.gd; then
			echo "check: finding kind '$kind' has no fixture in tests/unit/test_replay_*.gd" >&2
			failed=$((failed + 1))
		fi
	done <<<"$finding_kinds"

	# CLAUDE.md and the .claude/rules/*.md files its index points at are the design
	# of record, and docs/ holds the instruments' committed
	# measurements, so a citation nobody can follow is evidence gone missing. A
	# token counts as a citation only when it names a top-level directory of this
	# repo and carries a file extension — which is what keeps prose, a glob and a
	# sibling repo's path (qualified with that repo's name) out of it.
	cited_paths="$(
		grep -ohE '(^|[^A-Za-z0-9_./~-])(core|ai|scenes|data|tools|docs|tests|maps|assets|autoload|addons|generators)/[A-Za-z0-9_./-]*\.(md|gd|gdignore|txt|tres|tscn|png|sh|py|json|cfg)' \
			CLAUDE.md README.md docs/*.md .claude/rules/*.md | sed -E 's/^[^A-Za-z0-9_]//' | sort -u
	)"
	while read -r cited; do
		[[ -z "$cited" ]] && continue
		if [[ ! -e "$cited" ]]; then
			echo "check: $cited is cited in CLAUDE.md, .claude/rules/, README.md or docs/ and does not exist" >&2
			failed=$((failed + 1))
		fi
	done <<<"$cited_paths"

	# The generators' own docs are citers too, and they write their citations
	# from inside their package — `tests/measure_motion.py` means the sprite
	# generator's tests, `assets/LICENSES.md` means the game's. So a token is
	# resolved against the citing file's generator root first and the repo root
	# second, and only a token no root answers for is a citation nobody can
	# follow.
	for doc in generators/*/README.md generators/*/docs/*.md; do
		[[ -f "$doc" ]] || continue
		root="${doc#generators/}"
		root="generators/${root%%/*}"
		# What counts as a citation is the generator's own top-level directories —
		# `spritegen/`, `audiogen/`, `tests/` — read off the tree rather than named
		# here, so a second generator's package is linted the day it arrives, plus
		# the game's `docs/` and `assets/`.
		citable="assets|docs"
		for package in "$root"/*/; do
			citable="$citable|$(basename "$package")"
		done
		doc_citations="$(
			grep -ohE "(^|[^A-Za-z0-9_./~-])($citable)/[A-Za-z0-9_./-]*\.(md|gd|gdignore|txt|tres|tscn|png|sh|py|json|cfg)" \
				"$doc" | sed -E 's/^[^A-Za-z0-9_]//' | sort -u
		)"
		while read -r cited; do
			[[ -z "$cited" ]] && continue
			if [[ ! -e "$root/$cited" && ! -e "$cited" ]]; then
				echo "check: $doc cites $cited, which exists neither under $root/ nor at the repo root" >&2
				failed=$((failed + 1))
			fi
		done <<<"$doc_citations"
	done
fi

if ((failed > 0)); then
	echo "check: $failed failure(s) across $checked file(s)" >&2
	exit 1
fi

echo "check: $checked files OK"
