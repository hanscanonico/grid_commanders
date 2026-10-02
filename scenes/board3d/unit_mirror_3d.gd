class_name UnitMirror3D
extends Node3D
## One 3D model per unit sprite, posed every frame from that sprite.
##
## The sprites stay the board's one animated truth: BattleView spawns, fogs,
## greys and frees them and BattleAnimator walks, lunges and fades them. A model
## only copies what its sprite shows — where it stands, whether it is seen, how
## faded or flashed it is, its HP badge — so no animation, fog rule or scripted
## beat needs a 3D twin, and the two boards cannot disagree about a unit.

## Aircraft ride a slow bob, ships a slower roll; a unit in hand hops.
const AIR_BOB := 0.035
const SEA_ROLL_DEG := 2.5
const HELD_HOP := 0.06
const TURN_RATE := 12.0
## A dived sub sits this far down, its hull just awash, so the faint boat its
## sprite draws reads here as a whole translucent hull rather than a sail tip.
const DIVE_DEPTH := 0.04
## A ship at rest swings back broadside to the lens at this rate, so its length
## and its guns — what tells one hull from another — read across the screen.
const BROADSIDE_RATE := 3.0
## How much darker a greyed unit draws, and how its colour is washed toward grey.
const GREYED_TINT := Color(0.46, 0.46, 0.5)
const ROTOR_SPIN := 22.0
const BADGE_HEIGHT := 0.42
const BADGE_SIDE := 0.3
const BADGE_PX := 16
## How many frames the shadow's primer stands before the lens.
const PRIMER_FRAMES := 3

var map: MapData
var sprites_root: Node2D

## Keyed by the sprite's instance id rather than the sprite: a sprite freed by
## its own death tween is gone before the next sync, and a freed object cannot
## be read back out of a typed key.
var _models: Dictionary[int, Model] = {}
var _clock := 0.0
var _primer: MeshInstance3D
var _primed := 0


## Everything the mirror keeps about one model between frames.
class Model:
	extends RefCounted
	var node: Node3D
	var material: StandardMaterial3D
	var row := -1
	var yaw := 0.0
	var plane := Vector2.ZERO
	var hp: Label3D
	var fuel: Label3D
	var shadow: Node3D
	var mark: Sprite3D
	var top := 0.0
	var phase := 0.0


func _ready() -> void:
	_primer = AirShadow3D.primer()
	add_child(_primer)


## Poses every model off its sprite. `lens` is the camera's basis: the badges
## sit to its right and left of a unit whichever way the board is turned.
func sync(delta: float, lens: Basis) -> void:
	_clock += delta
	_prime()
	var seen: Dictionary[int, bool] = {}
	for child in sprites_root.get_children():
		var sprite := child as UnitSprite
		if sprite == null or sprite.is_queued_for_deletion() or sprite.unit == null:
			continue
		seen[sprite.get_instance_id()] = true
		var model: Model = _models.get(sprite.get_instance_id())
		if model == null or model.row != sprite.atlas_row:
			model = _rebuild(sprite, model)
		_pose(model, sprite, delta, lens)
		_badges(model, sprite, lens)
	for id: int in _models.keys():
		if not seen.has(id):
			_drop(_models[id])
			_models.erase(id)


## Holds the air shadow's primer a step before the lens for its first frames,
## so the shadow's shader is built as the board comes up, not when the first
## aircraft is bought or flies out of the fog.
func _prime() -> void:
	var lens := get_viewport().get_camera_3d()
	if _primer == null or lens == null:
		return
	_primer.global_position = lens.global_position - lens.global_basis.z
	_primed += 1
	if _primed > PRIMER_FRAMES:
		_primer.queue_free()
		_primer = null


## The cells a unit is seen standing on (or flying over) now, read off where
## each shown model is rather than off the sim, so a walk carries it along.
func standing_cells() -> Dictionary[Vector2i, bool]:
	var cells: Dictionary[Vector2i, bool] = {}
	for model: Model in _models.values():
		if model.node.visible:
			cells[BoardSpace3D.cell_at(model.plane)] = true
	return cells


func _rebuild(sprite: UnitSprite, old: Model) -> Model:
	var model := Model.new()
	if old != null:
		model.yaw = old.yaw
		_drop(old)
	else:
		var here := BoardSpace3D.plane_of(sprite.position)
		model.yaw = 0.0 if here.x < map.width / 2.0 else PI
	model.row = sprite.atlas_row
	model.node = UnitModels3D.build(
		sprite.unit.type.id, SideIdentity.theme_for_row(sprite.atlas_row)
	)
	var body := model.node.get_node("Body") as MeshInstance3D
	model.material = body.material_override as StandardMaterial3D
	model.top = body.mesh.get_aabb().end.y
	if BattleCampaign.unit_name(sprite.unit) != "":
		model.mark = UnitMark3D.make()
		add_child(model.mark)
	if sprite.unit.type.domain == UnitType.AIR:
		model.shadow = AirShadow3D.attach(model.node, sprite.unit.type.id)
	model.phase = float(sprite.unit.cell.x * 7 + sprite.unit.cell.y * 3)
	model.hp = _badge(Color.WHITE)
	model.fuel = _badge(UiTheme.AMMO)
	model.plane = BoardSpace3D.plane_of(sprite.position)
	add_child(model.node)
	_models[sprite.get_instance_id()] = model
	return model


func _pose(model: Model, sprite: UnitSprite, delta: float, lens: Basis) -> void:
	var node := model.node
	node.visible = sprite.visible
	if not node.visible:
		return
	var plane := BoardSpace3D.plane_of(sprite.position)
	var step := plane - model.plane
	model.plane = plane
	var domain := sprite.unit.type.domain
	if sprite.moving and step.length() > 0.0005:
		model.yaw = lerp_angle(model.yaw, atan2(-step.y, step.x), 1.0 - exp(-delta * TURN_RATE))
	elif domain == UnitType.SEA and not sprite.moving:
		var across := _broadside(model.yaw, lens)
		var ease := 1.0 if BoardBeat.still() else 1.0 - exp(-delta * BROADSIDE_RATE)
		model.yaw = lerp_angle(model.yaw, across, ease)
	var ground := BoardSpace3D.stand_at(map, plane)
	var height := ground
	var roll := 0.0
	if domain == UnitType.AIR:
		height = BoardSpace3D.fly_at(map, plane) + sin(_clock * 2.0 + model.phase) * AIR_BOB
	elif domain == UnitType.SEA:
		roll = deg_to_rad(SEA_ROLL_DEG) * sin(_clock * 1.3 + model.phase)
		if sprite.unit.dived:
			height -= DIVE_DEPTH
		height += _berth(ground)
	if sprite.in_hand and not BoardBeat.still():
		height += absf(sin(_clock * 9.0)) * HELD_HOP
	node.position = Vector3(plane.x, height, plane.y)
	node.rotation = Vector3(roll, model.yaw, 0)
	if model.shadow != null:
		AirShadow3D.lay(model.shadow, height, ground)
		model.shadow.visible = sprite.modulate.a >= 0.999
	_tint(model, sprite)
	if domain == UnitType.AIR:
		UnitModels3D.turn_rotors(node, _clock * ROTOR_SPIN + model.phase)


## How far a hull is raised as it comes alongside onto a port, whose quay
## stands at dry ground's height: its keel set on the quay, so the whole hull
## shows rather than half of it sunk in the concrete.
static func _berth(ground: float) -> float:
	var alongside := inverse_lerp(BoardSpace3D.SEA_TOP, BoardSpace3D.LAND_TOP, ground)
	return -SeaModels3D.KEEL * clampf(alongside, 0.0, 1.0)


## The heading nearer `yaw` of the two that lie along the lens's horizontal.
static func _broadside(yaw: float, lens: Basis) -> float:
	var across := atan2(-lens.x.z, lens.x.x)
	return across if absf(angle_difference(yaw, across)) <= PI / 2.0 else across + PI


## The sprite's fade, hit flash and acted scrim, carried onto the one material
## the model draws with.
func _tint(model: Model, sprite: UnitSprite) -> void:
	var alpha := sprite.modulate.a
	var flash := sprite.self_modulate
	var tint := Color(flash.r, flash.g, flash.b, alpha)
	if sprite.greyed():
		tint = Color(tint.r * GREYED_TINT.r, tint.g * GREYED_TINT.g, tint.b * GREYED_TINT.b, alpha)
	var faded := alpha < 0.999
	var mode := BaseMaterial3D.TRANSPARENCY_ALPHA if faded else BaseMaterial3D.TRANSPARENCY_DISABLED
	if model.material.transparency != mode:
		model.material.transparency = mode
		# A faded model writes its depth, so it draws as one silhouette rather
		# than showing its own far side through itself. Only while faded, so an
		# opaque model keeps the one shader every other board part shares.
		model.material.depth_draw_mode = (
			BaseMaterial3D.DEPTH_DRAW_ALWAYS if faded else BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		)
	model.material.albedo_color = tint


func _badges(model: Model, sprite: UnitSprite, lens: Basis) -> void:
	var shown := model.node.visible
	var above := model.node.position + Vector3.UP * BADGE_HEIGHT
	model.hp.visible = shown and sprite.hp_label.visible
	model.hp.text = sprite.hp_label.text
	model.hp.position = above + lens.x * BADGE_SIDE
	model.fuel.visible = shown and sprite.fuel_label.visible
	model.fuel.text = sprite.fuel_label.text
	model.fuel.position = above - lens.x * BADGE_SIDE
	if model.mark != null:
		model.mark.visible = shown
		UnitMark3D.place(model.mark, model.node.position, model.top, _clock)


func _drop(model: Model) -> void:
	model.node.queue_free()
	model.hp.queue_free()
	model.fuel.queue_free()
	if model.mark != null:
		model.mark.queue_free()


func _badge(colour: Color) -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.001
	label.font_size = BADGE_PX
	label.outline_size = 6
	label.modulate = colour
	label.outline_modulate = Color.BLACK
	label.no_depth_test = true
	label.render_priority = 2
	label.outline_render_priority = 1
	label.font = load(UiTheme.STAT_BOLD_FONT_PATH)
	label.visible = false
	add_child(label)
	return label
