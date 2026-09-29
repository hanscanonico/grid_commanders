class_name CutinBallistics3D
extends RefCounted
## Where every round, chunk and puff of the 3D combat cut-in is at a moment of
## its clock: when each figure's rounds leave and land, the path each kind of
## round flies, and the scatter a burst throws. Node-free and pure, so a volley
## posed mid-flight is the same volley every run and the paths are checked
## without a scene.

## A 2D style's pixel measures (arc, muzzle, burst radius) read on the stage at
## this many pixels to the cell — the flat cut-in's own band against the
## stage's spread between the squads.
const PX_PER_CELL := 40.0
## How much higher an indirect weapon lobs than the same style fired flat —
## the flat cut-in's `INDIRECT_LOB`, stood up a little further, since the lens
## looks along the lob as well as across it.
const INDIRECT_LOB := 1.5
## The gap between one figure's successive rounds, as a share of the volley's
## flight time: a sustained stream cycles, a salvo leaves close together.
const STREAM_GAP := 0.28
const SALVO_GAP := 0.07
## How far a burst spreads over its target, in cells.
const SPREAD := 0.35
## A torpedo runs this far under the surface.
const TORPEDO_DEPTH := 0.12
## A bomb is tossed this far up over the first share of its flight before it
## plunges.
const BOMB_LOFT := 1.3
const BOMB_TOSS := 0.4


## How far through its flight round `shot` of figure `figure` is at `t`, for a
## volley that leaves at `fire` and takes `flight` seconds: below 0 not yet
## fired, above 1 landed. `stagger` is the style's gap between figures.
static func round_progress(
	t: float, fire: float, flight: float, figure: int, shot: int, stagger: float, sustained: bool
) -> float:
	var gap := flight * (STREAM_GAP if sustained else SALVO_GAP)
	var leave := fire + figure * stagger + shot * gap
	return (t - leave) / maxf(flight, 0.01)


## When the last of a volley lands, after it left at `fire`.
static func volley_end(
	fire: float, flight: float, figures: int, shots: int, stagger: float, sustained: bool
) -> float:
	var gap := flight * (STREAM_GAP if sustained else SALVO_GAP)
	return fire + maxi(figures - 1, 0) * stagger + maxi(shots - 1, 0) * gap + flight


## A round's position along its path, `p` of the way: straight, lobbed over a
## `peak` in cells, dropped like a bomb, or run under the water like a
## torpedo.
static func path(kind: StringName, from: Vector3, to: Vector3, p: float, peak: float) -> Vector3:
	var at := clampf(p, 0.0, 1.0)
	match kind:
		BattleStyle.BOMB:
			var ahead := 1.0 - pow(1.0 - at, 3.0)
			var along := Vector3(from.x, 0.0, from.z).lerp(Vector3(to.x, 0.0, to.z), ahead)
			return along + Vector3.UP * _toss(from.y, to.y, at)
		BattleStyle.TORPEDO:
			var run := from.lerp(to, at)
			run.y = lerpf(from.y, to.y, at) - TORPEDO_DEPTH * sin(PI * minf(at * 1.4, 1.0))
			return run
	return from.lerp(to, at) + Vector3.UP * 4.0 * peak * at * (1.0 - at)


## Which way a round is flying at `p` along its path, for a dart's nose or a
## tracer's streak.
static func heading(kind: StringName, from: Vector3, to: Vector3, p: float, peak: float) -> Vector3:
	var ahead := path(kind, from, to, minf(p + 0.02, 1.0), peak)
	var behind := path(kind, from, to, maxf(p - 0.02, 0.0), peak)
	var dir := ahead - behind
	return dir.normalized() if dir.length() > 0.0001 else (to - from).normalized()


## A bomb's height: tossed up and over as it leaves the belly, then plunging
## faster and faster onto the target.
static func _toss(top: float, bottom: float, at: float) -> float:
	if at < BOMB_TOSS:
		return top + BOMB_LOFT * sin(at / BOMB_TOSS * PI * 0.5)
	var fall := (at - BOMB_TOSS) / (1.0 - BOMB_TOSS)
	return lerpf(top + BOMB_LOFT, bottom, fall * fall)


## The arc a style's round flies over, in cells.
static func peak_of(style: BattleStyle, lobbed: bool) -> float:
	return style.arc / PX_PER_CELL * (INDIRECT_LOB if lobbed else 1.0)


## A pixel measure of a style (a muzzle, a burst) on the stage, in cells.
static func cells(px: float) -> float:
	return px / PX_PER_CELL


## Where round `index` of a volley lands on `targets` (each figure's middle):
## one of them by hash, spread a little over it.
static func hit_point(targets: PackedVector3Array, index: int) -> Vector3:
	if targets.is_empty():
		return Vector3.ZERO
	var pick := int(SquadFormation3D.scatter(index, 41) * targets.size()) % targets.size()
	var jitter := Vector3(
		SquadFormation3D.scatter(index, 42) - 0.5,
		(SquadFormation3D.scatter(index, 43) - 0.5) * 0.6,
		SquadFormation3D.scatter(index, 44) - 0.5
	)
	return targets[pick] + jitter * SPREAD


## A chunk thrown out of a burst at `origin`: out along a hashed bearing, up,
## and back down under gravity, `p` of the way through its flight.
static func debris(origin: Vector3, index: int, p: float, reach: float) -> Vector3:
	var turn := TAU * SquadFormation3D.scatter(index, 51)
	var out := reach * (0.5 + 0.5 * SquadFormation3D.scatter(index, 52))
	var lift := reach * (1.0 + SquadFormation3D.scatter(index, 53))
	var at := clampf(p, 0.0, 1.0)
	var drop := lift * 4.0 * at * (1.0 - at) - reach * 0.3 * at * at
	return origin + Vector3(cos(turn) * out * at, drop, sin(turn) * out * at)


## A smoke puff off a burst: drifting up and out from `origin` as it grows.
static func puff(origin: Vector3, index: int, p: float, reach: float) -> Vector3:
	var turn := TAU * SquadFormation3D.scatter(index, 61)
	var out := reach * 0.6 * SquadFormation3D.scatter(index, 62)
	var at := 1.0 - pow(1.0 - clampf(p, 0.0, 1.0), 2.0)
	var rise := reach * (0.8 + 0.8 * SquadFormation3D.scatter(index, 63))
	return origin + Vector3(cos(turn) * out * at, rise * at, sin(turn) * out * at)
