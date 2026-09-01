class_name CombatCutscene
extends CutsceneDirector
## The battle cut-in: when an attack resolves, the board gives way to a
## full-screen versus frame — attacker on the left, defender on the right, each
## posed over its own terrain — the volley crosses, HP ticks down, the counter
## comes back, and the map returns.
##
## It replays; it never decides (plan D1). Every number below comes off the
## CombatSnapshot.CombatResult it is handed — the HP each side went in and came
## out with, the weapon each fired, whether the opening shot was lobbed — and the
## units themselves are read only for what they *are*: type, team, cell. Nothing
## here touches the damage chart, the RNG, or a rule.
##
## One clock, one exit — both `CutsceneDirector`'s, held rather than repeated.
## Every visual below is a pure function of `_play.t`, so skipping is the clock
## jumping to its end rather than a race between cancelled tweens, and the
## awaitable `play()` resolves exactly once whatever the player presses (plan R2).
## The randomness in the shake is a function of the clock too, so a posed frame is
## the same frame every run (R4). What the beat sheet *is* belongs to CombatBeats,
## which is Node-free and therefore checkable without a scene; this file owns what
## goes in the band, and the lifecycle and the shell around it — letterbox, dim,
## camera punch, cue ledger — are shared with CaptureCutscene.

## How far each half slides in from its own edge.
const SLIDE_PX := 60.0
## The band shake's two frequencies. Deliberately not the capture cut-in's 90/76 —
## see CutscenePlayback.frame_band for why the drift is carried rather than fixed.
const SHAKE_FREQ := Vector2(91.0, 77.0)
## How much higher an indirect weapon lobs its round than the same style fired
## flat. Artillery, Rockets and Missiles all share a style with something that
## shoots straight, and the arc is what tells them apart at a glance — so which
## shot it was is `CombatResult.attacker_indirect`, AttackRange's answer taken
## when the shot resolved, rather than a question asked again here.
##
## Held well under a doubling because the styles' own arcs are no longer flat: a
## rocket lobs high on its own now, and multiplying that again put a rocket battery's
## round through the top of the band.
const INDIRECT_LOB := 1.5
## How long a barrel stays alight after it fires. A sustained weapon ignores this
## and burns for its whole volley instead — see `_flashing`.
const FLASH_HOLD := 0.12
## How long the band's entry push is held at full before it eases off. It opens
## with the arrive, which is where the halves have finished sliding in.
const PUSH_HOLD := 0.3

var _atk: CutsceneSide
var _def: CutsceneSide
var _fx: CutsceneFx

var _beats := CombatBeats.new()
var _result: CombatSnapshot.CombatResult
## The two weapon signatures this exchange fires with. Read from data, never
## decided here — see BattleStyle.
var _styles: BattleStyleDB
var _atk_style: BattleStyle
var _def_style: BattleStyle


func _ready() -> void:
	_build()
	_styles = BattleStyleDB.shared()
	_play.root.hide()


# --- playing -----------------------------------------------------------------


## Plays one already-resolved exchange and returns when the map is back.
## Awaitable: both call sites hold the interaction flow on it.
##
## The animator punches the board in on its way here; the cut-in eases that flinch
## back out over the closing wipe, through the view (see CutscenePlayback).
func play(result: CombatSnapshot.CombatResult, attacker: Unit, defender: Unit) -> void:
	_pose(result, attacker, defender)
	run()
	await finished


## Freezes the cut-in at one moment of its own clock and leaves it there, for a
## capture (plan D6). No clock runs, no sound plays, and `finished` is never
## emitted — this is a still, not a playthrough, which is exactly what makes it
## byte-stable: every value on screen is a function of the `at` handed in.
##
## Dev-only. The scenario driver is the one caller; play never poses.
func pose_at(
	result: CombatSnapshot.CombatResult, attacker: Unit, defender: Unit, at: float
) -> void:
	_pose(result, attacker, defender)
	hold(at)


## The two halves, so a posed still can be read back. Dev-only, like `pose_at`
## and for the same caller: the scenario driver checks that each half is painted
## in the faction row SideIdentity gives its side (COM-10), and a check that
## re-derived the answer from the director's own fields would prove nothing.
func attacker_side() -> CutsceneSide:
	return _atk


func defender_side() -> CutsceneSide:
	return _def


# --- staging -----------------------------------------------------------------


## Poses both halves and works out the beat windows this exchange has.
func _pose(result: CombatSnapshot.CombatResult, attacker: Unit, defender: Unit) -> void:
	_result = result
	_atk_style = _styles.for_weapon(attacker.type, result.attacker_weapon_slot)
	_def_style = _styles.for_weapon(defender.type, result.counter_weapon_slot)
	_play.accent = accent_of(attacker.team)
	var atk_terrain := _terrain_at(attacker.cell)
	var def_terrain := _terrain_at(defender.cell)
	_atk.bind(
		attacker,
		_row_of(attacker.team),
		atk_terrain,
		_paving_for(atk_terrain),
		_owner_row_at(attacker.cell),
		false,
		_play.accent
	)
	_def.bind(
		defender,
		_row_of(defender.team),
		def_terrain,
		_paving_for(def_terrain),
		_owner_row_at(defender.cell),
		true,
		accent_of(defender.team)
	)
	# The chip names the weapon the *rules* selected, read straight off the style
	# the snapshotted slot resolved to. A defender that never answered gets none:
	# there is nothing for it to be shooting with.
	_atk.weapon_label = String(_atk_style.label)
	_def.weapon_label = String(_def_style.label) if result.countered else ""
	_atk.hp_shown = result.attacker_hp_before
	_def.hp_shown = result.defender_hp_before
	_squads(_atk, result.attacker_hp_before, result.attacker_hp_after, result.attacker_died)
	_squads(_def, result.defender_hp_before, result.defender_hp_after, result.defender_died)
	# How fast the clock this sheet will be played on runs, read once here and
	# never again: CombatBeats stretches the wind-up against it, and a rate read
	# per frame would re-plan the sheet mid-run. `FastForward` is deliberately out
	# — the player holding it has asked for the compression.
	var rate := Settings.speed.cutscene_rate() * speed
	_beats = CombatBeats.plan(result, _atk_style, _def_style, clampf(tail_scale, 0.0, 1.0), rate)


## How many figures a side posts and how many it keeps. A side that dies keeps
## all of them: the blast is what takes it, and toppling them first would leave
## the explosion going off over an empty patch of ground.
static func _squads(side: CutsceneSide, before: int, after: int, died: bool) -> void:
	side.squad_was = CutsceneSide.figures_for(before)
	side.squad_now = side.squad_was if died else CutsceneSide.figures_for(after)


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


## What paves the floor under a cell: the cell's own terrain where that art is a
## surface, and the surface it names where the art is an object that stands on one
## instead. Resolved here rather than in the side, which is handed everything it
## draws — and falling back to the terrain itself, so a board naming a paving that
## does not exist stages the way it always did rather than not at all.
func _paving_for(of: TerrainType) -> TerrainType:
	if not of.stands_in_cutin():
		return of
	var paving := view.db.by_id(of.cutin_ground)
	if paving == null:
		push_warning(
			"CombatCutscene: %s paves with unknown terrain '%s'" % [of.id, of.cutin_ground]
		)
		return of
	return paving


## The cell's terrain. An attacker fires from the cell it has already been moved
## to — the command applied before the animator was called — so this is the
## ground the shot was actually taken from, not the one it started the turn on.
func _terrain_at(cell: Vector2i) -> TerrainType:
	return view.map.terrain_at(cell)


## How long this exchange runs: the beat sheet's own end.
func _total() -> float:
	return _beats.total


# --- the frame ---------------------------------------------------------------


## Everything the cut-in shows — sounds go through `_play.cue`, which is what
## keeps a beat crossed twice heard once.
func _apply() -> void:
	var present := clampf(_play.window(_beats.wipe_in) - _play.window(_beats.wipe_out), 0.0, 1.0)
	var plates := _play.window(_beats.plates) * present
	_play.frame(present, _beats.wipe_out)
	_frame_band(present)

	var arrive := _play.window(_beats.arrive)
	var def_hit := _play.window(_beats.def_impact)
	var atk_hit := _play.window(_beats.atk_impact)
	var def_gone := _play.window(_beats.def_death)
	var atk_gone := _play.window(_beats.atk_death)

	_atk.clock = _play.t
	_atk.plate_p = plates
	_atk.arrive_p = arrive
	_atk.aim_p = _play.window(_beats.atk_ready)
	_atk.lunge = _lunge(_play.window(_beats.atk_recoil), _atk_style.recoil)
	_atk.flash = maxf(0.0, 1.0 - atk_hit / 0.3) if atk_hit > 0.0 else 0.0
	_atk.hp_shown = _tick(_result.attacker_hp_before, _result.attacker_hp_after, atk_hit)
	_atk.casualty_p = _play.window(_beats.atk_casualty)
	_atk.casualty_lost = _beats.atk_lost
	_atk.squad_alpha = 1.0 - atk_gone
	_style_pose(_atk, _atk_style)
	_atk.queue_redraw()

	_def.clock = _play.t
	_def.plate_p = plates
	_def.arrive_p = arrive
	_def.aim_p = _play.window(_beats.ctr_ready)
	_def.lunge = _lunge(_play.window(_beats.def_recoil), _def_style.recoil)
	_def.flash = maxf(0.0, 1.0 - def_hit / 0.3) if def_hit > 0.0 else 0.0
	_def.hp_shown = _tick(_result.defender_hp_before, _result.defender_hp_after, def_hit)
	_def.casualty_p = _play.window(_beats.def_casualty)
	_def.casualty_lost = _beats.def_lost
	_def.squad_alpha = 1.0 - def_gone
	_style_pose(_def, _def_style)
	_def.queue_redraw()

	_frame_fx(present)
	_sound()


## The look numbers a half draws its arrive, its wind-up and its scuff with —
## the style's own, copied on beside the beat progress above so both halves are
## posed from one place.
static func _style_pose(side: CutsceneSide, style: BattleStyle) -> void:
	side.aim_lift = style.aim_lift
	side.aim_pitch = style.aim_pitch
	side.arrive_scale = style.arrive_scale
	side.dust = style.dust


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
	var push := Vector2(_beats.arrive.x, _beats.arrive.x + PUSH_HOLD)
	_play.frame_band(present, jolt, SHAKE_FREQ, _play.window(push))


## Which side is firing, what it is firing, and where the blast goes off. Only
## one volley is ever in the air: the counter cannot start until the first has
## landed, which is the beat sheet's shape, not a rule enforced here.
func _frame_fx(present: float) -> void:
	var outgoing := _play.window(_beats.atk_travel)
	var returning := _play.window(_beats.def_travel)
	_fx.volley_p = 0.0
	_fx.volley_style = null
	_fx.volley_lead = PackedFloat32Array()
	if outgoing > 0.0 and outgoing < 1.0:
		_aim(_atk, _def, outgoing, _atk_style, _result.attacker_indirect)
	elif returning > 0.0 and returning < 1.0:
		# A counter is fired at adjacency by rule, so it is never a lob — which is
		# why the result snapshots the opening shot's stance and no other.
		_aim(_def, _atk, returning, _def_style, false)
	_fx.muzzles = PackedVector2Array()
	_fx.muzzle_lit = PackedFloat32Array()
	_fx.muzzle_radius = 0.0
	_fx.muzzle_kind = BattleStyle.NONE
	if _flashing(_beats.atk_fire, _beats.atk_travel, _atk_style) and _atk_style.fires():
		_flash_barrels(_atk, _def, _atk_style)
	elif _flashing(_beats.def_fire, _beats.def_travel, _def_style) and _def_style.fires():
		_flash_barrels(_def, _atk, _def_style)
	_frame_impact()
	var def_gone := _play.window(_beats.def_death)
	_fx.blast_p = def_gone if def_gone > 0.0 else _play.window(_beats.atk_death)
	_fx.blast_at = (
		_def.position + _def.center_point()
		if def_gone > 0.0
		else (_atk.position + _atk.center_point())
	)
	_fx.vs_alpha = present * (1.0 - clampf(_play.t / maxf(_beats.atk_fire, 0.01), 0.0, 1.0))
	_fx.def_amount = _result.defender_hp_before - _result.defender_hp_after
	_fx.def_tag = CutsceneFx.KO_TAG if _result.defender_died else ""
	_fx.def_p = _play.window(CombatBeats.callout_window(_beats.def_impact, _beats.def_death))
	_fx.def_at = _head_of(_def)
	_fx.atk_amount = _result.attacker_hp_before - _result.attacker_hp_after
	_fx.atk_tag = CutsceneFx.KO_TAG if _result.attacker_died else ""
	_fx.atk_p = _play.window(CombatBeats.callout_window(_beats.atk_impact, _beats.atk_death))
	_fx.atk_at = _head_of(_atk)
	_fx.modulate.a = present
	_fx.queue_redraw()


## Points the volley from the front rank of one squad at the middle of the
## other's, so a burst converges on what it is shooting at rather than at one
## figure of it.
func _aim(
	from: CutsceneSide, at: CutsceneSide, progress: float, style: BattleStyle, lobbed: bool
) -> void:
	var barrels := from.muzzle_points()
	var origin := (
		from.position + barrels[barrels.size() - 1]
		if not barrels.is_empty()
		else from.position + from.center_point()
	)
	_fx.volley_p = progress
	_fx.volley_style = style
	_fx.volley_figures = maxi(barrels.size(), 1)
	_fx.volley_arc = style.arc * (INDIRECT_LOB if lobbed else 1.0)
	_fx.volley_from = origin
	_fx.volley_to = at.position + at.center_point()


## Lights every standing figure's barrel on the firing side, pointed at the other.
func _flash_barrels(side: CutsceneSide, at_side: CutsceneSide, style: BattleStyle) -> void:
	var points := PackedVector2Array()
	for at in side.muzzle_points():
		points.append(side.position + at)
	_fx.muzzles = points
	_fx.muzzle_radius = style.muzzle
	_fx.muzzle_kind = style.projectile
	_fx.muzzle_toward = signf(
		(at_side.position + at_side.center_point()).x - (side.position + side.center_point()).x
	)


## The mark the landing volley leaves on whoever took it. Only one is ever up, for
## the same reason only one volley is: the counter cannot start until the opening
## shot has landed.
##
## A shot that cost the target nothing leaves nothing — the frame still shakes and
## the squad still flinches, because being shot at is not the same as being missed
## by nobody, but there is no hole to draw. `attack_damage` is the sim's own
## number, read rather than re-derived from the HP snapshots.
func _frame_impact() -> void:
	var def_hit := _play.window(_beats.def_impact)
	var atk_hit := _play.window(_beats.atk_impact)
	_fx.impact_p = 0.0
	_fx.impact_style = null
	_fx.impact_debris = 0
	if def_hit > 0.0 and def_hit < 1.0 and _result.attack_damage > 0:
		_fx.impact_p = def_hit
		_fx.impact_style = _atk_style
		_fx.impact_at = _def.position + _def.center_point()
	elif atk_hit > 0.0 and atk_hit < 1.0 and _result.counter_damage > 0:
		_fx.impact_p = atk_hit
		_fx.impact_style = _def_style
		_fx.impact_at = _atk.position + _atk.center_point()


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


## Pull back, then thrust, then settle — the recoil the volley leaves on, scaled
## by how much of it the weapon earns. A cannon slams its hull back and a machine
## gun barely twitches, which is the difference between the two reads of the same
## tank the whole feature is about.
##
## `progress` is the recoil window CombatBeats sized, which ends as the barrel
## lights rather than spanning the whole wind-up: the ramp is the shot being
## taken, not the aim being held.
static func _lunge(progress: float, recoil: float) -> float:
	if progress <= 0.0:
		return 0.0
	return CutsceneFx.ramp(progress, [0.0, 0.4, 0.7, 1.0], [0.0, -7.0, 13.0, 5.0]) * recoil


## HP holds for the first third of the impact, then runs down to the number the
## sim already committed. Rounded to whole displayed HP so the pips and the
## squad can never disagree about how many are left.
static func _tick(before: int, after: int, progress: float) -> int:
	if progress <= 0.0:
		return before
	return roundi(lerpf(before, after, clampf((progress - 0.35) / 0.65, 0.0, 1.0)))


## True while a barrel is alight. A gun flashes once as the round leaves; a burst
## weapon burns for its whole volley, strobing — it is firing the entire time its
## stream is in the air, and one flash at the front of that reads as a single shot.
##
## The strobe is a function of the clock like everything else here, so a posed still
## catches it mid-cycle at the same point every run.
func _flashing(at: float, travel: Vector2, style: BattleStyle) -> bool:
	if at <= 0.0 or _play.t < at:
		return false
	if not style.sustained:
		return _play.t < at + FLASH_HOLD
	if _play.t >= travel.y:
		return false
	return int(_play.t * CutsceneFx.STROBE_HZ * 2.0) % 2 == 0


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
