class_name CaptureShot3D
extends RefCounted
## The 3D capture cut-in as arithmetic: when the stage takes the lens and gives
## it back, where the lens stands in each shot, how high each flag flies, how the
## building jolts and flips, and where the dust and the confetti are — every one
## a pure function of the clock and the `CaptureBeats` sheet the flat cut-in
## plays to, so a mash lands on the same beat in both.
##
## Node-free: a still posed at any moment is the same still every run, and the
## beats are checked without a scene. Stage frame: Y up, +Z toward the lens's
## side; one unit is one cell of the stage's ground.

## The stage takes the lens as the letterbox closes, under a white flash, and
## gives it back halfway through the wipe out under another — so the set never
## shows round a band still framing the board, and neither ever pops.
const CUT_FLASH := 0.07
const FLIP_WASH := 0.35
## How long after its landing a mash's jolt and dust run.
const JOLT := 0.26
const DUST := 0.4
## How high a mash throws the squad, and how far toward the door it surges.
const HOP_HEIGHT := 0.6
const HOP_SURGE := 0.5
## The building's squash on a landing — flattened as the squad lands, then
## ringing out — and its swell as it flips.
const SQUASH := 0.1
const SWELL := 0.12
## The flag rig: the old flag runs down over the tail of the last mash and the
## flip's first half; the new one runs up from the flip's peak.
const LOWER_LEAD := 0.12
const RAISE := 0.4
## How long the squad's cheer runs, bouncing, after the flip.
const CHEER := 0.7
const CHEER_HOPS := 2.0
const CHEER_HEIGHT := 0.16
## The confetti: pieces thrown out of the roof at the flip's peak, falling under
## a flat gravity while they tumble.
const CONFETTI := 40
const CONFETTI_SECONDS := 1.1
const CONFETTI_SPEED := 7.5
const CONFETTI_GRAVITY := 2.6
## The two firework rings that pop over the building behind the banner.
const FIREWORKS: Array[Vector3] = [Vector3(-2.6, 2.9, -2.2), Vector3(2.9, 3.2, -2.8)]
const FIREWORK_DELAY: Array[float] = [0.08, 0.26]
const FIREWORK_SPARKS := 14
const FIREWORK_SECONDS := 0.7
const FIREWORK_REACH := 1.0
## The three shots, each an eye drifting from its first offset to its second and
## what it looks at. The march is a low wide from the front, the building on the
## right and the squad running in from the left; the mashes a low three-quarter
## at the squad's shoulder, the building towering; the flip a wide that takes in
## the building and its pole as the flag runs up, craning as the banner lands.
const MARCH_EYE: Array[Vector3] = [Vector3(0.3, 1.6, 11.4), Vector3(1.1, 1.7, 10.6)]
const MARCH_LOOK := Vector3(1.9, 1.55, 0.0)
## How much of the squad's way still to go the march's pan follows.
const MARCH_PAN := 0.6
const MASH_EYE: Array[Vector3] = [Vector3(-1.4, 0.8, 6.6), Vector3(-1.0, 0.7, 5.9)]
const MASH_LOOK_SHARE := 0.55
const MASH_LOOK_UP := 1.25
## A partial holds on the squad standing its ground, easing back.
const HOLD_PULL := Vector3(-0.5, 0.2, 0.9)
const FLIP_EYE: Array[Vector3] = [Vector3(-1.4, 1.0, 10.6), Vector3(-0.8, 1.7, 11.6)]
const FLIP_LOOK_SHARE := 0.55
## The pole height every shot is framed for: a taller one backs the lens off and
## lifts what it looks at, so the flag stays clear of the meter in the top right.
const FRAMED_POLE := 2.55
## How much a jolt shakes the lens, in stage units.
const LENS_SHAKE := 0.05


## The moment the stage takes the lens, and the moment it gives it back.
static func cut_in() -> float:
	return CaptureBeats.WIPE_IN


static func cut_out(beats: CaptureBeats) -> float:
	return (beats.wipe_out.x + beats.wipe_out.y) * 0.5


## Whether the stage holds the lens at `t`.
static func on_air(beats: CaptureBeats, t: float) -> bool:
	return t >= cut_in() and t < cut_out(beats)


## The white over the whole frame: a blink at each cut, and a softer one at the
## flip, whose own white is the building's.
static func flash(beats: CaptureBeats, captured: bool, t: float) -> float:
	var blink := maxf(_spike(t, cut_in(), CUT_FLASH), _spike(t, cut_out(beats), CUT_FLASH))
	return maxf(blink, bloom(beats, captured, t) * FLIP_WASH)


## The flip's own white, 0 -> 1 -> 0 across the flip window, peaking as the
## building changes colours. Nothing on a partial.
static func bloom(beats: CaptureBeats, captured: bool, t: float) -> float:
	if not captured:
		return 0.0
	return _spike(t, flip_at(beats), (beats.flip.y - beats.flip.x) * 0.5)


## The flip's peak: where the building changes colours under the flash.
static func flip_at(beats: CaptureBeats) -> float:
	return (beats.flip.x + beats.flip.y) * 0.5


## Whether the building wears the capturer's colours at `t`.
static func flipped(beats: CaptureBeats, captured: bool, t: float) -> bool:
	return captured and t >= flip_at(beats)


## The old flag's height on its pole, 1 at the top: it runs down to nothing by
## the flip's peak. A partial never lowers it.
static func old_flag(beats: CaptureBeats, captured: bool, t: float) -> float:
	if not captured:
		return 1.0
	var start := beats.flip.x - LOWER_LEAD
	return 1.0 - _ease_in(clampf((t - start) / (flip_at(beats) - start), 0.0, 1.0))


## The new flag's height, 0 until the flip's peak and running up after it.
static func new_flag(beats: CaptureBeats, captured: bool, t: float) -> float:
	if not captured:
		return 0.0
	return _ease_out(clampf((t - flip_at(beats)) / RAISE, 0.0, 1.0))


## The squad's hop: up, then down on the mash's landing.
static func hop(beats: CaptureBeats, t: float) -> float:
	for span in beats.hops:
		if t > span.x and t < span.y:
			return sin((t - span.x) / (span.y - span.x) * PI) * HOP_HEIGHT
	return 0.0


## How far toward the door the squad has surged, 0 -> 1: each mash carries it a
## step on and it eases back between them.
static func surge(beats: CaptureBeats, t: float) -> float:
	var out := 0.0
	for span in beats.hops:
		if t > span.x and t < span.y + JOLT:
			var p := clampf((t - span.x) / (span.y - span.x), 0.0, 1.0)
			var back := clampf((t - span.y) / JOLT, 0.0, 1.0)
			out = maxf(out, sin(p * PI * 0.5) * (1.0 - _ease_out(back)))
	return out * HOP_SURGE


## The squad's cheer after a flip: a couple of bounces in place.
static func cheer(beats: CaptureBeats, captured: bool, t: float) -> float:
	if not captured:
		return 0.0
	var p := (t - flip_at(beats)) / CHEER
	if p <= 0.0 or p >= 1.0:
		return 0.0
	return absf(sin(p * PI * CHEER_HOPS)) * CHEER_HEIGHT * (1.0 - p)


## How hard the last landing is still shaking things, 0 -> 1.
static func jolt(beats: CaptureBeats, t: float) -> float:
	var out := 0.0
	for land in beats.lands:
		var since := t - land
		if since >= 0.0 and since < JOLT:
			out = maxf(out, 1.0 - since / JOLT)
	return out


## The building's scale: squashed by each landing, swelling through the flip.
static func building_scale(beats: CaptureBeats, captured: bool, t: float) -> Vector3:
	var shock := jolt(beats, t)
	var squash := SQUASH * shock * cos((1.0 - shock) * PI * 2.5)
	var swell := 0.0
	if captured:
		var p := clampf((t - beats.flip.x) / (beats.flip.y - beats.flip.x), 0.0, 1.0)
		swell = sin(p * PI) * SWELL
	return Vector3(1.0 + squash * 0.5 + swell, 1.0 - squash + swell, 1.0 + squash * 0.5 + swell)


## One dust window per mash, 0 -> 1 as its puff spreads and fades.
static func dust(beats: CaptureBeats, index: int, t: float) -> float:
	if index >= beats.lands.size():
		return 0.0
	var p := (t - beats.lands[index]) / DUST
	return p if p > 0.0 and p < 1.0 else 0.0


## Where confetti piece `index` is, from the point it was thrown at, `since`
## seconds after the flip. Hashed scatter, never `randf`.
static func confetti_offset(index: int, since: float) -> Vector3:
	var turn := TAU * SquadFormation3D.scatter(index, 1)
	var lift := 0.55 + 0.45 * SquadFormation3D.scatter(index, 2)
	var speed := CONFETTI_SPEED * (0.6 + 0.4 * SquadFormation3D.scatter(index, 3))
	var out := Vector3(cos(turn) * (1.0 - lift), lift, sin(turn) * (1.0 - lift)).normalized()
	var s := clampf(since, 0.0, CONFETTI_SECONDS)
	var drag := (1.0 - exp(-2.2 * s)) / 2.2
	return out * speed * drag + Vector3.DOWN * CONFETTI_GRAVITY * 0.25 * s * s


## How much of the confetti is still in the air, 1 -> 0 over its run.
static func confetti_life(beats: CaptureBeats, captured: bool, t: float) -> float:
	if not captured:
		return 0.0
	var since := t - flip_at(beats)
	if since <= 0.0 or since >= CONFETTI_SECONDS:
		return 0.0
	return 1.0 - smoothstep(0.6, 1.0, since / CONFETTI_SECONDS)


## Firework `ring`'s burst, 0 -> 1 as its sparks fly out and die.
static func firework(beats: CaptureBeats, captured: bool, ring: int, t: float) -> float:
	if not captured:
		return 0.0
	var p := (t - beats.banner.x - FIREWORK_DELAY[ring]) / FIREWORK_SECONDS
	return p if p > 0.0 and p < 1.0 else 0.0


## Spark `index`'s offset from its ring's centre at burst progress `p`.
static func spark_offset(ring: int, index: int, p: float) -> Vector3:
	var turn := TAU * float(index) / float(FIREWORK_SPARKS) + ring * 0.4
	var tilt := (SquadFormation3D.scatter(index, 11 + ring) - 0.5) * 0.9
	var out := Vector3(cos(turn), sin(turn), tilt).normalized()
	return out * FIREWORK_REACH * _ease_out(p) + Vector3.DOWN * 0.5 * p * p


## Where the lens stands and what it looks at, `[eye, target]`, for the shot the
## clock is in. `squad` is the squad's middle at body height where it halts and
## `leading` where it is now, which the march pans with; `door` is the
## building's front at its foot, `top` its flag's top. A completing capture
## cranes up the pole for the flip; a partial holds on the squad standing its
## ground.
static func lens(
	beats: CaptureBeats,
	captured: bool,
	t: float,
	squad: Vector3,
	leading: Vector3,
	door: Vector3,
	top: Vector3
) -> PackedVector3Array:
	var eye: Vector3
	var target: Vector3
	var settled: float = beats.lands[beats.lands.size() - 1] + 0.05
	var between := squad.lerp(door, 0.5)
	var reach := maxf(1.0, (top.y - door.y) / FRAMED_POLE)
	if t < beats.march.y:
		var p := _ease_out(clampf((t - cut_in()) / (beats.march.y - cut_in()), 0.0, 1.0))
		var pan := Vector3.RIGHT * minf(leading.x - squad.x, 0.0) * MARCH_PAN
		eye = between + MARCH_EYE[0].lerp(MARCH_EYE[1], p) * reach + pan
		target = between + MARCH_LOOK * reach + pan
	elif not captured or t < beats.flip.x:
		var p := clampf((t - beats.march.y) / (settled - beats.march.y), 0.0, 1.0)
		eye = squad + MASH_EYE[0].lerp(MASH_EYE[1], p) * reach
		if not captured and t >= settled:
			eye += HOLD_PULL * _ease_out(clampf((t - settled) / 0.8, 0.0, 1.0))
		target = squad.lerp(door, MASH_LOOK_SHARE) + Vector3.UP * MASH_LOOK_UP * reach
	else:
		var p := _ease_out(clampf((t - beats.flip.x) / (beats.wipe_out.x - beats.flip.x), 0.0, 1.0))
		var middle := Vector3(squad.x, door.y, door.z).lerp(Vector3(top.x, door.y, top.z), 0.55)
		eye = middle + FLIP_EYE[0].lerp(FLIP_EYE[1], p) * reach
		target = middle + Vector3.UP * (top.y - door.y) * FLIP_LOOK_SHARE
	var shake := jolt(beats, t) * LENS_SHAKE
	eye += Vector3(sin(t * 91.0), cos(t * 77.0), 0.0) * shake
	return PackedVector3Array([eye, target])


## A peak of 1 at `at`, falling to nothing `width` either side.
static func _spike(t: float, at: float, width: float) -> float:
	var d := absf(t - at) / width
	return 1.0 - d if d < 1.0 else 0.0


static func _ease_out(p: float) -> float:
	return 1.0 - pow(1.0 - p, 3.0)


static func _ease_in(p: float) -> float:
	return p * p
