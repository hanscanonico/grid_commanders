class_name ActorPose3D
extends RefCounted
## A commander figure's body language as pure functions of one clock: `sample`
## says where every part of `CommanderActor3D` is `t` seconds into a clip, so a
## cinematic can scrub, skip or hold a pose without any animation state.
##
## `&"root"` is a Vector3 offset of the whole figure (the bob of a step, the hop
## of a surprise); every other part is a Vector3 of Euler radians about that
## part's pivot. The figure faces -Z, so +X on an arm or a leg swings it
## forward, +Z on the right arm (and -Z on the left) swings it out to the side,
## +X on the torso or the head leans it back, and Y turns it.
##
## A loop repeats every `LOOP_SECONDS`. A gesture is idle with an offset laid
## over it by a weight that eases in over `EASE_IN`, so its first frame is
## idle's and it never pops; once in, it holds with a little breathing in it.

const PARTS: Array[StringName] = [
	&"root", &"hips", &"torso", &"head", &"arm_l", &"arm_r", &"leg_l", &"leg_r"
]
const LOOPS: Array[StringName] = [&"idle", &"walk", &"talk"]
const GESTURES: Array[StringName] = [
	&"point", &"fist", &"shrug", &"salute", &"nod", &"shake", &"laugh", &"surprise", &"sigh"
]
const CLIPS: Array[StringName] = [
	&"idle",
	&"walk",
	&"talk",
	&"point",
	&"fist",
	&"shrug",
	&"salute",
	&"nod",
	&"shake",
	&"laugh",
	&"surprise",
	&"sigh",
]
## Every loop's period: each loop's own rhythms divide it.
const LOOP_SECONDS := 4.8
const EASE_IN := 0.3
## How far the arms hang out from the body at rest, so they clear the coat.
const ARM_REST := 0.1
const BREATH_SECONDS := 2.4
const STRIDE_SECONDS := 0.6


static func is_loop(clip: StringName) -> bool:
	return LOOPS.has(clip)


static func sample(clip: StringName, t: float) -> Dictionary:
	match clip:
		&"walk":
			return _walk(t)
		&"talk":
			return _talk(t)
		&"idle":
			return _idle(t)
	if not GESTURES.has(clip):
		return _idle(t)
	var pose := _idle(t)
	var weight := smoothstep(0.0, EASE_IN, t)
	var offset := _gesture(clip, t)
	for part: StringName in offset:
		pose[part] += offset[part] * weight
	return pose


static func _wave(t: float, period: float, phase: float = 0.0) -> float:
	return sin(TAU * (t / period + phase))


static func _idle(t: float) -> Dictionary:
	var breath := _wave(t, BREATH_SECONDS)
	var sway := _wave(t, LOOP_SECONDS)
	return {
		&"root": Vector3(0, 0.003 * (breath + 1.0), 0),
		&"hips": Vector3(0, 0.03 * sway, 0.015 * sway),
		&"torso": Vector3(0.025 * breath, -0.02 * sway, -0.01 * sway),
		&"head": Vector3(-0.02 * breath, 0.05 * _wave(t, LOOP_SECONDS, 0.25), 0.02 * sway),
		&"arm_l": Vector3(0.04 * breath, 0, -ARM_REST - 0.02 * breath),
		&"arm_r": Vector3(0.04 * breath, 0, ARM_REST + 0.02 * breath),
		&"leg_l": Vector3.ZERO,
		&"leg_r": Vector3.ZERO,
	}


static func _walk(t: float) -> Dictionary:
	var stride := _wave(t, STRIDE_SECONDS)
	var bob := absf(_wave(t, STRIDE_SECONDS))
	return {
		&"root": Vector3(0, 0.018 * bob, 0),
		&"hips": Vector3(0, 0.12 * stride, 0),
		&"torso": Vector3(-0.06, -0.16 * stride, 0),
		&"head": Vector3(0.04, 0.05 * stride, 0),
		&"arm_l": Vector3(0.55 * stride, 0, -ARM_REST),
		&"arm_r": Vector3(-0.55 * stride, 0, ARM_REST),
		&"leg_l": Vector3(-0.6 * stride, 0, 0),
		&"leg_r": Vector3(0.6 * stride, 0, 0),
	}


## Idle, a nod on the beats of speech and the right hand opening toward the
## listener for part of every loop, rising and falling on a smooth hump.
static func _talk(t: float) -> Dictionary:
	var pose := _idle(t)
	var nod := _wave(t, 1.6)
	var nod_turn := _wave(t, 2.4, 0.3)
	pose[&"head"] += Vector3(-0.07 * maxf(nod, 0.0) * maxf(nod, 0.0), 0.08 * nod_turn, 0)
	var hump := maxf(_wave(t, LOOP_SECONDS, 0.1), 0.0)
	var palm := hump * hump
	pose[&"arm_r"] += Vector3(0.9, -0.3, 0.25) * palm + Vector3(0.08 * _wave(t, 0.8), 0, 0) * palm
	pose[&"torso"] += Vector3(0, -0.08 * palm, 0)
	return pose


## A gesture's offset over idle at `t`, before the ease-in weight.
static func _gesture(clip: StringName, t: float) -> Dictionary:
	var life := _wave(t, 1.2)
	match clip:
		&"point":
			return {
				&"arm_r": Vector3(1.45 + 0.03 * life, -0.1, -ARM_REST - 0.05),
				&"torso": Vector3(0, -0.15, 0),
				&"head": Vector3(0.05, 0.1, 0),
			}
		&"fist":
			return {
				&"arm_r": Vector3(2.75 + 0.05 * life, 0, 0.2),
				&"arm_l": Vector3(-0.1, 0, -0.25),
				&"torso": Vector3(0.1, 0, 0),
				&"head": Vector3(0.2 + 0.03 * life, 0, 0),
			}
		&"shrug":
			return {
				&"arm_l": Vector3(0.55, 0, -0.75 - 0.04 * life),
				&"arm_r": Vector3(0.55, 0, 0.75 + 0.04 * life),
				&"head": Vector3(0.05, 0, 0.28),
				&"root": Vector3(0, 0.01, 0),
			}
		&"salute":
			return {
				&"arm_r": Vector3(2.5, 0, -ARM_REST - 0.34 - 0.02 * life),
				&"head": Vector3(0.06, -0.08, 0),
				&"torso": Vector3(0.05, 0, 0),
			}
		&"nod":
			var dips := sin(PI * minf(t, 1.2) / 0.6)
			return {&"head": Vector3(-0.32 * dips * dips - 0.04, 0, 0)}
		&"shake":
			var fade := 1.0 - smoothstep(0.9, 1.5, t)
			return {&"head": Vector3(-0.05, 0.38 * sin(TAU * t / 0.45) * fade, 0)}
		&"laugh":
			var shake := sin(TAU * t / 0.22)
			return {
				&"torso": Vector3(0.14 + 0.07 * shake, 0, 0),
				&"head": Vector3(0.3 + 0.05 * shake, 0, 0),
				&"root": Vector3(0, 0.006 * (shake + 1.0), 0),
				&"arm_l": Vector3(0.35, 0, 0.05),
				&"arm_r": Vector3(0.35, 0, -0.05),
			}
		&"surprise":
			var hop := sin(PI * clampf(t / 0.4, 0.0, 1.0))
			return {
				&"root": Vector3(0, 0.07 * hop, 0),
				&"arm_l": Vector3(0.45, 0, -0.85 - 0.03 * life),
				&"arm_r": Vector3(0.45, 0, 0.85 + 0.03 * life),
				&"torso": Vector3(0.1, 0, 0),
				&"head": Vector3(0.14, 0, 0),
				&"leg_l": Vector3(0.25 * hop, 0, -0.1 * hop),
				&"leg_r": Vector3(0.25 * hop, 0, 0.1 * hop),
			}
		&"sigh":
			return {
				&"head": Vector3(-0.28 - 0.03 * life, 0, 0.06),
				&"torso": Vector3(-0.1, 0, 0),
				&"arm_l": Vector3(0.05, 0, ARM_REST * 0.6),
				&"arm_r": Vector3(0.05, 0, -ARM_REST * 0.6),
				&"root": Vector3(0, -0.006, 0),
			}
	return {}
