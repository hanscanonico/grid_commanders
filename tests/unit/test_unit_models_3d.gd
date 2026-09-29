extends GutTest
## The 3D board's models against the geometry contract the board places them by:
## one cell is one world unit, a unit's footprint stays inside its cell, and a
## property leaves room for the unit standing on it. `mesh_for` returns a Resource
## and builds no Node, so the contract is checked without a scene.

const TOLERANCE := 0.005
const UNIT_HALF := 0.42
const PROPERTY_HALF := 0.46
const PROPERTY_TOP := 0.85
const AIR_TOP := 0.32
const SEA_TOP := 0.45
const SEA_KEEL := -0.06
const LAND_TOP := 0.42
const LAND_LOWEST_TOP := 0.22


func _theme(key: StringName) -> CommanderVisuals.FactionTheme:
	return CommanderVisuals.theme_for_key(key)


func _within_footprint(aabb: AABB, half: float, what: String) -> void:
	var end := aabb.end
	assert_gte(aabb.position.x, -half - TOLERANCE, "%s reaches past -X" % what)
	assert_lte(end.x, half + TOLERANCE, "%s reaches past +X" % what)
	assert_gte(aabb.position.z, -half - TOLERANCE, "%s reaches past -Z" % what)
	assert_lte(end.z, half + TOLERANCE, "%s reaches past +Z" % what)


func test_every_unit_has_a_model_inside_its_cell() -> void:
	var units := Fixture.unit_db().all()
	assert_eq(units.size(), 18)
	for unit_type in units:
		var mesh := UnitModels3D.mesh_for(unit_type.id, _theme(&"meridian"))
		var what := String(unit_type.id)
		assert_gt(mesh.get_surface_count(), 0, "%s has no mesh" % what)
		var aabb := mesh.get_aabb()
		_within_footprint(aabb, UNIT_HALF, what)
		var top := aabb.end.y
		match unit_type.domain:
			UnitType.AIR:
				assert_gte(aabb.position.y, -TOLERANCE, "%s dips below its belly" % what)
				assert_lte(top, AIR_TOP + TOLERANCE, "%s is too tall" % what)
			UnitType.SEA:
				assert_gte(aabb.position.y, SEA_KEEL - TOLERANCE, "%s draws too deep" % what)
				assert_lte(top, SEA_TOP + TOLERANCE, "%s is too tall" % what)
			_:
				assert_gte(aabb.position.y, -TOLERANCE, "%s sinks into the ground" % what)
				assert_between(top, LAND_LOWEST_TOP, LAND_TOP + TOLERANCE, "%s height" % what)


func test_every_property_has_a_model_inside_its_cell() -> void:
	var properties: Array[StringName] = []
	for terrain in Fixture.terrain_db().all():
		if terrain.is_property:
			properties.append(terrain.id)
	assert_eq(properties.size(), 5)
	for id in properties:
		var mesh := PropertyModels3D.mesh_for(id, _theme(CommanderVisuals.NEUTRAL_KEY))
		var aabb := mesh.get_aabb()
		assert_gt(mesh.get_surface_count(), 0, "%s has no mesh" % id)
		_within_footprint(aabb, PROPERTY_HALF, String(id))
		assert_gte(aabb.position.y, -TOLERANCE, "%s sinks into the ground" % id)
		assert_lte(aabb.end.y, PROPERTY_TOP, "%s is too tall" % id)


func test_the_hq_is_the_tallest_property() -> void:
	var neutral := _theme(CommanderVisuals.NEUTRAL_KEY)
	var hq := PropertyModels3D.mesh_for(&"hq", neutral).get_aabb().end.y
	for id: StringName in [&"city", &"base", &"airport", &"port"]:
		assert_lt(PropertyModels3D.mesh_for(id, neutral).get_aabb().end.y, hq, String(id))


func _colours(mesh: ArrayMesh) -> PackedColorArray:
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]


func test_two_owners_paint_the_same_model_differently() -> void:
	var red := UnitModels3D.mesh_for(&"tank", _theme(&"meridian"))
	var blue := UnitModels3D.mesh_for(&"tank", _theme(&"aurora"))
	assert_ne(_colours(red), _colours(blue))
	var ours := PropertyModels3D.mesh_for(&"city", _theme(&"meridian"))
	var nobody := PropertyModels3D.mesh_for(&"city", _theme(CommanderVisuals.NEUTRAL_KEY))
	assert_ne(_colours(ours), _colours(nobody))


func test_a_mesh_is_built_once_per_type_and_owner() -> void:
	var theme := _theme(&"verdant")
	assert_same(UnitModels3D.mesh_for(&"recon", theme), UnitModels3D.mesh_for(&"recon", theme))
	assert_same(
		PropertyModels3D.mesh_for(&"port", theme), PropertyModels3D.mesh_for(&"port", theme)
	)


func test_an_unknown_id_still_gets_a_model() -> void:
	var theme := _theme(&"gold")
	assert_gt(UnitModels3D.mesh_for(&"no_such_unit", theme).get_surface_count(), 0)
	assert_gt(PropertyModels3D.mesh_for(&"no_such_building", theme).get_surface_count(), 0)
