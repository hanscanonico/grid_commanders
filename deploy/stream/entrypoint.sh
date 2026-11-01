#!/bin/bash
# The stream's one process tree: a virtual screen, a silent sound card, an encoder
# that outlives every match, and one game process per match, so a crash or a leak
# costs a single match. If the screen, the sound card or a loop dies, the container
# exits and its restart policy brings the whole tree back clean.
set -u

readonly RUN=/run/stream
readonly GAME=/game
readonly SIZE=1280x720
readonly FPS=30
readonly TIER=hard
readonly DAYS_CAP=40
readonly CARD_SECONDS=8
readonly RESULT_HOLD_SECONDS=12
# By command count and pace, the longest measured match on these boards is about 31 minutes.
readonly MATCH_LIMIT_SECONDS=3600
readonly SITE=gridcommanders.com
readonly TITLE_FONT=$GAME/assets/fonts/PixelifySans-Variable.ttf
readonly LABEL_FONT=$GAME/assets/fonts/Silkscreen-Regular.ttf
readonly VGLRUN="/opt/VirtualGL/bin/vglrun -d egl"

export DISPLAY=:77
export HOME=$RUN/home
export XDG_DATA_HOME=$RUN/data XDG_CONFIG_HOME=$RUN/config XDG_CACHE_HOME=$RUN/cache
export XDG_RUNTIME_DIR=$RUN/runtime
export PULSE_SERVER=unix:$RUN/pulse.sock PULSE_SINK=stream

say() { echo "stream: $*"; }

wait_for_socket() {
	local _
	for _ in $(seq 1 50); do
		[ -S "$1" ] && return 0
		sleep 0.2
	done
	say "$1 never appeared"
	return 1
}

# Without the GPU the 3D board runs at 1-4 fps on every core the container has, so
# stopping is the honest answer. The logs say why and the restart policy retries.
require_gpu() {
	local renderer
	renderer=$($VGLRUN /opt/VirtualGL/bin/glxinfo </dev/null 2>&1 | sed -n 's/^OpenGL renderer string: //p')
	case "$renderer" in
	"" | *llvmpipe* | *softpipe*)
		say "no GPU to draw with (renderer: '${renderer:-none}'), stopping"
		return 1
		;;
	esac
	say "drawing with $renderer"
}

title_case() { echo "$1" | tr '_' ' ' | sed -E 's/(^| )([a-z])/\1\U\2/g'; }

commanders() {
	local file
	for file in "$GAME"/data/commanders/*.tres; do
		basename "$file" .tres
	done
}

# boards.txt without a comment or a board this build no longer ships.
boards() {
	local board
	while read -r board; do
		case "$board" in "" | \#*) continue ;; esac
		if [ -f "$GAME/maps/$board.txt" ]; then
			echo "$board"
		else
			say "boards.txt names $board, which is not in maps/" >&2
		fi
	done <"$GAME/deploy/stream/boards.txt"
}

# Prints "<board> <red> <blue> <seed>", never the board just played.
pick_match() {
	local previous=$1 board
	board=$(boards | grep -vx -- "$previous" | shuf -n1)
	echo "$board $(commanders | shuf -n2 | xargs) $(shuf -i 0-2147483647 -n1)"
}

# The line under the top bar, read by the encoder. Moved into place in one step so
# the encoder can never read half of it. It sits on the right because a commander's
# power window takes the left of the screen, and on a cut-in that height is black.
set_caption() {
	echo "$1" >"$RUN/caption.tmp"
	mv "$RUN/caption.tmp" "$RUN/caption.txt"
}

# What shows on the screen when no game window covers it. The game's boot splash is
# this same file (override.cfg), so the card stays up while the next match loads.
draw_card() {
	local board red blue portraits=$GAME/assets/portraits/commanders
	board=$(title_case "$1")
	red=$(title_case "$2")
	blue=$(title_case "$3")
	ffmpeg -hide_banner -loglevel error -nostdin -y \
		-f lavfi -i "color=c=0x14171f:s=$SIZE:d=1" -i "$portraits/$2.png" -i "$portraits/$3.png" \
		-filter_complex "\
[1]scale=330:402:flags=neighbor[left];\
[2]scale=330:402:flags=neighbor[right];\
[0][left]overlay=110:172[with_left];\
[with_left][right]overlay=840:172,\
drawtext=fontfile=$LABEL_FONT:text='NEXT MATCH':fontcolor=0xa8b0c0:fontsize=24:x=(w-text_w)/2:y=16,\
drawtext=fontfile=$TITLE_FONT:text='$board':fontcolor=0xf5c84c:fontsize=56:x=(w-text_w)/2:y=80,\
drawtext=fontfile=$TITLE_FONT:text='vs':fontcolor=white:fontsize=72:x=(w-text_w)/2:y=330,\
drawtext=fontfile=$LABEL_FONT:text='$red':fontcolor=white:fontsize=24:x=275-text_w/2:y=592,\
drawtext=fontfile=$LABEL_FONT:text='$blue':fontcolor=white:fontsize=24:x=1005-text_w/2:y=592,\
drawtext=fontfile=$LABEL_FONT:text='Grid Commanders - bots playing bots - $SITE':fontcolor=0xa8b0c0:fontsize=20:x=(w-text_w)/2:y=664" \
		-frames:v 1 "$RUN/card.png" && hsetroot -fill "$RUN/card.png" >/dev/null
}

play_match() {
	# shellcheck disable=SC2086
	timeout -k 10 "$MATCH_LIMIT_SECONDS" $VGLRUN godot --audio-driver PulseAudio \
		--max-fps "$FPS" --print-fps --resolution "$SIZE" --position 0,0 --path "$GAME" \
		scenes/battle/battle.tscn -- --watch --view=3d --speed=normal \
		--watch-hold="$RESULT_HOLD_SECONDS" --days="$DAYS_CAP" --map="$1" \
		--red="$2:$TIER" --blue="$3:$TIER" --seed="$4" </dev/null 2>&1 |
		grep --line-buffered -vE '^Project FPS: (2[5-9]|3[0-9]) '
}

match_loop() {
	local board red blue seed next_board next_red next_blue next_seed
	read -r board red blue seed <<<"$(pick_match "")"
	draw_card "$board" "$red" "$blue"
	while :; do
		set_caption "$(title_case "$board") - $(title_case "$red") vs $(title_case "$blue") - $SITE"
		sleep "$CARD_SECONDS"
		say "playing $board: $red vs $blue, seed $seed"
		read -r next_board next_red next_blue next_seed <<<"$(pick_match "$board")"
		play_match "$board" "$red" "$blue" "$seed" &
		# Drawn under the window once it is up, so the card is ready the moment the
		# window closes and the last match's card never flashes.
		sleep 20
		draw_card "$next_board" "$next_red" "$next_blue"
		wait $!
		board=$next_board red=$next_red blue=$next_blue seed=$next_seed
	done
}

encode() {
	local output
	if [ -n "${TWITCH_STREAM_KEY:-}" ]; then
		output=(-f flv)
		# ffmpeg does not check who it is talking to by default, and this sends the key.
		case "$TWITCH_INGEST" in
		rtmps://*) output+=(-tls_verify 1 -ca_file /etc/ssl/certs/ca-certificates.crt) ;;
		esac
		output+=("$TWITCH_INGEST/$TWITCH_STREAM_KEY")
	else
		mkdir -p "$RUN/preview"
		output=(-f segment -segment_time 60 -segment_wrap 5 -reset_timestamps 1 "$RUN/preview/part%d.mp4")
	fi
	ffmpeg -hide_banner -loglevel warning -nostdin \
		-thread_queue_size 1024 -f x11grab -draw_mouse 0 -framerate "$FPS" -video_size "$SIZE" -i "$DISPLAY" \
		-thread_queue_size 1024 -f pulse -i stream.monitor \
		-vf "drawtext=fontfile=$LABEL_FONT:textfile=$RUN/caption.txt:reload=$FPS:expansion=none:fontcolor=white:fontsize=16:box=1:boxcolor=black@0.6:boxborderw=6:x=w-text_w-10:y=52" \
		-c:v libx264 -preset veryfast -profile:v main -pix_fmt yuv420p \
		-b:v 3500k -maxrate 3500k -bufsize 7000k -g $((FPS * 2)) -keyint_min $((FPS * 2)) -sc_threshold 0 \
		-af aresample=async=1 -c:a aac -b:a 128k -ar 48000 -ac 2 \
		"${output[@]}"
}

# ffmpeg names its output in some errors, and that address holds the stream key. The
# second pass is for the key on its own, as a server's error message may repeat it.
redact_key() {
	local line
	sed -u -E 's#(/app/)[^[:space:]"'\'']+#\1<key>#g' | while IFS= read -r line; do
		printf '%s\n' "${line//"${TWITCH_STREAM_KEY:-}"/<key>}"
	done
}

# Twitch ends a broadcast after 48 hours and networks drop; both land here. Something
# that fails straight away, like a bad key, waits longer before trying again.
encoder_loop() {
	local started
	while :; do
		started=$SECONDS
		encode 2>&1 | redact_key
		if [ $((SECONDS - started)) -lt 60 ]; then
			say "encoder stopped early, retrying in 30 s"
			sleep 30
		else
			say "encoder stopped, reconnecting"
			sleep 2
		fi
	done
}

main() {
	# Only the encoder's address needs the key, so no child process inherits it.
	export -n TWITCH_STREAM_KEY
	mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
	chmod 700 "$XDG_RUNTIME_DIR"
	if [ -n "${TWITCH_STREAM_KEY:-}" ]; then
		say "going live"
	else
		say "no stream key: private preview, last five minutes in $RUN/preview"
	fi

	trap 'kill $(jobs -p) 2>/dev/null; exit 0' TERM INT

	Xvfb "$DISPLAY" -screen 0 "${SIZE}x24" -nolisten tcp >/dev/null 2>&1 &
	wait_for_socket /tmp/.X11-unix/X77 || exit 1
	pulseaudio -n --daemonize=no --exit-idle-time=-1 --realtime=no --high-priority=no --log-level=error \
		--load="module-null-sink sink_name=stream rate=48000" \
		--load="module-native-protocol-unix socket=$RUN/pulse.sock auth-anonymous=1" &
	wait_for_socket "$RUN/pulse.sock" || exit 1
	require_gpu || exit 1

	set_caption "$SITE"
	match_loop &
	encoder_loop &
	# Polled, because `wait -n` can miss a job that a signal killed before it got there.
	while [ "$(jobs -r | wc -l)" -eq 4 ]; do
		sleep 1
	done
	say "a required process stopped, restarting the container"
	# shellcheck disable=SC2046
	kill $(jobs -p) 2>/dev/null
	exit 1
}

main
