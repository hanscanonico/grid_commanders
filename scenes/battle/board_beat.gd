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
## The walk cycle's own rate, faster than a unit's idle by design.
const MOVE_MS := 160
## The sea's swell, the slowest of the three.
const SEA_MS := 900

## Captures pin the clock at frame A the way they pin game speed and the hint
## strip: a frame must not depend on when the shutter fired. Belt as well as
## braces — a capture also pins Instant, which `frame` already answers with
## frame A — because an explicit `--speed=` still wins over the pinned tier and a
## capture of a tier must not become a capture of a beat.
static var frozen := false


## Which frame of a two-frame clip is showing, at `period_ms` per frame.
##
## Instant is a still board by the same rule the tier states everywhere else —
## it shows a result rather than playing one out — so it answers frame A, the
## sheet every other surface draws from.
##
## The clock is a defaulted argument so that both stills — Instant and a pinned
## capture — are checkable rather than being read off whichever beat the suite
## happened to run in.
static func frame(period_ms: int, now_ms: int = Time.get_ticks_msec()) -> int:
	if frozen or Settings.speed.instant:
		return 0
	return frame_at(period_ms, now_ms)


## The same arithmetic on a clock of the caller's own. The two cut-ins read this
## one directly, off CutscenePlayback's `t`: inside a cut-in everything is a pure
## function of that clock, so a posed still and a skip both land on a fixed
## frame — which the board's wall beat and its two stills cannot promise.
static func frame_at(period_ms: int, elapsed_ms: int) -> int:
	return int(elapsed_ms / period_ms) % 2
