#!/usr/bin/env bash
#
# Presentation smoke check: proves every demo scenario still reaches its
# capture. Scenarios sharing a boot configuration (scene · fog · map) share one
# engine process — the driver runs them back-to-back with a scene reload in
# between (COM-117), so a full sweep opens a handful of windows rather than
# one per scenario. SMOKE_ISOLATE=1 restores the one-process-per-scenario path
# verbatim; a failing batch falls back to it by itself, so failures always
# read per-scenario.
#
# This is deliberately NOT a GUT suite. GUT stays limited to core/ and ai/,
# which are Node-free; the battle scene is verified by driving it. Each demo
# runs the real handlers a player's input reaches (see _run_demo in
# battle_scenario_driver.gd), so a scenario that stops producing a frame means
# the flow it exercises has broken — a menu never opened, a state was never
# reached, or the scene crashed on the way.
#
# Usage:  tools/smoke_scenarios.sh [mode ...]   (see the `smoke` target)
#
# A `menu_` mode boots the *main menu* instead of the battle scene; everything
# else about the run is identical. Those scenarios are the one place the sweep
# checks a screen the battle scene never draws, and they carry their own gate:
# the menu hands its centered column and its primary actions to
# MenuCaptureDriver._fits (see MainMenu._chrome).
#
# A mode may carry a `+fog` suffix — `victory+fog` is the victory scenario run
# with fog of war on. Fog is the one setting under which this scene *hides*
# units rather than merely drawing them, so a couple of fogged runs are part of
# the sweep; the mode name is the label and the capture filename, so a failure
# says which of the two it was.
#
# With no arguments it runs DEFAULT_MODES. Captures land in a temporary
# directory that is removed on exit unless SMOKE_KEEP is set, in which case the
# path is printed so the frames can be eyeballed.
#
# Needs a display: these runs render. They are not headless, so this is a local
# gate, not something to wire into a headless CI job as-is.

set -uo pipefail

GODOT="${GODOT:-bin/Godot.app/Contents/MacOS/Godot}"
BATTLE="${BATTLE:-scenes/battle/battle.tscn}"
# Every scenario opens a window. Launching through the wrapper keeps a
# scripted/agent run (no tty) from stealing the user's window focus once per
# scenario;
# interactive runs exec $GODOT directly as before. The wrapper `exec`s the
# engine, so run_with_timeout's kill still lands on the Godot process itself.
export GODOT
GODOT_GUI="$(cd "$(dirname "$0")" && pwd)/godot_gui.sh"
# Generous: `aiturn` plans and applies a whole AI turn. Captures pin the Instant
# game speed, so almost no tween is being waited on; this only has to catch a
# genuinely stuck scene, not time anything. The one exception is `capture_power`,
# which un-pins Instant on purpose so a cut-in really plays and then puts it back
# — still seconds, not a timeout's worth, and the scenario bounds its own wait.
SMOKE_TIMEOUT="${SMOKE_TIMEOUT:-90}"
# A frame that renders the map is tens of KB; anything this small is a blank or
# truncated capture, which means the scene never really came up.
MIN_BYTES="${SMOKE_MIN_BYTES:-2000}"

# One per branch of the interaction flow: targeting preview and resolved
# combat, capture, the build menu and a completed build, the map menu and the
# turn it ends, the load/drive/drop transport chain, supply, a Command Power
# fired from the HUD over an open menu, the same button fired one beat later
# while the capture cut-in is still playing (capture_power, COM-50), victory, and
# a full AI turn.
#
# Two of them run again under fog, where the sprite-hiding path exists at all:
# powermenu+fog fires a power, which redraws every sprite on the board at once,
# and victory+fog edits the sim behind the scene's back and resyncs. Both used
# to leak enemy positions.
#
# ambush and vanish turn fog on themselves — they are the same board with Sable
# Wren's power down and up, and only the second one may hide anything. Running
# both is what keeps `vanish` honest: a board that hid those units for some
# unrelated reason would pass on its own, but it would take `ambush` down with
# it.
# The commander-identity captures are the G3 and COM-18 gates:
# power_charging/ready/active/ai/mirror cover every state the bottom bar's
# commander block takes, and power_ready_contrast is the named legibility frame —
# the same ready meter as power_ready but staged over the bright strait, so the
# two together are the dark/light background comparison. (COM-18's
# power_cursor_fade retired with the floating chip it protected: a docked bar is
# never on top of a tile, so there is no cursor dodge left to prove.)
# power_mapmenu is the keyboard half of the same gate: the map menu's first row is
# the Command Power, so that menu has to open inside the board band, and the
# scenario measures the live rect against it rather than trusting the frame. The
# activation card, both-sides info sheet, and victory lockup are each still proved
# to render at native 640x360.
#
# The `cutin` family is the odd one out: every other mode drives the flow and
# photographs what it produces, but the battle cut-in is deliberately suppressed
# while capturing (a mid-tween frame is what made the camera shake
# undeterministic), so these pose the overlay at a fixed moment of its own clock
# instead. They are still real checks — each runs the real resolver and the real
# staging, so a cut-in that stopped rendering, or a unit or terrain it could not
# draw, fails here rather than in play.
#
# `cutin[_ko][:<attacker>:<defender>]` stages any matchup on whatever board the
# run was launched with, which is what makes "all eighteen units stage
# correctly" checkable. The ones below are one per branch with its own code:
# survival and the kill, a bombing run from the air, a torpedo across the water,
# a shot at a submarine — the one target the roster hides — and an indirect
# attack, which is the only case that frames a volley with no counter coming
# back. cutin_skip is a test rather than a picture; see _spam_skip.
#
# Every one of those runs commander-less, though, and a commander-less side draws
# in the row its slot number names — so for a while none of them could see a
# cut-in surface reading a team int where an atlas row belongs (COM-10: Iron
# armies came out Aurora blue). The two `_iron_commander` variants close that:
# they stage Iron against Verdant, rows 3 and 4, neither equal to its slot, and
# fight over a property apiece so the ground carries a faction row as well.
#
# None of the cut-in modes rests on a human eyeballing the frame, either: every
# one of them reads the rows back off the posed art and fails the run unless each
# is the row SideIdentity gives that side (see _check_cut_in_rows). A
# mispainted army renders a perfectly good picture, so "a frame was written" was
# never going to be the check.
#
# leave_confirm is COM-16's: the map menu now carries both routes out of a running
# match, and the scenario walks from those rows to the confirmation the unsaved one
# opens. Like power_mapmenu it measures rather than poses — the rows are read off
# the menu the scenario opened and the rects off the live control — because the
# board renders behind the opaque bars, so a menu two rows taller than it used to
# be, or a confirmation that armed its destructive row, would photograph perfectly
# well. It stops at the confirmation rather than going through: leaving frees the
# battle scene, which would leave the run with nothing to capture, so the two
# completed exits are proved by driving the real scenes instead (see the ticket).
#
# after_build_menu is COM-11's, and it is a *sequence* rather than a screen: the
# three battle menus share one ActionMenu, a PanelContainer grows to fit its rows
# and never shrinks back on its own, and the eleven-row build menu used to leave its
# panel standing behind every short menu opened after it. So the scenario opens the
# build menu, cancels, and opens a two-row unit menu, then measures that one against
# the one before it on both axes. `buildmenu` and `supply` each photograph one of
# those two menus perfectly well on its own, which is exactly why neither ever saw
# the bug. Note the name: a `menu_` prefix is reserved above for the main-menu
# scenarios, and this one is a battle-scene flow.
#
# rejected_confirm and enemy_range_preview are COM-13's pair, and both are checks
# rather than pictures. The first walks every refusal a confirm can meet — an
# acted unit, one built this turn, a reachable destination a friendly holds that
# is neither a Load nor a Join, and a press during the computer's turn — and reads
# the chip's words back after each one, because all four used to be silent no-ops
# and silence photographs exactly like a reason. The second is the regression gate
# the same finding owes the already-shipped range preview: clicking an enemy must
# still paint its reach and R its fire ring. Both flows live in
# BattleFeedbackScenario rather than in the driver, which is why the driver's line
# ceiling moved by the dispatch arm and not by the scenarios.
#
# end_turn_ready_units is COM-14's two-sided gate. It first opens the guard with
# live units ready and reads the count, every name/coordinate, and both choices
# back from the modal, then answers it three ways, because "operable" is a claim
# per input: the keyboard steps the two actions under left/right and backs out
# with Escape, a real click at the Review button's own rect backs out again — a
# click rather than its `pressed` signal, since the guard veils the board with a
# pointer-swallowing rect the actions have to sit on top of — and Enter on the
# stepped-to End anyway commits the next side's turn through the live pipeline.
# Every one of those must land on the same turn it was answered from, or the next
# one. Between them it marks a side spent and proves End Turn commits with no
# guard at all, and it ends on the day-two guard the capture photographs. The old
# endturn and aiturn modes choose End anyway through the same helper, so the new
# confirmation cannot strand either of those established flows.
#
# The menu pair is the same idea one screen earlier: `menu_with_save` poses a
# resumable match and `menu_no_save` poses none, and each measures the whole
# centered menu column plus all four primary actions against the 640x360 frame
# before it writes a thing. The column is the load-bearing witness, not the
# wordmark: a too-tall column is centered into an offset that runs off both ends
# at once, so the wordmark's own rect sat at exactly y=0 in a visibly sheared
# build while the header row's icon took the overflow (see
# MenuCaptureDriver._fits). COM-5 is why — with a save on disk the old menu
# clipped its own title and its Quit, and a returning player met a visibly
# broken screen while a fresh install never did. Both modes pose the save slot
# themselves, so neither reads nor writes the running machine's user://save.json.
#
# The mission_strip pair is COM-12's. Every other scenario runs with the
# first-match hints pinned retired, exactly as they run with the game speed
# pinned — otherwise whether a teaching card sits over the board would depend on
# how much of the game the person running the sweep had already played. These two
# pin them *empty* instead, so the strip opens as it does on a fresh install.
# `mission_strip` poses that first frame; `mission_strip_retired` drives a real
# selection and a real move and then checks the strip has moved on to CAPTURE,
# which is the acceptance criterion a still frame cannot show — a hint retires
# when the player performs it, and a strip stuck on SELECT photographs just as
# well as one that advanced.
DEFAULT_MODES=(
	attack resolve capture build buildmenu endturn
	load cargo drop transport supply divemenu dive mapmenu leave_confirm after_build_menu
	rejected_confirm enemy_range_preview end_turn_ready_units
	powermenu capture_power victory aiturn
	mission_strip mission_strip_retired
	powermenu+fog victory+fog ambush vanish
	power_charging power_ready power_ready_contrast power_active power_ai power_mirror
	power_mapmenu power_banner commander_info commander_victory
	cutin cutin_ko cutin_skip cutin_iron_commander
	cutin:bomber:tank cutin:sub:cruiser cutin:cruiser:sub cutin:artillery:mech
	capture_cutin capture_cutin_partial capture_cutin_skip capture_cutin_iron_commander
	menu_with_save menu_no_save
)

if [[ ! -x "$GODOT" ]]; then
	echo "smoke: Godot binary not found at $GODOT" >&2
	echo "smoke: see README.md for engine setup, or pass GODOT=<path>" >&2
	exit 1
fi

modes=("$@")
if ((${#modes[@]} == 0)); then
	modes=("${DEFAULT_MODES[@]}")
fi

out_dir="$(mktemp -d "${TMPDIR:-/tmp}/battle-smoke.XXXXXX")"
cleanup() {
	if [[ -n "${SMOKE_KEEP:-}" ]]; then
		echo "smoke: captures kept in $out_dir"
	else
		rm -rf "$out_dir"
	fi
}
trap cleanup EXIT

# macOS ships no coreutils `timeout`, so poll the child ourselves. A scenario
# that never reaches its state would otherwise block forever in _run_demo's
# `while state != ...` loop.
run_with_timeout() {
	local seconds="$1"
	shift
	"$@" >"$out_dir/last.log" 2>&1 &
	local pid=$!
	local waited=0
	while kill -0 "$pid" 2>/dev/null; do
		if ((waited >= seconds)); then
			kill -9 "$pid" 2>/dev/null
			wait "$pid" 2>/dev/null
			return 124
		fi
		sleep 1
		waited=$((waited + 1))
	done
	wait "$pid"
}

failed=0

# One scenario, one process — the shape the sweep always had, kept verbatim as
# the SMOKE_ISOLATE=1 path, the menu scenarios' path, and the re-run a failing
# group gets (see run_group). Prints the scenario's status line and bumps
# `failed` when it goes wrong.
run_one_scenario() {
	local mode="$1"
	# A cut-in mode carries its matchup in the name; colons are legal in a POSIX
	# filename but a menace in one, so they become dashes for the capture only.
	local shot="$out_dir/${mode//:/-}.png"
	printf 'smoke: %-14s ' "$mode"
	# `victory+fog` is the victory demo with fog on; anything else is the demo
	# name as written.
	local demo="${mode%+fog}"
	# A `menu_` mode boots the project's main scene — the menu — by passing no
	# scene at all, exactly as `make menu-screenshot` does. Everything else boots
	# the battle scene.
	local godot_args=(--path .)
	if [[ "$demo" != menu_* ]]; then
		godot_args+=("$BATTLE")
	fi
	godot_args+=(-- "--screenshot=$shot" "--demo=$demo")
	if [[ "$demo" != "$mode" ]]; then
		godot_args+=(--fog)
	fi
	# The naval scenarios need a board with water on it; the default has none.
	# power_ready_contrast borrows the same board for a different reason: it is
	# power_ready over the bright, sea-heavy strait rather than the dim default,
	# so the pair is the meter's dark/light legibility comparison.
	case "$demo" in
		divemenu | dive | power_ready_contrast | *:sub | *:sub:* | *:cruiser | *:battleship | *:lander)
			godot_args+=(--map=the_straits)
			;;
	esac
	run_with_timeout "$SMOKE_TIMEOUT" "$GODOT_GUI" "${godot_args[@]}"
	local status=$?

	if ((status == 124)); then
		echo "TIMEOUT after ${SMOKE_TIMEOUT}s"
		failed=$((failed + 1))
		return
	fi
	# The scene quits through get_tree().quit(), so a non-zero status here is a
	# real crash and not the engine's noisy-but-harmless exit diagnostics.
	if ((status != 0)); then
		echo "FAILED (exit $status)"
		sed -n '1,20p' "$out_dir/last.log" >&2
		failed=$((failed + 1))
		return
	fi
	if [[ ! -f "$shot" ]]; then
		echo "FAILED (no capture written)"
		failed=$((failed + 1))
		return
	fi
	# stat's portable-ish size flag differs between BSD and GNU.
	local bytes
	bytes="$(wc -c <"$shot" | tr -d ' ')"
	if ((bytes < MIN_BYTES)); then
		echo "FAILED (capture only ${bytes}B, expected >= ${MIN_BYTES}B)"
		failed=$((failed + 1))
		return
	fi
	echo "ok (${bytes}B)"
}

# FS2 (COM-117): the scenarios differ in only three boot facts — which scene,
# fog on or off, which map — so the sweep boots the engine once per
# configuration and the driver runs the group's scenarios in-process
# (`--demos=`, battle_scenario_driver.gd), reloading the scene between them.
# The key spells those three facts; scenarios that share it share a boot, and
# the window count falls from one per scenario to one per configuration.
group_key() {
	local mode="$1"
	local demo="${mode%+fog}"
	local fog=""
	[[ "$demo" != "$mode" ]] && fog=fog
	if [[ "$demo" == menu_* ]]; then
		echo "menu"
		return
	fi
	# The same map rule run_one_scenario applies, spelled once more because a
	# bash 3.2 function cannot return an array; keep the two case lists equal.
	local map=""
	case "$demo" in
		divemenu | dive | power_ready_contrast | *:sub | *:sub:* | *:cruiser | *:battleship | *:lander)
			map=the_straits
			;;
	esac
	echo "battle:${fog}:${map}"
}

# Boots one group in a single process. On success the per-scenario lines are
# printed from the captures the driver wrote; a group that fails in any way is
# re-run scenario-by-scenario (risk R2), so the diagnosis a developer reads is
# always per-scenario, in the same shape as always. run_with_timeout stays as
# the group-level backstop; the per-scenario deadline lives in the driver,
# which is the only place the stuck scenario's name is known (risk R3).
run_group() {
	local key="$1"
	shift
	local members=("$@")
	local m
	# The menu pair keeps its own per-scenario driver (MenuCaptureDriver is
	# deliberately not taught to batch), and a group of one IS the old path.
	if [[ "$key" == menu ]] || ((${#members[@]} == 1)); then
		for m in "${members[@]}"; do
			run_one_scenario "$m"
		done
		return
	fi
	# Two scenarios photograph glyph edges the process-wide font atlas can
	# shift: with thirty text-heavy scenarios rasterised before them, each came
	# out one antialiased column off its fresh-process frame. Running them
	# first, while the atlas still holds only the boot chrome a fresh process
	# would also have drawn, keeps every capture byte-identical to the
	# per-scenario baseline. The merge bar — the byte-diff over a full
	# SMOKE_KEEP sweep against an SMOKE_ISOLATE=1 one — is what keeps this
	# list honest when the roster moves; the status lines below still print in
	# the order the modes were given.
	local front=() rest=()
	for m in "${members[@]}"; do
		case "$m" in
			commander_info | cutin:bomber:tank) front+=("$m") ;;
			*) rest+=("$m") ;;
		esac
	done
	local demos=""
	for m in ${front[@]+"${front[@]}"} ${rest[@]+"${rest[@]}"}; do
		demos+="${demos:+,}$m"
	done
	local godot_args=(--path . "$BATTLE")
	godot_args+=(-- "--shots-dir=$out_dir" "--demos=$demos" "--scenario-timeout=$SMOKE_TIMEOUT")
	[[ "$key" == *:fog:* ]] && godot_args+=(--fog)
	local map="${key##*:}"
	[[ -n "$map" ]] && godot_args+=(--map="$map")
	run_with_timeout $((SMOKE_TIMEOUT * ${#members[@]})) "$GODOT_GUI" "${godot_args[@]}"
	local status=$?
	local ok=1 shot bytes
	((status != 0)) && ok=""
	for m in "${members[@]}"; do
		shot="$out_dir/${m//:/-}.png"
		if [[ ! -f "$shot" ]] || (($(wc -c <"$shot" | tr -d ' ') < MIN_BYTES)); then
			ok=""
		fi
	done
	if [[ -n "$ok" ]]; then
		for m in "${members[@]}"; do
			shot="$out_dir/${m//:/-}.png"
			bytes="$(wc -c <"$shot" | tr -d ' ')"
			printf 'smoke: %-14s ' "$m"
			echo "ok (${bytes}B)"
		done
		return
	fi
	echo "smoke: batch of ${#members[@]} ($key) failed; re-running its scenarios one by one" >&2
	for m in "${members[@]}"; do
		run_one_scenario "$m"
	done
}

if [[ -n "${SMOKE_ISOLATE:-}" ]]; then
	# One process per scenario, exactly as the sweep always ran — the escape
	# hatch risk R1 keeps for bisecting a pass that might lean on a batched
	# neighbour's leftover state.
	for mode in "${modes[@]}"; do
		run_one_scenario "$mode"
	done
else
	# Group in first-appearance order, so the sweep's lines stay deterministic.
	# bash 3.2 has no associative arrays; with four keys the rescan is nothing.
	keys=()
	for mode in "${modes[@]}"; do
		key="$(group_key "$mode")"
		seen=""
		for k in ${keys[@]+"${keys[@]}"}; do
			[[ "$k" == "$key" ]] && seen=1
		done
		[[ -z "$seen" ]] && keys+=("$key")
	done
	for key in "${keys[@]}"; do
		members=()
		for mode in "${modes[@]}"; do
			[[ "$(group_key "$mode")" == "$key" ]] && members+=("$mode")
		done
		run_group "$key" "${members[@]}"
	done
fi

if ((failed > 0)); then
	echo "smoke: $failed of ${#modes[@]} scenario(s) failed" >&2
	exit 1
fi

echo "smoke: ${#modes[@]} scenarios OK"
