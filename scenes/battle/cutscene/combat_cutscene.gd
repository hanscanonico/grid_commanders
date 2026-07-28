class_name CombatCutscene
extends CanvasLayer
## The battle cut-in: when an attack resolves, the board gives way to a
## full-screen versus frame — attacker on the left, defender on the right, each
## posed over its own terrain — the volley crosses, HP ticks down, the counter
## comes back, and the map returns.
##
## It replays; it never decides (plan D1). Every beat below is driven by a field
## of the CombatResolver.CombatResult it is handed, including the two HP
## snapshots that exist for exactly this — by the time the cut-in runs, the
## command has applied and both units hold post-combat HP. Nothing here touches
## the damage chart, the RNG, or a rule.
##
## One clock, one exit — both `CutscenePlayback`'s, held rather than repeated.
## Every visual below is a pure function of `_play.t`, so skipping is the clock
## jumping to its end rather than a race between cancelled tweens, and the
## awaitable `play()` resolves exactly once whatever the player presses (plan R2).
## The randomness in the shake is a function of the clock too, so a posed frame is
## the same frame every run (R4). This file owns the beat sheet and what goes in
## the band; the shell around it — letterbox, dim, camera punch, cue ledger — is
## shared with CaptureCutscene.
##
## Owned by Battle, which assigns `view` and hands it to the animator — the same
## assignment-not-constructor shape BattleView and BattleAnimator use, so the
## cut-in never learns what a Battle is either.

## Emitted once per cut-in, when the wipe has cleared and control belongs to the
## caller again. Every branch funnels through `_finish`, which is the only place
## that emits it.
signal finished

## Beat budgets, in seconds. A clean kill runs ~1.8 s and a full exchange with a
## counter ~2.3 s, which is the tempo the plan's beat sheet asks for: long enough
## to read, short enough to sit through two hundred times.
const WIPE_IN := 0.20
const PLATES := 0.22
const ANTICIPATION := 0.16
const TRAVEL := 0.29
const IMPACT := 0.40
const DEATH := 0.35
const HOLD := 0.25
const WIPE_OUT := 0.20
## The hold can be trimmed away entirely when the pacing asks for it, but the
## wipe cannot: a cut-in that vanishes on one frame reads as a glitch rather than
## as a fast exit.
const MIN_WIPE_SCALE := 0.4

## How far each half slides in from its own edge.
const SLIDE_PX := 60.0
## The band shake's two frequencies. Deliberately not the capture cut-in's 90/76 —
## see CutscenePlayback.frame_band for why the drift is carried rather than fixed.
const SHAKE_FREQ := Vector2(91.0, 77.0)
## How much higher an indirect weapon lobs its round than the same style fired
## flat. Artillery, Rockets and Missiles all share a style with something that
## shoots straight, and the arc is what tells them apart at a glance — so it is
## asked of AttackRange, the single authority on who is indirect, rather than
## re-derived from min_range here.
const INDIRECT_LOB := 2.6


## The windows every beat is read out of, in seconds from the wipe. A window of
## zero length is a beat this exchange does not have — an unanswered volley has
## no counter, a survivor has no death.
class Beats:
	var atk_ready := Vector2.ZERO
	var atk_fire := 0.0
	var atk_travel := Vector2.ZERO
	var def_impact := Vector2.ZERO
	var def_death := Vector2.ZERO
	var ctr_ready := Vector2.ZERO
	var def_fire := 0.0
	var def_travel := Vector2.ZERO
	var atk_impact := Vector2.ZERO
	var atk_death := Vector2.ZERO
	var wipe_out := Vector2.ZERO
	var total := 0.0


## The board the exchange is fought on. Assigned by Battle before first use. The
## cut-in reads exactly two things off it — the terrain each side stands on and
## who owns that cell — which is what dresses each half's ground strip.
var view: BattleView
## Playback rate, and how much of the closing hold and wipe is kept. Both are
## the AI-pacing levers (BA4): a side attacking over and over gets a faster
## cut-in with most of its ceremony cut away, while the beats that carry the
## information — the volley, the impact, the tick — keep their full length at
## every setting, because those are what the animation is *for*. The animator
## sets them; see BattleAnimator.animate_combat.
var speed := 1.0
var tail_scale := 1.0

## The clock, the letterbox and the single exit, shared with CaptureCutscene. It
## also owns the board camera: the cut-in eases it from the entry flinch's zoom
## back to rest over the closing wipe, so the board is already at rest on the
## frame it is uncovered — no snap when `play` returns, and a skip lands the zoom
## home exactly as it lands every other value, because it too is a pure function
## of the clock.
var _play := CutscenePlayback.new()
var _atk: CutsceneSide
var _def: CutsceneSide
var _fx: CutsceneFx

var _beats := Beats.new()
var _result: CombatResolver.CombatResult
var _atk_hp_after := 0
var _def_hp_after := 0
## The two weapon signatures this exchange fires with. Read from data, never
## decided here — see BattleStyle.
var _styles := BattleStyleDB.new()
var _atk_style: BattleStyle
var _def_style: BattleStyle


func _ready() -> void:
	_build()
	_styles = BattleStyleDB.load_default()
	_play.root.hide()
	set_process(false)


# --- playing -----------------------------------------------------------------


## Plays one already-resolved exchange and returns when the map is back.
## Awaitable: both call sites hold the interaction flow on it.
##
## The animator hands over the punched-in camera and the zoom to return it to;
## the cut-in eases it home over the closing wipe (see CutscenePlayback). Left
## null — as the scenario driver leaves it — the camera is untouched.
func play(
	result: CombatResolver.CombatResult,
	attacker: Unit,
	defender: Unit,
	camera: Camera2D = null,
	resting_zoom := Vector2.ONE
) -> void:
	_pose(result, attacker, defender)
	_play.begin(_beats.total, camera, resting_zoom)
	_play.layout()
	_apply()
	_play.root.show()
	set_process(true)
	set_process_unhandled_input(true)
	await finished


## Freezes the cut-in at one moment of its own clock and leaves it there, for a
## capture (plan D6). No clock runs, no sound plays, and `finished` is never
## emitted — this is a still, not a playthrough, which is exactly what makes it
## byte-stable: every value on screen is a function of the `at` handed in.
##
## Dev-only. The scenario driver is the one caller; play never poses.
func pose_at(
	result: CombatResolver.CombatResult, attacker: Unit, defender: Unit, at: float
) -> void:
	_pose(result, attacker, defender)
	# A still never punched the camera; `pose` keeps `_apply` off it.
	_play.pose(_beats.total, at)
	_play.layout()
	_apply()
	_play.root.show()


## The two halves, so a posed still can be read back. Dev-only, like `pose_at`
## and for the same caller: the scenario driver checks that each half is painted
## in the faction row SideIdentity gives its side (COM-10), and a check that
## re-derived the answer from the director's own fields would prove nothing.
func attacker_side() -> CutsceneSide:
	return _atk


func defender_side() -> CutsceneSide:
	return _def


## Fast-forwards every remaining beat to its end state. Never aborts: the clock
## is simply set to the end, the final tableau is applied, and the same exit runs
## — which is what makes a skip at any beat land on the right board.
func skip() -> void:
	_play.skip()


func _process(delta: float) -> void:
	if not _play.playing:
		return
	var done := _play.advance(delta * speed)
	_apply()
	if done:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if _play.consume_skip(event):
		get_viewport().set_input_as_handled()


## The single exit. Every branch reaches it, and it emits once.
func _finish() -> void:
	if not _play.playing:
		return
	_play.end()
	set_process(false)
	set_process_unhandled_input(false)
	finished.emit()


# --- staging -----------------------------------------------------------------


## Poses both halves and works out the beat windows this exchange has.
func _pose(result: CombatResolver.CombatResult, attacker: Unit, defender: Unit) -> void:
	_result = result
	_atk_hp_after = attacker.displayed_hp()
	_def_hp_after = defender.displayed_hp()
	_atk_style = _styles.for_unit(attacker.type)
	_def_style = _styles.for_unit(defender.type)
	_play.accent = _accent_of(attacker.team)
	_atk.bind(
		attacker,
		_row_of(attacker.team),
		_terrain_at(attacker.cell),
		_owner_row_at(attacker.cell),
		false,
		_play.accent
	)
	_def.bind(
		defender,
		_row_of(defender.team),
		_terrain_at(defender.cell),
		_owner_row_at(defender.cell),
		true,
		_accent_of(defender.team)
	)
	_atk.hp_shown = result.attacker_hp_before
	_def.hp_shown = result.defender_hp_before
	_squads(_atk, result.attacker_hp_before, _atk_hp_after, result.attacker_died)
	_squads(_def, result.defender_hp_before, _def_hp_after, result.defender_died)
	_beats = _plan(
		result,
		TRAVEL * _atk_style.travel_scale,
		TRAVEL * _def_style.travel_scale,
		clampf(tail_scale, 0.0, 1.0)
	)


## How many figures a side posts and how many it keeps. A side that dies keeps
## all of them: the blast is what takes it, and toppling them first would leave
## the explosion going off over an empty patch of ground.
static func _squads(side: CutsceneSide, before: int, after: int, died: bool) -> void:
	side.squad_was = CutsceneSide.figures_for(before)
	side.squad_now = side.squad_was if died else CutsceneSide.figures_for(after)


## A side's accent colour, asked of the identity that resolved the match rather
## than of the commander directly. SideIdentity gives a commanded side its own
## faction's colour and a commander-less one the classic its slot falls back to —
## the same two answers as before — and it is the only one that knows about the
## mirror borrow: in an Iron v Iron the later side's army is drawn in a borrowed
## classic, so asking CommanderVisuals for its general's faction would put slate
## on both name plates, in the very frame the borrow exists to tell apart.
func _accent_of(team: int) -> Color:
	return view.identity.theme(team).color_light


## The atlas row a side's army is drawn in. Resolved here, beside the accent, and
## handed to the side — the two answers are the same identity's, so the figure in
## the cut-in and the sprite on the board can never disagree about whose army it
## is (Faction Identity plan D1: ask SideIdentity, never re-derive).
func _row_of(team: int) -> int:
	return view.identity.atlas_row(team)


## And the row the ground under a side is drawn in: the property's owner, resolved
## the same way. Row 0 for unowned and for plain terrain, which the side applies.
func _owner_row_at(cell: Vector2i) -> int:
	return view.identity.atlas_row(view.game.owner_at(cell))


## The cell's terrain. An attacker fires from the cell it has already been moved
## to — the command applied before the animator was called — so this is the
## ground the shot was actually taken from, not the one it started the turn on.
func _terrain_at(cell: Vector2i) -> TerrainType:
	return view.map.terrain_at(cell)


## The beat sheet, laid out on the clock. Reads only the result's flags, so an
## exchange with no counter is genuinely shorter rather than padded with a pause.
## The two travel budgets come from the firing styles — an arcing shell is given
## longer to get there than a burst of tracer — and `tail` trims the closing hold
## and wipe, which is the only part the pacing is allowed to take.
static func _plan(
	result: CombatResolver.CombatResult, atk_travel: float, def_travel: float, tail: float
) -> Beats:
	var beats := Beats.new()
	beats.atk_ready = Vector2(WIPE_IN, WIPE_IN + ANTICIPATION)
	beats.atk_fire = beats.atk_ready.y
	beats.atk_travel = Vector2(beats.atk_fire, beats.atk_fire + atk_travel)
	beats.def_impact = Vector2(beats.atk_travel.y - 0.02, beats.atk_travel.y - 0.02 + IMPACT)
	var settled := beats.def_impact.y
	if result.defender_died:
		beats.def_death = Vector2(settled - 0.05, settled - 0.05 + DEATH)
		settled = beats.def_death.y
	elif result.countered:
		beats.ctr_ready = Vector2(settled, settled + ANTICIPATION)
		beats.def_fire = beats.ctr_ready.y
		beats.def_travel = Vector2(beats.def_fire, beats.def_fire + def_travel)
		beats.atk_impact = Vector2(beats.def_travel.y - 0.02, beats.def_travel.y - 0.02 + IMPACT)
		settled = beats.atk_impact.y
		if result.attacker_died:
			beats.atk_death = Vector2(settled - 0.05, settled - 0.05 + DEATH)
			settled = beats.atk_death.y
	var hold := settled + HOLD * tail
	beats.wipe_out = Vector2(hold, hold + WIPE_OUT * maxf(tail, MIN_WIPE_SCALE))
	beats.total = beats.wipe_out.y
	return beats


# --- the frame ---------------------------------------------------------------


## Everything the cut-in shows, as a pure function of `_play.t`. Called once per
## frame while playing and once more by `skip`, which is why it may never do
## anything that only makes sense the first time — sounds go through `_play.cue`.
func _apply() -> void:
	var present := clampf(
		_play.window(Vector2(0.0, WIPE_IN)) - _play.window(_beats.wipe_out), 0.0, 1.0
	)
	var plates := _play.window(Vector2(WIPE_IN * 0.5, WIPE_IN * 0.5 + PLATES)) * present
	_play.frame(present, _beats.wipe_out)
	_frame_band(present)

	var atk_ready := _play.window(_beats.atk_ready)
	var ctr_ready := _play.window(_beats.ctr_ready)
	var def_hit := _play.window(_beats.def_impact)
	var atk_hit := _play.window(_beats.atk_impact)
	var def_gone := _play.window(_beats.def_death)
	var atk_gone := _play.window(_beats.atk_death)

	_atk.clock = _play.t
	_atk.plate_p = plates
	_atk.lunge = _lunge(atk_ready)
	_atk.flash = maxf(0.0, 1.0 - atk_hit / 0.3) if atk_hit > 0.0 else 0.0
	_atk.hp_shown = _tick(_result.attacker_hp_before, _atk_hp_after, atk_hit)
	_atk.fall_p = _play.window(_topple(_beats.atk_impact))
	_atk.squad_alpha = 1.0 - atk_gone
	_atk.queue_redraw()

	_def.clock = _play.t
	_def.plate_p = plates
	_def.lunge = _lunge(ctr_ready)
	_def.flash = maxf(0.0, 1.0 - def_hit / 0.3) if def_hit > 0.0 else 0.0
	_def.hp_shown = _tick(_result.defender_hp_before, _def_hp_after, def_hit)
	_def.fall_p = _play.window(_topple(_beats.def_impact))
	_def.squad_alpha = 1.0 - def_gone
	_def.queue_redraw()

	_frame_fx(present)
	_sound()


## The two halves slide in from their own edges, and the whole band pushes in
## slightly over the exchange with a decaying shake on every impact. The push and
## the shake are the shell's; which beats jolt it is this cut-in's alone.
func _frame_band(present: float) -> void:
	var half := _play.band.size.x * 0.5
	_atk.position = Vector2(-SLIDE_PX * (1.0 - present), 0.0)
	_def.position = Vector2(half + SLIDE_PX * (1.0 - present), 0.0)
	_atk.modulate.a = present
	_def.modulate.a = present
	var jolt := (
		CutscenePlayback.decay(_play.window(_beats.def_impact))
		+ CutscenePlayback.decay(_play.window(_beats.atk_impact))
		+ CutscenePlayback.decay(_play.window(_beats.def_death))
		+ CutscenePlayback.decay(_play.window(_beats.atk_death))
	)
	_play.frame_band(present, jolt, SHAKE_FREQ, _play.window(Vector2(WIPE_IN, WIPE_IN + 0.3)))


## Which side is firing, what it is firing, and where the blast goes off. Only
## one volley is ever in the air: the counter cannot start until the first has
## landed, which is the beat sheet's shape, not a rule enforced here.
func _frame_fx(present: float) -> void:
	var outgoing := _play.window(_beats.atk_travel)
	var returning := _play.window(_beats.def_travel)
	_fx.volley_p = 0.0
	_fx.volley_style = null
	if outgoing > 0.0 and outgoing < 1.0:
		_aim(_atk, _def, outgoing, _atk_style)
	elif returning > 0.0 and returning < 1.0:
		_aim(_def, _atk, returning, _def_style)
	_fx.muzzles = PackedVector2Array()
	_fx.muzzle_radius = 0.0
	if _flashing(_beats.atk_fire) and _atk_style.fires():
		_flash_barrels(_atk, _atk_style)
	elif _flashing(_beats.def_fire) and _def_style.fires():
		_flash_barrels(_def, _def_style)
	var def_gone := _play.window(_beats.def_death)
	_fx.blast_p = def_gone if def_gone > 0.0 else _play.window(_beats.atk_death)
	_fx.blast_at = (
		_def.position + _def.center_point()
		if def_gone > 0.0
		else (_atk.position + _atk.center_point())
	)
	_fx.vs_alpha = present * (1.0 - clampf(_play.t / maxf(_beats.atk_fire, 0.01), 0.0, 1.0))
	_fx.def_amount = _result.defender_hp_before - _def_hp_after
	_fx.def_tag = CutsceneFx.KO_TAG if _result.defender_died else ""
	_fx.def_p = _play.window(_callout(_beats.def_impact, _beats.def_death))
	_fx.def_at = _head_of(_def)
	_fx.atk_amount = _result.attacker_hp_before - _atk_hp_after
	_fx.atk_tag = CutsceneFx.KO_TAG if _result.attacker_died else ""
	_fx.atk_p = _play.window(_callout(_beats.atk_impact, _beats.atk_death))
	_fx.atk_at = _head_of(_atk)
	_fx.modulate.a = present
	_fx.queue_redraw()


## Points the volley from the front rank of one squad at the middle of the
## other's, so a burst converges on what it is shooting at rather than at one
## figure of it.
func _aim(from: CutsceneSide, at: CutsceneSide, progress: float, style: BattleStyle) -> void:
	var barrels := from.muzzle_points()
	var origin := (
		from.position + barrels[barrels.size() - 1]
		if not barrels.is_empty()
		else from.position + from.center_point()
	)
	_fx.volley_p = progress
	_fx.volley_style = style
	_fx.volley_figures = maxi(barrels.size(), 1)
	_fx.volley_arc = style.arc * (INDIRECT_LOB if AttackRange.is_indirect(from.unit) else 1.0)
	_fx.volley_from = origin
	_fx.volley_to = at.position + at.center_point()


## Lights every standing figure's barrel on the firing side.
func _flash_barrels(side: CutsceneSide, style: BattleStyle) -> void:
	var points := PackedVector2Array()
	for at in side.muzzle_points():
		points.append(side.position + at)
	_fx.muzzles = points
	_fx.muzzle_radius = style.muzzle


## Fires the shot and explosion sounds as their beats come up. Silent during a
## fast-forward — skipping past four beats should not play four sounds at once —
## and silent for a posed still, which has no beats to cross.
func _sound() -> void:
	if not _play.playing:
		return
	if _atk_style.fires():
		_play.cue(&"atk_fire", _beats.atk_fire, _atk_style.sfx)
	if _def_style.fires():
		_play.cue(&"def_fire", _beats.def_fire, _def_style.sfx)
	_play.cue(&"def_death", _beats.def_death.x, &"explosion")
	_play.cue(&"atk_death", _beats.atk_death.x, &"explosion")


# --- curves ------------------------------------------------------------------


## The window surplus figures topple over: it opens just after the round lands
## and closes with the impact, leaving room for the per-figure stagger.
static func _topple(impact: Vector2) -> Vector2:
	if impact.y <= impact.x:
		return Vector2.ZERO
	return Vector2(impact.x + 0.06, impact.y + 0.1)


## The window a damage callout is shown over: it outlives the impact, and a
## death holds it until the explosion has finished.
static func _callout(impact: Vector2, death: Vector2) -> Vector2:
	if impact.y <= impact.x:
		return Vector2.ZERO
	var end := (death.y if death.y > death.x else impact.y) + 0.3
	return Vector2(impact.x + 0.08, end)


## Pull back, then thrust, then settle — the recoil every volley opens with.
static func _lunge(ready: float) -> float:
	if ready <= 0.0:
		return 0.0
	return CutsceneFx.ramp(ready, [0.0, 0.4, 0.7, 1.0], [0.0, -7.0, 13.0, 5.0])


## HP holds for the first third of the impact, then runs down to the number the
## sim already committed. Rounded to whole displayed HP so the pips and the
## squad can never disagree about how many are left.
static func _tick(before: int, after: int, progress: float) -> int:
	if progress <= 0.0:
		return before
	return roundi(lerpf(before, after, clampf((progress - 0.35) / 0.65, 0.0, 1.0)))


## True for the few frames a barrel is alight after `at`.
func _flashing(at: float) -> bool:
	return at > 0.0 and _play.t >= at and _play.t < at + 0.09


## Just above a side's squad, in the overlay's coordinates — where that side's
## damage callout is anchored. Taken from the middle of a *full* squad, so the
## number does not drift sideways as figures fall out from under it.
static func _head_of(side: CutsceneSide) -> Vector2:
	return side.position + side.center_point() + Vector2(0.0, -56.0)


# --- nodes -------------------------------------------------------------------


## The shell, then this cut-in's own three draw layers inside its band, then the
## letterbox over all of them — the ordering the bars depend on to sit on top.
func _build() -> void:
	_play.build(self, _place_layers)
	_atk = CutsceneSide.new()
	_def = CutsceneSide.new()
	_fx = CutsceneFx.new()
	_play.band.add_child(_atk)
	_play.band.add_child(_def)
	_play.band.add_child(_fx)
	_play.build_bars()


## Re-places the two halves and the overlay whenever the shell re-measures the
## viewport, so the cut-in still frames correctly if the base resolution changes.
func _place_layers(band: Vector2) -> void:
	_atk.size = Vector2(band.x * 0.5, band.y)
	_def.size = _atk.size
	_fx.position = Vector2.ZERO
	_fx.size = band
