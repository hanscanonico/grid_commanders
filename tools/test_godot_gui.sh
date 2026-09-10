#!/usr/bin/env bash
#
# What tools/godot_gui.sh does with a launch — which renderer it picks, what it
# says when it cannot pick the container one, and what the sweep's manifest
# records about it (COM-279).
#
# Everything here runs on fakes: a fake engine and a fake `docker`, each a tiny
# script that records its argv. Nothing renders, no container starts, and no
# Docker install is needed — which is why `make verify` can run it. Only
# external behaviour is asserted: the argv a fake recorded, the text on stderr,
# the exit status.
#
# Usage: tools/test_godot_gui.sh        (or `make capture-test`)

set -uo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
launcher="$repo_dir/tools/godot_gui.sh"
sweep="$repo_dir/tools/smoke_scenarios.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/godot-gui-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT

fake_bin="$work/bin"
mkdir -p "$fake_bin" "$work/shots"

cat >"$work/godot" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_ENGINE_ARGV"
for arg in "$@"; do
	case "$arg" in
		--screenshot=*)
			# Big enough to clear the sweep's blank-capture floor.
			head -c 4096 /dev/zero | tr '\0' 'x' >"${arg#--screenshot=}"
			;;
	esac
done
EOF
cat >"$fake_bin/docker" <<'EOF'
#!/usr/bin/env bash
# A watcher's `docker kill` lands after its own launcher exited, so it is
# recorded apart from the run's argv rather than inside whichever case is
# current by then.
if [[ "${1:-}" == "kill" ]]; then
	printf '%s\n' "$*" >>"$FAKE_DOCKER_KILL_ARGV"
	exit 0
fi
printf '%s\n' "$*" >>"$FAKE_DOCKER_ARGV"
case "${1:-}" in
	info) [[ "${FAKE_DOCKER_DAEMON:-up}" == "up" ]] || exit 1 ;;
	image) [[ "${FAKE_DOCKER_IMAGE:-present}" == "present" ]] || exit 1 ;;
	run)
		# The import-cache probe: failing it is how a case asks for a cold volume.
		[[ "$*" == *"--entrypoint test"* && "${FAKE_CAPTURE_CACHE:-warm}" == "cold" ]] &&
			exit 1
		;;
esac
exit 0
EOF
chmod +x "$work/godot" "$fake_bin/docker"

export GODOT="$work/godot"
export FAKE_ENGINE_ARGV="$work/engine.argv"
export FAKE_DOCKER_ARGV="$work/docker.argv"
export FAKE_DOCKER_KILL_ARGV="$work/docker.kill.argv"

failures=0
case_failures=0
case_name=""
engine_argv=""
docker_argv=""
stderr_text=""
status=0

# One launch with a clean slate: the fakes' records are truncated, the engine
# runs with no tty (which is what an agent or a script gives it), and what came
# back is left in the four variables the checks read.
run_launcher() {
	case_name="$1"
	case_failures=0
	shift
	: >"$FAKE_ENGINE_ARGV"
	: >"$FAKE_DOCKER_ARGV"
	PATH="$fake_bin:$PATH" "$launcher" "$@" \
		</dev/null >"$work/out" 2>"$work/err"
	status=$?
	engine_argv="$(cat "$FAKE_ENGINE_ARGV")"
	docker_argv="$(cat "$FAKE_DOCKER_ARGV")"
	stderr_text="$(cat "$work/err")"
}

fail() {
	echo "godot_gui test: FAIL $case_name — $1" >&2
	failures=$((failures + 1))
	case_failures=$((case_failures + 1))
}

pass() {
	((case_failures == 0)) && echo "godot_gui test: ok   $case_name"
	return 0
}

expect_engine_ran() {
	[[ -n "$engine_argv" ]] || fail "the engine was never launched"
}

expect_no_engine() {
	[[ -z "$engine_argv" ]] || fail "the engine ran on this desktop: $engine_argv"
}

expect_no_docker() {
	[[ -z "$docker_argv" ]] || fail "docker was probed: $docker_argv"
}

# The launch itself is the last `docker run` of the invocation: the cache probe
# and a cold cache's import come first.
expect_docker_run_has() {
	local needle="$1" line
	line="$(grep '^run ' "$FAKE_DOCKER_ARGV" | tail -1)"
	[[ -n "$line" ]] || {
		fail "no 'docker run' at all"
		return
	}
	[[ "$line" == *"$needle"* ]] || fail "'docker run' lacks $needle: $line"
}

expect_no_docker_run() {
	! grep -q '^run ' "$FAKE_DOCKER_ARGV" || fail "a container was started: $docker_argv"
}

expect_stderr_has() {
	[[ "$stderr_text" == *"$1"* ]] || fail "stderr lacks '$1': $stderr_text"
}

capture_args=(--path . scenes/battle/battle.tscn -- "--screenshot=$work/shots/frame.png")
sweep_args=(--path . scenes/battle/battle.tscn -- "--shots-dir=$work/shots")

# 1. A human's launch: tty, so the engine runs here whatever else is true. The
# terminal has to be fabricated, since `make` gives this script pipes.
if [[ "$(uname)" == "Darwin" ]] && command -v python3 >/dev/null 2>&1; then
	case_name="tty launch runs the engine directly"
	case_failures=0
	: >"$FAKE_ENGINE_ARGV"
	: >"$FAKE_DOCKER_ARGV"
	PATH="$fake_bin:$PATH" python3 "$repo_dir/tools/capture/run_on_tty.py" \
		"$launcher" "${capture_args[@]}" >/dev/null 2>&1
	status=$?
	engine_argv="$(cat "$FAKE_ENGINE_ARGV")"
	docker_argv="$(cat "$FAKE_DOCKER_ARGV")"
	expect_engine_ran
	expect_no_docker
	((status == 0)) || fail "the launcher exited $status instead of the engine's 0"
	pass
fi

# 2-4 and 7 are the automatic choice, which is macOS-only: elsewhere a windowed
# launch never stole anyone's focus in the first place.
if [[ "$(uname)" == "Darwin" ]]; then
	run_launcher "capture with the container available goes to docker" "${capture_args[@]}"
	expect_no_engine
	expect_docker_run_has "--rm"
	expect_docker_run_has "$repo_dir:$repo_dir"
	expect_docker_run_has ":$repo_dir/.godot"
	expect_docker_run_has "-w $repo_dir"
	expect_docker_run_has "--screenshot=$work/shots/frame.png"
	expect_docker_run_has "$work/shots:$work/shots"
	pass

	run_launcher "a sweep's --shots-dir goes to docker too" "${sweep_args[@]}"
	expect_no_engine
	expect_docker_run_has "--shots-dir=$work/shots"
	pass

	# A cold volume's import is a second container, so it needs the same name
	# the watcher kills — killed mid-import, a launcher would otherwise leave
	# it running.
	export FAKE_CAPTURE_CACHE=cold
	run_launcher "a cold cache imports under the killable name" "${capture_args[@]}"
	expect_no_engine
	expect_stderr_has "importing the project into the capture cache"
	import_run="$(grep '^run ' "$FAKE_DOCKER_ARGV" | grep -- '--import' | tail -1)"
	[[ "$import_run" == *"--name gc-capture-"* ]] ||
		fail "the import runs unnamed, so a killed launcher cannot stop it: $import_run"
	expect_docker_run_has "--name gc-capture-"
	pass
	unset FAKE_CAPTURE_CACHE

	export FAKE_DOCKER_DAEMON=down
	run_launcher "a daemon that is down falls back" "${capture_args[@]}"
	expect_engine_ran
	expect_stderr_has "daemon is not answering"
	pass
	unset FAKE_DOCKER_DAEMON

	export FAKE_DOCKER_IMAGE=missing
	run_launcher "a missing image falls back" "${capture_args[@]}"
	expect_engine_ran
	expect_stderr_has "make capture-image"
	pass
	unset FAKE_DOCKER_IMAGE

	run_launcher "a launch that captures nothing stays on the desktop" --path .
	expect_engine_ran
	expect_no_docker
	pass
fi

export GODOT_CAPTURE_RENDERER=desktop
run_launcher "GODOT_CAPTURE_RENDERER=desktop never probes docker" "${capture_args[@]}"
expect_engine_ran
expect_no_docker
pass

GODOT_CAPTURE_RENDERER=container
run_launcher "GODOT_CAPTURE_RENDERER=container goes to docker" "${capture_args[@]}"
expect_no_engine
expect_docker_run_has "--screenshot=$work/shots/frame.png"
pass
unset GODOT_CAPTURE_RENDERER

# 8. Forced and unavailable is a failure, not a fallback: the caller asked for a
# frame this desktop does not draw, so an unasked-for desktop frame would answer
# a different question.
export GODOT_CAPTURE_RENDERER=container FAKE_DOCKER_DAEMON=down
run_launcher "GODOT_CAPTURE_RENDERER=container with a blocker fails" "${capture_args[@]}"
expect_no_engine
expect_no_docker_run
expect_stderr_has "GODOT_CAPTURE_RENDERER=container, but the docker daemon is not answering"
((status != 0)) || fail "the launcher exited 0 with the container unavailable"
pass
unset FAKE_DOCKER_DAEMON

# 9. A caller that kills the launcher outright leaves no trap to run, so the
# container is stopped by a watcher that outlives the exec — measured here on
# the fake docker's argv, with the poll turned down so the case is quick.
case_name="the watcher kills the container when the launcher goes away"
case_failures=0
: >"$FAKE_DOCKER_KILL_ARGV"
GODOT_CAPTURE_WATCH_INTERVAL=0.05 PATH="$fake_bin:$PATH" \
	"$launcher" "${capture_args[@]}" </dev/null >/dev/null 2>&1 &
launcher_pid=$!
wait "$launcher_pid"
for _ in $(seq 1 100); do
	grep -q "^kill gc-capture-$launcher_pid\$" "$FAKE_DOCKER_KILL_ARGV" && break
	sleep 0.05
done
grep -q "^kill gc-capture-$launcher_pid\$" "$FAKE_DOCKER_KILL_ARGV" ||
	fail "no 'docker kill gc-capture-$launcher_pid': $(cat "$FAKE_DOCKER_KILL_ARGV")"
pass
unset GODOT_CAPTURE_RENDERER

# 10. The sweep's manifest carries the renderer, and a comparison refuses to
# cross it — the same refusal a manifest from another queue gets.
case_name="a manifest from the other renderer is refused"
case_failures=0
manifest="$work/hashes.txt"
sweep_env=(GODOT_CAPTURE_RENDERER=desktop SMOKE_HASHES="$manifest" SMOKE_ISOLATE=1)
env "${sweep_env[@]}" "$sweep" attack </dev/null >"$work/out" 2>&1 || fail "recording run failed"
grep -q '^# renderer: desktop' "$manifest" || fail "no renderer header in the manifest"
sed -i.bak 's/^# renderer: .*/# renderer: container/' "$manifest"
env "${sweep_env[@]}" "$sweep" attack </dev/null >"$work/out" 2>&1
status=$?
((status != 0)) || fail "the comparison accepted a manifest from the other renderer"
grep -q "recorded on the container renderer" "$work/out" || fail "no clear message: $(cat "$work/out")"
pass

if ((failures > 0)); then
	echo "godot_gui test: $failures case(s) failed" >&2
	exit 1
fi
echo "godot_gui test: all cases OK"
