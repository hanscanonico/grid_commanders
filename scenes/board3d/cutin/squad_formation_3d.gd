class_name SquadFormation3D
extends RefCounted
## Where each figure of a 3D cut-in squad stands and how it moves, as arithmetic:
## the staggered formation, the roll-in, the hover and the swell, the wind-up and
## the kick, and a casualty's fall. Node-free, so a squad posed at any moment of
## its cut-in's clock is the same squad every run and every rule is checked
## without a scene.
##
## A squad's frame: +X points at the foe, +Z toward the lens's side of the stage,
## Y up. One unit is one cell of the stage's ground, as on the board.

## Five slots, outermost first, staggered in depth so a full squad reads as a
## cluster rather than a rank. Measured in figure spacings along X and cells
## along Z; the posted slots are centred on the squad's anchor whatever their
## count, so a lone straggler holds the ground a full five did.
const SLOTS: Array[Vector2] = [
	Vector2(-2.0, -0.4),
	Vector2(-1.0, 0.42),
	Vector2(0.0, -0.3),
	Vector2(1.0, 0.5),
	Vector2(2.0, -0.18),
]
const MAX_FIGURES := 5
## How far outward a squad starts its entrance, per domain, before `arrive`
## carries it home: a tank rolls, an aircraft sweeps in from further out, a ship
## sails a shorter run.
const ARRIVE_LAND := 2.6
const ARRIVE_AIR := 5.5
const ARRIVE_SEA := 2.0
## A marching rank sets off in order, and each man's run is compressed rather
## than merely delayed so the last still lands as the beat closes.
const MARCH_STAGGER := 0.1
const TRUDGE_HEIGHT := 0.05
const TRUDGE_STEPS := 3.0
## The dip past the slot a vehicle halts on, which is what makes a stop read as
## weight.
const SETTLE_DIP := 0.06
const SETTLE_BAND := 0.18
## How high aircraft cruise over their ground, how far they bob and how fast.
## High enough that a flight framed from below its wing reads against the sky
## with the ground well under it, not skimming the horizon.
const CRUISE := 2.2
const HOVER_SWING := 0.07
const HOVER_RATE := 2.3
const HOVER_PHASE := 1.1
## The bank an aircraft sweeps in on, levelling as it arrives.
const ARRIVE_BANK := 0.45
## A hull's roll and pitch on the swell.
const SWELL_ROLL := 0.05
const SWELL_PITCH := 0.025
const SWELL_RATE := 1.4
## The wind-up eases over the front of its beat and then holds. A style's pitch
## is exaggerated here: a 3D barrel tipped by the 2D board's few degrees does
## not read at all.
const AIM_EASE := 0.6
const AIM_PITCH_SCALE := 2.5
const AIM_PITCH_MAX := 0.3
## The kick a gun gives its hull as the round leaves, in cells, and how long the
## hull takes to settle back.
const KICK := 0.14
const KICK_SNAP := 0.035
const KICK_SETTLE := 0.3
## Casualties fall one after another, a beat apart in fall progress; each is
## knocked back before it goes over.
const TOPPLE_STAGGER := 0.14
const KNOCK_SHARE := 0.22
const KNOCK_BACK := 0.16
const TOPPLE_TIP := 1.35
const TOPPLE_SINK := 0.05
const SEA_LIST := 0.5
const SEA_SINK := 0.45
const AIR_SPIN := 3.2
const AIR_DIVE := 0.9


## Where slot `slot` of a squad posting `posted` figures stands, in the squad's
## frame, with `spacing` cells between neighbours along X and `spread` scaling
## the depth stagger (0 lines them up — a bridge deck).
static func slot_point(slot: int, posted: int, spacing: float, spread: float) -> Vector3:
	var count := clampi(posted, 1, MAX_FIGURES)
	var at: Vector2 = SLOTS[clampi(slot, 0, MAX_FIGURES - 1)]
	var middle := (SLOTS[0].x + SLOTS[count - 1].x) * 0.5
	return Vector3((at.x - middle) * spacing, 0.0, at.y * spread)


## How far through its own entrance one figure is: a foot rank staggers, a
## vehicle, a flight and a hull arrive as one.
static func march_progress(arrive: float, slot: int, on_foot: bool) -> float:
	if not on_foot:
		return clampf(arrive, 0.0, 1.0)
	var lag := MARCH_STAGGER * clampi(slot, 0, MAX_FIGURES - 1)
	return clampf((arrive - lag) / (1.0 - lag), 0.0, 1.0)


## The entrance: an offset from the figure's slot, fast at first and easing into
## a short settle — so every frame after it closes is exactly the slot.
static func arrive_offset(
	progress: float, reach: float, domain: StringName, on_foot: bool
) -> Vector3:
	if progress >= 1.0:
		return Vector3.ZERO
	var run := pow(1.0 - progress, 3.0)
	var settle := clampf((progress - (1.0 - SETTLE_BAND)) / SETTLE_BAND, 0.0, 1.0)
	var dip := SETTLE_DIP * sin(settle * PI)
	var rise := 0.0
	if domain == UnitType.AIR:
		rise = 0.5 * run
	elif on_foot:
		rise = absf(sin(progress * PI * TRUDGE_STEPS)) * TRUDGE_HEIGHT * (1.0 - progress)
	return Vector3(-reach * run + dip, rise, 0.0)


## How far a domain enters from.
static func arrive_reach(domain: StringName) -> float:
	match domain:
		UnitType.AIR:
			return ARRIVE_AIR
		UnitType.SEA:
			return ARRIVE_SEA
	return ARRIVE_LAND


## An aircraft's height over its ground at `clock`: cruising, with a bob each
## figure holds out of step with the next.
static func cruise_height(clock: float, slot: int) -> float:
	return CRUISE + sin(clock * HOVER_RATE + slot * HOVER_PHASE) * HOVER_SWING


## A figure's attitude from its domain alone: an aircraft banks as it sweeps in,
## a hull rolls and pitches on the swell. (x: roll about the heading, z: pitch.)
static func attitude(domain: StringName, clock: float, slot: int, progress: float) -> Vector2:
	match domain:
		UnitType.AIR:
			return Vector2(-ARRIVE_BANK * pow(1.0 - clampf(progress, 0.0, 1.0), 2.0), 0.0)
		UnitType.SEA:
			var phase := clock * SWELL_RATE + slot * 1.7
			return Vector2(sin(phase) * SWELL_ROLL, sin(phase * 0.8 + 0.6) * SWELL_PITCH)
	return Vector2.ZERO


## The wind-up's ease: out over the front of the beat, held after.
static func aim_ease(aim: float) -> float:
	return 1.0 - pow(1.0 - clampf(aim / AIM_EASE, 0.0, 1.0), 3.0)


## The pitch the wind-up tips a figure by, nose-up positive — a style's pitch is
## nose-toward-the-foe positive, so a howitzer's negative one raises its barrel.
static func aim_pitch(aim: float, style_pitch: float) -> float:
	var pitch := clampf(-style_pitch * AIM_PITCH_SCALE, -AIM_PITCH_MAX, AIM_PITCH_MAX)
	return pitch * aim_ease(aim)


## The kick back along the firing axis `since` seconds after the round left,
## scaled by how much of it the weapon earns. Zero before the shot.
static func kick(since: float, recoil: float) -> float:
	if since <= 0.0 or recoil <= 0.0:
		return 0.0
	if since < KICK_SNAP:
		return -KICK * recoil * since / KICK_SNAP
	var settle := clampf((since - KICK_SNAP) / KICK_SETTLE, 0.0, 1.0)
	return -KICK * recoil * (1.0 - smoothstep(0.0, 1.0, settle))


## How far into its own fall casualty `slot` is, with `standing` survivors ahead
## of it and `posted` figures in all: the lost go down one after another, and
## the run is long enough for the last to finish.
static func casualty_run(casualty: float, slot: int, standing: int, posted: int) -> float:
	if slot < standing or casualty <= 0.0:
		return 0.0
	var reach := 1.0 + TOPPLE_STAGGER * maxf(posted - standing - 1, 0.0)
	return clampf(casualty * reach - (slot - standing) * TOPPLE_STAGGER, 0.0, 1.0)


## A casualty's pose off its own run: `x` how far it is thrown back, `y` how
## far it has dropped, `z` its tip in radians and `w` how much of it is left to
## see. The knock comes first; the fall after it.
static func topple(run: float, domain: StringName) -> Vector4:
	if run <= 0.0:
		return Vector4(0.0, 0.0, 0.0, 1.0)
	var knock := _hump(clampf(run / KNOCK_SHARE, 0.0, 1.0), 0.5) * KNOCK_BACK
	var fall := clampf((run - KNOCK_SHARE) / (1.0 - KNOCK_SHARE), 0.0, 1.0)
	var fade := 1.0 - smoothstep(0.55, 1.0, fall)
	match domain:
		UnitType.AIR:
			return Vector4(knock + fall * 0.6, CRUISE * fall * fall, AIR_DIVE * fall, fade)
		UnitType.SEA:
			return Vector4(knock * 0.5, SEA_SINK * fall, SEA_LIST * fall, fade)
	var tip := TOPPLE_TIP * (1.0 - pow(1.0 - fall, 2.0))
	return Vector4(knock + 0.2 * fall, TOPPLE_SINK * fall, tip, fade)


## The spin a falling aircraft takes about its own heading, in radians.
static func air_spin(run: float) -> float:
	var fall := clampf((run - KNOCK_SHARE) / (1.0 - KNOCK_SHARE), 0.0, 1.0)
	return AIR_SPIN * fall * fall


## A stable number in [0, 1) for one index and one question — the scatter a
## volley, a burst or a fall is spread by, never `randf`.
static func scatter(index: int, salt: int) -> float:
	return float(hash(Vector2i(index * 7919 + 13, salt)) % 10007) / 10007.0


## Up and back down once across a window, peaking at `at` of it.
static func _hump(progress: float, at: float) -> float:
	if progress <= 0.0 or progress >= 1.0:
		return 0.0
	if progress < at:
		return progress / at
	return (1.0 - progress) / (1.0 - at)
