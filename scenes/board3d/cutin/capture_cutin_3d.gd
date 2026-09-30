class_name CaptureCutin3D
extends CutsceneDirector
## The capture cut-in on the 3D board: the property stands big on its own ground
## in its owner's colours, flag flying; the capturer's squad marches in and
## mashes it one to three times as the meter knocks off each chip; on a
## completion the old flag runs down, the building flips to the capturer's
## colours under a white flash, the new flag runs up, CAPTURED! and a burst — on
## a partial the squad stands its ground under OCCUPYING.
##
## The flat `CaptureCutscene`'s sibling on the same seam and the same sheet:
## `CaptureBeats` says when, `CaptureShot3D` says where, and every visual is a
## pure function of `_play.t`, so a skip is the clock jumping to its end and lands
## the stage off the air with the board back. It replays the `CaptureResult` it is
## handed and decides nothing.

## Where the squad's middle halts, in the stage's frame: before the property the
## right-hand plot stands, facing it across the seam.
const SQUAD_AT := Vector3(-0.9, 0.0, -0.6)
const MARCH_SCALE := 2.4
## The chips rise from this share of the roof's height, so they clear the
## banner as they climb.
const CHIP_FROM := 0.55
## CaptureHud draws its flash at 0.55 of this, so a cut's blink is a full white.
const WASH := 1.8

var stage: CutinStage3D

var _hud: CaptureHud
var _beats := CaptureBeats.new()
var _result: CaptureCommand.CaptureResult
var _rig: CaptureRig3D
var _squad: StageSquad3D
## Where the squad's own frame puts its middle before it is carried to SQUAD_AT.
var _squad_anchor := Vector3.ZERO


func _ready() -> void:
	layer = 2
	_play.build(self, _place_layers)
	_hud = CaptureHud.new()
	_play.band.add_child(_hud)
	_play.build_bars()
	_play.root.hide()


## Plays one already-applied capture and returns when the board is back.
func play(result: CaptureCommand.CaptureResult, unit: Unit, cell: Vector2i) -> void:
	_pose(result, unit, cell)
	run()
	await finished


## Freezes the cut-in at `at` of its own clock, for a screenshot. Dev-only.
func pose_at(result: CaptureCommand.CaptureResult, unit: Unit, cell: Vector2i, at: float) -> void:
	_pose(result, unit, cell)
	hold(at)


func _pose(result: CaptureCommand.CaptureResult, unit: Unit, cell: Vector2i) -> void:
	_result = result
	_beats = CaptureBeats.plan(result, clampf(tail_scale, 0.0, 1.0))
	_play.accent = accent_of(unit.team)
	var terrain := view.map.terrain_at(cell)
	var ground := _ground_of(terrain, unit.type)
	var before := SideIdentity.theme_for_row(view.identity.atlas_row(result.owner_before))
	var after := SideIdentity.theme_for_row(view.identity.atlas_row(unit.team))
	stage.clear()
	var left := stage.plot(ground, ground, before, -1)
	var right := stage.plot(terrain, ground, before, 1)
	var figures := CutsceneSide.figures_for(unit.displayed_hp())
	_squad = stage.squad(unit.type, after, figures, figures, left)
	_squad.arrive_scale = MARCH_SCALE
	_squad_anchor = _squad.focus() - Vector3.UP * _squad.figure_height() * 0.5
	_rig = CaptureRig3D.new()
	stage.dress(_rig)
	_rig.position = right.position + right.buildings[0].position
	_rig.setup(terrain.id, right.buildings, before, after)
	_hud.plate_unit = unit
	_hud.plate_terrain = terrain
	_hud.plate_accent = _play.accent


## What the squad stands on: the ground a property is paved with in the flat
## cut-in, but only ground the squad could walk — a port's paving is the sea, and
## a squad takes a port from the quay.
func _ground_of(terrain: TerrainType, type: UnitType) -> TerrainType:
	var ground := view.db.by_id(terrain.cutin_ground) if terrain.stands_in_cutin() else terrain
	if ground == null or not ground.is_passable(type.move_class):
		return view.db.ground()
	return ground


func _total() -> float:
	return _beats.total


func _apply() -> void:
	var t := _play.t
	var captured := _result.captured
	var present := clampf(
		_play.window(Vector2(0.0, CaptureBeats.WIPE_IN)) - _play.window(_beats.wipe_out), 0.0, 1.0
	)
	var on_air := CaptureShot3D.on_air(_beats, t)
	_play.frame(present, _beats.wipe_out, 0.0 if on_air else 1.0)
	stage.rolling = _play.playing and t < _beats.total
	if on_air:
		stage.enter()
	else:
		stage.leave()
	stage.set_clock(t)
	_pose_squad(t, captured)
	var bodies := _squad.body_points()
	var feet := PackedVector3Array()
	var leading := Vector3.ZERO
	for body in bodies:
		leading += body / bodies.size()
		feet.append(Vector3(body.x, 0.0, body.z) - _rig.position)
	var squad := SQUAD_AT + Vector3.UP * _squad.figure_height() * 0.5
	var door := _rig.position + _rig.door()
	var top := _rig.position + _rig.flag_top
	var lens := CaptureShot3D.lens(_beats, captured, t, squad, leading, door, top)
	stage.frame(lens[0], lens[1])
	_rig.pose(_beats, captured, t, feet, lens[0] - _rig.position)
	_frame_hud(t, present)
	_sound()


## The squad marches in, hops on each mash and surges at the building, and
## cheers after a flip — the formation's own entrance, carried whole to its mark.
func _pose_squad(t: float, captured: bool) -> void:
	_squad.clock = t
	_squad.arrive = _play.window(_beats.march)
	_squad.pose()
	var lift := CaptureShot3D.hop(_beats, t) + CaptureShot3D.cheer(_beats, captured, t)
	_squad.position = SQUAD_AT - _squad_anchor + Vector3(CaptureShot3D.surge(_beats, t), lift, 0.0)


func _frame_hud(t: float, present: float) -> void:
	_hud.plate_p = _play.window(_beats.plates) * present
	_hud.points_shown = _beats.points_at(_result.points_before, t)
	_hud.meter_p = _play.window(_beats.plates) * present
	_hud.chip_values = _beats.chips
	var chip_p := PackedFloat32Array()
	var cut := _beats.flip.x if _result.captured else _beats.banner.x
	for land in _beats.lands:
		chip_p.append(_play.window(Vector2(land, land + 0.6)) if t < cut else 0.0)
	_hud.chip_p = chip_p
	var head := _rig.position + _rig.roof_top * CHIP_FROM
	_hud.chip_at = stage.screen_of(head) - _play.band.position
	_hud.flash = CaptureShot3D.flash(_beats, _result.captured, t) * WASH
	_hud.specks_p = 0.0
	_hud.frame_banner(_beats, _result, t)
	_hud.queue_redraw()


func _sound() -> void:
	if not _play.playing:
		return
	for i in _beats.lands.size():
		_play.cue(StringName("mash_%d" % i), _beats.lands[i], &"capture")
	if _result.captured:
		_play.cue(&"flip", _beats.banner.x, &"fanfare")


func _place_layers(band: Vector2) -> void:
	_hud.position = Vector2.ZERO
	_hud.size = band
