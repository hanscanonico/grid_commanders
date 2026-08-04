extends GutTest

var db: TerrainDB


func before_each() -> void:
	db = TerrainDB.load_default()


## The database is a directory scan, so the number worth pinning is "all of
## them", not a literal. Registration drops a terrain silently on a duplicate id
## or symbol, and that is the failure this catches; spelling the count out here
## would only be a chore every time the roster grows.
func test_loads_every_terrain_resource() -> void:
	assert_eq(db.size(), _resource_count(TerrainDB.TERRAIN_DIR))
	assert_gt(db.size(), 0, "data/terrain should not be empty")


func test_lookup_by_symbol() -> void:
	assert_eq(db.by_symbol(".").id, &"plains")
	assert_eq(db.by_symbol("Q").display_name, "HQ")
	assert_null(db.by_symbol("?"))


func test_lookup_by_id() -> void:
	assert_eq(db.by_id(&"woods").defense_stars, 2)
	assert_null(db.by_id(&"nonexistent"))


func test_sea_impassable_for_all_ground_classes() -> void:
	var sea := db.by_id(&"sea")
	for move_class: StringName in [
		TerrainType.FOOT,
		TerrainType.BOOT,
		TerrainType.TIRES,
		TerrainType.TREADS,
	]:
		assert_false(sea.is_passable(move_class), "sea should block %s" % move_class)
		assert_eq(sea.move_cost(move_class), TerrainType.IMPASSABLE)


func test_mountain_costs() -> void:
	var mountain := db.by_id(&"mountain")
	assert_eq(mountain.move_cost(TerrainType.FOOT), 2)
	assert_eq(mountain.move_cost(TerrainType.BOOT), 1)
	assert_false(mountain.is_passable(TerrainType.TIRES))
	assert_false(mountain.is_passable(TerrainType.TREADS))


func test_woods_slow_vehicles() -> void:
	var woods := db.by_id(&"woods")
	assert_eq(woods.move_cost(TerrainType.TIRES), 3)
	assert_eq(woods.move_cost(TerrainType.TREADS), 2)
	assert_eq(woods.move_cost(TerrainType.FOOT), 1)


func test_properties_flagged() -> void:
	for id: StringName in [&"city", &"base", &"hq"]:
		assert_true(db.by_id(id).is_property, "%s should be a property" % id)
		assert_true(db.by_id(id).team_tinted)
	assert_false(db.by_id(&"plains").is_property)


## `GameState.home_hqs`, the save's home-HQ check and the AI's capture multiplier
## all read this flag instead of naming the id, so an HQ that lost it would leave
## every seat homeless without anything else failing. A terrain that carries it
## has to be capturable, or the seat it homes could never change hands.
func test_headquarters_flagged() -> void:
	assert_true(db.by_id(&"hq").is_headquarters, "the HQ is an army's seat of command")
	assert_false(db.by_id(&"city").is_headquarters)
	assert_false(db.by_id(&"base").is_headquarters)
	for terrain in db.all():
		if terrain.is_headquarters:
			assert_true(
				terrain.is_property, "%s is a headquarters, so it must capture" % terrain.id
			)


func test_defense_stars() -> void:
	assert_eq(db.by_id(&"road").defense_stars, 0)
	assert_eq(db.by_id(&"plains").defense_stars, 1)
	assert_eq(db.by_id(&"city").defense_stars, 3)
	assert_eq(db.by_id(&"hq").defense_stars, 4)
	assert_eq(db.by_id(&"mountain").defense_stars, 4)


## Every terrain admits aircraft at cost 1: that one row of data, and nothing in
## the movement resolver, is the whole air movement model. A terrain added
## without it would quietly become a hole in the sky.
func test_every_terrain_is_flyable_at_cost_one() -> void:
	for terrain in db.all():
		assert_eq(
			terrain.move_cost(TerrainType.AIR),
			1,
			"%s should cost an aircraft exactly one point to cross" % terrain.id
		)


## The cut-in's two presentation keys are one decision written in two fields, and
## nothing at draw time can tell that they disagree: `stands_in_cutin` reads
## `cutin_ground` alone and the scenery reads `cutin_scenery` alone. A terrain
## carrying only one of them paves the frame with its own art *and* stands
## silhouettes on it — the carpet the split exists to stop — and the wrong
## pavement is just as silent: an id no terrain answers to falls back to the cell
## itself, and one that stands rather than paves floors the frame in buildings,
## since the lookup is done once and never followed further. A shape outside the
## vocabulary is the third: the renderer's match falls through to buildings, so a
## typo puts towers on a mountain. All three come from a data edit, so this is
## where they are caught.
func test_cut_in_ground_and_scenery_are_one_decision() -> void:
	var shapes: Array[StringName] = [TerrainType.BUILDINGS, TerrainType.TREES, TerrainType.PEAKS]
	for terrain in db.all():
		assert_eq(
			terrain.stands_in_cutin(),
			terrain.cutin_scenery != TerrainType.NO_SCENERY,
			"%s should name a pavement and a shape together, or neither" % terrain.id
		)
		if not terrain.stands_in_cutin():
			continue
		assert_has(shapes, terrain.cutin_scenery, "%s stands an unknown shape" % terrain.id)
		var paving := db.by_id(terrain.cutin_ground)
		assert_not_null(
			paving,
			(
				"%s is paved with '%s', which no terrain answers to"
				% [terrain.id, terrain.cutin_ground]
			)
		)
		if paving == null:
			continue
		assert_false(
			paving.stands_in_cutin(),
			"%s stands on %s, which stands rather than paves" % [terrain.id, paving.id]
		)


## Which property builds what, and which refits what, is terrain data — the
## facilities the base game shipped with have to keep saying what they always
## meant, or every land unit quietly loses production and repair.
func test_land_properties_build_and_service_the_ground_army() -> void:
	var base := db.by_id(&"base")
	for move_class: StringName in [
		TerrainType.FOOT, TerrainType.BOOT, TerrainType.TIRES, TerrainType.TREADS
	]:
		assert_true(base.can_build(move_class), "a base should build %s units" % move_class)
	assert_false(base.can_build(TerrainType.AIR), "a base should not build aircraft")
	for id: StringName in [&"city", &"base", &"hq"]:
		assert_true(db.by_id(id).services_domain(UnitType.LAND), "%s should refit vehicles" % id)
		assert_false(db.by_id(id).services_domain(UnitType.AIR), "%s should not refit air" % id)
	for id: StringName in [&"city", &"hq"]:
		assert_true(db.by_id(id).builds.is_empty(), "%s should not be a factory" % id)


func test_airport_builds_and_services_only_aircraft() -> void:
	var airport := db.by_id(&"airport")
	assert_true(airport.is_property, "an airport should be capturable and pay income")
	assert_true(airport.can_build(TerrainType.AIR))
	assert_false(airport.can_build(TerrainType.TREADS), "an airport should not build tanks")
	assert_true(airport.services_domain(UnitType.AIR))
	assert_false(airport.services_domain(UnitType.LAND), "tanks refit at a city, not a hangar")
	assert_true(
		airport.is_passable(TerrainType.FOOT), "ground units should be able to walk onto the field"
	)


## Reads data/terrain the way TerrainDB does, so the count is derived rather than
## restated.
func _resource_count(dir_path: String) -> int:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return -1
	var count := 0
	for file in dir.get_files():
		if file.trim_suffix(".remap").ends_with(".tres"):
			count += 1
	return count


## Sea admits hulls and nothing else that drives. This is the whole naval
## movement model, exactly as `air: 1` everywhere is the air one.
func test_sea_carries_hulls_only() -> void:
	var sea := db.by_id(&"sea")
	assert_eq(sea.move_cost(TerrainType.SHIP), 1)
	assert_eq(sea.move_cost(TerrainType.LANDER), 1)
	for move_class: StringName in [
		TerrainType.FOOT, TerrainType.BOOT, TerrainType.TIRES, TerrainType.TREADS
	]:
		assert_false(sea.is_passable(move_class), "%s should not cross open water" % move_class)


## A shoal is the beach a lander runs onto: land units and the landing craft,
## never a warship. A bridge is the mirror image — everything that drives, and no
## hull at all, which is what makes it a chokepoint on the water as well as a
## crossing on land.
func test_shoals_and_bridges_split_the_fleet_from_the_army() -> void:
	var shoal := db.by_id(&"shoal")
	assert_true(shoal.is_passable(TerrainType.TREADS))
	assert_true(shoal.is_passable(TerrainType.LANDER))
	assert_false(shoal.is_passable(TerrainType.SHIP), "a warship cannot beach itself")
	var bridge := db.by_id(&"bridge")
	assert_true(bridge.is_passable(TerrainType.TREADS))
	assert_false(bridge.is_passable(TerrainType.SHIP), "hulls do not fit under a bridge")
	assert_false(bridge.is_passable(TerrainType.LANDER))


func test_reefs_slow_hulls_and_hide_them() -> void:
	var reef := db.by_id(&"reef")
	assert_eq(reef.move_cost(TerrainType.SHIP), 2)
	assert_false(reef.is_passable(TerrainType.FOOT), "a reef is still open water to an army")
	assert_true(reef.conceals, "a reef is the sea's woods")
	assert_true(db.by_id(&"woods").conceals, "and woods still conceal, now that it is a flag")
	assert_false(db.by_id(&"plains").conceals)


func test_port_builds_and_services_only_hulls() -> void:
	var port := db.by_id(&"port")
	assert_true(port.is_property)
	assert_true(port.can_build(TerrainType.SHIP))
	assert_true(port.can_build(TerrainType.LANDER))
	assert_false(port.can_build(TerrainType.TREADS), "a dockyard does not turn out tanks")
	assert_true(port.services_domain(UnitType.SEA))
	assert_false(port.services_domain(UnitType.LAND))
	assert_true(port.is_passable(TerrainType.SHIP), "a hull has to be able to tie up at it")
	assert_true(port.is_passable(TerrainType.FOOT), "and an infantryman to walk up and take it")
