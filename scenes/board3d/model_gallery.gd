extends Node3D
## Dev-only gallery for the 3D board's models: every unit in a row per faction
## and every property for neutral and two owners, under the board's camera
## angle, so the models are judged at the size they are played at.
##
## Boot with:  tools/godot_gui.sh --path . scenes/board3d/model_gallery.tscn --
##             [--screenshot=/abs.png] [--closeup=tank,md_tank,hq] [--actors]
## `--closeup` lays out only the named units or properties, one row per faction,
## with the camera pulled in. `--actors` lays out only the generals: two rows
## at rest, then a row playing every clip and a hologram; `--actors=a,b` only
## the named ones, or one named general in every clip.

const UNIT_ROWS: Array[StringName] = [&"meridian", &"aurora", &"verdant", &"gold", &"iron"]
const PROPERTY_OWNERS: Array[StringName] = [&"neutral", &"meridian", &"iron"]
const PROPERTIES: Array[StringName] = [&"city", &"base", &"airport", &"port", &"hq"]
const AIR: Array[StringName] = [&"fighter", &"bomber", &"b_copter", &"t_copter"]
const SEA: Array[StringName] = [&"battleship", &"cruiser", &"lander", &"sub"]
const PITCH_DEG := 50.0
const GRASS := Color("5d8043")
const WATER := Color("3f78a8")
const ACTOR_COLUMNS := 11
## Where on each clip a posed general is caught: past every gesture's ease-in.
const ACTOR_T := 1.3


func _ready() -> void:
	var args := CmdArgs.user()
	var closeup := CmdArgs.value(args, "--closeup")
	var extent: Vector2
	var margin := 3.0
	if CmdArgs.has(args, "--actors"):
		var only := CmdArgs.value(args, "--actors").split(",", false)
		extent = _lay_out_actors(only)
		margin = 0.6 if only.size() > 0 else margin
	elif closeup.is_empty():
		extent = _lay_out_all()
	else:
		extent = _lay_out_closeup(closeup.split(",", false))
	_stage(extent, margin)
	var shot_path := ScreenshotUtil.requested()
	if shot_path != "":
		ScreenshotUtil.capture_and_quit(self, shot_path)


func _unit_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for unit_type in UnitDB.load_default().all():
		ids.append(unit_type.id)
	return ids


func _lay_out_all() -> Vector2:
	var ids := _unit_ids()
	for row in UNIT_ROWS.size():
		var theme := CommanderVisuals.theme_for_key(UNIT_ROWS[row])
		for col in ids.size():
			_place_unit(ids[col], theme, Vector3(col, 0, row))
	var z0 := UNIT_ROWS.size() + 0.5
	for i in PROPERTY_OWNERS.size():
		var theme := CommanderVisuals.theme_for_key(PROPERTY_OWNERS[i])
		for p in PROPERTIES.size():
			var cell := Vector3(1 + p + i * (PROPERTIES.size() + 1), 0, z0)
			add_child(_at(PropertyModels3D.build(PROPERTIES[p], theme), cell))
	var generals := _generals()
	for i in generals.size():
		var clip := ActorPose3D.CLIPS[i % ActorPose3D.CLIPS.size()]
		_place_actor(
			generals[i], clip, Vector3(i * ids.size() / float(generals.size()), 0, z0 + 1.2)
		)
	return Vector2(ids.size(), z0 + 2.2)


func _generals() -> Array[CommanderType]:
	var generals: Array[CommanderType] = []
	for commander in CommanderDB.load_default().all():
		if commander.id != CommanderType.NEUTRAL_ID:
			generals.append(commander)
	return generals


func _lay_out_actors(only: PackedStringArray) -> Vector2:
	var generals := _generals()
	if not only.is_empty():
		generals = generals.filter(func(c: CommanderType) -> bool: return only.has(String(c.id)))
		if generals.size() == 1:
			return _lay_out_clips(generals[0])
		for i in generals.size():
			_place_actor(generals[i], &"idle", Vector3(i, 0, 0))
		return Vector2(generals.size(), 1)
	for i in generals.size():
		var cell := Vector3(i % ACTOR_COLUMNS, 0, floorf(i / float(ACTOR_COLUMNS)))
		_place_actor(generals[i], &"idle", cell)
	var row := ceili(generals.size() / float(ACTOR_COLUMNS))
	for i in ActorPose3D.CLIPS.size():
		var commander := generals[i % generals.size()]
		var cell := Vector3(i % ACTOR_COLUMNS, 0, row + floorf(i / float(ACTOR_COLUMNS)))
		_place_actor(commander, ActorPose3D.CLIPS[i], cell)
	var holo := _place_actor(null, &"talk", Vector3(ACTOR_COLUMNS - 1, 0, row + 1))
	holo.set_hologram(Color("6fd8ff"))
	return Vector2(ACTOR_COLUMNS, row + 2)


## One general in every clip, two rows of six.
func _lay_out_clips(commander: CommanderType) -> Vector2:
	var columns := 6
	for i in ActorPose3D.CLIPS.size():
		var cell := Vector3((i % columns) * 0.8, 0, floorf(i / float(columns)))
		_place_actor(commander, ActorPose3D.CLIPS[i], cell)
	return Vector2(columns * 0.8, 2)


func _place_actor(commander: CommanderType, clip: StringName, cell: Vector3) -> CommanderActor3D:
	var actor := CommanderActor3D.make(commander)
	actor.pose(clip, ACTOR_T)
	add_child(_at(actor, cell))
	actor.rotation.y = deg_to_rad(160)
	return actor


func _lay_out_closeup(names: PackedStringArray) -> Vector2:
	for row in UNIT_ROWS.size():
		var theme := CommanderVisuals.theme_for_key(UNIT_ROWS[row])
		if row == 0 and PROPERTIES.has(StringName(names[0])):
			theme = CommanderVisuals.theme_for_key(CommanderVisuals.NEUTRAL_KEY)
		for col in names.size():
			var id := StringName(names[col])
			var cell := Vector3(col, 0, row)
			if PROPERTIES.has(id):
				add_child(_at(PropertyModels3D.build(id, theme), cell))
			else:
				_place_unit(id, theme, cell)
	return Vector2(names.size(), UNIT_ROWS.size())


func _place_unit(id: StringName, theme: CommanderVisuals.FactionTheme, cell: Vector3) -> void:
	if SEA.has(id):
		var water := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(0.98, 0.98)
		water.mesh = plane
		water.material_override = _flat(WATER)
		add_child(_at(water, cell + Vector3(0, 0.002, 0)))
	var model := UnitModels3D.build(id, theme)
	add_child(_at(model, cell))
	if AIR.has(id):
		model.position.y = BoardSpace3D.AIR_ALTITUDE
		AirShadow3D.lay(AirShadow3D.attach(model, id), model.position.y, 0.0)


func _at(node: Node3D, pos: Vector3) -> Node3D:
	node.position = pos
	return node


func _flat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material


## Ground, sun, sky light and a camera pitched like the board's, framing a
## `extent` of cells (columns, rows) laid out from the origin with `margin`
## cells to spare.
func _stage(extent: Vector2, margin: float) -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(extent.x + 6, extent.y + 6)
	ground.mesh = plane
	ground.material_override = _flat(GRASS)
	var centre := Vector3((extent.x - 1) / 2.0, 0, (extent.y - 1) / 2.0)
	add_child(_at(ground, centre + Vector3(0, -0.001, 0)))

	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.light_energy = 0.9
	sun.rotation_degrees = Vector3(-55, -35, 0)
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("20262c")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c8d4e0")
	env.ambient_light_energy = 0.4
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)

	var camera := Camera3D.new()
	camera.fov = 30.0
	var width := maxf(extent.x, extent.y * 1.9) + margin
	var distance := width / 2.0 / (tan(deg_to_rad(camera.fov / 2.0)) * 16.0 / 9.0)
	var pitch := deg_to_rad(PITCH_DEG)
	camera.position = centre + Vector3(0, sin(pitch), cos(pitch)) * distance
	camera.rotation = Vector3(-pitch, 0, 0)
	add_child(camera)
	camera.make_current()
