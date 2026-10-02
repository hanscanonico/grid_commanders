class_name StageSquad3D
extends Node3D
## One side's squad on the 3D cut-in stage: up to five figures of the unit's own
## 3D model, one per two displayed HP, in a staggered formation facing the foe.
##
## Dumb in the `CutsceneSide` idiom: a director sets the pose fields off its own
## clock and calls `pose()`, which places every figure as a pure function of
## them — so a still posed at any moment is the same still every run, and a skip
## lands on the final tableau. Which figures fall is by index, never by chance:
## the survivors are the outermost `standing`, the lost are the ones nearest the
## foe, as on the flat cut-in.

## A figure's hit flash, as emission over its own colours.
const FLASH_ENERGY := 0.55
const FLASH_COLOUR := Color("#fff4dc")
## A casualty and a wreck char toward this.
const CHAR := Color(0.28, 0.27, 0.27)
const ROTOR_SPIN := 26.0
## Figures stand larger than the board's own models, so a squad holds its own
## against a patch of ground built at the board's scale: a unit has a cell to
## itself there and a whole stage here.
const FIGURE_SCALE: Dictionary[StringName, float] = {
	UnitType.LAND: 1.3,
	UnitType.AIR: 1.45,
	UnitType.SEA: 1.9,
}

## The clock the hover, the swell and the rotors read.
var clock := 0.0
## 0 -> 1 over the entrance; 1 is in the slot.
var arrive := 1.0
## Where the entrance starts, as a multiple of the domain's own reach.
var arrive_scale := 1.0
## 0 -> 1 over the wind-up, and the style's lift (cells) and pitch it holds.
var aim := 0.0
var aim_lift := 0.0
var aim_pitch := 0.0
## Signed offset along the firing axis, positive toward the foe: the kick.
var kick := 0.0
## The hit: a white flash and a shove away from the foe, both 0 -> 1.
var flash := 0.0
var shove := 0.0
## 0 -> 1 over the casualty window: the lost figures go down.
var casualty := 0.0
## How much of the whole squad is left to see, and how burnt it is — a squad
## the kill blast takes chars and fades as one.
var alpha := 1.0
var char_by := 0.0

var type: UnitType
## A sub fought under the water rides low, its sail all that shows; a surfaced
## one is lifted to show its hull (`SeaModels3D.surfaced_rise`).
var dived := false
var posted := 0
var standing := 0
## +1 faces +X (the left side, firing right), -1 faces -X.
var facing := 1.0

var _plot: StagePlot3D
var _anchor := Vector3.ZERO
var _spacing := 1.0
var _scale := 1.0
var _muzzle := Vector3.ZERO
var _height := 0.3
var _figures: Array[Node3D] = []
var _materials: Array[StandardMaterial3D] = []


## Stands `p_posted` figures of `p_type` on `plot` in `theme`, `p_standing` of
## which survive the exchange.
func setup(
	p_type: UnitType,
	theme: CommanderVisuals.FactionTheme,
	p_posted: int,
	p_standing: int,
	plot: StagePlot3D
) -> void:
	type = p_type
	posted = clampi(p_posted, 1, SquadFormation3D.MAX_FIGURES)
	standing = clampi(p_standing, 0, posted)
	_plot = plot
	facing = -float(plot.side)
	_scale = FIGURE_SCALE.get(type.domain, 1.0)
	var aabb := UnitModels3D.figure_mesh_for(type.id, theme).get_aabb()
	_muzzle = UnitModels3D.muzzle_for(type.id, aabb)
	aabb = AABB(aabb.position * _scale, aabb.size * _scale)
	_spacing = maxf(maxf(aabb.size.x, aabb.size.z) + 0.3, 0.75)
	_height = aabb.size.y
	var slots := SquadFormation3D.SLOTS
	_anchor = plot.squad_anchor((slots[slots.size() - 1].x - slots[0].x) * 0.5 * _spacing)
	for slot in posted:
		var figure := UnitModels3D.build(type.id, theme, true)
		var body := figure.get_node("Body") as GeometryInstance3D
		_materials.append(
			MeshKit.flashable(body.material_override as StandardMaterial3D, FLASH_COLOUR)
		)
		_figures.append(figure)
		add_child(figure)
	pose()


## Places every figure off the pose fields.
func pose() -> void:
	var domain := type.domain
	var on_foot := is_on_foot()
	var reach := SquadFormation3D.arrive_reach(domain) * arrive_scale
	var lift := aim_lift * SquadFormation3D.aim_ease(aim)
	var pitch := SquadFormation3D.aim_pitch(aim, aim_pitch)
	for slot in posted:
		var run := SquadFormation3D.casualty_run(casualty, slot, standing, posted)
		var fall := SquadFormation3D.topple(run, domain)
		var progress := SquadFormation3D.march_progress(arrive, slot, on_foot)
		var local := SquadFormation3D.slot_point(slot, posted, _spacing, _plot.spread)
		local += SquadFormation3D.arrive_offset(progress, reach, domain, on_foot)
		local.x += kick - shove * 0.08 - fall.x
		var attitude := SquadFormation3D.attitude(domain, clock, slot, progress)
		var ground := _ground_at(local)
		var height := ground + _ride() + lift - fall.y
		if domain == UnitType.AIR:
			height = ground + SquadFormation3D.cruise_height(clock, slot) + lift - fall.y
		var figure := _figures[slot]
		figure.position = _to_stage(local, height)
		var tip := fall.z
		var roll := attitude.x + (SquadFormation3D.air_spin(run) if domain == UnitType.AIR else tip)
		var nose := attitude.y + pitch
		if domain == UnitType.AIR:
			nose -= tip
		figure.rotation = Vector3(roll, 0.0 if facing > 0.0 else PI, nose)
		figure.scale = Vector3.ONE * _scale
		figure.visible = fall.w > 0.0 and alpha > 0.0
		_paint(slot, fall.w * alpha, maxf(char_by, run * 0.8))
		UnitModels3D.turn_rotors(figure, clock * ROTOR_SPIN)


## Whether this squad marches in rather than rolling, flying or sailing.
func is_on_foot() -> bool:
	return type.id == &"infantry" or type.id == &"mech"


## The barrel mouths of the first `firing` figures (every survivor when
## negative), in the stage's frame, nearest the foe last — where a flash goes
## off and a volley leaves from. An attacker fires with every figure it went in
## with; a counter only with those still up.
func muzzle_points(firing: int = -1) -> PackedVector3Array:
	var points := PackedVector3Array()
	for slot in standing if firing < 0 else mini(firing, posted):
		points.append(transform * (_figures[slot].transform * _muzzle))
	return points


## Every posted figure's middle, in the stage's frame — where a round is aimed
## and a burst goes off. Includes the lost, which are hit before they fall.
func body_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	for figure in _figures:
		points.append(transform * (figure.transform * Vector3(0.0, _height * 0.5 / _scale, 0.0)))
	return points


## The squad's middle at body height as it stands posted, in the stage's frame
## and without the hover: a lens framed on it, or a number pinned to it, does
## not judder.
func focus() -> Vector3:
	var cruise := SquadFormation3D.CRUISE if type.domain == UnitType.AIR else 0.0
	return transform * (_anchor + Vector3.UP * (cruise + _ride() + _height * 0.5))


## How tall one figure stands.
func figure_height() -> float:
	return _height


func _ride() -> float:
	return 0.0 if dived else SeaModels3D.surfaced_rise(type.id) * _scale


func _ground_at(local: Vector3) -> float:
	return _plot.stand_at(_to_stage(local, 0.0))


## A point of the squad's frame on the stage: +X of the frame toward the foe.
func _to_stage(local: Vector3, height: float) -> Vector3:
	return _anchor + Vector3(local.x * facing, height, local.z)


func _paint(slot: int, shown: float, charred: float) -> void:
	var material := _materials[slot]
	var tint := Color.WHITE.lerp(CHAR, clampf(charred, 0.0, 1.0))
	material.albedo_color = Color(tint, shown)
	var faded := shown < 0.999
	var mode := BaseMaterial3D.TRANSPARENCY_ALPHA if faded else BaseMaterial3D.TRANSPARENCY_DISABLED
	if material.transparency != mode:
		material.transparency = mode
	var lit := flash > 0.0 and slot < standing
	material.emission_energy_multiplier = FLASH_ENERGY * flash if lit else 0.0
