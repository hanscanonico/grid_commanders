class_name CombatShots3D
extends RefCounted
## The 3D combat cut-in's shot list: where the lens stands at every moment of
## the exchange, cut on the beat sheet's own windows so the 3D volley lands when
## the flat one does and nothing is lengthened. Node-free and pure — a still
## posed at any `t`, and a skip, frame the same picture every run.
##
## The shots, in order: a low wide as the squads arrive; over the attacker's
## shoulder as it winds up and fires; onto the defender for the hits and the
## falls; the mirror pair for a counter; and a closing wide on the tableau.
## Every point is in the stage's frame, the attacker left of the seam.

enum Shot { OPEN, ATTACKER_FIRES, DEFENDER_HIT, DEFENDER_FIRES, ATTACKER_HIT, CLOSE }

## The wide: how far back it stands per cell the two squads span, and how
## high; how far it pushes in over its length.
const WIDE_REACH := 1.05
const WIDE_REACH_MIN := 13.0
## What the wide stands back for beyond the squads' own spread: the ranks either
## side of each anchor.
const WIDE_MARGIN := 7.5
const WIDE_RISE := 0.16
const WIDE_PUSH := 0.12
const WIDE_SWING := 0.2
## Over a shoulder: behind the firing squad on its outer side, toward the lens,
## looking across at the target.
const SHOULDER := Vector3(-3.4, 1.3, 4.6)
const SHOULDER_PUSH := Vector3(0.5, -0.1, -0.5)
const SHOULDER_LOOK := 0.62
## Onto the side taking the hit: in front of it from the firing side.
const RECEIVER := Vector3(-3.0, 1.35, 5.4)
const RECEIVER_PUSH := Vector3(0.25, 0.0, -0.55)
const RECEIVER_LOOK := Vector3(0.45, -0.1, 0.0)
## Over an aircraft the lens drops to just under it, so the flight is seen
## against the sky rather than against the ground below.
const AIRBORNE := 0.9
const UNDER_WING := 0.3
## When the lens leaves the firer for the target: this far into the round's
## flight, so the round is seen leaving and seen landing.
const HANDOFF := 0.45
## How hard an impact shakes the lens, in cells, and its two frequencies.
const SHAKE := 0.05
const SHAKE_FREQ := Vector2(91.0, 77.0)

var starts := PackedFloat32Array()
var kinds: Array[Shot] = []
var _eyes: Array[Vector3] = []
var _looks: Array[Vector3] = []
var _beats: CombatBeats


## Plans the shots for one exchange between squads framed at `atk` and `def`
## (their middles at body height), off the sheet it will be played on. `lob` is
## how high the opening round arcs, in cells: the shot of it landing stands
## back and looks up to take the fall in.
static func plan(beats: CombatBeats, atk: Vector3, def: Vector3, lob: float = 0.0) -> CombatShots3D:
	var shots := CombatShots3D.new()
	shots._beats = beats
	var mid := (atk + def) * 0.5
	var reach := maxf(absf(def.x - atk.x) * WIDE_REACH + WIDE_MARGIN, WIDE_REACH_MIN)
	var open_eye := mid + Vector3(reach * WIDE_SWING, reach * WIDE_RISE, reach)
	shots._add(Shot.OPEN, 0.0, open_eye, open_eye * (1.0 - WIDE_PUSH) + mid * WIDE_PUSH, mid)
	var ready := beats.atk_ready
	shots._fire(Shot.ATTACKER_FIRES, lerpf(ready.x, ready.y, 0.5), atk, def)
	shots._hit(Shot.DEFENDER_HIT, _handoff(beats.atk_travel), def, atk, lob)
	var settled := _settled(beats.def_impact, beats.def_casualty, beats.def_death)
	if beats.ctr_ready != Vector2.ZERO:
		shots._fire(Shot.DEFENDER_FIRES, settled, def, atk)
		shots._hit(Shot.ATTACKER_HIT, _handoff(beats.def_travel), atk, def, 0.0)
		settled = _settled(beats.atk_impact, beats.atk_casualty, beats.atk_death)
	var close_eye := mid + Vector3(-reach * WIDE_SWING, reach * WIDE_RISE * 1.3, reach * 0.92)
	shots._add(Shot.CLOSE, settled, close_eye, close_eye * 1.0 + Vector3(0, 0.4, 0.8), mid)
	return shots


## Which shot is up at `t`.
func shot_at(t: float) -> int:
	var at := 0
	for i in starts.size():
		if t >= starts[i]:
			at = i
	return at


## Which shot is up at `t`, by kind.
func kind_at(t: float) -> Shot:
	return kinds[shot_at(t)]


## The lens at `t`: [eye, look-at], shaken by whatever just landed.
func pose_at(t: float) -> Array[Vector3]:
	var i := shot_at(t)
	var end := starts[i + 1] if i + 1 < starts.size() else _beats.total
	var span := maxf(end - starts[i], 0.01)
	var along := 1.0 - pow(1.0 - clampf((t - starts[i]) / span, 0.0, 1.0), 2.0)
	var eye := _eyes[i * 2].lerp(_eyes[i * 2 + 1], along)
	var shake := jolt(t) * SHAKE
	var nudge := Vector3(sin(t * SHAKE_FREQ.x), cos(t * SHAKE_FREQ.y), 0.0) * shake
	var pose: Array[Vector3] = [eye + nudge, _looks[i] + nudge]
	return pose


## How hard the lens is shaken at `t`: every landing volley and every death.
func jolt(t: float) -> float:
	var total := 0.0
	for span: Vector2 in [_beats.def_impact, _beats.atk_impact]:
		total += _decay(t, span)
	for span: Vector2 in [_beats.def_death, _beats.atk_death]:
		total += 2.0 * _decay(t, span)
	return total


func _fire(kind: Shot, at: float, from: Vector3, toward: Vector3) -> void:
	var out := signf(from.x - toward.x)
	var eye := from + Vector3(-SHOULDER.x * out, _rise(from, SHOULDER.y), SHOULDER.z)
	var push := Vector3(-SHOULDER_PUSH.x * out, SHOULDER_PUSH.y, SHOULDER_PUSH.z)
	_add(kind, at, eye, eye + push, from.lerp(toward, SHOULDER_LOOK))


func _hit(kind: Shot, at: float, target: Vector3, from: Vector3, lob: float) -> void:
	var out := signf(target.x - from.x)
	var eye := target + Vector3(RECEIVER.x * out, _rise(target, RECEIVER.y), RECEIVER.z)
	eye += Vector3(out * -0.3, 0.1, 0.6) * lob
	var push := Vector3(RECEIVER_PUSH.x * out, RECEIVER_PUSH.y, RECEIVER_PUSH.z)
	var look := (
		target + Vector3(RECEIVER_LOOK.x * out, RECEIVER_LOOK.y + lob * 0.3, RECEIVER_LOOK.z)
	)
	_add(kind, at, eye, eye + push, look)


func _add(kind: Shot, at: float, eye_from: Vector3, eye_to: Vector3, look: Vector3) -> void:
	starts.append(at)
	kinds.append(kind)
	_eyes.append(eye_from)
	_eyes.append(eye_to)
	_looks.append(look)


## How far above a subject the lens stands: `over` for one on the ground, just
## under one in the air.
static func _rise(subject: Vector3, over: float) -> float:
	return -UNDER_WING if subject.y > AIRBORNE else over


static func _handoff(travel: Vector2) -> float:
	return lerpf(travel.x, travel.y, HANDOFF)


## When a side has finished taking its hit: the impact, the falls and the
## blast all over.
static func _settled(impact: Vector2, casualty: Vector2, death: Vector2) -> float:
	return maxf(maxf(impact.y, casualty.y), death.y)


static func _decay(t: float, span: Vector2) -> float:
	if span.y <= span.x:
		return 0.0
	return CutscenePlayback.decay(clampf((t - span.x) / (span.y - span.x), 0.0, 1.0))
