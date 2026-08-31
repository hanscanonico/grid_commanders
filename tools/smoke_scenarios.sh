#!/usr/bin/env bash
#
# Presentation smoke check: proves every demo scenario still reaches its
# capture. The whole sweep runs in one engine process and one window
# (COM-117/COM-118): each scenario carries its own boot facts (scene · fog ·
# map), the driver reloads or scene-changes between them, and only the last
# one quits. SMOKE_ISOLATE=1 restores the one-process-per-scenario path
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
# path is printed so the frames can be eyeballed. SMOKE_HASHES=<file> records a
# manifest of what those frames hashed to, or compares this run against one —
# see compare_capture_hashes for why it is recorded rather than committed.
#
# Needs a display: these runs render. They are not headless, so this is a local
# gate, not something to wire into a headless CI job as-is.

set -uo pipefail

GODOT="${GODOT:-bin/Godot.app/Contents/MacOS/Godot}"
source "$(dirname "$0")/lib/require_godot.sh" || exit 1
BATTLE="${BATTLE:-scenes/battle/battle.tscn}"
# Every boot opens a window — one per group, not one per scenario. Launching
# through the wrapper keeps a scripted/agent run (no tty) from stealing the
# user's window focus on each of them;
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
# The three scenarios that actually fire a power — powermenu, powermenu+fog and
# power_banner — also photograph the marks the activation leaves on the board
# (COM-247). They pose at rest while capturing, exactly as the card holds,
# because there they are half of what the frame is of.
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
# scenario measures the live rect against it rather than trusting the frame.
# power_targeting is the first aimed power (MC4), stopped mid-aim over Red's own
# corner, and it measures too: the painted square is read back off the overlay and
# compared with what the strike would actually clear, since a preview showing nine
# tiles over a power that clears sixteen photographs just as well.
# power_meteor is that same square one beat later: the strike it gets, frozen at
# the impact flash. Posed rather than played, the meteor being a pure function of
# its own clock. The
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
# `cutin_volley` is the same staging frozen with the round still in the air, and it
# exists because the impact pose above shows what a hit looks like and nothing at
# all of what threw it. Since a unit picks its weapon by matchup, that is where the
# six signatures actually differ: tank-vs-mech is the machine gun's stream and
# plain `cutin_volley` is the same tank's cannon, mech-vs-tank the rocket, and the
# bomber, sub and anti-air entries the lobbed drop, the wake and the flak.
# `cutin_volley:artillery:mech` is the sixth: the howitzer is the only style that
# arcs its shell over its own indirect lob, and it fires late enough that the pose
# constant is measured against it (BattleCutsceneScenario.VOLLEY_POSE). The
# paired impact frames (cutin:tank:mech, cutin:mech:tank) are the other half of it:
# a strafing hit leaves sparks and no burst, a rocket leaves a hole.
#
# `cutin_scenery:mech:mech` is the other half of the ground plane. A terrain either
# paves that plane with its own art or stands a drawn shape on it, and the three
# shapes need three frames: `cutin_iron_commander` fights over a base and an HQ and
# so sweeps the buildings, but every other mode here fights on plains, road or open
# water, all of which pave — leaving trees and peaks drawn by nothing the sweep ever
# photographed, though either turns up the moment a unit fires from woods or a
# mountain. This one stands the pair on the default board's adjacent woods and
# mountain, one shape per half. Mechs because a mountain takes foot and boot only.
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
# ai_pause is the same route one turn later: the map menu opened *during* a
# computer turn, which is the only way to a menu at all in a match where every
# turn is one. It ends the player's turn for real, waits for the AI to take the
# board, asks for the pause the way Esc does, and then reads the rows back —
# because the two that act for the side on turn have to be gone, and a menu that
# still carried them would photograph exactly as well.
#
# auto_off is the Auto row's round trip, and it is a check rather than a picture:
# the player hands their own seat to the computer, pauses that seat's own Auto
# turn, and takes it back off the Off row. Turning Auto on has never been in
# doubt; the way back is what nobody could reach, because the hand-off banner was
# left running while the computer's first turn opened its own, and the first
# banner's epilogue rested the board to IDLE underneath the second — an
# interactive board on a computer's turn, where the Auto row is not offered at
# all. Every step of that photographs perfectly well, so the mode reads the rows
# off the live menu, checks the seat really left ai_teams, and then watches the
# handed-back seat for a command it must no longer issue.
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
# still paint its reach and R its fire ring — and then, since R answers from rest
# too, the same ring must come up on one key for both units a confirm can only
# preview (an enemy, and one of ours that has already acted) and re-aim rather
# than switch off when the cursor walks onto another. Both flows live in
# BattleFeedbackScenario rather than in the driver, which is why the driver's line
# ceiling moved by the dispatch arm and not by the scenarios.
#
# power_range_readout is COM-80's, and it sits beside the preview for the reason
# they share: both are what the game tells a player about reach. The bar printed
# the unit type's own min/max, so under Rhea Sol's Grid Saturation — +1 tile on
# her indirects — it read 2-3 while the fire ring and AttackCommand played 2-4.
# The scenario reads the bar's order line back against AttackRange before and
# during the power, because two wrong numbers photograph as well as two right
# ones.
#
# field_overlays is the one frame that has to hold three overlays at once: a
# capture chip counting down, the arrowed route to the cell under the cursor, and
# the threat lens shading everywhere the other side can shoot. Each reads fine
# alone — which is why it is photographed together. Three reds and a blue over the
# same terrain is the only question this scenario asks, and no per-overlay capture
# can answer it. It checks what a picture cannot: that the capture left progress
# to draw, that the raised lens is shading something, and that the cursor is on a
# reachable stop, since an empty overlay photographs as a perfectly good board.
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
# The menu scenarios are the same idea one screen earlier: `menu_with_save` poses a
# resumable match and `menu_no_save` poses none, and each measures the whole
# centered menu column, every seat row and all three primary actions against the 640x360 frame
# before it writes a thing. The column is the load-bearing witness, not the
# wordmark: a too-tall column is centered into an offset that runs off both ends
# at once, so the wordmark's own rect sat at exactly y=0 in a visibly sheared
# build while the header row's icon took the overflow (see
# MenuCaptureDriver._fits). COM-5 is why — with a save on disk the old menu
# clipped its own title and its Quit, and a returning player met a visibly
# broken screen while a fresh install never did. Both modes pose the save slot
# themselves, so neither reads nor writes the running machine's user://save.json.
# `menu_replays` opens the recordings page over a posed list, for the reason
# `menu_with_save` poses a save: how many matches the machine running the sweep
# happens to have played is not something a frame may depend on.
# `menu_commander_select` is the page Start opens, which no frame held either:
# the faction tabs, the roster grid and the seat chips. It photographs the page
# as it opens rather than driving it, because Random draws with the global RNG
# and this sweep's frames are compared byte for byte.
# `menu_setup_context` additionally poses an all-human table and proves the
# tutorial board leads, static facts/help, and disabled AI difficulty — a table
# with no computer at it has none to tune — before photographing them. It opens
# on the tutorial board, as every other menu mode does, so `menu_four_seats`
# selects the first board on the shelf that deals more than a duel: the picker's
# `· NP` suffix and a four-row seat strip are otherwise in no frame at all.
#
# The campaign menu scenarios are the same argument for the six authored
# wars, which had no frame anywhere: `menu_campaigns` is the war picker,
# `menu_campaign_hub` its mission list, `menu_campaign_brief` that hub with the
# open mission's briefing up, and `menu_campaign_debrief` and
# `menu_campaign_interlude` the two panels a war speaks through on the way back
# from a board. Each poses a fresh profile the way `menu_with_save` poses a
# save — how far the machine running the sweep has played is not something a
# frame may depend on — and each measures its own page's chrome against the
# frame before it writes, as the rest of the menu family does: a panel whose
# rows stacked at the container's origin writes a perfectly healthy PNG.
# `menu_campaign_deep` is the sixth, and the only frame in the sweep where the
# hub's list is scrolled: it walks the flagship war forward past the twelve rows
# that fit the page, so the open mission is one the list has to scroll to, which
# makes it the regression frame for that list's follow_focus.
#
# The mission_strip pair is COM-12's, and since COM-122 both run on the tutorial
# board — the only one the strip teaches on. Every other scenario runs with the
# first-match hints pinned retired, exactly as they run with the game speed
# pinned — otherwise whether a teaching card sits over the board would depend on
# how much of the game the person running the sweep had already played. These two
# pin them *empty* instead, so the strip opens as it does on a fresh install.
# `mission_strip` poses that first frame; `mission_strip_retired` drives a real
# selection and a real move and then checks the strip has moved on to CAPTURE,
# which is the acceptance criterion a still frame cannot show — a hint retires
# when the player performs it, and a strip stuck on SELECT photographs just as
# well as one that advanced.
#
# objective_panel, mission_event, mission_defection, campaign_mapmenu and
# campaign_win_stops_ai are the five scenarios that play a campaign mission, and the
# only way the in-battle objective card, a scripted beat and the pause menu's
# Briefing row are reachable at all: all of them are down for every skirmish,
# which is what keeps every other frame in this sweep byte-stable. None names a
# board — the mission's own is not in the map catalogue, so they are launched the
# way the campaign hub launches one, through MatchConfig — and the first two read
# their open card back off its live labels for the reason commander_info does.
#
# mission_event runs the same mission one step further on: it hands the player the
# depot the mission's own beat waits for, fires through the shipped seam, and
# photographs Ferrow's line over the raider that just landed on the road.
#
# campaign_mapmenu is the same launch stopped at the pause menu: the Briefing and
# Objectives rows are offered only inside a campaign, so mapmenu, power_mapmenu
# and ai_pause all photograph the menu without them, and it reads the rows back
# like power_mapmenu does — a menu that dropped either, or carried it somewhere
# other than after Commanders, writes a perfectly healthy PNG.
#
# campaign_win_stops_ai is a check the picture cannot make at all. A mission is won
# on its objectives, never on `game.winner`, so a verdict reached in the middle of
# the computer's turn used to leave the runner planning the next command under the
# raised end card — the match ran on, and the card's own buttons stayed guarded shut
# because the runner had overwritten the state that releases them. It wins the
# mission mid-turn, then watches the finished board for a second and a half and
# fails if anything on it moved.
#
# mission_defection is the other half of what a beat can do to the board, and it
# is a check before it is a picture: a unit that changed army has to be redrawn in
# the colours it changed to, and a sprite still wearing the army it left writes a
# perfectly healthy PNG. It poses the defection on The Long Front's exemplar
# board, whose units the mission already names one of, and reads every sprite's
# atlas row back against SideIdentity's answer for its owner.
#
# commander_info is a check as well as a picture, and the only one whose check is
# about its own layout. It was passing on a blank screen: the sweep's bar is a file
# size, and a sheet that drew its faction headers over collapsed columns wrote a
# perfectly healthy PNG (COM-47 review). Rather than commit a reference frame — the
# sweep has no golden images, and its own notes above record how far glyph edges
# move between runs — the scenario reads the open sheet back off the live controls
# and fails the run unless every card is shown at least its portrait band, which is
# the same shape of check the cut-in family's atlas rows already get.
#
# mixed_seat_handoff is the four-players D7 gate, on the quartet board with fog on:
# two seats at the table and two played by the computer — a roster the menu's seat
# strip can now set up, posed here so the gate does not walk a menu to reach it.
# It drives whole turns through the live end-
# turn route and proves the three things a still frame cannot — that the blackout
# fires for the incoming person across an intervening computer turn, that a computer
# turn is watched through the fog of the person who just played rather than the first
# human seat, and that the last player standing is never asked to hand the device to
# themselves.
#
# The transition pair is COM-15's two-sided state-boundary gate. The banner mode
# deliberately keeps day one's card: an attempted build may only skip that beat,
# never open its menu underneath, and the next press opens production on the
# clear board. The outcome mode wins through a real attack, sends a buffered
# Enter into the new lockup, waits out its short mash guard, and proves the next
# fresh press highlights an action without activating it.
DEFAULT_MODES=(
	attack resolve capture build buildmenu endturn
	load cargo drop transport supply divemenu dive mapmenu leave_confirm after_build_menu
	rejected_confirm enemy_range_preview end_turn_ready_units field_overlays
	power_range_readout
	turn_banner_build_attempt outcome_mash_guard
	powermenu capture_power victory aiturn ai_pause auto_off
	mission_strip mission_strip_retired objective_panel mission_event mission_defection
	campaign_mapmenu campaign_win_stops_ai
	powermenu+fog victory+fog ambush vanish preview_fog
	power_charging power_ready power_ready_contrast power_active power_ai power_mirror
	power_mapmenu power_banner power_targeting power_meteor
	commander_info commander_victory side_victory
	mixed_seat_handoff+fog
	cutin cutin_ko cutin_skip cutin_iron_commander cutin_scenery:mech:mech
	cutin:bomber:tank cutin:sub:cruiser cutin:cruiser:sub cutin:artillery:mech
	cutin:tank:mech cutin:mech:tank
	cutin_volley cutin_volley:tank:mech cutin_volley:mech:tank
	cutin_volley:bomber:tank cutin_volley:sub:cruiser cutin_volley:anti_air:infantry
	cutin_volley:artillery:mech
	capture_cutin capture_cutin_partial capture_cutin_skip capture_cutin_iron_commander
	menu_with_save menu_no_save menu_setup_context menu_four_seats menu_replays
	menu_campaigns menu_campaign_hub menu_campaign_brief menu_campaign_debrief
	menu_campaign_interlude menu_campaign_deep menu_commander_select
)

# mobile_back is deliberately NOT in that list. A touch build is a boot fact of the
# whole process — MobileProfile resolves --mobile once — so a mobile scenario can
# never share the one-boot sweep with a desktop one, and adding it would also put
# every recorded manifest on a different queue. Run it on its own:
# `make smoke MODES=mobile_back`. It drives the touch dock out of all four
# targeting states and through a paused computer turn (mobile plan MB3).

require_godot smoke

modes=("$@")
if ((${#modes[@]} == 0)); then
	modes=("${DEFAULT_MODES[@]}")
fi

out_dir="$(mktemp -d "${TMPDIR:-/tmp}/battle-smoke.XXXXXX")"
# Non-empty when the one-boot sweep failed as a batch and had to be re-run one
# process per scenario; the entry names the log the batch left behind.
batch_fallbacks=()
cleanup() {
	# A fallback's log and captures are the only record of batch rot — the
	# scenarios pass on their own, so nothing else is left to look at.
	if [[ -n "${SMOKE_KEEP:-}" ]] || ((${#batch_fallbacks[@]} > 0)); then
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

# The board a demo needs, or nothing for the default one. The naval scenarios
# need water on the map; the default board has none. power_ready_contrast
# borrows the same board for a different reason: it is power_ready over the
# bright, sea-heavy strait rather than the dim default, so the pair is the
# meter's dark/light legibility comparison. The mission_strip pair needs the
# tutorial board because that is now the only one the strip teaches on at all
# (COM-122) — on any other board the scenarios would photograph a blank sky.
#
# One spelling, two callers — the `--map=` a single scenario boots with and the
# `@<map>` a batch entry carries — so a new water scenario cannot reach one and
# not the other.
map_for_demo() {
	case "$1" in
		divemenu | dive | power_ready_contrast | *:sub | *:sub:* | *:cruiser | *:battleship | *:lander)
			echo the_straits
			;;
		mission_strip | mission_strip_retired)
			echo boot_camp
			;;
		side_victory | mixed_seat_handoff)
			# The four-army fixture — sized to fit the battle viewport whole, which no
			# shipped four-seat board is. For side_victory four seats are the whole
			# point of the frame: four liveries behind a lockup that names a side rather
			# than one of them (four-players plan D5). mixed_seat_handoff needs four
			# seats for a different reason — it is the only roster that can put a
			# computer's turn between two people's (D7).
			echo quartet
			;;
	esac
}

# One scenario, one process — the shape the sweep always had, kept verbatim as
# the SMOKE_ISOLATE=1 path and the re-run a failing sweep gets (see
# run_batched_sweep). Prints the scenario's status line and bumps `failed` when
# it goes wrong.
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
	# A touch build is a boot fact of the whole process (MobileProfile resolves it
	# once), so a mobile scenario can only run one process to itself — which is why
	# none is in DEFAULT_MODES and why the flag is added here and not in the batch.
	[[ "$demo" == mobile_* ]] && godot_args+=(--mobile)
	if [[ "$demo" != "$mode" ]]; then
		godot_args+=(--fog)
	fi
	local map
	map="$(map_for_demo "$demo")"
	[[ -n "$map" ]] && godot_args+=(--map="$map")
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

# FS3 (COM-118): one boot for the whole sweep. Scene, fog and map are
# per-scenario boot facts now — each `--demos` entry carries its own (`+fog`
# stays in the mode name, `@<map>` is appended here) and the driver
# reconfigures between scenarios: the battle scene reloads with the entry's
# flags and the `menu_` pair runs through a scene change, all in one window.
# On success the per-scenario lines are printed from the captures the driver
# wrote, in the order the modes were given; a sweep that fails in any way is
# re-run scenario-by-scenario (risk R2), so the diagnosis a developer reads is
# always per-scenario, in the same shape as always. run_with_timeout stays as
# the whole-sweep backstop; the per-scenario deadline lives in the driver,
# which is the only place the stuck scenario's name is known (risk R3).
#
# Execution order is not the given order: the two scenarios whose glyph edges
# the process-wide font atlas can shift run first (the FS2 finding — each came
# out one antialiased column off its fresh-process frame with thirty text-heavy
# scenarios before it), then the default-board battle roster, then the strait
# and fog boards, and the menu pair last. The merge bar — the byte-diff over a
# full SMOKE_KEEP sweep against an SMOKE_ISOLATE=1 one — is what keeps that
# ordering honest when the roster moves.
run_batched_sweep() {
	local members=("$@")
	local m
	if ((${#members[@]} == 1)); then
		run_one_scenario "${members[0]}"
		return
	fi
	local front=() battle_rest=() boards=() menu=() solo=()
	local demo
	for m in "${members[@]}"; do
		demo="${m%+fog}"
		# A mobile mode needs --mobile, which MobileProfile resolves once per
		# process, so it can never share a boot with a desktop scenario.
		if [[ "$demo" == mobile_* ]]; then
			solo+=("$m")
			continue
		fi
		case "$m" in
			commander_info | cutin:bomber:tank)
				front+=("$m")
				continue
				;;
		esac
		if [[ "$demo" == menu_* ]]; then
			menu+=("$m")
		elif [[ "$demo" != "$m" || -n "$(map_for_demo "$demo")" ]]; then
			boards+=("$m")
		else
			battle_rest+=("$m")
		fi
	done
	local batched=(
		${front[@]+"${front[@]}"} ${battle_rest[@]+"${battle_rest[@]}"}
		${boards[@]+"${boards[@]}"} ${menu[@]+"${menu[@]}"}
	)
	for m in ${solo[@]+"${solo[@]}"}; do
		run_one_scenario "$m"
	done
	((${#batched[@]} == 0)) && return
	local demos="" first="" map
	for m in "${batched[@]}"; do
		first="${first:-$m}"
		map="$(map_for_demo "${m%+fog}")"
		demos+="${demos:+,}${m}${map:+@$map}"
	done
	# The boot scene is the first entry's; the driver crosses to the other
	# scene when the queue does.
	local godot_args=(--path .)
	[[ "${first%+fog}" != menu_* ]] && godot_args+=("$BATTLE")
	godot_args+=(-- "--shots-dir=$out_dir" "--demos=$demos" "--scenario-timeout=$SMOKE_TIMEOUT")
	run_with_timeout $((SMOKE_TIMEOUT * ${#batched[@]})) "$GODOT_GUI" "${godot_args[@]}"
	local status=$?
	local ok=1 shot bytes
	((status != 0)) && ok=""
	for m in "${batched[@]}"; do
		shot="$out_dir/${m//:/-}.png"
		if [[ ! -f "$shot" ]] || (($(wc -c <"$shot" | tr -d ' ') < MIN_BYTES)); then
			ok=""
		fi
	done
	if [[ -n "$ok" ]]; then
		for m in "${batched[@]}"; do
			shot="$out_dir/${m//:/-}.png"
			bytes="$(wc -c <"$shot" | tr -d ' ')"
			printf 'smoke: %-14s ' "$m"
			echo "ok (${bytes}B)"
		done
		return
	fi
	# The re-runs below reuse last.log, so the batch's own diagnosis has to be
	# moved aside first: when every scenario then passes on its own, this log is
	# the only thing left that says the batch broke.
	local batch_log="$out_dir/batch-sweep.log"
	cp "$out_dir/last.log" "$batch_log" 2>/dev/null
	batch_fallbacks+=("one-boot sweep ($batch_log)")
	echo "smoke: one-boot sweep of ${#batched[@]} failed; log kept at $batch_log" >&2
	echo "smoke: re-running its scenarios one by one" >&2
	for m in "${batched[@]}"; do
		run_one_scenario "$m"
	done
}

# The captures are called byte-stable in three places (focus-steal D1,
# range-preview D1, the README), and the sweep's own assertion is a size floor:
# nothing ever compared a byte. SMOKE_HASHES=<file> is that comparison, and it
# is the shape check_determinism.sh already uses — record the side to diff
# against, then diff against it:
#
#   SMOKE_HASHES=/tmp/before.txt make smoke   # writes the manifest
#   ...the change...
#   SMOKE_HASHES=/tmp/before.txt make smoke   # fails on any frame that moved
#
# Nothing is committed, deliberately. Unlike the determinism golden — integer
# and IEEE-754 arithmetic any platform reproduces — a frame is this machine's
# renderer and glyph rasteriser, and the process-wide font atlas shifts the
# glyph edges with the queue's composition, so one scenario writes different
# bytes in `make smoke MODES=cutin` than in the full sweep. A manifest is
# therefore only read against a run of the same modes, which its first line
# records and the comparison refuses to cross: a narrowed run is a different
# picture of the same scene, not a regression.
capture_manifest() {
	local m shot
	echo "# queue: ${modes[*]}"
	for m in "${modes[@]}"; do
		shot="$out_dir/${m//:/-}.png"
		printf '%s  %s\n' "$(shasum -a 256 <"$shot" | cut -d ' ' -f1)" "$m"
	done
}

# Non-zero only when a recorded frame moved; silent and successful when
# SMOKE_HASHES is unset, which is every ordinary run.
compare_capture_hashes() {
	local manifest="${SMOKE_HASHES:-}"
	[[ -z "$manifest" ]] && return 0
	if [[ ! -f "$manifest" ]]; then
		capture_manifest >"$manifest"
		echo "smoke: recorded ${#modes[@]} capture hashes in $manifest"
		return 0
	fi
	if [[ "$(head -1 "$manifest")" != "# queue: ${modes[*]}" ]]; then
		echo "smoke: $manifest was recorded from a different queue, so its bytes" >&2
		echo "smoke: answer for a different font atlas — record a new one to compare" >&2
		return 1
	fi
	local m shot want got moved=0
	for m in "${modes[@]}"; do
		shot="$out_dir/${m//:/-}.png"
		want="$(awk -v mode="$m" '$2 == mode {print $1}' "$manifest")"
		got="$(shasum -a 256 <"$shot" | cut -d ' ' -f1)"
		if [[ "$want" != "$got" ]]; then
			echo "smoke: $m moved — recorded ${want:0:12}, now ${got:0:12}" >&2
			moved=$((moved + 1))
		fi
	done
	((moved == 0)) && echo "smoke: ${#modes[@]} captures byte-identical to $manifest" && return 0
	echo "smoke: $moved capture(s) moved. If the change is deliberate, record a new manifest." >&2
	return 1
}

# Batch rot does not fail the sweep — every scenario passing on its own is a
# pass — but it must never be silent, so it is named again after the summary.
report_batch_fallbacks() {
	((${#batch_fallbacks[@]} == 0)) && return
	echo "smoke: ${#batch_fallbacks[@]} batch(es) failed and fell back to one process per scenario:" >&2
	local entry
	for entry in "${batch_fallbacks[@]}"; do
		echo "smoke:   $entry" >&2
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
	run_batched_sweep "${modes[@]}"
fi

if ((failed > 0)); then
	echo "smoke: $failed of ${#modes[@]} scenario(s) failed" >&2
	report_batch_fallbacks
	exit 1
fi

echo "smoke: ${#modes[@]} scenarios OK"
report_batch_fallbacks
compare_capture_hashes || exit 1
