#!/usr/bin/env bash
#
# Windowed Godot launcher that gives the user their focus back.
#
# This engine build (4.7.1) activates its window unconditionally on startup:
# no CLI flag, `open -g`, bundle-id trickery, or the no_focus window flag
# stops the app from becoming frontmost — all four were tried. So the steal
# is undone instead: watch the launched instance for its whole lifetime and
# re-activate the user's app every time the game becomes frontmost. The
# focus loss shrinks from the whole run to a sub-second blip per activation,
# however late the window appears (a cold worktree imports for well over ten
# seconds before its first frame) and however often the engine re-activates.
# An activation long after the last one is a human clicking in, not the
# engine, and the watcher stands down for good rather than fight them.
#
# A launch from an interactive terminal execs Godot directly — a human who
# starts the game wants it focused. Agent and script launches (no tty) get
# the restore behavior.
#
# A scripted *capture* has no business on this desktop at all, so it renders
# off it instead: same arguments, same engine version, inside the Linux
# container image (COM-279). The restore watcher below stays as the safety net
# for every launch that container cannot answer.
#
# Usage: [GODOT=<binary>] [GODOT_CAPTURE_RENDERER=auto|container|desktop]
#        tools/godot_gui.sh <godot args...>
#
# The wrapper ends in `exec`, so its pid, exit status, and stdio are Godot's
# own — timeout-and-kill callers (smoke_scenarios.sh) need no special casing.

set -u

GODOT="${GODOT:-bin/Godot.app/Contents/MacOS/Godot}"
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
source "$repo_dir/tools/capture/image.env"

readonly DESKTOP_RENDERER=desktop
readonly CONTAINER_RENDERER=container
# The shell test turns this down rather than waiting half a second per case.
readonly WATCH_INTERVAL="${GODOT_CAPTURE_WATCH_INTERVAL:-0.5}"

# A tty means a human is watching this launch, on either path below.
is_interactive() {
	[[ -t 0 || -t 1 || -t 2 ]]
}

# Which renderer actually ran, for a caller that has to record it —
# SMOKE_HASHES writes it into its manifest, because a container frame and a
# desktop frame are two rasterisers and their bytes may not be compared.
record_renderer() {
	[[ -n "${GODOT_CAPTURE_RENDERER_OUT:-}" ]] &&
		printf '%s\n' "$1" >"$GODOT_CAPTURE_RENDERER_OUT"
	return 0
}

# Where this launch writes its frames — the directory of a `--screenshot=`
# file, or a `--shots-dir=` — read only from the engine arguments after the
# `--` separator, which is where the game's own flags start. Empty output
# means this launch captures nothing.
capture_dir() {
	local arg separated=""
	for arg in "$@"; do
		if [[ -z "$separated" ]]; then
			[[ "$arg" == "--" ]] && separated=1
			continue
		fi
		case "$arg" in
			--screenshot=*)
				dirname "${arg#--screenshot=}"
				return
				;;
			--shots-dir=*)
				printf '%s\n' "${arg#--shots-dir=}"
				return
				;;
		esac
	done
}

# Why the container cannot take this run, or nothing when it can. Available
# means all three: the CLI, a daemon that answers, and the image already
# built — the launcher never builds it, since a capture that silently spent
# ten minutes fetching Debian is a hung capture.
container_blocker() {
	local shots="$1"
	# A relative capture path means one thing on this side of the boundary and
	# another on the other, and there is no directory to bind by name.
	if [[ "$shots" != /* ]]; then
		echo "the capture path $shots is relative"
	elif ! command -v docker >/dev/null 2>&1; then
		echo "docker is not on PATH"
	elif ! docker info >/dev/null 2>&1; then
		echo "the docker daemon is not answering"
	elif ! docker image inspect "$GODOT_CAPTURE_IMAGE" >/dev/null 2>&1; then
		echo "the image $GODOT_CAPTURE_IMAGE is missing — build it with 'make capture-image'"
	else
		return 1
	fi
}

# Hand the run to the container and never come back. The checkout and the
# capture directory are bound at their own absolute paths, so every path on
# the command line means the same thing on both sides of the boundary; the
# import cache is a named volume per checkout and engine version, so a
# worktree keeps its own and the macOS `.godot/` is never written by Linux.
exec_in_container() {
	local repo_dir="$1" shots="$2"
	shift 2
	local volume name mounts=()
	volume="gc-capture-$(printf '%s %s' "$repo_dir" "$GODOT_CAPTURE_VERSION" |
		shasum -a 256 | cut -c1-12)"
	name="gc-capture-$$"
	mounts+=(-v "$repo_dir:$repo_dir" -v "$volume:$repo_dir/.godot")
	[[ "$shots" == "$repo_dir"/* ]] || mounts+=(-v "$shots:$shots")
	record_renderer "$CONTAINER_RENDERER"
	# A caller that kills this launcher outright (the sweep's timeout uses
	# SIGKILL) leaves no trap to run, so the container is stopped by a watcher
	# that outlives us — `$$` still names this process after the exec below.
	# The import below and the capture run one after the other under the same
	# name, so this one kill reaches whichever is current.
	local launcher_pid=$$
	(
		while kill -0 "$launcher_pid" 2>/dev/null; do sleep "$WATCH_INTERVAL"; done
		docker kill "$name"
	) >/dev/null 2>&1 &
	# A capture reads imported assets, never source ones, and this cache starts
	# empty — so a new volume gets the one-off headless import the macOS tree
	# gets from `make import`. Without it the scene comes up with every texture
	# and sound missing, which reads as a hang rather than as a cold cache.
	if ! docker run --rm -v "$volume:/cache" --entrypoint test \
		"$GODOT_CAPTURE_IMAGE" -d /cache/imported; then
		echo "godot_gui: importing the project into the capture cache (first run on this checkout)" >&2
		docker run --rm --init --name "$name" "${mounts[@]}" -w "$repo_dir" \
			"$GODOT_CAPTURE_IMAGE" --headless --path "$repo_dir" --import >&2
	fi
	exec docker run --rm --init --name "$name" "${mounts[@]}" -w "$repo_dir" \
		"$GODOT_CAPTURE_IMAGE" "$@"
}

capture_shots="$(capture_dir "$@")"
capture_renderer="${GODOT_CAPTURE_RENDERER:-auto}"
forced_container=0
[[ "$capture_renderer" == "$CONTAINER_RENDERER" ]] && forced_container=1
# `auto` containerises exactly the launches that would otherwise flash a window
# across a developer's desktop: a capture, from a script, on macOS. A tty launch
# is the human's own (D3) and stays silent; on another host a windowed launch
# never stole anyone's focus, and that is the one auto case worth naming.
consider_container=$forced_container
if [[ "$capture_renderer" == "auto" && -n "$capture_shots" ]] && ! is_interactive; then
	if [[ "$(uname)" == "Darwin" ]]; then
		consider_container=1
	else
		echo "godot_gui: capturing on the desktop — the container renderer is" \
			"chosen automatically on macOS only" >&2
	fi
fi

if ((consider_container)) && [[ -n "$capture_shots" ]]; then
	if blocker="$(container_blocker "$capture_shots")"; then
		# A caller who named the container asked for a frame that is not drawn
		# on this desktop, so drawing it here anyway answers a different
		# question. Say what is missing and take nothing.
		if ((forced_container)); then
			echo "godot_gui: GODOT_CAPTURE_RENDERER=container, but $blocker" >&2
			exit 1
		fi
		echo "godot_gui: capturing on the desktop — $blocker" >&2
	else
		exec_in_container "$repo_dir" "$capture_shots" "$@"
	fi
fi
record_renderer "$DESKTOP_RENDERER"

if is_interactive || [[ "$(uname)" != "Darwin" ]]; then
	exec "$GODOT" "$@"
fi

# The restore helper activates an app by unix pid (see activate_pid.swift for
# why pid). Compiled once into the gitignored .godot/ cache. Without a Swift
# toolchain, fall back to LaunchServices by bundle id — over the same targets
# `restorable` below allows, and only while that app is still running.
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
activate_bin="$repo_dir/.godot/activate_pid"
activate_src="$repo_dir/tools/activate_pid.swift"
if command -v swiftc >/dev/null 2>&1; then
	if [[ ! -x "$activate_bin" || "$activate_src" -nt "$activate_bin" ]]; then
		mkdir -p "$repo_dir/.godot"
		swiftc -O -suppress-warnings -o "$activate_bin" "$activate_src" \
			2>/dev/null || rm -f "$activate_bin"
	fi
fi

# One sample is one app: take the frontmost ASN once, then ask that ASN for
# both fields. Two independent `lsappinfo front` calls could straddle a switch
# and hand the pid of one app with the bundle id of another — which is how a
# denylisted app slips past the check below and gets latched as the target.
front_asn() {
	lsappinfo front 2>/dev/null
}
asn_pid() {
	[[ -n "$1" ]] || return 0
	lsappinfo info -only pid "$1" 2>/dev/null | sed -E 's/[^0-9]*([0-9]+).*/\1/'
}
asn_bundle() {
	[[ -n "$1" ]] || return 0
	lsappinfo info -only bundleid "$1" 2>/dev/null |
		sed -E 's/.*"CFBundleIdentifier"="([^"]*)".*/\1/'
}

# $$ survives the exec below, so inside the watcher it names the game process.
game_pid=$$
(
	# Only a real user app may be adopted as a restore target: never the game
	# itself (any Godot instance), and never transient system UI — a restore
	# was observed landing on com.apple.systemuiserver instead of the app the
	# focus was taken from.
	restorable() {
		[[ "$1" =~ ^[0-9]+$ && "$1" != "$game_pid" ]] || return 1
		case "$2" in
			"" | org.godotengine.* | com.apple.systemuiserver | com.apple.dock | com.apple.Spotlight | com.apple.loginwindow)
				return 1
				;;
		esac
	}
	# Adopt a restore target: the app that is front now if it qualifies, else
	# the first restorable app in the front-to-back window order — a launch
	# can land on the beat between two scenarios, when window teardown briefly
	# puts system UI in front, and a watcher left without a target restores
	# nothing for its whole run. Re-run when the target has quit (the
	# launching terminal) so it is replaced rather than wedging us.
	seed_target() {
		local asn cand_pid cand_bundle
		prev_pid=""
		prev_bundle=""
		asn="$(front_asn)"
		cand_pid="$(asn_pid "$asn")"
		cand_bundle="$(asn_bundle "$asn")"
		if ! restorable "$cand_pid" "$cand_bundle"; then
			cand_pid=""
			cand_bundle=""
			for asn in $(lsappinfo visibleProcessList 2>/dev/null); do
				asn="${asn%%-\"*}:"
				cand_pid="$(asn_pid "$asn")"
				cand_bundle="$(asn_bundle "$asn")"
				restorable "$cand_pid" "$cand_bundle" && break
				cand_pid=""
				cand_bundle=""
			done
		fi
		[[ -n "$cand_pid" || -n "$cand_bundle" ]] || return 1
		prev_pid="$cand_pid"
		prev_bundle="$cand_bundle"
	}
	# Is the adopted target still around? `open -b` on a bundle whose app has
	# quit *launches* it, so a dead target must never reach the fallback: the
	# user quit that app on purpose. A live target that merely refused to
	# activate is kept and retried, not traded for whatever is first in
	# window order.
	target_alive() {
		[[ -n "$prev_pid" ]] && kill -0 "$prev_pid" 2>/dev/null
	}
	seed_target
	# Watch for the game's whole lifetime — the exit condition is the child
	# dying, nothing else — and restore on every activation. The longer sleep
	# after a restore keeps a genuinely re-activating engine from turning
	# this loop into a spin. The engine's own activations arrive in tight
	# clusters (measured 0.15-1.25s apart, at window creation or right after
	# a restore); one that arrives long after the last is the user clicking
	# into the game, so the watcher stands down for the rest of the run.
	human_gap=5
	last_front=""
	while kill -0 "$game_pid" 2>/dev/null; do
		asn="$(front_asn)"
		now="$(asn_pid "$asn")"
		if [[ "$now" == "$game_pid" ]]; then
			if [[ -n "$last_front" ]] && ((SECONDS - last_front > human_gap)); then
				break
			fi
			last_front=$SECONDS
			restored=0
			if [[ -x "$activate_bin" && -n "$prev_pid" ]] &&
				"$activate_bin" "$prev_pid" 2>/dev/null; then
				restored=1
			elif target_alive; then
				[[ -n "$prev_bundle" ]] && open -b "$prev_bundle" 2>/dev/null
				restored=1
			fi
			((restored)) || seed_target
			sleep 0.3
			continue
		fi
		# Keep tracking where the user actually is: they may switch apps
		# between our launch and the steal.
		now_bundle="$(asn_bundle "$asn")"
		if restorable "$now" "$now_bundle"; then
			prev_pid="$now"
			prev_bundle="$now_bundle"
		fi
		sleep 0.1
	done
) &

exec "$GODOT" "$@"
