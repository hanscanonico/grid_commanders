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
	# nothing for its whole run. Re-run when a restore fails so a target that
	# has quit (the launching terminal) is replaced rather than wedging us.
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
			elif [[ -n "$prev_bundle" ]] && open -b "$prev_bundle" 2>/dev/null; then
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
