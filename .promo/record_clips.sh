#!/usr/bin/env bash
#
# Video capture of the game playing itself. `make smoke` photographs a scenario;
# this records one.
#
# It records through the engine's Movie Maker mode (`--write-movie`) rather than
# a screen grabber, because that mode drives the game off a fixed 60 fps clock
# and renders every frame of it however long the frame took to draw. So a clip is
# the same length and the same frames on any machine — a slow laptop records the
# tween a fast one does, not a dropped-frame version of it — which is what lets
# make_reel.sh name a moment by its timestamp. The game's own music and effects
# are mixed into the file as it goes.
#
# Two things decide what is worth pointing it at:
#
#   * A `--demo=` run is a *capture*, and a capture pins the Instant speed and
#     suppresses the cut-ins, the camera shake and the ambient beat so that a
#     still frame cannot depend on the machine that took it (see
#     BattleScenarioDriver). There is nothing to film in a suppressed animation,
#     so the footage of the theatre comes from watched matches instead: `--watch`
#     plays a Balance Lab row in the real window with everything switched on.
#   * It renders, so it needs a display, exactly as `make smoke` does. Not
#     something to wire into a headless CI job.
#
# Needs ffmpeg on PATH. The writer's MJPEG AVI runs about 7 MB per second of
# video, so each clip is transcoded to H.264 and the AVI dropped; KEEP_AVI=1
# keeps it, which is the form make_promo.sh reads its two clips in.
#
# Usage:  [GODOT=<binary>] .promo/record_clips.sh [clip ...]
#
# With no arguments it records all four. Clips land in .promo/clips (gitignored,
# like every other rendered thing under .promo); CLIP_DIR=<dir> moves them.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-bin/Godot.app/Contents/MacOS/Godot}"
source "$ROOT/tools/lib/require_godot.sh" || exit 1
export GODOT
GODOT_GUI="$ROOT/tools/godot_gui.sh"
BATTLE="scenes/battle/battle.tscn"
OUT_DIR="${CLIP_DIR:-$ROOT/.promo/clips}"

ALL_CLIPS=(menu land sea victory)

# What each clip boots, and how many frames of the 60 fps clock to hold it for.
# The seeds are pinned rather than left to the day: the sim is deterministic, so
# a seed is the whole match, and re-recording one is how a cut list stays usable.
#
# `land` and `sea` are the two watched matches — one inland board and one with
# submarines and cruisers on it — long enough to meet a capture, several cut-ins
# and a Command Power. `menu` is the main menu's drift and blink, and `victory`
# is the one demo worth filming: the lockup a routed side raises, which a watched
# match of this length never reaches.
select_clip() {
	CLIP_SCENE=""
	CLIP_USER=()
	case "$1" in
		menu)
			CLIP_FRAMES=420
			;;
		land)
			CLIP_FRAMES=9000
			CLIP_SCENE="$BATTLE"
			CLIP_USER=(
				--watch --map=ironworks
				--red=gideon_holt:normal --blue=cass_orlov:normal
				--seed=1003 --speed=normal
			)
			;;
		sea)
			CLIP_FRAMES=9000
			CLIP_SCENE="$BATTLE"
			CLIP_USER=(
				--watch --map=the_straits
				--red=rhea_sol:normal --blue=viktor_draeg:normal
				--seed=42 --speed=normal
			)
			;;
		victory)
			CLIP_FRAMES=150
			CLIP_SCENE="$BATTLE"
			CLIP_USER=(--demo=victory --speed=normal --screenshot="$OUT_DIR/victory.png")
			;;
		*)
			return 1
			;;
	esac
}

record_clip() {
	local name="$1"
	if ! select_clip "$name"; then
		echo "record: unknown clip: $name (known: ${ALL_CLIPS[*]})" >&2
		return 1
	fi
	local avi="$OUT_DIR/$name.avi"
	local mp4="$OUT_DIR/$name.mp4"
	printf 'record: %-8s ' "$name"

	local -a args=(--path "$ROOT")
	[[ -n "$CLIP_SCENE" ]] && args+=("$CLIP_SCENE")
	args+=(--write-movie "$avi" --quit-after "$CLIP_FRAMES")
	((${#CLIP_USER[@]})) && args+=(-- "${CLIP_USER[@]}")
	if ! "$GODOT_GUI" "${args[@]}" >"$OUT_DIR/$name.log" 2>&1; then
		echo "FAILED (see $OUT_DIR/$name.log)"
		return 1
	fi
	if [[ ! -f "$avi" ]]; then
		echo "FAILED (nothing recorded; see $OUT_DIR/$name.log)"
		return 1
	fi

	if ! ffmpeg -y -hide_banner -loglevel error -i "$avi" \
		-c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p \
		-c:a aac -b:a 160k -movflags +faststart "$mp4"; then
		echo "FAILED (transcode)"
		return 1
	fi
	[[ -n "${KEEP_AVI:-}" ]] || rm -f "$avi"
	rm -f "$OUT_DIR/$name.log"
	echo "ok ($((CLIP_FRAMES / 60))s, $(du -h "$mp4" | cut -f1))"
}

require_godot record
command -v ffmpeg >/dev/null || {
	echo "record: ffmpeg not found on PATH" >&2
	exit 1
}
mkdir -p "$OUT_DIR"

clips=("$@")
((${#clips[@]})) || clips=("${ALL_CLIPS[@]}")

failed=0
for clip in "${clips[@]}"; do
	record_clip "$clip" || failed=$((failed + 1))
done

if ((failed)); then
	echo "record: $failed clip(s) failed" >&2
	exit 1
fi
echo "record: wrote ${#clips[@]} clip(s) to $OUT_DIR"
