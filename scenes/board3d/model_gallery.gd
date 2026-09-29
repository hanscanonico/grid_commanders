extends Node3D
## Dev-only gallery for the 3D board's models: every unit in a row per faction
## and every property for neutral and two owners, under the board's camera
## angle, so the models are judged at the size they are played at.
##
## Boot with:  tools/godot_gui.sh --path . scenes/board3d/model_gallery.tscn --
##             [--screenshot=/abs.png] [--closeup=tank,md_tank,hq]
## `--closeup` lays out only the named units or properties, one row per faction,
## with the camera pulled in.

const UNIT_ROWS: Array[StringName] = [&"meridian", &"aurora", &"verdant", &"gold", &"iron"]
const PROPERTY_OWNERS: Array[StringName] = [&"neutral", &"meridian", &"iron"]
const PROPERTIES: Array[StringName] = [&"city", &"base", &"airport", &"port", &"hq"]
const AIR: Array[StringName] = [&"fighter", &"bomber", &"b_copter", &"t_copter"]
const SEA: Array[StringName] = [&"battleship", &"cruiser", &"lander", &"sub"]
const PITCH_DEG := 50.0
const GRASS := Color("5d8043")
const WATER := Color("3f78a8")


func _ready() -> void:
	var args := CmdArgs.user()
	var closeup := CmdArgs.value(args, "--closeup")
	var extent: Vector2
	if closeup.is_empty():
		extent = _lay_out_all()
	else:
		extent = _lay_out_closeup(closeup.split(",", false))
	_stage(extent)
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
	return Vector2(ids.size(), z0 + 1)


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
	var lift := Vector3(0, 0.35, 0) if AIR.has(id) else Vector3.ZERO
	add_child(_at(UnitModels3D.build(id, theme), cell + lift))


func _at(node: Node3D, pos: Vector3) -> Node3D:
	node.position = pos
	return node


func _flat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material


## Ground, sun, sky light and a camera pitched like the board's, framing a
## `extent` of cells (columns, rows) laid out from the origin.
func _stage(extent: Vector2) -> void:
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
	var width := maxf(extent.x, extent.y * 1.9) + 3.0
	var distance := width / 2.0 / (tan(deg_to_rad(camera.fov / 2.0)) * 16.0 / 9.0)
	var pitch := deg_to_rad(PITCH_DEG)
	camera.position = centre + Vector3(0, sin(pitch), cos(pitch)) * distance
	camera.rotation = Vector3(-pitch, 0, 0)
	add_child(camera)
	camera.make_current()
