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
#
# A launch from an interactive terminal execs Godot directly — a human who
# starts the game wants it focused. Agent and script launches (no tty) get
# the restore behavior.
#
# Usage: [GODOT=<binary>] tools/godot_gui.sh <godot args...>
#
# The wrapper ends in `exec`, so its pid, exit status, and stdio are Godot's
# own — timeout-and-kill callers (smoke_scenarios.sh) need no special casing.

set -u

GODOT="${GODOT:-bin/Godot.app/Contents/MacOS/Godot}"

if [[ -t 0 || -t 1 || -t 2 ]] || [[ "$(uname)" != "Darwin" ]]; then
	exec "$GODOT" "$@"
fi

# The restore helper activates an app by unix pid (see activate_pid.swift for
# why pid). Compiled once into the gitignored .godot/ cache. Without a Swift
# toolchain, fall back to LaunchServices by bundle id, which restores every
# previous app except another Godot.
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

front_pid() {
	lsappinfo info -only pid "$(lsappinfo front)" | sed -E 's/[^0-9]*([0-9]+).*/\1/'
}
front_bundle() {
	lsappinfo info -only bundleid "$(lsappinfo front)" |
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
		[[ -n "$1" && "$1" != "$game_pid" ]] || return 1
		case "$2" in
			"" | org.godotengine.* | com.apple.systemuiserver | com.apple.dock | com.apple.Spotlight | com.apple.loginwindow)
				return 1
				;;
		esac
	}
	# Snapshot the app that was front before the launch as the first target;
	# the tracking below follows the user if they genuinely switch apps.
	prev_pid="$(front_pid)"
	prev_bundle="$(front_bundle)"
	if ! restorable "$prev_pid" "$prev_bundle"; then
		# A launch can land on the beat between two scenarios, when window
		# teardown briefly puts system UI in front. Seed from the window
		# order instead of the bare frontmost process — a watcher seeded
		# empty would have no restore target for its whole run.
		prev_pid=""
		prev_bundle=""
		for asn in $(lsappinfo visibleProcessList 2>/dev/null); do
			asn="${asn%%-\"*}:"
			cand_pid="$(lsappinfo info -only pid "$asn" 2>/dev/null |
				sed -E 's/[^0-9]*([0-9]+).*/\1/')"
			cand_bundle="$(lsappinfo info -only bundleid "$asn" 2>/dev/null |
				sed -E 's/.*"CFBundleIdentifier"="([^"]*)".*/\1/')"
			if restorable "$cand_pid" "$cand_bundle"; then
				prev_pid="$cand_pid"
				prev_bundle="$cand_bundle"
				break
			fi
		done
	fi
	# Watch for the game's whole lifetime — the exit condition is the child
	# dying, nothing else — and restore on every activation. The longer sleep
	# after a restore keeps a genuinely re-activating engine from turning
	# this loop into a spin.
	while kill -0 "$game_pid" 2>/dev/null; do
		now="$(front_pid)"
		if [[ "$now" == "$game_pid" ]]; then
			if [[ -x "$activate_bin" && -n "$prev_pid" ]]; then
				"$activate_bin" "$prev_pid" 2>/dev/null
			elif [[ -n "$prev_bundle" ]]; then
				open -b "$prev_bundle"
			fi
			sleep 0.3
			continue
		fi
		# Keep tracking where the user actually is: they may switch apps
		# between our launch and the steal.
		now_bundle="$(front_bundle)"
		if restorable "$now" "$now_bundle"; then
			prev_pid="$now"
			prev_bundle="$now_bundle"
		fi
		sleep 0.1
	done
) &

exec "$GODOT" "$@"
