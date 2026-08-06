#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROMO_DIR="$ROOT/.promo"
FRAME_DIR="$PROMO_DIR/frames"
CLIP_DIR="$PROMO_DIR/clips"
LANDSCAPE_DIR="$PROMO_DIR/slides-landscape"
LANDSCAPE_OVERLAY_DIR="$PROMO_DIR/overlays-landscape"
VERTICAL_DIR="$PROMO_DIR/slides-vertical"
FONT_BOLD="/System/Library/Fonts/Supplemental/Arial Black.ttf"
FONT_REGULAR="/System/Library/Fonts/Supplemental/Arial Bold.ttf"
ACCENT="#f5b841"
DURATION="14.95"

mkdir -p "$LANDSCAPE_DIR" "$LANDSCAPE_OVERLAY_DIR" "$VERTICAL_DIR"

require_file() {
	if [[ ! -f "$1" ]]; then
		printf 'promo: missing required file: %s\n' "$1" >&2
		exit 1
	fi
}

for file in \
	"$FRAME_DIR/attack.png" \
	"$FRAME_DIR/cutin_bomber_tank.png" \
	"$FRAME_DIR/capture_cutin.png" \
	"$FRAME_DIR/power_banner.png" \
	"$FRAME_DIR/cutin_sub_cruiser.png" \
	"$FRAME_DIR/commander_victory.png" \
	"$CLIP_DIR/combat.avi" \
	"$CLIP_DIR/capture.avi"; do
	require_file "$file"
done

make_landscape_slide() {
	local source="$1"
	local output="$2"
	local kicker="$3"
	local headline="$4"
	local detail="$5"

	magick "$source" \
		-resize 1280x720^ -gravity center -extent 1280x720 \
		-fill '#070b10b8' -draw 'rectangle 0,0 1280,178' \
		-fill '#070b10b8' -draw 'rectangle 0,628 1280,720' \
		-fill "$ACCENT" -font "$FONT_REGULAR" -pointsize 19 \
		-gravity northwest -annotate +60+28 "$kicker" \
		-fill white -font "$FONT_BOLD" -pointsize 43 \
		-gravity northwest -annotate +58+70 "$headline" \
		-fill white -font "$FONT_REGULAR" -pointsize 24 \
		-gravity southwest -annotate +48+28 "$detail" \
		-fill "$ACCENT" -draw 'rectangle 60,151 294,158' \
		"$output"
}

make_landscape_overlay() {
	local output="$1"
	local kicker="$2"
	local headline="$3"
	local detail="$4"

	magick -size 1280x720 canvas:none \
		-fill '#070b10e0' -draw 'rectangle 0,0 1280,178' \
		-fill '#070b10d0' -draw 'rectangle 0,628 1280,720' \
		-fill "$ACCENT" -font "$FONT_REGULAR" -pointsize 19 \
		-gravity northwest -annotate +60+28 "$kicker" \
		-fill white -font "$FONT_BOLD" -pointsize 43 \
		-gravity northwest -annotate +58+70 "$headline" \
		-fill white -font "$FONT_REGULAR" -pointsize 24 \
		-gravity southwest -annotate +48+28 "$detail" \
		-fill "$ACCENT" -draw 'rectangle 60,151 294,158' \
		"$output"
}

make_landscape_title() {
	local source="$1"
	local output="$2"
	local headline="$3"
	local detail="$4"

	magick "$source" \
		-resize 1280x720^ -gravity center -extent 1280x720 \
		-blur 0x16 -modulate 52,85,100 \
		-fill '#05080dcc' -colorize 38% \
		-fill "$ACCENT" -draw 'rectangle 384,228 896,238' \
		-fill white -font "$FONT_BOLD" -pointsize 86 \
		-gravity center -annotate +0-18 "$headline" \
		-fill '#dce2e9' -font "$FONT_REGULAR" -pointsize 28 \
		-gravity center -annotate +0+70 "$detail" \
		"$output"
}

make_vertical_slide() {
	local source="$1"
	local output="$2"
	local kicker="$3"
	local headline="$4"
	local detail="$5"
	local name
	name="$(basename "$output" .png)"
	local backdrop="$VERTICAL_DIR/.${name}-backdrop.png"
	local gameplay="$VERTICAL_DIR/.${name}-gameplay.png"

	magick "$source" \
		-resize 1080x1920^ -gravity center -extent 1080x1920 \
		-blur 0x28 -modulate 48,90,100 \
		-fill '#05080dbb' -colorize 42% \
		"$backdrop"
	magick "$source" \
		-resize 1000x563^ -gravity center -extent 1000x563 \
		-bordercolor "$ACCENT" -border 4 \
		"$gameplay"
	magick "$backdrop" \
		-fill '#080c13d9' -draw 'roundrectangle 42,78 1038,500 30,30' \
		-fill '#080c13d9' -draw 'roundrectangle 42,1218 1038,1818 30,30' \
		"$gameplay" -gravity north -geometry +0+590 -composite \
		-fill "$ACCENT" -font "$FONT_REGULAR" -pointsize 28 \
		-gravity northwest -annotate +86+128 "$kicker" \
		-fill white -font "$FONT_BOLD" -pointsize 68 \
		-gravity northwest -interline-spacing 7 -annotate +82+205 "$headline" \
		-fill white -font "$FONT_REGULAR" -pointsize 34 \
		-gravity northwest -interline-spacing 6 -annotate +84+1300 "$detail" \
		-fill "$ACCENT" -draw 'rectangle 84,1732 414,1742' \
		-fill white -font "$FONT_BOLD" -pointsize 40 \
		-gravity southwest -annotate +84+98 'GRID COMMANDER' \
		-fill '#d3d9e2' -font "$FONT_REGULAR" -pointsize 24 \
		-gravity southeast -annotate +84+101 'TURN-BASED TACTICS' \
		"$output"
}

make_vertical_title() {
	local source="$1"
	local output="$2"
	local headline="$3"
	local detail="$4"

	magick "$source" \
		-resize 1080x1920^ -gravity center -extent 1080x1920 \
		-blur 0x28 -modulate 48,85,100 \
		-fill '#05080dcc' -colorize 38% \
		-fill "$ACCENT" -draw 'rectangle 210,746 870,760' \
		-fill white -font "$FONT_BOLD" -pointsize 94 \
		-gravity center -interline-spacing 6 -annotate +0-70 "$headline" \
		-fill '#dce2e9' -font "$FONT_REGULAR" -pointsize 34 \
		-gravity center -interline-spacing 5 -annotate +0+105 "$detail" \
		"$output"
}

make_landscape_title \
	"$FRAME_DIR/attack.png" "$LANDSCAPE_DIR/00.png" \
	"GRID COMMANDER" "TURN-BASED TACTICAL STRATEGY • PLAN • MOVE • ATTACK • CAPTURE"
make_landscape_slide \
	"$FRAME_DIR/attack.png" "$LANDSCAPE_DIR/01.png" \
	"YOUR TURN" "MOVE ON THE GRID. THINK AHEAD." \
	"Use terrain, movement ranges and damage forecasts."
make_landscape_slide \
	"$FRAME_DIR/cutin_bomber_tank.png" "$LANDSCAPE_DIR/02.png" \
	"UNIT MATCHUPS" "COMMIT YOUR ATTACK" \
	"Firing ranges, strengths and counters decide the exchange."
make_landscape_slide \
	"$FRAME_DIR/capture_cutin.png" "$LANDSCAPE_DIR/03.png" \
	"CONTROL THE ECONOMY" "CAPTURE CITIES. BUILD UNITS." \
	"Properties generate funds for your next turn."
make_landscape_overlay \
	"$LANDSCAPE_OVERLAY_DIR/02.png" \
	"UNIT MATCHUPS" "COMMIT YOUR ATTACK" \
	"Firing ranges, strengths and counters decide the exchange."
make_landscape_overlay \
	"$LANDSCAPE_OVERLAY_DIR/03.png" \
	"CONTROL THE ECONOMY" "CAPTURE CITIES. BUILD UNITS." \
	"Properties generate funds for your next turn."
make_landscape_slide \
	"$FRAME_DIR/power_banner.png" "$LANDSCAPE_DIR/04.png" \
	"13 PLAYSTYLES" "CHOOSE YOUR COMMANDER" \
	"Distinct doctrines and powers reshape your strategy."
make_landscape_slide \
	"$FRAME_DIR/cutin_sub_cruiser.png" "$LANDSCAPE_DIR/05.png" \
	"18 SPECIALIZED UNITS" "FIGHT ON LAND, AIR AND SEA" \
	"Build a force with distinct roles, ranges and counters."
make_landscape_title \
	"$FRAME_DIR/commander_victory.png" "$LANDSCAPE_DIR/06.png" \
	"TAKE THE ADVANTAGE" "GRID COMMANDER • SOLO vs AI • LOCAL HOT-SEAT"

make_vertical_title \
	"$FRAME_DIR/attack.png" "$VERTICAL_DIR/00.png" \
	"GRID\nCOMMANDER" "TURN-BASED TACTICAL STRATEGY\nPLAN • MOVE • ATTACK • CAPTURE"
make_vertical_slide \
	"$FRAME_DIR/attack.png" "$VERTICAL_DIR/01.png" \
	"YOUR TURN" "MOVE ON\nTHE GRID.\nTHINK AHEAD." \
	"Use terrain, movement ranges\nand damage forecasts."
make_vertical_slide \
	"$FRAME_DIR/cutin_bomber_tank.png" "$VERTICAL_DIR/02.png" \
	"UNIT MATCHUPS" "COMMIT\nYOUR ATTACK" \
	"Firing ranges, strengths\nand counters decide the exchange."
make_vertical_slide \
	"$FRAME_DIR/capture_cutin.png" "$VERTICAL_DIR/03.png" \
	"CONTROL THE ECONOMY" "CAPTURE CITIES.\nBUILD UNITS." \
	"Properties generate funds\nfor your next turn."
make_vertical_slide \
	"$FRAME_DIR/power_banner.png" "$VERTICAL_DIR/04.png" \
	"13 PLAYSTYLES" "CHOOSE YOUR\nCOMMANDER" \
	"Distinct doctrines and powers\nreshape your strategy."
make_vertical_slide \
	"$FRAME_DIR/cutin_sub_cruiser.png" "$VERTICAL_DIR/05.png" \
	"18 SPECIALIZED UNITS" "LAND.\nAIR.\nSEA." \
	"Build a force with distinct\nroles, ranges and counters."
make_vertical_title \
	"$FRAME_DIR/commander_victory.png" "$VERTICAL_DIR/06.png" \
	"TAKE THE\nADVANTAGE" "GRID COMMANDER\nSOLO vs AI • LOCAL HOT-SEAT"

ffmpeg -y -hide_banner -loglevel warning \
	-f lavfi -i "sine=frequency=55:duration=$DURATION:sample_rate=48000" \
	-f lavfi -i "sine=frequency=110:duration=$DURATION:sample_rate=48000" \
	-i "$ROOT/assets/sfx/select.wav" \
	-i "$ROOT/assets/sfx/rocket.wav" \
	-i "$ROOT/assets/sfx/capture.wav" \
	-i "$ROOT/assets/sfx/fanfare.wav" \
	-i "$ROOT/assets/sfx/torpedo.wav" \
	-i "$ROOT/assets/sfx/explosion.wav" \
	-i "$ROOT/assets/sfx/fanfare.wav" \
	-filter_complex \
	"[0:a]volume=0.045,tremolo=f=2.38:d=0.92,lowpass=f=180[bed0]; \
	 [1:a]volume=0.018,tremolo=f=4.76:d=0.72,lowpass=f=360[bed1]; \
	 [2:a]adelay=2100:all=1,volume=0.8[s2]; \
	 [3:a]adelay=4200:all=1,volume=0.8[s3]; \
	 [4:a]adelay=6300:all=1,volume=0.9[s4]; \
	 [5:a]adelay=8400:all=1,volume=0.6[s5]; \
	 [6:a]adelay=10500:all=1,volume=0.8[s6]; \
	 [7:a]adelay=10900:all=1,volume=0.65[s7]; \
	 [8:a]adelay=12600:all=1,volume=0.9[s8]; \
	 [bed0][bed1][s2][s3][s4][s5][s6][s7][s8] \
	 amix=inputs=9:normalize=0,alimiter=limit=0.9, \
	 afade=t=in:st=0:d=0.3,afade=t=out:st=14.2:d=0.75, \
	 loudnorm=I=-16:LRA=9:TP=-1.5[a]" \
	-map "[a]" -c:a pcm_s16le "$PROMO_DIR/soundtrack.wav"

render_landscape() {
	ffmpeg -y -hide_banner -loglevel warning \
		-loop 1 -t 2.35 -i "$LANDSCAPE_DIR/00.png" \
		-loop 1 -t 2.35 -i "$LANDSCAPE_DIR/01.png" \
		-i "$CLIP_DIR/combat.avi" \
		-loop 1 -t 2.35 -i "$LANDSCAPE_OVERLAY_DIR/02.png" \
		-i "$CLIP_DIR/capture.avi" \
		-loop 1 -t 2.35 -i "$LANDSCAPE_OVERLAY_DIR/03.png" \
		-loop 1 -t 2.35 -i "$LANDSCAPE_DIR/04.png" \
		-loop 1 -t 2.35 -i "$LANDSCAPE_DIR/05.png" \
		-loop 1 -t 2.35 -i "$LANDSCAPE_DIR/06.png" \
		-i "$PROMO_DIR/soundtrack.wav" \
		-filter_complex \
		"[0:v]fps=30,zoompan=z='min(zoom+0.00055,1.045)':d=71:s=1280x720:fps=30,trim=duration=2.35,setpts=PTS-STARTPTS[v0]; \
		 [1:v]fps=30,zoompan=z='min(zoom+0.00045,1.04)':d=71:s=1280x720:fps=30,trim=duration=2.35,setpts=PTS-STARTPTS[v1]; \
		 [2:v]trim=start=0.20:duration=2.35,setpts=PTS-STARTPTS,fps=30,scale=1280:720[combat]; \
		 [3:v]fps=30,format=rgba[combat_title]; \
		 [combat][combat_title]overlay=0:0:shortest=1,format=yuv420p[v2]; \
		 [4:v]trim=start=0.55:duration=2.35,setpts=PTS-STARTPTS,fps=30,scale=1280:720[capture]; \
		 [5:v]fps=30,format=rgba[capture_title]; \
		 [capture][capture_title]overlay=0:0:shortest=1,format=yuv420p[v3]; \
		 [6:v]fps=30,zoompan=z='min(zoom+0.00055,1.045)':d=71:s=1280x720:fps=30,trim=duration=2.35,setpts=PTS-STARTPTS[v4]; \
		 [7:v]fps=30,zoompan=z='min(zoom+0.00045,1.04)':d=71:s=1280x720:fps=30,trim=duration=2.35,setpts=PTS-STARTPTS[v5]; \
		 [8:v]fps=30,zoompan=z='min(zoom+0.00055,1.045)':d=71:s=1280x720:fps=30,trim=duration=2.35,setpts=PTS-STARTPTS[v6]; \
		 [v0][v1]xfade=transition=fade:duration=0.25:offset=2.10[x1]; \
		 [x1][v2]xfade=transition=fade:duration=0.25:offset=4.20[x2]; \
		 [x2][v3]xfade=transition=fade:duration=0.25:offset=6.30[x3]; \
		 [x3][v4]xfade=transition=fade:duration=0.25:offset=8.40[x4]; \
		 [x4][v5]xfade=transition=fade:duration=0.25:offset=10.50[x5]; \
		 [x5][v6]xfade=transition=fade:duration=0.25:offset=12.60, \
		 fade=t=in:st=0:d=0.25,fade=t=out:st=14.55:d=0.4,format=yuv420p[v]" \
		-map "[v]" -map 9:a \
		-c:v libx264 -preset medium -crf 19 -profile:v high \
		-c:a aac -b:a 192k -ar 48000 -movflags +faststart -shortest \
		"$PROMO_DIR/grid-commander-promo-16x9.mp4"
}

render_vertical() {
	ffmpeg -y -hide_banner -loglevel warning \
		-loop 1 -t 2.35 -i "$VERTICAL_DIR/00.png" \
		-loop 1 -t 2.35 -i "$VERTICAL_DIR/01.png" \
		-i "$CLIP_DIR/combat.avi" \
		-loop 1 -t 2.35 -i "$VERTICAL_DIR/02.png" \
		-i "$CLIP_DIR/capture.avi" \
		-loop 1 -t 2.35 -i "$VERTICAL_DIR/03.png" \
		-loop 1 -t 2.35 -i "$VERTICAL_DIR/04.png" \
		-loop 1 -t 2.35 -i "$VERTICAL_DIR/05.png" \
		-loop 1 -t 2.35 -i "$VERTICAL_DIR/06.png" \
		-i "$PROMO_DIR/soundtrack.wav" \
		-filter_complex \
		"[0:v]fps=30,zoompan=z='min(zoom+0.00055,1.045)':d=71:s=1080x1920:fps=30,trim=duration=2.35,setpts=PTS-STARTPTS[v0]; \
		 [1:v]fps=30,zoompan=z='min(zoom+0.00045,1.04)':d=71:s=1080x1920:fps=30,trim=duration=2.35,setpts=PTS-STARTPTS[v1]; \
		 [2:v]trim=start=0.20:duration=2.35,setpts=PTS-STARTPTS,fps=30,scale=1000:563[combat]; \
		 [3:v]fps=30,scale=1080:1920[shell2]; \
		 [shell2][combat]overlay=40:594:shortest=1,format=yuv420p[v2]; \
		 [4:v]trim=start=0.55:duration=2.35,setpts=PTS-STARTPTS,fps=30,scale=1000:563[capture]; \
		 [5:v]fps=30,scale=1080:1920[shell3]; \
		 [shell3][capture]overlay=40:594:shortest=1,format=yuv420p[v3]; \
		 [6:v]fps=30,zoompan=z='min(zoom+0.00055,1.045)':d=71:s=1080x1920:fps=30,trim=duration=2.35,setpts=PTS-STARTPTS[v4]; \
		 [7:v]fps=30,zoompan=z='min(zoom+0.00045,1.04)':d=71:s=1080x1920:fps=30,trim=duration=2.35,setpts=PTS-STARTPTS[v5]; \
		 [8:v]fps=30,zoompan=z='min(zoom+0.00055,1.045)':d=71:s=1080x1920:fps=30,trim=duration=2.35,setpts=PTS-STARTPTS[v6]; \
		 [v0][v1]xfade=transition=fade:duration=0.25:offset=2.10[x1]; \
		 [x1][v2]xfade=transition=fade:duration=0.25:offset=4.20[x2]; \
		 [x2][v3]xfade=transition=fade:duration=0.25:offset=6.30[x3]; \
		 [x3][v4]xfade=transition=fade:duration=0.25:offset=8.40[x4]; \
		 [x4][v5]xfade=transition=fade:duration=0.25:offset=10.50[x5]; \
		 [x5][v6]xfade=transition=fade:duration=0.25:offset=12.60, \
		 fade=t=in:st=0:d=0.25,fade=t=out:st=14.55:d=0.4,format=yuv420p[v]" \
		-map "[v]" -map 9:a \
		-c:v libx264 -preset medium -crf 19 -profile:v high \
		-c:a aac -b:a 192k -ar 48000 -movflags +faststart -shortest \
		"$PROMO_DIR/grid-commander-promo-9x16.mp4"
}

render_landscape
render_vertical

printf 'promo: wrote %s\n' "$PROMO_DIR/grid-commander-promo-16x9.mp4"
printf 'promo: wrote %s\n' "$PROMO_DIR/grid-commander-promo-9x16.mp4"
