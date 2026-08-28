# One answer to "is the engine here?" for every gate script.
#
# The vendored macOS engine is a default, not the rule: CI fetches the Linux
# build of the same version and points GODOT at a name on PATH, so a path that
# is executable and a name `command -v` resolves are equally good. Three of the
# four gates used to test the first alone, which made `GODOT=godot make verify`
# pass `test` and fail `check` and `determinism`.
#
# Sourced by tools/check_scripts.sh, tools/check_determinism.sh,
# tools/run_tests.sh and tools/smoke_scenarios.sh. The label is the prefix the
# caller already writes its own diagnostics with, so no message changed.
#
# It exits rather than returning: every caller's answer to a missing engine is
# the same, and a `set -e`-less script that forgot the `|| exit` would run the
# whole gate against a binary that is not there.

require_godot() {
	local label="$1"
	if [[ -x "${GODOT:-}" ]] || command -v "${GODOT:-}" >/dev/null; then
		return 0
	fi
	echo "$label: Godot binary not found at ${GODOT:-}" >&2
	echo "$label: see README.md for engine setup, or pass GODOT=<path>" >&2
	exit 1
}
