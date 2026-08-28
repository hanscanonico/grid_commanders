extends GutTest
## Cross-consumer checks for the live selector. Exact data and resolver replay
## have their own focused files; these pin the two callers most likely to retain
## the old global dry-ammo shortcut.

var unit_db: UnitDB


func before_each() -> void:
	unit_db = Fixture.unit_db()


func test_ai_uses_a_dry_tanks_secondary() -> void:
	var state := Fixture.state("[terrain]\n==\n[units]\n1 t 0 0\n2 i 1 0")
	state.units[0].ammo = 0
	var command := AIController.new(unit_db, AIProfile.load_default()).plan_next_command(state)
	assert_true(command is AttackCommand, "the dry Tank should still take its legal MG shot")
	assert_eq((command as AttackCommand).target_cell, Vector2i(1, 0))


func test_threat_map_prices_a_dry_tank_per_target() -> void:
	var state := Fixture.state("[terrain]\n=====\n[units]\n2 t 4 0")
	var enemy := state.units[0]
	enemy.ammo = 0
	var map := ThreatMap.build(state, [enemy])
	var infantry := Unit.create(unit_db.by_id(&"infantry"), 1, Vector2i(0, 0))
	var tank := Unit.create(unit_db.by_id(&"tank"), 1, Vector2i(0, 0))
	var fighter := Unit.create(unit_db.by_id(&"fighter"), 1, Vector2i(0, 0))
	assert_eq(map.incoming_damage(state, infantry, Vector2i(0, 0)), 75)
	assert_eq(map.incoming_damage(state, tank, Vector2i(0, 0)), 6)
	assert_eq(map.incoming_damage(state, fighter, Vector2i(0, 0)), 0)
