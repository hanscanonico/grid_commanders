class_name BoardBeat
extends RefCounted
## The board's shared wall clock. Every looping sheet the generator ships — the
## units' ambient beat, and the clips later slices wire in — reads its frame from
## here, so no surface has to ask another what time it is and none of them needs a
## conductor. Node-free and static: a frame is a pure function of the clock.
##
## The cadences are the generator's, one per clip (assets/tiles/anim.json), and
## deliberately not multiples of one another — the whole board turning over on the
## same tick reads as a stutter rather than as motion. They are hardcoded rather
## than loaded from the manifest, which would put a JSON parse in the draw path;
## tests/unit/test_anim_manifest.gd is where the two are held together.

## Milliseconds per ambient beat, and one cadence for both motions because the
## sheets encode one: frame B is the whole army a beat later, so a rotor and a
## swell cannot be given different rates without a third sheet. Half a second is
## the slowest rate a swept rotor still reads as turning, which is the faster of
## the two motions and so the one that sets the beat.
const AMBIENT_MS := 500
## The walk cycle's own rate, faster than a unit's idle by design, and authored
## at the default tier — `move_ms` is what a sprite plays it at.
const MOVE_MS := 160
## The sea's swell, the slowest of the units' three cadences.
const SEA_MS := 900
## The river's flow (S9): faster than the open sea's swell — a current reads
## livelier than a swell — and coprime-ish with the other four the way MOVE_MS
## is with AMBIENT_MS/SEA_MS: it neither divides nor is divided by 500, 160 or
## 900, nor by SHOAL_MS below.
const RIVER_MS := 700
## The shoal's foam edge (S9), the laziest of the five: a breaking scallop
## reads slower than either the river's current or the open sea's swell.
## Disjoint from all four of the others the same way RIVER_MS is.
const SHOAL_MS := 1150

## Captures pin the clock at frame A the way they pin game speed and the hint
## strip: a frame must not depend on when the shutter fired. Belt as well as
## braces — a capture also pins Instant, which `frame` already answers with
## frame A — because an explicit `--speed=` still wins over the pinned tier and a
## capture of a tier must not become a capture of a beat.
static var frozen := false


## The gait's cadence at the tier being played. Alone among the three, the walk
## cycle belongs to a motion the tier already scales — `BattleAnimator` tweens
## each leg for `move_step_seconds()` — so legs that beat on the authored rate
## at every tier stride out of step with the body. The other two are scenery on
## a wall clock and stay authored.
static func move_ms() -> int:
	return Settings.speed.clip_period_ms(MOVE_MS)


## Which frame of an N-frame clip is showing, at `period_ms` per frame.
## `frames` defaults to two, the ambient and sea beats' own count, so every
## call site that predates the move clip's four stays valid unread.
##
## Instant is a still board by the same rule the tier states everywhere else —
## it shows a result rather than playing one out — so it answers frame A, the
## sheet every other surface draws from.
##
## The clock is a defaulted argument so that both stills — Instant and a pinned
## capture — are checkable rather than being read off whichever beat the suite
## happened to run in.
static func frame(period_ms: int, now_ms: int = Time.get_ticks_msec(), frames: int = 2) -> int:
	if frozen or Settings.speed.instant:
		return 0
	return frame_at(period_ms, now_ms, frames)


## The same arithmetic on a clock of the caller's own. The two cut-ins read this
## one directly, off CutscenePlayback's `t`: inside a cut-in everything is a pure
## function of that clock, so a posed still and a skip both land on a fixed
## frame — which the board's wall beat and its two stills cannot promise.
static func frame_at(period_ms: int, elapsed_ms: int, frames: int = 2) -> int:
	return int(elapsed_ms / period_ms) % frames
