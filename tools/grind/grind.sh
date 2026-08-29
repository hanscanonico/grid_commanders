#!/usr/bin/env bash
#
# The grind box: this repo's offline instruments, played around the clock on a
# machine nobody is sitting at.
#
#   make grind                      # rotate forever
#   make grind GRIND="--once"       # one pass and stop
#   make grind GRIND="--once --dry-run"   # print the plan, play nothing
#   make grind GRIND="--jobs=difficulty-check --once"
#
# Nothing here is a new instrument. Every job is a `make` target that already
# exists, run under `nice`, logged, and marked finished so the next pass does not
# replay it. What the box adds is the rotation, the crash resilience and the
# digest — `reports/grind/DIGEST.md`, the one page a person (or a session) reads
# instead of the raw CSVs.
#
# **A job's own resume is preferred to the supervisor's.** `arena-search` and
# `balance-pool` pick themselves up where they stopped, and a killed job costs
# the shard in flight and nothing else; the done-markers under
# `reports/grind/done/` only exist for the runners that have no resume of their
# own, and they are keyed on the commit so a new commit re-measures.
#
# **No job may take the supervisor down.** `set -e` is deliberately absent: a
# failing instrument is a finding, logged and reported in the digest, and the
# loop moves to the next one. `legibility-ratchet` exiting 1 is such a finding —
# a cell that used to pass no longer does — not a crash.
#
# Flags (via GRIND="…"):
#   --once            one pass, then stop
#   --dry-run         print each job's command and whether it would run
#   --jobs=a,b        only these jobs (prefix match, so `--jobs=arena-search`
#                     takes all three bases)
#   --refresh         ignore every done-marker and finished run
#   --sleep=SECONDS   idle between passes (default 600)
#   --workers=N       engines at a time (default cores - 1)
#   --publish         push the digest and the reports to the `grind-results`
#                     branch after every pass
#
# Small-knob overrides, for a dry run on a laptop: GRIND_EXTRA_DIFF,
# GRIND_EXTRA_BAL, GRIND_EXTRA_CAMPAIGN, GRIND_EXTRA_SEARCH, GRIND_EXTRA_POOL
# and GRIND_EXTRA_SIM are appended to their job's flag list, so
# `GRIND_EXTRA_DIFF="--seeds=1 --days=6"` plays a real job end to end in a
# minute. docs/grind_box.md is the install and the reading.
set -u -o pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
GRIND_REL="reports/grind"
GRIND_DIR="$ROOT/$GRIND_REL"
DIGEST="$ROOT/tools/grind/digest.py"
SHA=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)
HOST=$(hostname -s 2>/dev/null || hostname)
BOOT=$(date +%s)

ONCE=""
DRY=""
REFRESH=""
PUBLISH=""
FILTER=""
SLEEP=600
CORES=$( (nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4) | tr -d ' ')
WORKERS=$((CORES > 1 ? CORES - 1 : 1))
# The seed counts a laptop never affords; the whole reason the box exists.
DIFF_SEEDS=${GRIND_DIFF_SEEDS:-30}
POOL_SEEDS=${GRIND_POOL_SEEDS:-32}
SIM_SEEDS=${GRIND_SIM_SEEDS:-6}
HEARTBEAT=${GRIND_HEARTBEAT:-300}
GRIND_EXTRA_DIFF=${GRIND_EXTRA_DIFF:-}
GRIND_EXTRA_BAL=${GRIND_EXTRA_BAL:-}
GRIND_EXTRA_CAMPAIGN=${GRIND_EXTRA_CAMPAIGN:-}
GRIND_EXTRA_SEARCH=${GRIND_EXTRA_SEARCH:-}
GRIND_EXTRA_POOL=${GRIND_EXTRA_POOL:-}
GRIND_EXTRA_SIM=${GRIND_EXTRA_SIM:-}

for arg in "$@"; do
	case "$arg" in
	--once) ONCE=1 ;;
	--dry-run) DRY=1 ;;
	--refresh) REFRESH=1 ;;
	--publish) PUBLISH=1 ;;
	--jobs=*) FILTER="${arg#*=}" ;;
	--sleep=*) SLEEP="${arg#*=}" ;;
	--workers=*) WORKERS="${arg#*=}" ;;
	-h | --help)
		sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'
		exit 0
		;;
	*)
		echo "grind: unknown flag '$arg' — see tools/grind/grind.sh" >&2
		exit 2
		;;
	esac
done

say() { printf '%s grind: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# ---------------------------------------------------------------- bootstrap

# The engine the workflow pins, read out of the workflow rather than repeated
# here: one version number, in the file CI already answers to.
engine_version() {
	sed -n 's/^ *GODOT_VERSION: *//p' "$ROOT/.github/workflows/verify.yml" | head -1
}

engine_runs() {
	local engine=$1
	[ -x "$engine" ] || [ -x "$ROOT/$engine" ] || command -v "$engine" >/dev/null 2>&1
}

fetch_engine() {
	local version url zip
	version=$(engine_version)
	url="https://github.com/godotengine/godot-builds/releases/download/${version}/Godot_v${version}_linux.x86_64.zip"
	zip=$(mktemp -t godot.XXXXXX)
	say "fetching Godot $version"
	curl -sSfL -o "$zip" "$url" || return 1
	rm -rf "$ROOT/bin/godot-unpack"
	unzip -q "$zip" -d "$ROOT/bin/godot-unpack" || return 1
	mkdir -p "$ROOT/bin"
	mv "$ROOT/bin/godot-unpack/Godot_v${version}_linux.x86_64" "$ROOT/bin/godot"
	rm -rf "$ROOT/bin/godot-unpack" "$zip"
	chmod +x "$ROOT/bin/godot"
	"$ROOT/bin/godot" --headless --version
}

# Idempotent, and different per platform on purpose: a Linux box fetches the
# pinned build exactly as CI does, a Mac uses the vendored engine README's setup
# installed so this script can be dry-run before it is deployed.
bootstrap() {
	if [ "$(uname -s)" = "Linux" ]; then
		GODOT=${GODOT:-bin/godot}
		if ! engine_runs "$GODOT"; then
			fetch_engine || {
				say "no engine and the fetch failed — see docs/grind_box.md"
				return 1
			}
		fi
	else
		GODOT=${GODOT:-bin/Godot.app/Contents/MacOS/Godot}
		engine_runs "$GODOT" || {
			say "no engine at $GODOT — see README.md engine setup"
			return 1
		}
	fi
	export GODOT
	# A fresh checkout that skipped this reads as broken assets rather than as a
	# cold cache, so it is part of the bootstrap and not of a job — and a dry run
	# does it too, because the plan itself asks the engine which boards to play.
	if [ ! -f "$GRIND_DIR/imported" ]; then
		say "importing assets (once per checkout)"
		make -C "$ROOT" import >"$GRIND_DIR/logs/import.log" 2>&1 || {
			say "import failed — see $GRIND_REL/logs/import.log"
			return 1
		}
		date >"$GRIND_DIR/imported"
	fi
	return 0
}

# ---------------------------------------------------------------------- plan

# Each job is one line: name | command | reading kind | artifact | log marker |
# exit codes that still count as finished.
JOBS=()

add_job() {
	JOBS+=("$1|$2|$3|$4|$5|$6")
}

field() { printf '%s' "$1" | cut -d'|' -f"$2"; }

# The boards the pool plays, read out of the repo the way `make arena-anchors`
# reads them — `ArenaPools` is the one list of duel boards that resolve inside
# the cap, and re-deriving a second one here is how two tools start disagreeing
# about what a board is.
pool_boards() {
	local plan maps
	for pool in training validation; do
		plan=$("$GODOT" --headless --path "$ROOT" -s res://tools/run_arena_plan.gd -- \
			--pool="$pool" 2>/dev/null | grep '^--maps=' | head -1)
		# The plan is one line of flags; the boards are the first of them, and the
		# `--pairings=` that follows carries commas of its own.
		maps=${plan#--maps=}
		printf '%s\n' "${maps%% *}" | tr ',' '\n'
	done | sed '/^$/d' | sort -u
}

plan_jobs() {
	JOBS=()
	local base board
	for base in default easy hard; do
		add_job "arena-search-$base" \
			"make -C '$ROOT' arena-search SEARCH=\"--block=all --base=data/ai/$base.tres --workers=$WORKERS $GRIND_EXTRA_SEARCH\"" \
			arena "reports/ai_arena/search/$base" "" "0"
	done
	add_job difficulty-check \
		"make -C '$ROOT' difficulty-check DIFF=\"--seeds=$DIFF_SEEDS $GRIND_EXTRA_DIFF\"" \
		section "" "=== difficulty ladder ===" "0"
	add_job commander-balance \
		"make -C '$ROOT' commander-balance BAL=\"$GRIND_EXTRA_BAL\"" \
		section "" "=== commander balance ===" "0"
	add_job campaign-difficulty \
		"make -C '$ROOT' campaign-difficulty CAMPAIGN=\"$GRIND_EXTRA_CAMPAIGN\"" \
		section "" "campaign-difficulty: " "0"
	# Exit 1 here is the finding it exists to report — a cell that passed now
	# fails — so the job is finished either way and the digest carries the cells.
	add_job legibility-ratchet \
		"make -C '$ROOT' legibility-ratchet" \
		section "" "# Legibility ratchet" "0 1"
	for board in $(pool_boards); do
		add_job "balance-pool-$board" \
			"make -C '$ROOT' balance-pool POOL=\"--maps=$board --pairings=none:normal/none:hard --seeds=$POOL_SEEDS --workers=$WORKERS --out=balance_pool/grind_$board $GRIND_EXTRA_POOL\"" \
			pool "reports/balance_pool/grind_$board" "" "0"
		# The pool plays with telemetry off, so the recordings the analyser reads
		# come from a short Lab run of the same pairing rather than from it.
		add_job "replay-survey-$board" \
			"make -C '$ROOT' balance-sim SIM=\"--map=$board --red=none:normal --blue=none:hard --seeds=$SIM_SEEDS --replays --out=reports/balance_sim/grind_replays_$board $GRIND_EXTRA_SIM\" && make -C '$ROOT' replay-report REPLAY=reports/balance_sim/grind_replays_$board/replays ARGS=--out=reports/replay/grind_$board" \
			survey "reports/replay/grind_$board" "" "0"
	done
}

wanted() {
	local name=$1 pick
	[ -z "$FILTER" ] && return 0
	for pick in $(printf '%s' "$FILTER" | tr ',' ' '); do
		case "$name" in "$pick"*) return 0 ;; esac
	done
	return 1
}

# A search is finished when it has written its page and every block it started
# has been replayed on the held-out pool. Both facts are the run's own artifacts
# — `report.md` and each block's `summary.json` beside its `search.json` — so
# nothing here re-does the search's arithmetic.
arena_finished() {
	local run="$ROOT/$1" started finished
	[ -f "$run/report.md" ] || return 1
	started=$(find "$run" -mindepth 2 -maxdepth 2 -name search.json 2>/dev/null | wc -l | tr -d ' ')
	finished=$(find "$run" -mindepth 2 -maxdepth 2 -name summary.json 2>/dev/null | wc -l | tr -d ' ')
	[ "$started" -gt 0 ] && [ "$started" = "$finished" ]
}

marker_path() { printf '%s/done/%s-%s' "$GRIND_DIR" "$1" "$SHA"; }

# Why a job would be skipped, or "" if it would run.
skip_reason() {
	local name=$1 kind=$2 artifact=$3
	[ -n "$REFRESH" ] && return 0
	if [ "$kind" = arena ]; then
		arena_finished "$artifact" && printf 'the search finished on this commit'
		return 0
	fi
	[ -f "$(marker_path "$name")" ] && printf 'done at %s' "$SHA"
	return 0
}

# ----------------------------------------------------------------- progress

# What a running job is doing right now, from the artifact it is already
# writing. `tools/grind/status.sh` prints the same readings.
job_progress() {
	local name=$1 log=$2 status
	case "$name" in
	arena-search-*) status="$ROOT/reports/ai_arena/search/${name#arena-search-}/pool/status.txt" ;;
	balance-pool-*) status="$ROOT/reports/balance_pool/grind_${name#balance-pool-}/status.txt" ;;
	*) status="" ;;
	esac
	if [ -n "$status" ] && [ -f "$status" ]; then
		cat "$status"
		return
	fi
	[ -f "$log" ] && grep -v '^[[:space:]]*$' "$log" | tail -1
}

state() {
	local phase=$1 job=$2 started=$3
	python3 "$DIGEST" --dir "$GRIND_REL" --state --host "$HOST" --sha "$SHA" \
		--pass "$PASS" --job "$job" --phase "$phase" --started "$started" \
		--boot "$BOOT" --queue "$QUEUE" --order "$ORDER" >/dev/null
}

record() {
	python3 "$DIGEST" --dir "$GRIND_REL" --record --job "$1" --status "$2" --exit "$3" \
		--started "$4" --ended "$5" --log "$6" --kind "$7" --artifact "$8" --marker "$9" >/dev/null
}

# ------------------------------------------------------------------ running

CHILD=0
STOPPING=""

shutdown() {
	STOPPING=1
	say "stopping — signalling the running job"
	if [ "$CHILD" -ne 0 ]; then
		kill -TERM -"$CHILD" 2>/dev/null || kill -TERM "$CHILD" 2>/dev/null
	fi
}
trap shutdown INT TERM

# Job control on, so a job and everything it spawns (a pool is a dozen engines)
# share a process group this can signal as one.
set -m

run_job() {
	local name=$1 cmd=$2 kind=$3 artifact=$4 marker=$5 ok_codes=$6
	local log="$GRIND_REL/logs/$name-$(date +%Y%m%d-%H%M%S).log"
	local started status waited beat code finished accepted
	started=$(date +%s)
	say "job $name starts: $cmd"
	say "job $name logs to $log"
	state running "$name" "$started"
	record "$name" running 0 "$started" "$(date +%s)" "$log" "$kind" "$artifact" "$marker"

	(nice -n 10 bash -c "$cmd" 2>&1 | tee "$ROOT/$log") &
	CHILD=$!
	beat=$started
	while kill -0 "$CHILD" 2>/dev/null; do
		sleep 5
		waited=$(($(date +%s) - beat))
		if [ "$waited" -ge "$HEARTBEAT" ]; then
			beat=$(date +%s)
			say "job $name running $((beat - started))s — $(job_progress "$name" "$ROOT/$log")"
		fi
	done
	wait "$CHILD"
	code=$?
	CHILD=0
	status=failed
	for accepted in $ok_codes; do
		[ "$code" = "$accepted" ] && status=done
	done
	finished=$(date +%s)
	say "job $name ends: exit $code ($status) after $((finished - started))s"
	if [ "$status" = done ] && [ "$kind" != arena ]; then
		mkdir -p "$GRIND_DIR/done"
		date >"$(marker_path "$name")"
	fi
	record "$name" "$status" "$code" "$started" "$finished" "$log" "$kind" "$artifact" "$marker"
	state idle "" 0
}

# ------------------------------------------------------------------ publish

# `reports/` is gitignored, so an orphan branch in its own worktree is the only
# durable copy — and it is why nothing here ever commits to the checkout's own
# branch.
publish() {
	local worktree="$GRIND_DIR/publish-worktree" board base run champion
	if [ ! -d "$worktree/.git" ] && [ ! -f "$worktree/.git" ]; then
		git -C "$ROOT" worktree add --detach "$worktree" >/dev/null 2>&1 || return 1
		if git -C "$ROOT" ls-remote --exit-code --heads origin grind-results >/dev/null 2>&1; then
			git -C "$worktree" fetch origin grind-results >/dev/null 2>&1
			git -C "$worktree" checkout -B grind-results origin/grind-results >/dev/null 2>&1
		else
			git -C "$worktree" checkout --orphan grind-results >/dev/null 2>&1
			git -C "$worktree" rm -rq --cached . >/dev/null 2>&1
			find "$worktree" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
		fi
	fi
	mkdir -p "$worktree/arena" "$worktree/replay"
	cp "$GRIND_DIR/DIGEST.md" "$GRIND_DIR/status.json" "$worktree/" 2>/dev/null
	for run in "$ROOT"/reports/ai_arena/search/*/; do
		[ -d "$run" ] || continue
		base=$(basename "$run")
		mkdir -p "$worktree/arena/$base"
		cp "$run/report.md" "$worktree/arena/$base/" 2>/dev/null
		for champion in $(python3 "$DIGEST" --champions "$run"); do
			cp "$ROOT/$champion" "$worktree/arena/$base/" 2>/dev/null
		done
	done
	for survey in "$ROOT"/reports/replay/grind_*/survey.md; do
		[ -f "$survey" ] || continue
		board=$(basename "$(dirname "$survey")")
		cp "$survey" "$worktree/replay/$board.md"
	done
	git -C "$worktree" add -A >/dev/null
	git -C "$worktree" diff --cached --quiet && {
		say "publish: nothing changed"
		return 0
	}
	git -C "$worktree" commit -q -m "Grind results from $HOST at $SHA" || return 1
	git -C "$worktree" push -q -u origin grind-results && say "publish: pushed grind-results"
}

# --------------------------------------------------------------------- loop

mkdir -p "$GRIND_DIR/logs" "$GRIND_DIR/done" "$GRIND_DIR/jobs"
bootstrap || exit 1

PASS=0
while :; do
	PASS=$((PASS + 1))
	plan_jobs
	ORDER=$(for job in "${JOBS[@]}"; do printf '%s,' "$(field "$job" 1)"; done)
	QUEUE=$ORDER
	say "pass $PASS starts at $SHA — $WORKERS workers, ${#JOBS[@]} jobs"
	state idle "" 0
	for job in "${JOBS[@]}"; do
		name=$(field "$job" 1)
		cmd=$(field "$job" 2)
		kind=$(field "$job" 3)
		artifact=$(field "$job" 4)
		marker=$(field "$job" 5)
		ok_codes=$(field "$job" 6)
		QUEUE=${QUEUE#*"$name",}
		wanted "$name" || continue
		reason=$(skip_reason "$name" "$kind" "$artifact")
		if [ -n "$reason" ]; then
			say "job $name skipped: $reason"
			continue
		fi
		if [ -n "$DRY" ]; then
			say "job $name would run: $cmd"
			continue
		fi
		run_job "$name" "$cmd" "$kind" "$artifact" "$marker" "$ok_codes"
		[ -n "$STOPPING" ] && break
	done
	[ -n "$STOPPING" ] && break
	[ -n "$DRY" ] || python3 "$DIGEST" --dir "$GRIND_REL" >/dev/null
	[ -n "$PUBLISH" ] && [ -z "$DRY" ] && publish
	[ -n "$ONCE" ] && break
	say "pass $PASS done — sleeping ${SLEEP}s"
	state sleeping "" "$(date +%s)"
	waited=0
	while [ "$waited" -lt "$SLEEP" ] && [ -z "$STOPPING" ]; do
		sleep 5
		waited=$((waited + 5))
	done
	[ -n "$STOPPING" ] && break
done

say "stopped after pass $PASS"
exit 0
