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
## The artillery's one long barrel is its identity, raised steeply over its hull
## higher than anything else on land: the one land unit past `LAND_TOP`.
const ARTILLERY_TOP := 0.8
## A mesh stores its vertex colours a byte a channel.
const COLOUR_STEP := 1.5 / 255.0


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
				var ceiling := ARTILLERY_TOP if unit_type.id == &"artillery" else LAND_TOP
				assert_between(top, LAND_LOWEST_TOP, ceiling + TOLERANCE, "%s height" % what)


func _land(id: StringName) -> AABB:
	return UnitModels3D.mesh_for(id, _theme(&"meridian")).get_aabb()


func test_the_artillery_barrel_is_the_tallest_thing_on_land() -> void:
	var aabb := _land(&"artillery")
	var artillery := aabb.end.y
	var muzzle := UnitModels3D.muzzle_for(&"artillery", aabb)
	assert_almost_eq(muzzle.y, artillery, 0.03, "the cut-in fires from the barrel's top")
	for unit_type in Fixture.unit_db().all():
		if unit_type.domain == UnitType.LAND and unit_type.id != &"artillery":
			assert_lt(_land(unit_type.id).end.y, artillery, String(unit_type.id))


## The tiers part by bulk: a recon under a tank under a medium tank, which
## reaches the cell's edge and carries the thicker gun; the tank's gun stays
## short of the cell's edge, and the APC rides lower than the tank.
func test_the_land_tiers_part_by_bulk() -> void:
	var recon := _land(&"recon")
	var tank := _land(&"tank")
	var md_tank := _land(&"md_tank")
	assert_lt(recon.size.x, tank.size.x, "recon is shorter than the tank")
	assert_lt(tank.size.x, md_tank.size.x, "tank is shorter than the medium tank")
	assert_lt(tank.end.y, md_tank.end.y, "tank is lower than the medium tank")
	assert_lt(tank.end.x, md_tank.end.x, "the tank's gun is the shorter")
	assert_almost_eq(md_tank.end.x, UNIT_HALF, TOLERANCE, "the medium tank reaches the edge")
	assert_gte(TrackedModels3D.MD_TANK_GUN, TrackedModels3D.TANK_GUN * 1.55, "the thicker gun")
	assert_lt(_land(&"apc").end.y, tank.end.y, "the APC rides lower than the tank")


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


func _armies() -> Array[FactionRamp3D]:
	var ramps: Array[FactionRamp3D] = []
	for key in CommanderVisuals.FACTION_ORDER:
		ramps.append(FactionRamp3D.of(_theme(key)))
	ramps.append(FactionRamp3D.of(_theme(CommanderVisuals.NEUTRAL_KEY)))
	return ramps


## Running gear under every army's darkest tone and a weapon over every army's
## lit tone, so neither melts into its hull — the Iron Dominion's above all.
func test_the_parts_vocabulary_clears_every_army() -> void:
	var rubber := UnitPalette3D.RUBBER.get_luminance()
	var steel := UnitPalette3D.STEEL.get_luminance()
	for ramp in _armies():
		assert_lt(rubber, ramp.dark.get_luminance(), "rubber under %s's dark" % ramp.dark)
		assert_gt(steel, ramp.light.get_luminance(), "steel over %s's light" % ramp.light)


func test_an_army_ramp_steps_from_dark_through_base_to_light() -> void:
	for ramp in _armies():
		assert_lt(ramp.dark.get_luminance(), ramp.base.get_luminance())
		assert_lt(ramp.base.get_luminance(), ramp.light.get_luminance())
		assert_lte(ramp.light.get_luminance(), FactionRamp3D.LIT_CEILING + 0.001)


## One rule places the three tones: a face painted base looks up and wears the
## light tone, looks down and wears the dark, and keeps base on the flanks.
func test_the_ramp_places_its_tones_by_facing() -> void:
	var ramp := FactionRamp3D.of(_theme(&"iron"))
	var st := MeshKit.begin()
	MeshKit.box(st, MeshKit.at(Vector3.ZERO), Vector3.ONE * 0.2, ramp.base)
	MeshKit.box(st, MeshKit.at(Vector3.UP), Vector3.ONE * 0.2, UnitPalette3D.STEEL)
	var arrays := ramp.commit(st).surface_get_arrays(0)
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in colours.size():
		var expected := ramp.base
		if vertices[i].y > 0.5:
			expected = UnitPalette3D.STEEL
		elif normals[i].y > 0.5:
			expected = ramp.light
		elif normals[i].y < -0.5:
			expected = ramp.dark
		var seen := colours[i]
		var off := maxf(
			absf(seen.r - expected.r), maxf(absf(seen.g - expected.g), absf(seen.b - expected.b))
		)
		assert_lt(off, COLOUR_STEP, "vertex %d facing %s wears %s" % [i, normals[i], seen])


func _thin_aabb(build: Callable) -> AABB:
	var st := MeshKit.begin()
	build.call(st)
	return st.commit().get_aabb()


## A barrel or a mast asked for thinner than the minimum comes out at it, in a
## scaled frame as well as a plain one.
func test_a_thin_part_cannot_be_authored() -> void:
	var least := UnitParts3D.MIN_THICKNESS - TOLERANCE
	var plain := MeshKit.at(Vector3.ZERO)
	var shrunk := Transform3D(Basis.from_scale(Vector3.ONE * 0.5), Vector3.ZERO)
	for xf: Transform3D in [plain, shrunk]:
		var barrel := _thin_aabb(
			func(st: SurfaceTool) -> void: UnitParts3D.barrel(st, xf, 0.3, 0.001, Color.WHITE)
		)
		assert_gte(barrel.size.y, least, "a barrel's height")
		assert_gte(barrel.size.z, least, "a barrel's width")
		var mast := _thin_aabb(
			func(st: SurfaceTool) -> void: UnitParts3D.mast(st, xf, 0.3, 0.001, Color.WHITE)
		)
		assert_gte(mast.size.x, least, "a mast's depth")
		assert_gte(mast.size.z, least, "a mast's width")
	assert_gte(AirModels3D.BLADE_CHORD, UnitParts3D.MIN_THICKNESS, "a rotor blade's chord")
