extends GutTest
## The Blender-built models against the contract the board places them by, the
## same one `test_unit_models_3d.gd` holds the code models to: a footprint inside
## the cell, the height of its domain, the tiers that tell a unit from its
## neighbours, and everything the game asks of a model's file by name.

const TOLERANCE := 0.006
const UNIT_HALF := 0.42
const PROPERTY_HALF := 0.46
const PROPERTY_TOP := 0.85
const AIR_TOP := 0.325
const SEA_TOP := 0.45
const SEA_KEEL := -0.06
const SUB_KEEL := -0.1
const LAND_TOP := 0.42
const LAND_LOWEST_TOP := 0.22
const ARTILLERY_TOP := 0.8
const UNARMED: Array[StringName] = [&"apc", &"t_copter", &"lander"]
const BONES: Array[StringName] = [
	&"hips",
	&"torso",
	&"head",
	&"arm_l",
	&"arm_r",
	&"fore_l",
	&"fore_r",
	&"leg_l",
	&"leg_r",
	&"shin_l",
	&"shin_r",
	&"prop",
]


func before_each() -> void:
	PaintedArt.force(true)


func after_each() -> void:
	PaintedArt.force(false)


func _model(id: StringName) -> PaintedModels3D.Baked:
	return PaintedModels3D.baked(PaintedModels3D.UNITS, id)


func _within_footprint(aabb: AABB, half: float, what: String) -> void:
	assert_gte(aabb.position.x, -half - TOLERANCE, "%s reaches past -X" % what)
	assert_lte(aabb.end.x, half + TOLERANCE, "%s reaches past +X" % what)
	assert_gte(aabb.position.z, -half - TOLERANCE, "%s reaches past -Z" % what)
	assert_lte(aabb.end.z, half + TOLERANCE, "%s reaches past +Z" % what)


func test_the_switch_can_still_show_the_code_models() -> void:
	PaintedArt.force(false)
	assert_false(PaintedArt.on())
	var code_model := UnitModels3D.build(&"tank", CommanderVisuals.theme_for(null))
	assert_true(ModelSkin3D.materials_of(code_model)[0] is StandardMaterial3D)
	code_model.free()


func test_every_unit_has_a_model_inside_its_cell() -> void:
	for unit_type in Fixture.unit_db().all():
		var what := String(unit_type.id)
		assert_true(PaintedModels3D.exists(PaintedModels3D.UNITS, unit_type.id), what)
		var aabb := _model(unit_type.id).mesh.get_aabb()
		_within_footprint(aabb, UNIT_HALF, what)
		match unit_type.domain:
			UnitType.AIR:
				assert_gte(aabb.position.y, -TOLERANCE, "%s dips below its belly" % what)
				assert_lte(aabb.end.y, AIR_TOP + TOLERANCE, "%s is too tall" % what)
			UnitType.SEA:
				var keel := SUB_KEEL if unit_type.id == &"sub" else SEA_KEEL
				assert_gte(aabb.position.y, keel - TOLERANCE, "%s draws too deep" % what)
				assert_lte(aabb.end.y, SEA_TOP + TOLERANCE, "%s is too tall" % what)
			_:
				assert_gte(aabb.position.y, -TOLERANCE, "%s sinks into the ground" % what)
				var ceiling := ARTILLERY_TOP if unit_type.id == &"artillery" else LAND_TOP
				assert_between(aabb.end.y, LAND_LOWEST_TOP, ceiling + TOLERANCE, what)


func test_the_land_tiers_part_by_bulk() -> void:
	var recon := _model(&"recon").mesh.get_aabb()
	var tank := _model(&"tank").mesh.get_aabb()
	var md_tank := _model(&"md_tank").mesh.get_aabb()
	assert_lt(recon.size.x, tank.size.x, "recon is shorter than the tank")
	assert_lt(tank.size.x, md_tank.size.x, "tank is shorter than the medium tank")
	assert_lt(tank.end.y, md_tank.end.y, "tank is lower than the medium tank")
	assert_almost_eq(md_tank.end.x, UNIT_HALF, TOLERANCE, "the medium tank reaches the edge")
	assert_lt(_model(&"apc").mesh.get_aabb().end.y, tank.end.y, "the APC rides lower")
	assert_gt(_model(&"artillery").mesh.get_aabb().end.y, tank.end.y, "the barrel stands tallest")


func test_the_bomber_spans_widest_in_the_air() -> void:
	var bomber := _model(&"bomber").mesh.get_aabb().size.z
	for id: StringName in [&"fighter", &"b_copter", &"t_copter"]:
		assert_gt(bomber, _model(id).mesh.get_aabb().size.z, String(id))


func test_the_ships_part_by_length() -> void:
	var battleship := _model(&"battleship").mesh.get_aabb().size.x
	assert_gt(battleship, _model(&"cruiser").mesh.get_aabb().size.x)
	assert_gt(battleship, _model(&"sub").mesh.get_aabb().size.x)


func test_every_armed_unit_marks_its_muzzle_on_its_figure() -> void:
	for unit_type in Fixture.unit_db().all():
		var marked := PaintedModels3D.muzzle_of(unit_type.id, true)
		if UNARMED.has(unit_type.id):
			continue
		var what := String(unit_type.id)
		assert_true(marked.is_finite(), "%s has no muzzle" % what)
		var figure := UnitModels3D.figure_mesh_for(unit_type.id, CommanderVisuals.theme_for(null))
		var box := figure.get_aabb().grow(0.05)
		assert_true(box.has_point(marked), "%s's muzzle is off its figure" % what)


func test_a_foot_unit_posts_a_lone_figure_in_a_cut_in() -> void:
	for id: StringName in [&"infantry", &"mech"]:
		var lone := PaintedModels3D.unit_id(id, true)
		assert_ne(lone, id)
		assert_true(PaintedModels3D.exists(PaintedModels3D.UNITS, lone), String(lone))


func test_a_helicopter_builds_a_rotor_at_every_hub() -> void:
	var theme := CommanderVisuals.theme_for(null)
	for id: StringName in AirModels3D.ROTOR_HUBS:
		var model := UnitModels3D.build(id, theme)
		var hubs: Array = AirModels3D.ROTOR_HUBS[id]
		for i in hubs.size():
			var rotor := model.get_node(UnitModels3D.ROTOR_PART % i) as MeshInstance3D
			assert_eq(rotor.position, hubs[i] as Vector3)
			var reach: float = rotor.mesh.get_aabb().end.x
			assert_lte(absf(rotor.position.x) + reach, 0.5 + TOLERANCE, "%s's rotor" % id)
		model.free()


func test_every_property_has_a_model_inside_its_cell_and_the_hq_is_tallest() -> void:
	var hq := PaintedModels3D.baked(PaintedModels3D.BUILDINGS, &"hq").mesh.get_aabb().end.y
	for id: StringName in [&"city", &"base", &"airport", &"port", &"hq"]:
		var aabb := PaintedModels3D.baked(PaintedModels3D.BUILDINGS, id).mesh.get_aabb()
		_within_footprint(aabb, PROPERTY_HALF, String(id))
		assert_lte(aabb.end.y, PROPERTY_TOP + TOLERANCE, String(id))
		if id != &"hq":
			assert_lt(aabb.end.y, hq, String(id))


func test_every_general_has_a_figure_on_the_skeleton_the_clips_pose() -> void:
	var ids: Array[StringName] = [CommanderActor3D.PAINTED_OFFICER]
	for commander in CommanderDB.load_default().all():
		if commander.id != CommanderType.NEUTRAL_ID:
			ids.append(commander.id)
	for id in ids:
		assert_true(PaintedModels3D.exists(PaintedModels3D.GENERALS, id), String(id))
		var path := PaintedModels3D.ROOT % [PaintedModels3D.GENERALS, "%s.glb" % id]
		var figure: Node3D = load(path).instantiate()
		var skeleton: Skeleton3D = figure.find_children("*", "Skeleton3D", true, false)[0]
		for bone in BONES:
			assert_gte(skeleton.find_bone(String(bone)), 0, "%s lacks %s" % [id, bone])
		figure.free()


func test_a_flip_reuses_one_mesh_and_recolours_its_material() -> void:
	var red := PropertyModels3D.mesh_for(&"city", CommanderVisuals.theme_for_key(&"meridian"))
	var blue := PropertyModels3D.mesh_for(&"city", CommanderVisuals.theme_for_key(&"aurora"))
	assert_same(red, blue)


func test_a_captured_building_takes_the_badge_nobody_wore_before_it() -> void:
	var nobody := CommanderVisuals.theme_for_key(CommanderVisuals.NEUTRAL_KEY)
	var army := CommanderVisuals.theme_for_key(&"meridian")
	var material := PaintedModels3D.material_for(PaintedModels3D.BUILDINGS, &"base", nobody)
	assert_null(material.get_shader_parameter(&"emblem"), "nobody wears no badge")
	PaintedModels3D.wear(material, army)
	assert_not_null(material.get_shader_parameter(&"emblem"), "the army's badge goes on")
	assert_gt(float(material.get_shader_parameter(&"emblem_radius")), 0.0, "and it has a size")
	PaintedModels3D.wear(material, nobody)
	assert_null(material.get_shader_parameter(&"emblem"), "and it comes off again")


func test_terrain_tiles_and_models_are_there() -> void:
	for tile: String in ["grass", "floor", "road", "sand", "earth"]:
		assert_true(ResourceLoader.exists(PaintedBoard3D.TEXTURES % tile), tile)
	for id: StringName in [&"woods", &"mountain"]:
		assert_true(PaintedModels3D.exists(PaintedModels3D.TERRAIN, id), String(id))
