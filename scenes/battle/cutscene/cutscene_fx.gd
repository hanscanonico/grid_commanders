class_name CutsceneFx
extends Control
## The cut-in's overlay layer: whatever crosses the seam or sits on top of both
## halves — muzzle flash, the volley in flight, the mark it leaves where it lands,
## the damage each side took, and the VS badge that holds the frame together before
## the first shot.
##
## Three of those are keyed to the *weapon* rather than the unit, because a unit
## with two of them picks by matchup: the round's silhouette, the flash at the
## barrel and the burst on the target all come off the BattleStyle the rules
## already selected. That is the whole shape of it — a tank strafing a foot squad
## and the same tank shelling a tank are two different reads of one attacker, and
## nothing below decides which; it is handed the style and draws it.
##
## Like CutsceneSide it only draws. Every field below is written by
## CombatCutscene once per frame from its own clock, and every number it prints
## was handed to the cut-in by the sim — nothing here is computed from a rule.

## The one word that outranks a damage number. Lives here rather than on
## CombatCutscene so the dependency between the two runs one way: the director
## reads the overlay's vocabulary, never the reverse.
const KO_TAG := "K.O."

const INK := Color(0.078, 0.090, 0.102)
const FLASH_GOLD := Color(0.988, 0.847, 0.353)
const KO_RED := Color(0.902, 0.302, 0.243)
## A rocket's three body colours and how far it pitches off level, in radians.
const ROCKET_HULL := Color(0.910, 0.925, 0.937)
const ROCKET_FIN := Color(0.667, 0.702, 0.729)
const ROCKET_FLAME := Color(1.0, 0.478, 0.235)
const ROCKET_PITCH := deg_to_rad(22.0)
## A shell's body, and the tick a strafing round leaves where it hit.
const SHELL_BODY := Color(0.184, 0.200, 0.220)
const SPARK_TINT := Color(1.0, 0.878, 0.541)
## The puffs it leaves, and how far back along its own arc each one sits.
const ROCKET_PUFFS := 4
const ROCKET_PUFF_LAG := 0.09
## The backblast cone behind a launch tube, as multiples of the muzzle radius: how
## far back it reaches and how wide it has spread by then.
const BACKBLAST_REACH := 2.6
const BACKBLAST_FLARE := 1.1

## Ceiling on rounds drawn per volley. Five figures firing three apiece is
## fifteen dashes on a 640 px stage, which reads as a smear rather than a burst.
const MAX_ROUNDS := 8
## How far apart, in travel progress, consecutive rounds leave the barrel.
const ROUND_STAGGER := 0.085
## A sustained weapon's stream: how many rounds are in the air at once, how far
## apart they left, and how much faster the stream cycles than the window it runs
## in. The overshoot is the whole point — rounds are still leaving the barrel
## after the first has arrived, which is what makes a burst read as continuous
## fire rather than as one wave of dashes crossing the frame.
const STREAM_ROUNDS := 6
const STREAM_STAGGER := 0.11
const STREAM_CYCLE := 1.45
## Fixed vertical spread across a stream's rounds, so a burst walks across the
## target instead of drilling one hole. Deterministic, like everything here.
const STREAM_SPREAD := 5.0
## How far below the firing line a torpedo runs. The firing line is at the hull's
## gun, so this is roughly the waterline the wake belongs on.
const WAKE_DEPTH := 26.0
## How far gravity has dragged a bomb down by the time it arrives, on top of its
## own lob. Kept under the lob's height so the release still reads as upward.
const BOMB_FALL := 48.0
## The muzzle strobe's rate, in flashes per second, for a sustained weapon. Fast
## enough to read as a barrel alight rather than as a countable blink.
const STROBE_HZ := 18.0
## A struck squad's spark ticks: how many, how far they scatter either way of the
## hit, how big, and how fast each blinks in and out over the impact.
const SPARK_COUNT := 5
const SPARK_SPREAD := Vector2(9.0, 7.0)
const SPARK_SIZE := 5.0
const SPARK_FLICKER := 22.0
## Rising smoke behind an impact burst: four squares, thrown out along a fan and
## lifted as they go.
const SMOKE_COUNT := 4
const SMOKE_SIZE := 8.0
const SMOKE_FAN := 0.5
const SMOKE_LIFT := 13.0
const SMOKE_TINT := Color(0.47, 0.49, 0.53)
## How many spokes each fireball is torn into. The kill blast fills the frame and
## can carry the detail; an impact burst a third of its size cannot, and reads as a
## circle again once the teeth get that fine.
const IMPACT_SPOKES := 12
const BLAST_SPOKES := 18

# --- pose, written every frame by CombatCutscene ------------------------------

## 0 while nothing is in flight; otherwise the volley's travel, 0 -> 1.
var volley_p := 0.0
var volley_from := Vector2.ZERO
var volley_to := Vector2.ZERO
## The firing side's BattleStyle: what the rounds look like, how many there are,
## and how high they arc. Never null while a volley is up.
var volley_style: BattleStyle
## How many figures are firing it. Held separately from `muzzles`, which is only
## populated for the few frames the barrels are alight — the volley outlives the
## flash, and a squad that has already stopped flashing is still five men firing.
var volley_figures := 1
## The lob height this particular volley uses. Held here rather than read off the
## style, because an indirect weapon arcs higher than the same style fired flat
## and a Resource is shared — writing the nudge onto it would change the arc for
## every unit that names it.
var volley_arc := 0.0
## Every barrel alight this frame — one per standing figure. Empty for all but
## the handful of frames after a volley leaves, and for the dark half of a
## sustained weapon's strobe, which the director simply does not populate.
var muzzles := PackedVector2Array()
var muzzle_radius := 0.0
## Which flash the alight barrels wear. Held as the projectile kind rather than
## the style, because that is the vocabulary the rounds already switch on: a
## launcher vents backwards out of its tube, everything else throws a star.
var muzzle_kind := BattleStyle.NONE
## Which way those barrels point, +1 toward screen right. The backblast is the one
## thing at a muzzle that has to know, because it comes out the other end.
var muzzle_toward := 1.0
## The hit the volley landed, 0 -> 1, where it landed, and what landed. Zero for a
## shot that cost the target nothing: a miss shakes the frame but leaves no mark.
var impact_p := 0.0
var impact_at := Vector2.ZERO
var impact_style: BattleStyle
## The kill blast, 0 -> 1, and where it goes off.
var blast_p := 0.0
var blast_at := Vector2.ZERO
## Fades out as the first volley leaves — the badge belongs to the stare-down.
var vs_alpha := 0.0
## Damage callouts, keyed left (attacker) and right (defender). `amount` is the
## displayed HP the side lost, straight off the result's snapshot; `tag` is the
## one word that outranks it, which today is only ever "K.O.".
## `at` is the head of the figure it belongs to, so what a hit cost is printed
## over the thing that took it.
var atk_amount := 0
var atk_tag := ""
var atk_p := 0.0
var atk_at := Vector2.ZERO
var def_amount := 0
var def_tag := ""
var def_p := 0.0
var def_at := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if vs_alpha > 0.0:
		_draw_vs()
	for at in muzzles:
		_draw_muzzle(at)
	if volley_p > 0.0 and volley_p < 1.0 and volley_style != null:
		_draw_volley()
	if impact_p > 0.0 and impact_p < 1.0 and impact_style != null:
		_draw_impact()
	if blast_p > 0.0 and blast_p < 1.0:
		_draw_blast()
	_draw_callout(atk_at, atk_amount, atk_tag, atk_p)
	_draw_callout(def_at, def_amount, def_tag, def_p)


## The volley in flight, drawn the way its style says. Rounds are staggered along
## the firing line so a squad's burst reads as several shots rather than one
## thick dash, and the whole thing is a function of `volley_p` like everything
## else here.
func _draw_volley() -> void:
	if not volley_style.fires():
		return
	if volley_style.sustained:
		_draw_stream()
		return
	var rounds := mini(volley_style.shots_per_figure * maxi(volley_figures, 1), MAX_ROUNDS)
	for i in rounds:
		var lag := clampf(volley_p - i * ROUND_STAGGER, 0.0, 1.0)
		if lag <= 0.0 or lag >= 1.0:
			continue
		_draw_round(lag, i)


## A sustained weapon's stream. Same silhouettes as a volley — a machine gun throws
## tracer and an autocannon throws air-bursting flak, and which is which is still
## the projectile's business — but the timing is a burst's rather than a salvo's:
## unclamped, so a round that has arrived is gone rather than parked on the target,
## and cycling faster than the window, so rounds are still leaving after the first
## has landed and the barrel never looks like it stopped.
##
## Squad size still tells: a lone straggler's three rounds are a thinner stream
## than a full squad's six, which is what `shots_per_figure` has always meant.
func _draw_stream() -> void:
	var rounds := mini(volley_style.shots_per_figure * maxi(volley_figures, 1), STREAM_ROUNDS)
	for i in rounds:
		var lag := volley_p * STREAM_CYCLE - i * STREAM_STAGGER
		if lag <= 0.0 or lag >= 1.0:
			continue
		_draw_round(lag, i)


## Where one round of a stream rides, as a fixed offset off the firing line. The
## step is coprime with the span, so six consecutive rounds land on six different
## rungs and the spray never settles into a visible ladder — and it is arithmetic
## rather than a roll, so a posed still is the same still every run.
static func _rung(index: int) -> float:
	var span := roundi(STREAM_SPREAD * 2.0) + 1
	return float((index * 37) % span) - STREAM_SPREAD


## One round, at `lag` along its travel, drawn the way its projectile kind says.
## Six kinds cover eighteen units, which is the whole point of D5 — each has to
## be recognisable in a fifth of a second, so each gets a different silhouette
## rather than a different colour of the same dash.
func _draw_round(lag: float, index: int) -> void:
	var at := volley_from.lerp(volley_to, lag)
	var toward := signf(volley_to.x - volley_from.x)
	var tint := Color(volley_style.tint, 1.0 - index * 0.09)
	match volley_style.projectile:
		BattleStyle.TORPEDO:
			_draw_torpedo(at, toward, tint)
		BattleStyle.BOMB:
			# Lobbed clear of the aircraft and then owned by gravity, so it rises
			# a little, tips over and lands on the target rather than flying at
			# it. Sum of the two, not a choice between them: the lob is what makes
			# it read as thrown and the fall is what makes it read as dropped.
			at.y -= sin(lag * PI) * volley_arc
			at.y += lag * lag * BOMB_FALL + (index % 2) * 9.0
			_draw_bomb(at, tint)
		BattleStyle.FLAK:
			at.y -= sin(lag * PI) * volley_arc
			at.y += _rung(index)
			_draw_flak(at, lag, tint)
		BattleStyle.ROCKET:
			at.y -= sin(lag * PI) * volley_arc
			at.y += (index % 3 - 1) * 4.0
			_draw_rocket(at, toward, lag, tint)
		BattleStyle.SHELL:
			at.y -= sin(lag * PI) * volley_arc
			at.y += (index % 3 - 1) * 3.0
			_draw_shell(at, toward, tint)
		_:
			at.y += _rung(index)
			_draw_tracer_dash(at, toward, tint)


## The default: a bright dash with a hard outline, so it reads over sky, ground
## and a unit alike. Short on purpose — six of these in the air at once are a burst,
## and lengthening them turns the same six into one smear.
func _draw_tracer_dash(at: Vector2, toward: float, tint: Color) -> void:
	var length := 9.0
	var body := Rect2(at.x - (length if toward < 0.0 else 0.0), at.y - 1.5, length, 3.0)
	draw_rect(body.grow(1.0), Color(INK, tint.a * 0.8))
	draw_rect(body, tint)


## A heavy round: one dark shot, lit along its top edge and shaded underneath, with
## two short dashes of its own passage behind it. Dark on purpose — a shell is a
## lump of metal, and the thing that makes it legible against sky and ground alike
## is that it is the only round in the game that reads as a silhouette rather than
## as a light source.
func _draw_shell(at: Vector2, toward: float, tint: Color) -> void:
	for trail in 2:
		var back := at - Vector2(toward * (9.0 + trail * 7.0), 0.0)
		var length := 6.0 - trail * 2.0
		draw_rect(
			Rect2(back.x - (length if toward < 0.0 else 0.0), back.y - 1.0, length, 2.0),
			Color(tint, tint.a * (0.5 - trail * 0.18))
		)
	draw_circle(at, 6.0, Color(INK, tint.a))
	draw_circle(at, 4.5, Color(SHELL_BODY, tint.a))
	draw_circle(at + Vector2(-toward * 1.2, -1.4), 2.0, Color(tint, tint.a * 0.8))


## Anti-air fire: rounds that go off in the air rather than arriving, so the
## volley reads as a wall of bursts the target has to fly through.
func _draw_flak(at: Vector2, lag: float, tint: Color) -> void:
	var puff := ramp(lag, [0.0, 0.55, 1.0], [1.5, 9.0, 13.0])
	var fade := ramp(lag, [0.0, 0.5, 1.0], [1.0, 0.8, 0.0])
	draw_circle(at, puff + 1.5, Color(INK, tint.a * fade * 0.7))
	draw_circle(at, puff, Color(tint, tint.a * fade))
	draw_circle(at, puff * 0.45, Color(1.0, 1.0, 1.0, tint.a * fade))


## A rocket: a grey fuselage with a red nosecone and a swept tail fin, flame out
## the back, riding its arc nose-first — pitched up while it is climbing and down
## once it is falling, which is the one cue that tells a launcher from a gun at a
## glance. Behind it, four puffs left along the same arc it flew.
func _draw_rocket(at: Vector2, toward: float, lag: float, tint: Color) -> void:
	for puff in ROCKET_PUFFS:
		var back := lag - (puff + 1) * ROCKET_PUFF_LAG
		if back <= 0.0:
			continue
		var fade := clampf(0.42 - puff * 0.09, 0.0, 1.0) * tint.a
		draw_circle(_arced(back), 3.0 + puff * 0.75, Color(SMOKE_TINT.lightened(0.45), fade))
	# Pitch follows the arc's own slope: nose up over the climb, level at the top,
	# nose down into the target. The mirror rides in the transform's x scale, so the
	# body below is written once, forward-facing, for both halves of the frame.
	draw_set_transform(at, cos(lag * PI) * -ROCKET_PITCH * toward, Vector2(toward, 1.0))
	_draw_rocket_body(tint.a)
	draw_set_transform(Vector2.ZERO)


## The rocket itself, in its own frame: origin at the middle of the fuselage, +x
## pointing where it is going, and the tail's flame trailing off the far side.
func _draw_rocket_body(alpha: float) -> void:
	draw_colored_polygon(
		PackedVector2Array([Vector2(-2.0, -3.0), Vector2(-2.0, 3.0), Vector2(-5.0, 0.0)]),
		Color(ROCKET_FIN, alpha)
	)
	draw_circle(Vector2(-6.5, 0.0), 2.2, Color(ROCKET_FLAME, alpha * 0.9))
	draw_circle(Vector2(-5.0, 0.0), 3.2, Color(FLASH_GOLD, alpha))
	draw_circle(Vector2(-4.0, 0.0), 1.6, Color(1.0, 1.0, 1.0, alpha))
	draw_rect(Rect2(-4.0, -1.5, 8.0, 3.0), Color(INK, alpha))
	draw_rect(Rect2(-3.5, -1.0, 7.0, 2.0), Color(ROCKET_HULL, alpha))
	draw_rect(Rect2(-3.5, 0.2, 7.0, 0.8), Color(ROCKET_HULL.darkened(0.3), alpha))
	draw_colored_polygon(
		PackedVector2Array([Vector2(4.0, -1.6), Vector2(4.0, 1.6), Vector2(7.5, 0.0)]),
		Color(KO_RED, alpha)
	)


## A point on the volley's own arc, at `lag` along it. What the rocket's smoke
## trail is laid along, so the puffs sit where the round actually was rather than
## on the straight line between the barrel and the target.
func _arced(lag: float) -> Vector2:
	var at := volley_from.lerp(volley_to, lag)
	at.y -= sin(lag * PI) * volley_arc
	return at


## A bomb: small, dark, and falling — the only round in the game whose shape
## reads vertically, because it is the only one that arrives from above.
func _draw_bomb(at: Vector2, tint: Color) -> void:
	draw_circle(at, 4.5, Color(INK, tint.a))
	draw_circle(at + Vector2(0.0, -1.0), 3.0, tint)
	draw_rect(Rect2(at.x - 1.5, at.y + 3.0, 3.0, 5.0), Color(INK, tint.a * 0.8))


## A torpedo, run flat under the waterline: the head is barely visible and the
## wake behind it is what the eye actually follows.
func _draw_torpedo(at: Vector2, toward: float, tint: Color) -> void:
	var depth := at + Vector2(0.0, WAKE_DEPTH)
	for trail in 5:
		var back := depth - Vector2(toward * (8.0 + trail * 11.0), 0.0)
		var foam := clampf(0.6 - trail * 0.11, 0.0, 1.0)
		draw_rect(
			Rect2(back.x - 5.0, back.y - 1.5 + trail * 0.5, 10.0, 3.0 - trail * 0.4),
			Color(1.0, 1.0, 1.0, foam * tint.a)
		)
	draw_circle(depth, 4.0, Color(INK, tint.a * 0.75))
	draw_circle(depth, 2.5, tint)


## What one alight barrel looks like. One per standing figure, so a full squad
## lights up along its whole front and a lone survivor gives off a single flash.
##
## A launcher is the one that differs: a tube vents as much backwards as forwards,
## so it gets a round flash and a cone of backblast out of its own rear instead of
## a gun's four-pointed star.
func _draw_muzzle(at: Vector2) -> void:
	if muzzle_radius <= 0.0:
		return
	if muzzle_kind == BattleStyle.ROCKET:
		# Three rings falling off rather than one disc: a tube lights the air around
		# it, and a hard edge on that reads as a painted dot.
		_draw_backblast(at)
		draw_circle(at, muzzle_radius, Color(FLASH_GOLD, 0.35))
		draw_circle(at, muzzle_radius * 0.72, Color(FLASH_GOLD, 0.8))
		draw_circle(at, muzzle_radius * 0.38, Color(1.0, 1.0, 1.0, 0.95))
		return
	var points := PackedVector2Array()
	for i in 8:
		var reach := muzzle_radius if i % 2 == 0 else muzzle_radius * 0.32
		var angle := float(i) * PI / 4.0
		points.append(at + Vector2(cos(angle), sin(angle)) * reach)
	draw_colored_polygon(points, FLASH_GOLD)
	draw_circle(at, muzzle_radius * 0.35, Color(1.0, 1.0, 1.0, 0.95))


## The wedge of exhaust out of the back of a launch tube, widening away from it.
func _draw_backblast(at: Vector2) -> void:
	var back := -muzzle_toward
	var reach := muzzle_radius * BACKBLAST_REACH
	var flare := muzzle_radius * BACKBLAST_FLARE
	draw_colored_polygon(
		PackedVector2Array(
			[
				at + Vector2(0.0, -muzzle_radius * 0.4),
				at + Vector2(0.0, muzzle_radius * 0.4),
				at + Vector2(back * reach, flare),
				at + Vector2(back * reach, -flare),
			]
		),
		Color(ROCKET_HULL, 0.32)
	)


## What the hit looks like on the receiving side, keyed to the weapon that landed
## — the other half of "the shot is chosen by matchup": a tank strafing infantry
## has to leave sparks stitched across them, and the same tank shelling a tank has
## to leave a hole. Suppressed entirely when the shot cost the target nothing, and
## kept well under the kill blast, which owns the frame when it comes.
func _draw_impact() -> void:
	if impact_style.impact_radius <= 0.0:
		_draw_sparks()
		return
	var reach := ramp(impact_p, [0.0, 0.35, 1.0], [0.0, 1.0, 0.78]) * impact_style.impact_radius
	var alpha := ramp(impact_p, [0.0, 0.15, 0.75, 1.0], [0.0, 1.0, 0.55, 0.0])
	_draw_smoke_squares(alpha)
	# Torn rings rather than nested discs, for the reason the kill blast gives
	# below: three concentric circles at this size read as a bullseye.
	_draw_flare(impact_at, reach, Color(KO_RED, alpha * 0.9), 0.0, IMPACT_SPOKES)
	_draw_flare(impact_at, reach * 0.62, Color(FLASH_GOLD, alpha), 0.4, IMPACT_SPOKES)
	_draw_flare(impact_at, reach * 0.3, Color(1.0, 1.0, 1.0, alpha), 0.8, IMPACT_SPOKES)


## Four squares of smoke thrown up out of the burst along a fan and lifting as they
## go, so the hit leaves something behind rather than simply switching off.
func _draw_smoke_squares(alpha: float) -> void:
	var reach := ramp(impact_p, [0.0, 1.0], [3.0, impact_style.impact_radius * 1.06])
	for i in SMOKE_COUNT:
		var angle := -PI * 0.5 + (i - (SMOKE_COUNT - 1) * 0.5) * SMOKE_FAN
		var at := (
			impact_at
			+ Vector2(cos(angle), sin(angle)) * reach
			+ Vector2(0.0, -impact_p * SMOKE_LIFT)
		)
		draw_rect(
			Rect2(at - Vector2(SMOKE_SIZE, SMOKE_SIZE) * 0.5, Vector2(SMOKE_SIZE, SMOKE_SIZE)),
			Color(SMOKE_TINT, alpha * 0.8)
		)


## A stream's impact: spark ticks flickering across the target, and no burst at
## all. Many small hits arriving one after another is the whole read, so each tick
## blinks on its own beat of the impact rather than fading in step with the rest.
func _draw_sparks() -> void:
	var alpha := ramp(impact_p, [0.0, 0.8, 1.0], [1.0, 1.0, 0.0])
	for i in SPARK_COUNT:
		if (int(impact_p * SPARK_FLICKER) + i) % 3 == 0:
			continue
		draw_colored_polygon(_spark_points(impact_at + _scatter(i)), Color(SPARK_TINT, alpha))


## Where one tick lands, either way of the hit. Arithmetic off the index with two
## steps that stride most of the way across their spans each time, which is what
## makes five ticks read as a stitch across the target — coprimality alone only
## buys "never repeats", and a step of ±1 mod its span never repeats either while
## laying the ticks down in one tight diagonal. The steps belong to *these* spans:
## the reference used 53 and 29 against spans of 36 and 30, and halving the
## spreads for a 640px stage is what left them reduced to ±1. Being arithmetic
## rather than a roll, a posed still catches the same five every run.
static func _scatter(index: int) -> Vector2:
	return Vector2(
		float((index * 7) % int(SPARK_SPREAD.x * 2.0)) - SPARK_SPREAD.x,
		float((index * 5) % int(SPARK_SPREAD.y * 2.0)) - SPARK_SPREAD.y
	)


## One tick: a small four-pointed star, the same silhouette as a muzzle flash and
## deliberately so — a spark is a round going off where it landed.
static func _spark_points(at: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 8:
		var reach := SPARK_SIZE if i % 2 == 0 else SPARK_SIZE * 0.35
		var angle := float(i) * PI / 4.0
		points.append(at + Vector2(cos(angle), sin(angle)) * reach)
	return points


## The kill blast: a shock ring running out ahead of a ragged fireball, debris
## thrown clear on a ballistic arc, and smoke left rising behind it. Original and
## procedural — no explosion sheet, which is the fence D2 puts around this whole
## feature.
##
## The fireball is a jagged star rather than a disc on purpose: nested circles
## read as a bullseye at this size, and a torn silhouette reads as a blast.
func _draw_blast() -> void:
	var ring := ramp(blast_p, [0.0, 1.0], [14.0, 104.0])
	var ring_alpha := ramp(blast_p, [0.0, 0.3, 1.0], [0.9, 0.28, 0.0])
	draw_arc(blast_at, ring, 0.0, TAU, 28, Color(1.0, 1.0, 1.0, ring_alpha), 2.0)
	_draw_debris()
	_draw_smoke()
	var core := ramp(blast_p, [0.0, 0.22, 1.0], [4.0, 54.0, 18.0])
	var core_alpha := ramp(blast_p, [0.0, 0.15, 0.7, 1.0], [0.0, 1.0, 0.6, 0.0])
	_draw_flare(blast_at, core, Color(KO_RED, core_alpha * 0.9), 0.0, BLAST_SPOKES)
	_draw_flare(blast_at, core * 0.68, Color(FLASH_GOLD, core_alpha), 0.42, BLAST_SPOKES)
	_draw_flare(blast_at, core * 0.34, Color(1.0, 1.0, 1.0, core_alpha), 0.84, BLAST_SPOKES)


## One ragged ring of a fireball: alternating long and short spokes, rotated so
## stacked layers do not line their teeth up. Shared by the weapon's impact burst
## and the kill blast, which is why nothing here knows which it is drawing — only
## how big, how torn and how bright.
func _draw_flare(at: Vector2, reach: float, tint: Color, turn: float, spokes: int) -> void:
	if reach <= 0.0 or tint.a <= 0.0:
		return
	var points := PackedVector2Array()
	for i in spokes:
		var angle := turn + float(i) * TAU / spokes
		var length := reach if i % 2 == 0 else reach * 0.66
		points.append(at + Vector2(cos(angle), sin(angle) * 0.86) * length)
	draw_colored_polygon(points, tint)


## Wreckage thrown clear: out fast, then dragged down, so it arcs instead of
## sliding along a straight line out of the fireball.
func _draw_debris() -> void:
	var alpha := ramp(blast_p, [0.0, 0.1, 0.75, 1.0], [0.0, 1.0, 0.9, 0.0])
	for i in 12:
		var angle := float(i) * TAU / 12.0 + (i % 3) * 0.17
		var reach := ramp(blast_p, [0.0, 0.6, 1.0], [4.0, 58.0 + (i % 4) * 16.0, 96.0])
		var drop := blast_p * blast_p * 54.0
		var at := blast_at + Vector2(cos(angle), sin(angle) * 0.7) * reach + Vector2(0.0, drop)
		var chip := 7.0 - (i % 3) * 1.5
		draw_rect(
			Rect2(at - Vector2(chip, chip) * 0.5, Vector2(chip, chip)),
			Color(FLASH_GOLD if i % 2 == 0 else KO_RED, alpha)
		)


## What is left over the wreck once the fire is out.
func _draw_smoke() -> void:
	var alpha := ramp(blast_p, [0.0, 0.35, 0.7, 1.0], [0.0, 0.0, 0.45, 0.0])
	if alpha <= 0.0:
		return
	for i in 4:
		var lift := ramp(blast_p, [0.35, 1.0], [0.0, 34.0 + i * 9.0])
		var at := blast_at + Vector2((i - 1.5) * 15.0, -lift)
		draw_circle(at, 13.0 + i * 2.5, Color(0.35, 0.34, 0.36, alpha))


## The damage that landed, rising and fading over the side it landed on. Scaled
## through a quick overshoot so it punches rather than drifts.
func _draw_callout(at: Vector2, amount: int, tag: String, progress: float) -> void:
	if progress <= 0.0 or progress >= 1.0:
		return
	var font := get_theme_font(&"font", &"Label")
	var rise := ramp(progress, [0.0, 0.3, 1.0], [10.0, -8.0, -26.0])
	var punch := ramp(progress, [0.0, 0.25, 1.0], [0.4, 1.2, 1.0])
	var alpha := ramp(progress, [0.0, 0.15, 0.7, 1.0], [0.0, 1.0, 1.0, 0.0])
	var origin := at + Vector2(0.0, rise)
	draw_set_transform(origin, 0.0, Vector2(punch, punch))
	if tag != "":
		var tag_width := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		var tag_tint := KO_RED if tag == KO_TAG else FLASH_GOLD
		_stroked(font, Vector2(-tag_width * 0.5, -18.0), tag, 15, Color(tag_tint, alpha))
	if amount > 0:
		var text := "-%d" % amount
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		_stroked(font, Vector2(-width * 0.5, 8.0), text, 26, Color(1.0, 1.0, 1.0, alpha))
	draw_set_transform(Vector2.ZERO)


func _draw_vs() -> void:
	var font := get_theme_font(&"font", &"Label")
	var width := font.get_string_size("VS", HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	_stroked(
		font,
		Vector2(size.x * 0.5 - width * 0.5, size.y * 0.5 + 8.0),
		"VS",
		22,
		Color(1.0, 1.0, 1.0, vs_alpha)
	)


## Outlined text. Everything the overlay prints sits over moving art, so nothing
## is ever drawn without a stroke around it.
func _stroked(font: Font, at: Vector2, text: String, font_size: int, tint: Color) -> void:
	draw_string_outline(
		font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(INK, tint.a)
	)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)


## Piecewise linear interpolation over matched stop/value lists — the one shape
## every eased value in the cut-in is written as, here and in the director.
static func ramp(at: float, stops: Array, values: Array) -> float:
	for i in range(1, stops.size()):
		if at <= stops[i]:
			var span: float = stops[i] - stops[i - 1]
			var t: float = 0.0 if span <= 0.0 else (at - stops[i - 1]) / span
			return lerpf(values[i - 1], values[i], t)
	return values[values.size() - 1]
