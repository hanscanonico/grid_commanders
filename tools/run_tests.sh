#!/usr/bin/env bash
#
# `make test`: the GUT suite, run as two engines at once.
#
# Two suites dominate the wall clock — the alliance and campaign soaks play
# whole matches to a verdict — so they run in one engine while every other
# script runs in a second. Nothing about what is tested changes: the two halves
# are a partition of tests/unit, and the run prints one combined summary.
#
# The slow half is named here (SLOW_TESTS) and the fast half is *derived* as the
# complement on disk, so a new suite is run by whichever half it is not in
# rather than by an edit to a list. What the script asserts before launching is
# that the two halves really are a partition of what is on disk — every named
# slow script exists, no script is in both, none is in neither.
#
# Usage:  tools/run_tests.sh          # two engines
#         TEST_JOBS=1 tools/run_tests.sh   # the verbatim .gutconfig.json run
#         SERIAL=1 tools/run_tests.sh      # same

set -uo pipefail

# Repo-relative throughout, and the generated configs are written to a mktemp
# directory rather than the tree — a config in res:// would be a second, stale
# statement of what the suite is.
cd "$(dirname "$0")/.." || exit 1

GODOT="${GODOT:-bin/Godot.app/Contents/MacOS/Godot}"
source "$(dirname "$0")/lib/require_godot.sh"
GUT_CONFIG=".gutconfig.json"
TEST_DIR="tests/unit"

# The scripts worth their own engine. Wall clock is the only reason a name is
# here; both are legality gates and neither may be trimmed to make the suite
# faster.
SLOW_TESTS=(
	"$TEST_DIR/test_alliance_soak.gd"
	"$TEST_DIR/test_campaign_soak.gd"
)

require_godot test

if [[ ${TEST_JOBS:-} == "1" || ${SERIAL:-} == "1" ]]; then
	exec "$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd
fi

# bash 3.2 (macOS system bash) has neither mapfile nor an associative array, so
# the set of slow scripts is a space-delimited string matched with `case`.
ON_DISK=()
while IFS= read -r script; do
	ON_DISK+=("$script")
done < <(find "$TEST_DIR" -name 'test_*.gd' | sort)
if ((${#ON_DISK[@]} == 0)); then
	echo "test: no test scripts under $TEST_DIR" >&2
	exit 1
fi

# The partition, checked rather than assumed: a slow name that no longer exists
# would quietly leave one engine idle, and an overlap would run a soak twice and
# double-count it in the combined summary.
slow_set=" "
for script in "${SLOW_TESTS[@]}"; do
	if [[ ! -f $script ]]; then
		echo "test: SLOW_TESTS names '$script', which is not on disk" >&2
		exit 1
	fi
	case "$slow_set" in
	*" $script "*)
		echo "test: SLOW_TESTS names '$script' twice" >&2
		exit 1
		;;
	esac
	slow_set="$slow_set$script "
done

FAST_TESTS=()
for script in "${ON_DISK[@]}"; do
	case "$slow_set" in
	*" $script "*) ;;
	*) FAST_TESTS+=("$script") ;;
	esac
done

covered=$((${#SLOW_TESTS[@]} + ${#FAST_TESTS[@]}))
if ((covered != ${#ON_DISK[@]})); then
	echo "test: the halves cover $covered scripts, but $TEST_DIR holds ${#ON_DISK[@]}" >&2
	exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Every option but the directory scan comes from the repo config, so log level,
# exit policy and anything added there govern both halves without being restated.
write_config() {
	local dest="$1"
	shift
	python3 - "$GUT_CONFIG" "$dest" "$@" <<-'PY'
		import json, sys

		source, dest, *tests = sys.argv[1:]
		with open(source) as handle:
		    config = json.load(handle)
		for key in ("dirs", "include_subdirs", "prefix", "suffix"):
		    config.pop(key, None)
		config["tests"] = ["res://" + path for path in tests]
		with open(dest, "w") as handle:
		    json.dump(config, handle, indent=2)
	PY
}

SLOW_CONFIG="$TMP_DIR/slow.gutconfig.json"
FAST_CONFIG="$TMP_DIR/fast.gutconfig.json"
write_config "$SLOW_CONFIG" "${SLOW_TESTS[@]}" || exit 1
write_config "$FAST_CONFIG" "${FAST_TESTS[@]}" || exit 1

SLOW_LOG="$TMP_DIR/slow.log"
FAST_LOG="$TMP_DIR/fast.log"

echo "test: ${#SLOW_TESTS[@]} script(s) in one engine, ${#FAST_TESTS[@]} in another"

run_half() {
	"$GODOT" --headless --path . -s res://addons/gut/gut_cmdln.gd -gconfig="$1" >"$2" 2>&1
}

run_half "$SLOW_CONFIG" "$SLOW_LOG" &
slow_pid=$!
run_half "$FAST_CONFIG" "$FAST_LOG" &
fast_pid=$!

wait "$slow_pid"
slow_status=$?
wait "$fast_pid"
fast_status=$?

# Both logs in full, one after the other — a failure's output is the reason to
# read either of them, and interleaving two engines would make it unreadable.
echo "===== soaks ====="
cat "$SLOW_LOG"
echo "===== rest of the suite ====="
cat "$FAST_LOG"

# GUT's summary lines, with the colour escapes it paints them with cut off.
total_of() {
	sed $'s/\033\[[0-9;]*m//g' "$1" |
		awk -v want="$2" '
			$0 ~ "^" want "  " {
				value = $NF
				sub(/^.*\//, "", value)
				print value + 0
				found = 1
				exit
			}
			END { if (!found) print 0 }
		'
}

sum_of() {
	echo $(($(total_of "$SLOW_LOG" "$1") + $(total_of "$FAST_LOG" "$1")))
}

scripts="$(sum_of Scripts)"
tests="$(sum_of Tests)"
passing="$(sum_of 'Passing Tests')"
failing="$(sum_of 'Failing Tests')"
asserts="$(sum_of Asserts)"

echo "===== combined ====="
printf 'Scripts       %6s\n' "$scripts"
printf 'Tests         %6s\n' "$tests"
printf 'Passing Tests %6s\n' "$passing"
printf 'Failing Tests %6s\n' "$failing"
printf 'Asserts       %6s\n' "$asserts"

if ((slow_status != 0 || fast_status != 0)); then
	echo "test: soaks exited $slow_status, rest of the suite exited $fast_status" >&2
	exit 1
fi

if ((scripts != ${#ON_DISK[@]})); then
	echo "test: ran $scripts scripts, but $TEST_DIR holds ${#ON_DISK[@]}" >&2
	exit 1
fi

echo "test: all tests passed"
