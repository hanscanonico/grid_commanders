#!/usr/bin/env bash
#
# Cuts the animation reel out of the footage record_clips.sh records: one
# labelled segment per animation the game plays, in the order a match meets them,
# carrying the game's own sound.
#
# The cut list below names moments by timestamp, which is only usable because the
# footage is reproducible — the sim is deterministic at a pinned seed and the
# movie writer runs on a fixed 60 fps clock, so `record_clips.sh land` writes the
# same match to the same frame on any machine. A rules, balance or planner change
# moves that match: the seeds still record cleanly, the timestamps quietly stop
# pointing at what they name. So look at the reel after one, rather than trusting
# a stale cut.
#
# Needs ffmpeg with libfreetype (the labels are drawn in the game's own UI font).
#
# Usage:  .promo/make_reel.sh
#
# Records nothing itself: run `.promo/record_clips.sh` first. Reads .promo/clips
# (CLIP_DIR=<dir> moves it) and writes .promo/animation_reel.mp4.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIP_DIR="${CLIP_DIR:-$ROOT/.promo/clips}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
OUT="$ROOT/.promo/animation_reel.mp4"
FONT="$ROOT/assets/fonts/Silkscreen-Bold.ttf"
# One encode for every segment, because the reel is assembled by stream copy:
# concat -c copy refuses a list whose parts disagree about codec, rate or size.
ENCODE=(-c:v libx264 -pix_fmt yuv420p -crf 21 -preset medium -r 60
	-c:a aac -b:a 160k -ar 48000 -ac 2)

# clip | start | seconds | label | label y | hold
#
# The label sits in the top bar, where a cut-in's letterbox is already black —
# except on the menu, whose own wordmark is there, so that one is captioned from
# the lower third instead. `hold` freezes the last frame for that many seconds,
# which the victory clip needs: the demo ends the moment the lockup is up.
CUTS=(
	"menu|0.5|6.0|MAIN MENU|636|0"
	"land|0.0|7.0|TURN BANNER + BOARD|20|0"
	"land|16.5|7.0|PROPERTY CAPTURE|20|0"
	"land|50.5|7.0|BATTLE CUT-IN|20|0"
	"land|70.0|7.0|DIRECT HIT|20|0"
	"land|82.0|8.0|COMMAND POWER|20|0"
	"sea|16.0|7.0|NAVAL CUT-IN|20|0"
	"sea|38.0|7.0|SHORE BOMBARDMENT|20|0"
	"land|122.0|7.0|CAPTURED|20|0"
	"land|132.0|7.0|KNOCKED OUT|20|0"
	"victory|0.0|1.7|VICTORY|20|2.8"
)

# Read the list rather than piping it into `grep -q`: the early close that makes
# -q fast leaves ffmpeg on a SIGPIPE, which under `pipefail` fails a build whose
# ffmpeg is perfectly good.
case "$(ffmpeg -hide_banner -filters 2>/dev/null)" in
	*" drawtext "*) ;;
	*)
		echo "reel: this ffmpeg has no drawtext filter (build it with libfreetype)" >&2
		exit 1
		;;
esac

title_card() {
	ffmpeg -y -hide_banner -loglevel error \
		-f lavfi -i "color=c=0x121417:s=1280x720:r=60:d=3" \
		-f lavfi -i "anullsrc=r=48000:cl=stereo" -t 3 \
		-vf "drawtext=fontfile=$FONT:text='GRID COMMANDERS':x=(w-tw)/2:y=300:fontsize=54\
:fontcolor=0xF2E9D8:alpha='min(1,t/0.6)',\
drawtext=fontfile=$FONT:text='ANIMATION REEL':x=(w-tw)/2:y=380:fontsize=26\
:fontcolor=0xC8532F:alpha='min(1,max(0,(t-0.4)/0.6))',\
fade=t=out:st=2.6:d=0.4" \
		"${ENCODE[@]}" "$WORK/000.mp4"
}

# One cut, labelled and faded. `hold` and `last` are what the reel ends on: the
# frozen lockup, and the fade to black over it.
cut_segment() {
	local clip="$1" start="$2" seconds="$3" label="$4" label_y="$5" hold="$6" out="$7" last="$8"
	local source="$CLIP_DIR/$clip.mp4"
	if [[ ! -f "$source" ]]; then
		echo "reel: no footage at $source — run .promo/record_clips.sh $clip" >&2
		return 1
	fi
	# The label reads for the first beats and then leaves the picture alone.
	local video="drawtext=fontfile=$FONT:text='$label':x=28:y=$label_y:fontsize=24"
	video+=":fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=12"
	video+=":alpha='if(lt(t,2.6),1,max(0,1-(t-2.6)/0.5))'"
	local audio="afade=t=in:st=0:d=0.25"
	local length="$seconds"
	if [[ "$hold" != "0" ]]; then
		video+=",tpad=stop_mode=clone:stop_duration=$hold"
		audio="apad,$audio"
		length="$(awk "BEGIN { print $seconds + $hold }")"
	fi
	if ((last)); then
		video+=",fade=t=out:st=$(awk "BEGIN { print $length - 0.6 }"):d=0.6"
	fi
	audio+=",afade=t=out:st=$(awk "BEGIN { print $length - 0.3 }"):d=0.3"

	ffmpeg -y -hide_banner -loglevel error -ss "$start" -i "$source" -t "$length" \
		-vf "$video" -af "$audio" "${ENCODE[@]}" "$out"
}

title_card || exit 1
printf "file '%s'\n" "$WORK/000.mp4" >"$WORK/list.txt"

index=1
for cut in "${CUTS[@]}"; do
	IFS='|' read -r clip start seconds label label_y hold <<<"$cut"
	segment="$(printf '%s/%03d.mp4' "$WORK" "$index")"
	last=0
	((index == ${#CUTS[@]})) && last=1
	printf 'reel: %-20s ' "$label"
	if ! cut_segment "$clip" "$start" "$seconds" "$label" "$label_y" "$hold" "$segment" "$last"; then
		exit 1
	fi
	echo "ok"
	printf "file '%s'\n" "$segment" >>"$WORK/list.txt"
	index=$((index + 1))
done

ffmpeg -y -hide_banner -loglevel error -f concat -safe 0 -i "$WORK/list.txt" \
	-c copy -movflags +faststart "$OUT" || exit 1
printf 'reel: wrote %s (%ss)\n' "$OUT" \
	"$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT" | cut -d. -f1)"
