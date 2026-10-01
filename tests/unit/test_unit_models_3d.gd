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
## The sub rides sunk, only its hull's top third clear of the water, so its
## keel runs deeper than a surface ship's.
const SUB_KEEL := -0.1
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
				var keel := SUB_KEEL if unit_type.id == &"sub" else SEA_KEEL
				assert_gte(aabb.position.y, keel - TOLERANCE, "%s draws too deep" % what)
				assert_lte(top, SEA_TOP + TOLERANCE, "%s is too tall" % what)
			_:
				assert_gte(aabb.position.y, -TOLERANCE, "%s sinks into the ground" % what)
				var ceiling := ARTILLERY_TOP if unit_type.id == &"artillery" else LAND_TOP
				assert_between(top, LAND_LOWEST_TOP, ceiling + TOLERANCE, "%s height" % what)


func _model(id: StringName) -> AABB:
	return UnitModels3D.mesh_for(id, _theme(&"meridian")).get_aabb()


func test_the_artillery_barrel_is_the_tallest_thing_on_model() -> void:
	var aabb := _model(&"artillery")
	var artillery := aabb.end.y
	var muzzle := UnitModels3D.muzzle_for(&"artillery", aabb)
	assert_almost_eq(muzzle.y, artillery, 0.03, "the cut-in fires from the barrel's top")
	for unit_type in Fixture.unit_db().all():
		if unit_type.domain == UnitType.LAND and unit_type.id != &"artillery":
			assert_lt(_model(unit_type.id).end.y, artillery, String(unit_type.id))


## The tiers part by bulk: a recon under a tank under a medium tank, which
## reaches the cell's edge and carries the thicker gun; the tank's gun stays
## short of the cell's edge, and the APC rides lower than the tank.
func test_the_land_tiers_part_by_bulk() -> void:
	var recon := _model(&"recon")
	var tank := _model(&"tank")
	var md_tank := _model(&"md_tank")
	assert_lt(recon.size.x, tank.size.x, "recon is shorter than the tank")
	assert_lt(tank.size.x, md_tank.size.x, "tank is shorter than the medium tank")
	assert_lt(tank.end.y, md_tank.end.y, "tank is lower than the medium tank")
	assert_lt(tank.end.x, md_tank.end.x, "the tank's gun is the shorter")
	assert_almost_eq(md_tank.end.x, UNIT_HALF, TOLERANCE, "the medium tank reaches the edge")
	assert_gte(TrackedModels3D.MD_TANK_GUN, TrackedModels3D.TANK_GUN * 1.55, "the thicker gun")
	assert_lt(_model(&"apc").end.y, tank.end.y, "the APC rides lower than the tank")


## The bomber is the biggest thing in the air: the widest span of any
## aircraft, and at least the review's fifteen percent past the fighter's. Its
## span was capped inside the cell, so the fighter was narrowed with it.
func test_the_bomber_spans_widest_in_the_air() -> void:
	var bomber := _model(&"bomber").size.z
	for id: StringName in [&"fighter", &"b_copter", &"t_copter"]:
		assert_lt(_model(id).size.z, bomber, String(id))
	assert_gte(bomber, _model(&"fighter").size.z * 1.15, "the bomber's span over the fighter's")


## The transport is the tandem: one rotor over its cab, one on a raised pylon
## at its tail, where the gunship turns one.
func test_the_transport_flies_on_tandem_rotors() -> void:
	var tandem: Array = AirModels3D.ROTOR_HUBS[&"t_copter"]
	assert_eq(tandem.size(), 2)
	assert_gt(tandem[0].x, 0.0, "the fore rotor rides over the cab")
	assert_lt(tandem[1].x, 0.0, "the aft rotor rides over the tail")
	assert_gt(tandem[1].y, tandem[0].y, "the aft rotor stands on its raised pylon")
	assert_eq(AirModels3D.ROTOR_HUBS[&"b_copter"].size(), 1)


## A spinning rotor is part of its unit, so its disc stays inside the cell the
## body's footprint is held to.
func test_every_rotor_disc_stays_in_its_cell() -> void:
	for id: StringName in AirModels3D.ROTOR_HUBS:
		var radius: float = AirModels3D.ROTOR_RADII[id]
		for hub: Vector3 in AirModels3D.ROTOR_HUBS[id]:
			assert_lte(absf(hub.x) + radius, UNIT_HALF + TOLERANCE, String(id))
			assert_lte(absf(hub.z) + radius, UNIT_HALF + TOLERANCE, String(id))


## The battleship fills the cell's length, the cruiser runs about four-fifths
## of it and the sub a little more, and the sub's hull is mostly under water.
func test_the_ships_part_by_length_and_the_sub_rides_sunk() -> void:
	var battleship := _model(&"battleship").size.x
	assert_almost_eq(battleship, 2.0 * UNIT_HALF, TOLERANCE, "the battleship fills the cell")
	assert_almost_eq(_model(&"cruiser").size.x / battleship, 0.8, 0.04, "the cruiser's length")
	assert_almost_eq(_model(&"sub").size.x / battleship, 0.85, 0.04, "the sub's length")
	var clear := SeaModels3D.SUB_HULL_CENTRE + SeaModels3D.SUB_HULL_RISE
	assert_gt(clear, 0.0, "the sub's hull breaks the surface")
	assert_lte(clear / (2.0 * SeaModels3D.SUB_HULL_RISE), 0.36, "only its top third clears")


## Heavy turret guns stand far enough apart that two read as two, not as one
## grey stripe: the gap between them is itself a visible part. They are heavier
## than the least gun, and well over twice as long as they are thick — the
## crates they once read as were under twice — so a pair reads as two guns.
func test_a_turret_gun_stands_clear_of_its_neighbour() -> void:
	var gap := SeaModels3D.GUN_SPACING - SeaModels3D.GUN_THICKNESS
	assert_gte(gap, UnitParts3D.MIN_THICKNESS / 2.0, "the gap between a turret's guns")
	assert_gt(SeaModels3D.GUN_THICKNESS, UnitParts3D.MIN_THICKNESS, "a heavy gun")
	assert_gte(SeaModels3D.GUN_LENGTH, SeaModels3D.GUN_THICKNESS * 2.5, "a gun, not a crate")


## A cut-in figure's shot leaves from somewhere on the figure, so a muzzle a
## builder states cannot drift off a gun it has since moved.
func test_every_muzzle_is_on_its_figure() -> void:
	for unit_type in Fixture.unit_db().all():
		var aabb := UnitModels3D.figure_mesh_for(unit_type.id, _theme(&"meridian")).get_aabb()
		var muzzle := UnitModels3D.muzzle_for(unit_type.id, aabb)
		assert_true(aabb.grow(TOLERANCE).has_point(muzzle), String(unit_type.id))


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
## lit tone but the Gilded Concord's yellow, so neither melts into its hull —
## the Iron Dominion's above all. A gold barrel parts from its hull by hue.
func test_the_parts_vocabulary_clears_every_army() -> void:
	var rubber := UnitPalette3D.RUBBER.get_luminance()
	var steel := UnitPalette3D.STEEL.get_luminance()
	var gold := FactionRamp3D.of(_theme(&"gold"))
	for ramp in _armies():
		assert_lt(rubber, ramp.dark.get_luminance(), "rubber under %s's dark" % ramp.dark)
		if ramp != gold:
			assert_gt(steel, ramp.light.get_luminance(), "steel over %s's light" % ramp.light)


## White means ordnance or an aircraft's livery: no grey part is lighter than
## the light steel a vehicle's panel wears, and that stays under both.
func test_white_is_kept_for_ordnance_and_livery() -> void:
	var cap := UnitPalette3D.STEEL_LIGHT.get_luminance()
	for grey: Color in [
		UnitPalette3D.STEEL,
		UnitPalette3D.STEEL_MID,
		UnitPalette3D.GUNMETAL,
		UnitPalette3D.RUBBER,
		UnitPalette3D.GLASS,
		UnitPalette3D.PLATING,
	]:
		assert_lte(grey.get_luminance(), cap, "%s over the light steel" % grey)
	for white: Color in [UnitPalette3D.ORDNANCE, UnitPalette3D.LIVERY]:
		assert_gt(white.get_luminance(), cap, "%s under the light steel" % white)


func _wears(id: StringName, colour: Color) -> bool:
	for seen in _colours(UnitModels3D.mesh_for(id, _theme(&"iron"))):
		var off := maxf(
			absf(seen.r - colour.r), maxf(absf(seen.g - colour.g), absf(seen.b - colour.b))
		)
		if off < COLOUR_STEP:
			return true
	return false


## Livery white is the aircraft's alone and cream the battleship's deck's alone.
func test_livery_flies_and_cream_is_the_battleships_deck() -> void:
	for unit_type in Fixture.unit_db().all():
		var id := unit_type.id
		if unit_type.domain != UnitType.AIR:
			assert_false(_wears(id, UnitPalette3D.LIVERY), "%s wears livery" % id)
		if id != &"battleship":
			assert_false(_wears(id, UnitPalette3D.DECK), "%s wears the deck's cream" % id)
	assert_true(_wears(&"battleship", UnitPalette3D.DECK))


## The lit tone is the army's own base raised in lightness alone, so a top
## face keeps the army's colour rather than paling toward a tint of it. A ramp
## lowered whole onto the ceiling (the Gilded Concord's) is deepened past that.
func test_the_lit_tone_keeps_the_armys_saturation() -> void:
	for key in CommanderVisuals.FACTION_ORDER:
		var ramp := FactionRamp3D.of(_theme(key))
		if ramp.light.get_luminance() >= FactionRamp3D.LIT_CEILING - 0.001:
			continue
		assert_almost_eq(ramp.light.ok_hsl_s, ramp.base.ok_hsl_s, 0.03, "%s's saturation" % key)
		assert_gt(ramp.light.ok_hsl_l, ramp.base.ok_hsl_l, "%s's light is lighter" % key)


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


## A barrel or a mast asked for thinner than its floor comes out at it, in a
## scaled frame as well as a plain one: a weapon at `MIN_THICKNESS`, a mast or an
## antenna at the thinner `MAST_THICKNESS`, so it never reads as a chimney.
func test_a_thin_part_cannot_be_authored() -> void:
	var least := UnitParts3D.MIN_THICKNESS - TOLERANCE
	var least_mast := UnitParts3D.MAST_THICKNESS - TOLERANCE
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
		assert_gte(mast.size.x, least_mast, "a mast's depth")
		assert_gte(mast.size.z, least_mast, "a mast's width")
		assert_lt(mast.size.x, least, "a mast stays thinner than a weapon")
	assert_lt(UnitParts3D.MAST_THICKNESS, UnitParts3D.MIN_THICKNESS)
	for id: StringName in AirModels3D.BLADE_CHORDS:
		assert_gte(AirModels3D.BLADE_CHORDS[id], UnitParts3D.MIN_THICKNESS, "%s's blade" % id)


## A flyer's shadow darkens the ground under its body by `SHADE` and leaves the
## rest of its tile clear, so it marks the cell without hiding it.
func test_an_air_shadow_darkens_only_under_its_body() -> void:
	var atlas := AirShadow3D.atlas()
	var px := AirShadow3D.TILE_PX
	for tile in AirShadow3D.FLYERS.size():
		var centre := atlas.get_pixel(tile * px + px / 2, px / 2).r
		assert_almost_eq(centre, AirShadow3D.SHADE, 0.01, "%s's shadow" % AirShadow3D.FLYERS[tile])
		assert_eq(atlas.get_pixel(tile * px, 0).r, 1.0, "the clear corner")
