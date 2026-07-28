#!/usr/bin/env bash
#
# Focus-theft instrument: wraps any command, samples the frontmost app for the
# command's whole lifetime, then prints the timeline with runs of the same app
# collapsed — plus the counters the focus-steal plan's milestones are measured
# by (steal count, total and longest stolen interval, restores that landed on
# the wrong app).
#
# Focus theft is the one defect `make verify` can never see: it happens on the
# developer's desktop and leaves no artefact. This script is the measurement
# the hand-rolled `lsappinfo front` shell loops of 2026-07-27 should have been,
# shipped so a claim about the sweep's focus behaviour is a number, not an
# anecdote.
#
# Usage:  tools/focus_timeline.sh <command...>
#         tools/focus_timeline.sh make smoke
#
# A "steal" is an interval where the frontmost app matches FOCUS_THIEF
# (default: the Godot engine's bundle id prefix). A "restore to the wrong app"
# is the interval right after a steal landing on something that is neither the
# app the focus was taken from nor the thief again — observed once in the wild
# as com.apple.systemuiserver, which is exactly what this counter makes
# visible (plan risk R4).
#
# Steal durations are resolution-limited: the sampler is a shell loop, so each
# tick costs a few exec()s and the real resolution lands near 0.15–0.25 s. The
# report prints the measured resolution so the durations are read with the
# right error bars.
#
# macOS-only, honestly: on any other platform (or without `lsappinfo`) it runs
# the command untouched and says the timeline is unavailable. Deliberately in
# no `make verify` gate — it needs a display and a human's desktop, exactly
# like the smoke sweep it measures. Exit status is always the wrapped
# command's own.

set -u

if (($# == 0)); then
	echo "usage: tools/focus_timeline.sh <command...>" >&2
	exit 2
fi

if [[ "$(uname)" != "Darwin" ]] || ! command -v lsappinfo >/dev/null 2>&1; then
	echo "focus_timeline: not macOS (or no lsappinfo) — timeline unavailable, running the command as-is" >&2
	exec "$@"
fi

FOCUS_THIEF="${FOCUS_THIEF:-org.godotengine}"
INTERVAL="${FOCUS_TIMELINE_INTERVAL:-0.1}"

front_bundle() {
	local asn bundle
	asn="$(lsappinfo front 2>/dev/null)"
	if [[ -z "$asn" ]]; then
		echo "-"
		return
	fi
	bundle="$(lsappinfo info -only bundleid "$asn" 2>/dev/null |
		sed -E 's/.*"CFBundleIdentifier"="([^"]*)".*/\1/')"
	# No match leaves sed's input untouched (still quoted) and some processes
	# carry no bundle id at all; both collapse to the "no frontmost app" mark.
	if [[ -z "$bundle" || "$bundle" == *'"'* ]]; then
		echo "-"
	else
		echo "$bundle"
	fi
}

now() {
	perl -MTime::HiRes=time -e 'printf "%.3f", time'
}

report() {
	kill "$sampler_pid" 2>/dev/null
	wait "$sampler_pid" 2>/dev/null

	echo
	echo "focus_timeline: front app over the run (runs of the same app collapsed)"
	awk -v thief="$FOCUS_THIEF" '
		# Explicit init: an uninitialized n subscripts as the string "", not 0,
		# which would silently drop the first sample.
		BEGIN { n = 0 }
		# Transient system UI is never the app the user was in; it must not become
		# the baseline a restore is measured against (plan risk R4).
		function sysui(app) {
			return app ~ /^com\.apple\.(systemuiserver|dock|Spotlight|loginwindow)$/
		}
		# What may be the app a restore is expected to land on: not the thief,
		# not system UI, not the "no frontmost app" mark. One predicate, so the
		# baseline is seeded by the same rule that later moves it.
		function baseline_ok(app) {
			return app != "-" && app !~ thief && !sysui(app)
		}
		# An interrupt can cut the sampler off mid-line; half a sample is no sample.
		NF < 2 { next }
		{ t[n] = $1; a[n] = $2; n++ }
		END {
			if (n == 0) {
				print "  no samples captured"
				exit
			}
			t0 = t[0]
			# Collapse consecutive samples of the same app into runs.
			rn = 0
			for (i = 0; i < n; i++) {
				if (i == 0 || a[i] != a[i - 1]) {
					rstart[rn] = t[i]
					rapp[rn] = a[i]
					rn++
				}
			}
			for (r = 0; r < rn - 1; r++) rend[r] = rstart[r + 1]
			rend[rn - 1] = t[n - 1]

			# The baseline follows the user: a deliberate app switch (a non-thief
			# run that is not the tail of a steal) becomes the new app restores are
			# expected to land on. It is seeded from the first run that could be
			# one at all — a first sample of "-" or of system UI is not an app the
			# developer was in.
			expected = ""
			for (r = 0; r < rn; r++) {
				if (baseline_ok(rapp[r])) {
					expected = rapp[r]
					break
				}
			}
			steals = 0; stolen = 0; longest = 0; wrong = 0
			# The run a restore is judged against is the last one that had an app:
			# a "-" run between the steal and the restore is not itself a restore,
			# and must not hide the one after it.
			prev = ""
			for (r = 0; r < rn; r++) {
				dur = rend[r] - rstart[r]
				line = sprintf("%7.2f  %s", rstart[r] - t0, rapp[r])
				if (rapp[r] ~ thief) {
					steals++
					stolen += dur
					if (dur > longest) longest = dur
					line = line sprintf("   ← steal (+%.2fs)", dur)
				} else if (prev ~ thief && prev != "" && expected != "" && rapp[r] != expected && rapp[r] != "-") {
					wrong++
					line = line "   ← restored to wrong app"
				} else if (baseline_ok(rapp[r])) {
					expected = rapp[r]
				}
				if (rapp[r] != "-") prev = rapp[r]
				print line
			}
			printf "\n  steals: %d   total stolen: %.1fs   longest: %.2fs   restored to wrong app: %d\n", \
				steals, stolen, longest, wrong
			span = t[n - 1] - t0
			if (n > 1) res = span / (n - 1); else res = 0
			printf "  sampling: %d samples over %.1fs, ~%.2fs resolution — steal durations are resolution-limited\n", \
				n, span, res
		}
	' "$samples"
}

samples="$(mktemp "${TMPDIR:-/tmp}/focus-timeline.XXXXXX")"
trap 'rm -f "$samples"' EXIT

# One synchronous sample before the command starts, so the baseline — the app
# the developer was in, the one every restore should land back on — is
# guaranteed to predate the launch.
printf '%s %s\n' "$(now)" "$(front_bundle)" >"$samples"

(
	while :; do
		printf '%s %s\n' "$(now)" "$(front_bundle)"
		sleep "$INTERVAL"
	done
) >>"$samples" &
sampler_pid=$!

# A wrapped run is minutes long (`tools/focus_timeline.sh make smoke`), and an
# interrupted run is still a measurement: INT/TERM fall through to the report
# on the samples gathered so far rather than discarding them, and the script
# then exits 128+signal instead of the command's status.
signalled=0
trap 'signalled=2' INT
trap 'signalled=15' TERM

"$@"
status=$?

report

if ((signalled != 0)); then
	exit $((128 + signalled))
fi

exit "$status"
