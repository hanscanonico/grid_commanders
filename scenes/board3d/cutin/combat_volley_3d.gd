class_name CombatVolley3D
extends RefCounted
## How one side's fire looks on the 3D stage, drawn into `CutinFx3D` as a pure
## function of the clock: every figure's muzzle flash, the rounds each kind of
## weapon throws (tracer, flak, shell, rocket, bomb, torpedo), what they leave
## on whatever they hit, and the blast that takes a squad. Paths and timing are
## `CutinBallistics3D`'s; the look is the `BattleStyle` the rules' weapon slot
## resolved to — tint, muzzle, burst, chips, cadence — never decided here.

const FIRE_CORE := Color("#fff7d6")
const FIRE := Color("#ffb04a")
const FIRE_DEEP := Color("#e0501c")
const SMOKE := Color("#66646a")
const SMOKE_LIGHT := Color("#8d8a88")
const DUST := Color("#a48762")
const SPRAY := Color("#eef7ff")
const WAKE := Color("#dff0ff")
const SHELL := Color("#3a3a3e")
const ROCKET_BODY := Color("#e9e6df")
const ROCKET_NOSE := Color("#c8402c")
const TORPEDO := Color("#2d3338")
## How long a barrel stays alight after a round leaves, as on the flat cut-in.
const FLASH_HOLD := 0.12
## How long a burst burns and its smoke hangs, in seconds.
const BURST_LIFE := 0.5
const SPARK_LIFE := 0.16
## A rocket's trail: how many puffs it leaves and how far apart, in flight.
const TRAIL_PUFFS := 16
const TRAIL_STEP := 0.022
const BLAST_STAGGER := 0.06


## One side's volley: `from` its barrels (nearest the foe last), `targets` the
## foe's figures, fired at `fire` with rounds `flight` seconds in the air.
class Volley:
	var style: BattleStyle
	var from := PackedVector3Array()
	var targets := PackedVector3Array()
	var fire := 0.0
	var flight := 0.3
	var lobbed := false
	## The water's top under the target, for a torpedo's run and a splash; the
	## ground's under it otherwise.
	var floor_y := 0.0
	var wet := false
	var airborne := false
	## Whether the shot cost the target anything: a miss leaves no burst.
	var harmed := true

	func shots() -> int:
		return style.shots_per_figure * (2 if style.sustained else 1)

	func stagger() -> float:
		return minf(style.fire_stagger, 0.22 / maxf(from.size() - 1, 1.0))

	func progress(t: float, figure: int, shot: int) -> float:
		return CutinBallistics3D.round_progress(
			t, fire, flight, figure, shot, stagger(), style.sustained
		)


## Every barrel alight at `t`, and the light they throw.
static func draw_muzzles(fx: CutinFx3D, v: Volley, t: float, toward: Vector3) -> void:
	var radius := CutinBallistics3D.cells(v.style.muzzle) * 0.75
	if radius <= 0.0:
		return
	var lit := 0.0
	for f in v.from.size():
		var strength := 0.0
		for s in v.shots():
			var since := v.progress(t, f, s) * v.flight
			if since >= 0.0 and since < FLASH_HOLD:
				strength = maxf(strength, 1.0 - since / FLASH_HOLD)
		if strength <= 0.0:
			continue
		var at := v.from[f]
		var dir := (toward - at).normalized()
		var flicker := 0.8 + 0.2 * sin(t * 97.0 + f)
		fx.star(at, dir, radius * (0.6 + 0.6 * strength) * flicker, Color(v.style.tint, strength))
		fx.glow_ball(at, radius * 0.35 * strength, Color(FIRE_CORE, strength))
		lit = maxf(lit, strength)
	if lit > 0.0:
		fx.light(0, v.from[v.from.size() - 1], 2.2 * lit, v.style.tint)


## A puff of gun smoke off each heavy barrel, drifting up after the shot.
static func draw_gun_smoke(fx: CutinFx3D, v: Volley, t: float) -> void:
	if v.style.sustained or v.style.muzzle < 14.0:
		return
	for f in v.from.size():
		var since := t - (v.fire + f * v.stagger())
		if since <= 0.0 or since >= 0.6:
			continue
		var q := since / 0.6
		for k in 2:
			var at := CutinBallistics3D.puff(v.from[f], f * 4 + k, q, 0.35)
			fx.smoke_ball(at, 0.07 + 0.12 * q, Color(SMOKE_LIGHT, 0.55 * (1.0 - q)))


## Every round in the air at `t`.
static func draw_rounds(fx: CutinFx3D, v: Volley, t: float) -> void:
	var kind := v.style.projectile
	if kind == BattleStyle.NONE:
		return
	var peak := CutinBallistics3D.peak_of(v.style, v.lobbed)
	for f in v.from.size():
		for s in v.shots():
			var p := v.progress(t, f, s)
			if p <= 0.0 or p >= 1.0:
				continue
			var index := f * 8 + s
			var from := v.from[f]
			var to := CutinBallistics3D.hit_point(v.targets, index)
			if kind == BattleStyle.TORPEDO:
				from.y = v.floor_y
				to.y = v.floor_y
			elif kind == BattleStyle.BOMB:
				from += Vector3.DOWN * 0.12
			var at := CutinBallistics3D.path(kind, from, to, p, peak)
			var dir := CutinBallistics3D.heading(kind, from, to, p, peak)
			_round(
				fx,
				v,
				kind,
				at,
				dir,
				CutinBallistics3D.path(kind, from, to, maxf(p - 0.1, 0.0), peak),
				p
			)
			if kind == BattleStyle.ROCKET:
				_trail(fx, kind, from, to, p, peak, index)
			elif kind == BattleStyle.TORPEDO:
				_wake(fx, from, at, v.floor_y)


static func _round(
	fx: CutinFx3D, v: Volley, kind: StringName, at: Vector3, dir: Vector3, back: Vector3, p: float
) -> void:
	var tint := v.style.tint
	match kind:
		BattleStyle.TRACER, BattleStyle.FLAK:
			fx.streak(at - dir * 0.5, at, 0.055, Color(tint, 1.0))
			fx.glow_ball(at, 0.04, Color(FIRE_CORE, 1.0))
			if kind == BattleStyle.FLAK and p > 0.82:
				var q := (p - 0.82) / 0.18
				fx.glow_ball(at, 0.08 + 0.16 * q, Color(FIRE, 0.8 * (1.0 - q)))
				fx.smoke_ball(at, 0.06 + 0.14 * q, Color(SMOKE, 0.7))
		BattleStyle.SHELL:
			fx.solid_box(at, dir, Vector3(0.12, 0.06, 0.06), SHELL)
			fx.streak(back, at, 0.05, Color(tint, 0.55))
			fx.glow_ball(at - dir * 0.05, 0.04, Color(tint, 0.9))
		BattleStyle.ROCKET:
			fx.dart(at, dir, 0.28, 0.035, ROCKET_BODY, ROCKET_NOSE)
			fx.glow_ball(at - dir * 0.16, 0.035, Color(FIRE_CORE, 0.9))
			fx.glow_ball(at - dir * 0.2, 0.05, Color(FIRE, 0.75))
		BattleStyle.BOMB:
			fx.dart(at, dir, 0.24, 0.055, SHELL, SHELL)
			fx.solid_box(at - dir * 0.12, dir, Vector3(0.04, 0.14, 0.14), SHELL)
		BattleStyle.TORPEDO:
			fx.dart(at, dir, 0.36, 0.045, TORPEDO, TORPEDO)


## A rocket's smoke, laid where the rocket has been.
static func _trail(
	fx: CutinFx3D, kind: StringName, from: Vector3, to: Vector3, p: float, peak: float, index: int
) -> void:
	for k in range(1, TRAIL_PUFFS + 1):
		var q := p - k * TRAIL_STEP
		if q <= 0.0:
			break
		var at := CutinBallistics3D.path(kind, from, to, q, peak)
		var drift := Vector3(0.0, 0.015 * k, 0.0)
		var size := 0.035 + 0.01 * k + 0.015 * SquadFormation3D.scatter(index * 20 + k, 71)
		var fade := 1.0 - float(k) / (TRAIL_PUFFS + 1)
		fx.smoke_ball(at + drift, size, Color(SMOKE_LIGHT, 0.6 * fade))


## The white wake a torpedo draws on the surface over its run.
static func _wake(fx: CutinFx3D, from: Vector3, at: Vector3, water: float) -> void:
	var start := Vector3(from.x, water + 0.01, from.z)
	var head := Vector3(at.x, water + 0.01, at.z)
	fx.streak(start.lerp(head, 0.35), head, 0.07, Color(WAKE, 0.35))
	fx.streak(start.lerp(head, 0.75), head, 0.12, Color(WAKE, 0.5))
	fx.glow_ball(head, 0.06, Color(WAKE, 0.6))


## What each landed round leaves on its target at `t`: a burst with smoke, chips
## and a kick of dirt or a column of spray for a heavy round; a stitch of sparks
## for a stream of small ones. A shot that cost nothing leaves nothing.
static func draw_impacts(fx: CutinFx3D, v: Volley, t: float) -> void:
	if not v.harmed or v.style.projectile == BattleStyle.NONE:
		return
	var burst := CutinBallistics3D.cells(v.style.impact_radius)
	var brightest := 0.0
	var centre := Vector3.ZERO
	for f in v.from.size():
		for s in v.shots():
			var since := (v.progress(t, f, s) - 1.0) * v.flight
			var index := f * 8 + s
			var at := CutinBallistics3D.hit_point(v.targets, index)
			if burst > 0.0 and since >= 0.0 and since < BURST_LIFE:
				_burst(fx, v, at, burst, since / BURST_LIFE, index)
				brightest = maxf(brightest, 1.0 - since / BURST_LIFE)
				centre = at
			elif burst <= 0.0 and since >= 0.0 and since < SPARK_LIFE:
				_sparks(fx, v, at, since / SPARK_LIFE, index)
				brightest = maxf(brightest, 0.5 * (1.0 - since / SPARK_LIFE))
				centre = at
	if brightest > 0.0:
		fx.light(1, centre + Vector3.UP * 0.3, 3.0 * brightest, FIRE)


static func _burst(
	fx: CutinFx3D, v: Volley, at: Vector3, radius: float, q: float, index: int
) -> void:
	var grow := 1.0 - pow(1.0 - q, 3.0)
	var fade := 1.0 - q
	var flare := clampf(1.0 - q * 2.5, 0.0, 1.0)
	fx.glow_ball(at, radius * (0.2 + 0.4 * grow), Color(FIRE, 0.6 * flare))
	fx.glow_ball(at, radius * 0.25 * flare, Color(FIRE_CORE, flare))
	for k in 3:
		var puff := CutinBallistics3D.puff(at, index * 5 + k, q, radius * 1.2)
		fx.smoke_ball(puff, radius * (0.12 + 0.28 * grow), Color(SMOKE, 0.7 * fade))
	for k in v.style.impact_debris:
		var chip := CutinBallistics3D.debris(at, index * 7 + k, q, radius * 1.6)
		if v.wet:
			fx.glow_ball(chip, radius * 0.08, Color(SPRAY, 0.8 * fade))
		else:
			fx.solid_box(chip, Vector3(1.0, k, 0.5), Vector3.ONE * radius * 0.13, DUST)
	if v.airborne:
		return
	var base := Vector3(at.x, v.floor_y, at.z)
	if v.wet:
		_splash(fx, base, radius, grow, fade, index)
	else:
		for k in 2:
			var kick := CutinBallistics3D.puff(base, index * 3 + k + 20, q, radius)
			fx.smoke_ball(kick, radius * (0.3 + 0.35 * grow), Color(DUST, 0.7 * fade))


## A column of spray thrown up where a round hits the water: a few jets of
## different heights, a crown of droplets and a ring spreading on the surface.
static func _splash(
	fx: CutinFx3D, base: Vector3, radius: float, grow: float, fade: float, index: int
) -> void:
	for k in 4:
		var turn := TAU * (k + SquadFormation3D.scatter(index * 4 + k, 101)) / 4.0
		var foot := base + Vector3(cos(turn), 0.0, sin(turn)) * radius * 0.25
		var tall := radius * (1.6 + 1.6 * SquadFormation3D.scatter(index * 4 + k, 102)) * grow
		fx.streak(foot, foot + Vector3.UP * tall, radius * 0.16, Color(SPRAY, 0.4 * fade))
		fx.glow_ball(foot + Vector3.UP * tall, radius * 0.12, Color(SPRAY, 0.6 * fade))
	fx.ring(base + Vector3.UP * 0.01, radius * (0.4 + 1.2 * grow), 0.05, Color(SPRAY, 0.5 * fade))


static func _sparks(fx: CutinFx3D, v: Volley, at: Vector3, q: float, index: int) -> void:
	for k in 4:
		var turn := TAU * SquadFormation3D.scatter(index * 4 + k, 81)
		var lift := SquadFormation3D.scatter(index * 4 + k, 82) * 0.8 + 0.2
		var dir := Vector3(cos(turn), lift, sin(turn)).normalized()
		var tip := at + dir * (0.08 + 0.22 * q)
		fx.streak(at + dir * 0.18 * q, tip, 0.025, Color(v.style.tint, 1.0 - q))
	fx.glow_ball(at, 0.06 * (1.0 - q), Color(FIRE_CORE, 1.0 - q))


## The blast that takes a whole squad, `p` of the way through the death beat:
## a fireball on every figure a beat apart, smoke climbing off them, chips
## flung wide and a shockwave rolling out over the ground.
static func draw_blast(
	fx: CutinFx3D, points: PackedVector3Array, p: float, floor_y: float, wet: bool, airborne: bool
) -> void:
	if p <= 0.0 or p >= 1.0 or points.is_empty():
		return
	var middle := Vector3.ZERO
	for i in points.size():
		middle += points[i]
		var q := clampf((p - i * BLAST_STAGGER) / (1.0 - BLAST_STAGGER * points.size()), 0.0, 1.0)
		if q <= 0.0 or q >= 1.0:
			continue
		var at := points[i]
		var grow := 1.0 - pow(1.0 - q, 2.5)
		var fade := 1.0 - q
		fx.glow_ball(at + Vector3.UP * 0.2 * q, 0.2 + 0.6 * grow, Color(FIRE_DEEP, 0.9 * fade))
		fx.glow_ball(at + Vector3.UP * 0.15 * q, 0.15 + 0.4 * grow, Color(FIRE, fade))
		fx.glow_ball(at, 0.3 * (1.0 - q), Color(FIRE_CORE, 1.0 - q))
		for k in 4:
			var puff := CutinBallistics3D.puff(at, i * 9 + k, q, 1.1)
			fx.smoke_ball(puff, 0.12 + 0.35 * grow, Color(SMOKE, 0.65 * minf(1.0, fade * 1.6)))
		for k in 6:
			var chip := CutinBallistics3D.debris(at, i * 11 + k, q, 1.2)
			fx.solid_box(chip, Vector3(k, 1.0, 0.3), Vector3.ONE * 0.06, SHELL)
	middle /= points.size()
	var wave := clampf(p / 0.6, 0.0, 1.0)
	if not airborne and wave < 1.0:
		var ground := Vector3(middle.x, floor_y + 0.02, middle.z)
		fx.ring(ground, 0.3 + 3.0 * wave, 0.1, Color(SPRAY if wet else FIRE, 0.4 * (1.0 - wave)))
	fx.light(1, middle + Vector3.UP * 0.5, 6.0 * (1.0 - p), FIRE)
