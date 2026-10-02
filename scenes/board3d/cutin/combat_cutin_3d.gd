class_name CombatCutin3D
extends CutsceneDirector
## The combat cut-in on the 3D board: the flat `CombatCutscene` re-staged as a
## 3D battle. The letterbox closes over the board, a white flash cuts to the
## stage — each side's squad on a patch of its own ground, attacker left — and
## the lens cuts on the beat sheet: a wide as the squads arrive, over the
## attacker's shoulder as it fires, onto the defender for the hits and the
## falls, the mirror pair for a counter, a closing wide; then the flash cuts
## back and the bars leave.
##
## It replays; it never decides. The windows are `CombatBeats.plan` exactly as
## the flat director asks for them, so the volley lands when the flat one does;
## every number is the `CombatResult`'s and every look the `BattleStyle` its
## weapon slot resolved to. One clock, one exit — `CutsceneDirector`'s — and
## every visual a pure function of `_play.t`: the lens (`CombatShots3D`), the
## squads (`StageSquad3D`), the rounds and bursts (`CombatVolley3D` into
## `CutinFx3D`), the plates (`CutinPlates3D`).

## Level with the flat cut-ins.
const LAYER := 2
## How far into the wipe the lens cuts to the stage, and back out of it.
const CUT_IN_SHARE := 0.45
const CUT_OUT_SHARE := 0.5
## The white flash over each cut: up just before it, gone a beat after.
const FLASH_LEAD := 0.04
const FLASH_TAIL := 0.16
const FLASH_ALPHA := 0.9
## How long a squad glows white after a volley lands, as a share of the impact.
const HIT_FLASH := 0.3

## The set, handed over by Board3D with the view.
var stage: CutinStage3D

var _result: CombatSnapshot.CombatResult
var _styles: BattleStyleDB
var _atk_style: BattleStyle
var _def_style: BattleStyle
var _atk_arrival: BattleStyle
var _def_arrival: BattleStyle
var _beats := CombatBeats.new()
var _shots: CombatShots3D
var _atk_plot: StagePlot3D
var _def_plot: StagePlot3D
var _atk: StageSquad3D
var _def: StageSquad3D
var _fx: CutinFx3D
var _plates: CutinPlates3D
var _flash: ColorRect


func _ready() -> void:
	layer = LAYER
	_play.build(self, _place_layers)
	_plates = CutinPlates3D.new()
	_play.band.add_child(_plates)
	_flash = ColorRect.new()
	_flash.color = Color(Color.WHITE, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_play.root.add_child(_flash)
	_play.build_bars()
	_styles = BattleStyleDB.shared()
	_play.root.hide()
	finished.connect(_on_finished)


## Plays one resolved exchange and returns when the board is back. Awaitable,
## as the flat director's `play` is.
func play(result: CombatSnapshot.CombatResult, attacker: Unit, defender: Unit) -> void:
	_pose(result, attacker, defender)
	stage.rolling = true
	run()
	await finished


## Freezes the cut-in at `at` on its own clock, for a capture. Dev-only; the
## scenario driver is the one caller.
func pose_at(
	result: CombatSnapshot.CombatResult, attacker: Unit, defender: Unit, at: float
) -> void:
	_pose(result, attacker, defender)
	hold(at)


func _on_finished() -> void:
	stage.leave()
	stage.rolling = false


func _total() -> float:
	return _beats.total


# --- staging -----------------------------------------------------------------


func _pose(result: CombatSnapshot.CombatResult, attacker: Unit, defender: Unit) -> void:
	_result = result
	_atk_style = _styles.for_weapon(attacker.type, result.attacker_weapon_slot)
	_def_style = _styles.for_weapon(defender.type, result.counter_weapon_slot)
	_atk_arrival = _styles.by_id(attacker.type.battle_style)
	_def_arrival = _styles.by_id(defender.type.battle_style)
	_play.accent = accent_of(attacker.team)
	# Read once, as the flat director reads it: a rate read per frame would
	# re-plan the sheet mid-run.
	var rate := Settings.speed.cutscene_rate() * speed
	_beats = CombatBeats.plan(result, _atk_style, _def_style, clampf(tail_scale, 0.0, 1.0), rate)
	stage.clear()
	_atk_plot = _plot_for(attacker, -1)
	_def_plot = _plot_for(defender, 1)
	_atk = _squad_for(
		attacker,
		_atk_plot,
		result.attacker_hp_before,
		result.attacker_hp_after,
		result.attacker_died
	)
	_def = _squad_for(
		defender,
		_def_plot,
		result.defender_hp_before,
		result.defender_hp_after,
		result.defender_died
	)
	_fx = CutinFx3D.new()
	stage.dress(_fx)
	var lob := CutinBallistics3D.peak_of(_atk_style, result.attacker_indirect)
	_shots = CombatShots3D.plan(_beats, _atk.focus(), _def.focus(), lob)
	_plates.left = _plate(attacker, _atk_style.label, result.attacker_cover_stars)
	_plates.right = _plate(
		defender, _def_style.label if result.countered else &"", result.defender_cover_stars
	)


func _plot_for(unit: Unit, side: int) -> StagePlot3D:
	var terrain := view.map.terrain_at(unit.cell)
	var owner_row := view.identity.atlas_row(view.game.owner_at(unit.cell))
	return stage.plot(
		terrain, _ground_for(terrain, unit), SideIdentity.theme_for_row(owner_row), side
	)


## What a squad stands on: the cell's own terrain where its art is a surface,
## the surface it names where its art stands (a city's road, a wood's floor) —
## and dry ground under a unit that could not stand on that surface, a tank in
## a port being on the quay rather than in the berth.
func _ground_for(terrain: TerrainType, unit: Unit) -> TerrainType:
	var ground := terrain
	if terrain.stands_in_cutin():
		ground = view.db.by_id(terrain.cutin_ground)
		if ground == null:
			ground = terrain
	if unit.type.domain != UnitType.AIR and not ground.is_passable(unit.type.move_class):
		return view.db.ground()
	return ground


## A side's squad: one figure per two HP it went in with, and the ones it keeps.
## A side that dies keeps them all — the blast takes it whole.
func _squad_for(unit: Unit, plot: StagePlot3D, before: int, after: int, died: bool) -> StageSquad3D:
	var posted := CutsceneSide.figures_for(before)
	var standing := posted if died else CutsceneSide.figures_for(after)
	var theme := SideIdentity.theme_for_row(view.identity.atlas_row(unit.team))
	var squad := stage.squad(unit.type, theme, maxi(posted, 1), standing, plot)
	squad.dived = unit.dived
	squad.pose()
	return squad


func _plate(unit: Unit, weapon: StringName, cover: int) -> CutinPlates3D.Plate:
	var plate := CutinPlates3D.Plate.new()
	var terrain := view.map.terrain_at(unit.cell)
	plate.title = unit.type.display_name.to_upper()
	plate.accent = accent_of(unit.team)
	plate.weapon = String(weapon)
	plate.terrain = terrain.display_name.to_upper()
	plate.stars = CutsceneSide.lit_stars(cover, terrain.defense_stars)
	plate.note = CutsceneSide.terrain_note(cover, terrain.defense_stars)
	return plate


# --- the frame ---------------------------------------------------------------


func _apply() -> void:
	var t := _play.t
	var present := clampf(_play.window(_beats.wipe_in) - _play.window(_beats.wipe_out), 0.0, 1.0)
	var on_stage := t >= _cut_in() and t < _cut_out()
	_play.frame(present, _beats.wipe_out, 0.0 if on_stage else 1.0)
	if on_stage:
		stage.enter()
	else:
		stage.leave()
	_flash.color.a = _flash_at(t)
	stage.set_clock(t)
	_pose_squads(t)
	var lens := _shots.pose_at(t)
	stage.frame(lens[0], lens[1])
	_frame_fx(t, lens[0])
	_frame_plates(on_stage)
	_sound()


## When the lens cuts to the stage and back.
func _cut_in() -> float:
	return lerpf(_beats.wipe_in.x, _beats.wipe_in.y, CUT_IN_SHARE)


func _cut_out() -> float:
	return lerpf(_beats.wipe_out.x, _beats.wipe_out.y, CUT_OUT_SHARE)


func _flash_at(t: float) -> float:
	var brightest := 0.0
	for cut in [_cut_in(), _cut_out()]:
		var since: float = t - cut
		if since < 0.0 and since > -FLASH_LEAD:
			brightest = maxf(brightest, 1.0 + since / FLASH_LEAD)
		elif since >= 0.0 and since < FLASH_TAIL:
			brightest = maxf(brightest, 1.0 - since / FLASH_TAIL)
	return FLASH_ALPHA * brightest


func _pose_squads(t: float) -> void:
	var arrive := _play.window(Vector2(_cut_in(), _beats.arrive.y))
	_pose_side(_atk, t, arrive, _atk_style, _atk_arrival, _beats.atk_ready, _beats.atk_fire)
	_pose_hit(_atk, _beats.atk_impact, _beats.atk_casualty, _beats.atk_death)
	_pose_side(_def, t, arrive, _def_style, _def_arrival, _beats.ctr_ready, _beats.def_fire)
	_pose_hit(_def, _beats.def_impact, _beats.def_casualty, _beats.def_death)
	_atk.pose()
	_def.pose()


func _pose_side(
	squad: StageSquad3D,
	t: float,
	arrive: float,
	style: BattleStyle,
	arrival: BattleStyle,
	ready: Vector2,
	fire: float
) -> void:
	squad.clock = t
	squad.arrive = arrive
	squad.arrive_scale = arrival.arrive_scale
	squad.aim = _play.window(ready)
	squad.aim_lift = CutinBallistics3D.cells(style.aim_lift)
	squad.aim_pitch = style.aim_pitch
	squad.kick = SquadFormation3D.kick(t - fire, style.recoil) if fire > 0.0 else 0.0


func _pose_hit(squad: StageSquad3D, impact: Vector2, casualty: Vector2, death: Vector2) -> void:
	var hit := _play.window(impact)
	squad.flash = maxf(0.0, 1.0 - hit / HIT_FLASH) if hit > 0.0 else 0.0
	squad.shove = CutscenePlayback.decay(hit)
	squad.casualty = _play.window(casualty)
	var gone := _play.window(death)
	squad.char_by = minf(1.0, gone * 3.0)
	squad.alpha = 1.0 - smoothstep(0.35, 0.9, gone)


func _frame_fx(t: float, eye: Vector3) -> void:
	_fx.begin(eye)
	if _atk_style.fires():
		var out := _volley(_atk, _def, _atk_style, _beats.atk_travel, _atk.posted)
		out.lobbed = _result.attacker_indirect
		out.harmed = _result.attack_damage > 0
		_draw_volley(out, t, _def)
	if _def_style.fires() and _beats.def_fire > 0.0:
		# A counter is fired at adjacency by rule, so it is never a lob.
		var back := _volley(_def, _atk, _def_style, _beats.def_travel, _def.standing)
		back.harmed = _result.counter_damage > 0
		_draw_volley(back, t, _atk)
	_draw_blast(_def, _def_plot, _beats.def_death)
	_draw_blast(_atk, _atk_plot, _beats.atk_death)
	_fx.commit()


func _volley(
	from: StageSquad3D, at: StageSquad3D, style: BattleStyle, travel: Vector2, firing: int
) -> CombatVolley3D.Volley:
	var v := CombatVolley3D.Volley.new()
	v.style = style
	v.from = from.muzzle_points(firing)
	if style.projectile == BattleStyle.BOMB:
		v.from = from.body_points().slice(0, firing)
	v.targets = at.body_points()
	v.fire = travel.x
	v.flight = travel.y - travel.x
	var plot := _atk_plot if at == _atk else _def_plot
	v.floor_y = plot.stand_at(at.focus())
	v.wet = v.floor_y < BoardSpace3D.LAND_TOP - 0.01
	v.airborne = at.type.domain == UnitType.AIR
	return v


func _draw_volley(v: CombatVolley3D.Volley, t: float, target: StageSquad3D) -> void:
	CombatVolley3D.draw_muzzles(_fx, v, t, target.focus())
	CombatVolley3D.draw_gun_smoke(_fx, v, t)
	CombatVolley3D.draw_rounds(_fx, v, t)
	CombatVolley3D.draw_impacts(_fx, v, t)


func _draw_blast(squad: StageSquad3D, plot: StagePlot3D, death: Vector2) -> void:
	var p := _play.window(death)
	if p <= 0.0 or p >= 1.0:
		return
	var floor_y := plot.stand_at(squad.focus())
	CombatVolley3D.draw_blast(
		_fx,
		squad.body_points(),
		p,
		floor_y,
		floor_y < BoardSpace3D.LAND_TOP - 0.01,
		squad.type.domain == UnitType.AIR
	)


func _frame_plates(on_stage: bool) -> void:
	var plates := _play.window(_beats.plates) * float(on_stage)
	_plates.plate_p = plates
	_plates.left.hp = _tick(
		_result.attacker_hp_before, _result.attacker_hp_after, _play.window(_beats.atk_impact)
	)
	_plates.right.hp = _tick(
		_result.defender_hp_before, _result.defender_hp_after, _play.window(_beats.def_impact)
	)
	var callouts: Array[CutinPlates3D.Callout] = []
	# A number is pinned over the squad it belongs to only while the lens is on
	# that squad or on the whole field; a shot of the other side would leave it
	# hanging off the edge of the frame.
	var shot := _shots.kind_at(_play.t)
	var wide := shot == CombatShots3D.Shot.CLOSE
	if on_stage and (wide or shot == CombatShots3D.Shot.DEFENDER_HIT):
		callouts.append(
			_callout(
				_def,
				_result.defender_hp_before - _result.defender_hp_after,
				_result.defender_died,
				_beats.def_impact,
				_beats.def_death
			)
		)
	if on_stage and (wide or shot == CombatShots3D.Shot.ATTACKER_HIT):
		callouts.append(
			_callout(
				_atk,
				_result.attacker_hp_before - _result.attacker_hp_after,
				_result.attacker_died,
				_beats.atk_impact,
				_beats.atk_death
			)
		)
	_plates.callouts = callouts
	_plates.queue_redraw()


func _callout(
	squad: StageSquad3D, amount: int, died: bool, impact: Vector2, death: Vector2
) -> CutinPlates3D.Callout:
	var callout := CutinPlates3D.Callout.new()
	callout.amount = amount
	callout.tag = CutsceneFx.KO_TAG if died else ""
	callout.progress = _play.window(CombatBeats.callout_window(impact, death))
	var head := squad.focus() + Vector3.UP * squad.figure_height() * 1.4
	if stage.sees(head):
		callout.at = stage.screen_of(head) - _plates.get_global_rect().position
	else:
		callout.progress = 0.0
	return callout


## HP holds for the first third of the impact, then runs down to the number the
## sim committed, whole — the flat cut-in's tick.
static func _tick(before: int, after: int, progress: float) -> int:
	if progress <= 0.0:
		return before
	return roundi(lerpf(before, after, clampf((progress - 0.35) / 0.65, 0.0, 1.0)))


## The flat cut-in's cues, on the same beats.
func _sound() -> void:
	if not _play.playing:
		return
	if _atk_style.fires():
		_play.cue(&"atk_fire", _beats.atk_fire, _atk_style.sfx)
	if _def_style.fires():
		_play.cue(&"def_fire", _beats.def_fire, _def_style.sfx)
	_play.cue(&"def_death", _beats.def_death.x, &"explosion")
	_play.cue(&"atk_death", _beats.atk_death.x, &"explosion")


func _place_layers(band: Vector2) -> void:
	_plates.position = Vector2.ZERO
	_plates.size = band
	_flash.position = Vector2.ZERO
	_flash.size = _play.view_size
