extends GutTest
## The hook layer itself: that the neutral commander really is neutral, and that
## the damage formula's golden values do not move.
##
## This file is the R1 guard. Every general is balance-tested against the chain
## in CombatResolver's header, so a reordered multiplier or a second rounding has
## to fail here before it can quietly re-balance twenty-two doctrines at once.

const COMMANDER_DIR := "res://data/commanders"

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = Fixture.terrain_db()
	unit_db = Fixture.unit_db()
	chart = Fixture.chart()


func _fight(attacker: Unit, defender: Unit) -> Engagement:
	return Engagement.create(
		attacker,
		attacker.cell,
		attacker.displayed_hp(),
		defender,
		defender.cell,
		defender.displayed_hp()
	)


# --- the neutral commander ---------------------------------------------------


func test_teams_start_neutral() -> void:
	var state := Fixture.state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	for team in GameState.TEAMS:
		assert_eq(state.commander_of(team).id, CommanderType.NEUTRAL_ID)
		assert_false(state.commander_of(team).has_power())
		assert_false(state.power_active(team))
		assert_eq(state.commander_state(team).charge, 0)


func test_neutral_hooks_return_the_pre_commander_rules() -> void:
	var state := Fixture.state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	var tank := state.units[0]
	var infantry := state.units[1]
	var co := state.commander_of(1)
	var fight := _fight(tank, infantry)
	assert_eq(co.attack_bonus(state, fight), 0)
	assert_eq(co.defense_bonus(state, fight), 0)
	assert_eq(co.star_bonus(state, fight), 0)
	assert_eq(co.star_pierce(state, fight), 0)
	assert_eq(co.luck_min(state, fight), 0)
	assert_eq(co.luck_max(state, fight), 9)
	assert_eq(co.move_bonus(state, tank), 0)
	assert_eq(co.enemy_move_bonus(state, 2, tank), 0)
	assert_eq(co.range_bonus(state, tank), 0)
	assert_eq(co.vision_bonus(state, tank), 0)
	assert_eq(co.enemy_vision_bonus(state, 2, tank), 0)
	assert_false(co.sees_into_cover(state, tank))
	assert_false(co.hides_unit(state, tank))
	assert_eq(co.capture_bonus_pct(state, tank), 0)
	assert_eq(co.supply_range(state, tank), 1)
	assert_eq(co.repair_cost_pct(state, tank), 100)
	assert_eq(co.build_cost_pct(state, 1, tank.type), 100)
	assert_eq(co.kill_bounty_pct(state, 1, infantry), 0)
	var plains := terrain_db.by_symbol(".")
	assert_eq(co.terrain_cost(state, tank, plains, 1), 1, "neutral passes the base cost through")


## Golden values, hand-computed from the formula in CombatResolver's header with
## att = def = 100. These are the numbers every doctrine's percentage points
## are applied on top of; if one of them moves, the whole roster re-balances.
func test_golden_damage_matrix_for_the_neutral_commander() -> void:
	# map, attacker, defender, expected damage
	var cases: Array = [
		# Tank MG -> Infantry, base 75.
		["[terrain]\n==\n[units]\n1 t 0 0\n2 i 1 0", 75],  # 0 stars: 75 * 1.0
		["[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0", 68],  # plains 1*: 75 * 0.9
		["[terrain]\n.F\n[units]\n1 t 0 0\n2 i 1 0", 60],  # woods 2*: 75 * 0.8
		["[terrain]\n.C\n[units]\n1 t 0 0\n2 i 1 0", 53],  # city 3*: 75 * 0.7
		["[terrain]\n.M\n[units]\n1 t 0 0\n2 i 1 0", 45],  # mountain 4*: 75 * 0.6
		# infantry -> tank, base 5
		["[terrain]\n..\n[units]\n1 i 0 0\n2 t 1 0", 5],  # plains 1*: 5 * 0.9 = 4.5
	]
	for case: Array in cases:
		var state := Fixture.state(case[0])
		var forecast := CombatResolver.forecast(
			state, state.units[0], state.units[0].cell, state.units[1]
		)
		assert_eq(forecast.attack_damage, case[1], "%s" % case[0])


## Damage scales on *displayed* HP, and a damaged defender hides behind terrain
## less well. Pinned here because both terms sit inside the same multiplier
## chain the doctrines hook into.
func test_golden_damage_matrix_for_damaged_units() -> void:
	var state := Fixture.state("[terrain]\n..\n[units]\n1 t 0 0\n2 i 1 0")
	state.units[0].hp = 50  # 5 displayed
	# 75 * 0.5 * (1 - 0.1 * 1 * 1.0) = 33.75 -> 34.
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		34
	)
	state.units[0].hp = 100
	state.units[1].hp = 50  # 5 displayed: terrain shields it half as well
	# 75 * 1.0 * (1 - 0.1 * 1 * 0.5) = 71.25 -> 71.
	assert_eq(
		(
			CombatResolver
			. forecast(state, state.units[0], Vector2i(0, 0), state.units[1])
			. attack_damage
		),
		71
	)


## A match nobody picked a commander for remains deterministic through the
## neutral hooks. Same seed and commands land on the same board, down to HP and
## funds; the golden HP includes the deliberate Tank MG lethality change.
func test_a_no_commander_match_is_deterministic() -> void:
	var first := _play_scripted_match()
	var second := _play_scripted_match()
	for key: String in first:
		assert_eq(first[key], second[key], "same seed + same commands must agree on %s" % key)
	# A doctrine leaking into a neutral match — a hook called on the wrong side,
	# a stray multiplier — moves these.
	assert_eq(first["red_hp"], 91, "red tank HP after the exchange")
	assert_eq(first["blue_hp"], 46, "blue infantry HP after the exchange")
	assert_eq(first["day"], 2)
	assert_eq(first["red_funds"], 2000, "two properties, two turns of income")


## Fixed seed, fixed command list: attack, end turn, end turn.
func _play_scripted_match() -> Dictionary:
	var state := Fixture.state("[terrain]\n.C.\n.C.\n[units]\n1 t 0 0\n2 i 1 0")
	state.rng.seed = 424242
	state.set_owner(Vector2i(1, 0), 1)
	state.set_owner(Vector2i(1, 1), 1)
	AttackCommand.new(state.units[0], [Vector2i(0, 0)], Vector2i(1, 0)).apply(state)
	EndTurnCommand.new().apply(state)
	EndTurnCommand.new().apply(state)
	return {
		"red_hp": state.units_of(1)[0].hp,
		"blue_hp": state.units_of(2)[0].hp,
		"day": state.day,
		"red_funds": state.funds[1],
	}


# --- the commander database --------------------------------------------------


func test_db_always_answers_with_a_commander() -> void:
	var db := Fixture.commander_db()
	assert_true(db.has(CommanderType.NEUTRAL_ID), "neutral is always registered")
	assert_eq(db.by_id(&"alina_ward").display_name, "Alina Ward")
	assert_eq(
		db.by_id(&"a_general_who_was_cut").id,
		CommanderType.NEUTRAL_ID,
		"an unknown id falls back to neutral so an old save still loads"
	)


## "No commander" is a legal seat and a legal pick, but it is the absence of a
## doctrine rather than one of them — so a roster measurement is over the
## playable ones, and this is the single answer to which those are.
func test_the_playable_roster_is_everyone_but_neutral() -> void:
	var db := Fixture.commander_db()
	assert_false(db.is_playable(CommanderType.NEUTRAL_ID), "no commander is not a commander")
	assert_false(
		db.is_playable(&"a_general_who_was_cut"), "and neither is a name nobody answers to"
	)
	assert_true(db.is_playable(&"alina_ward"))
	assert_eq(db.playable().size(), db.all().size() - 1, "exactly one seat's worth of nobody")
	for co in db.playable():
		assert_ne(co.id, CommanderType.NEUTRAL_ID)


func test_every_shipped_commander_is_well_formed() -> void:
	var db := Fixture.commander_db()
	for co in db.all():
		if co.id == CommanderType.NEUTRAL_ID:
			continue
		assert_ne(co.display_name, "", "%s needs a name" % co.id)
		assert_ne(co.faction, "", "%s needs a faction" % co.id)
		assert_ne(co.power_name, "", "%s needs a power name" % co.id)
		assert_ne(co.doctrine_text, "", "%s needs doctrine text for the picker" % co.id)
		assert_ne(co.power_text, "", "%s needs power text for the picker" % co.id)
		# The plan's band. Below it a power fires most turns and stops being an
		# event; above it a match can end before the meter ever fills. A number
		# outside this is a balance decision, not a typo, so it has to be made
		# here as well as in the .tres. The ceiling is Hammerfall's 24000
		# (more-commanders D4) for everyone but Colt: the retune that stopped
		# Second Wind sparing attackers doubled its price, so a whole second turn
		# for an army that has already acted is deliberately the dearest meter on
		# the roster — and it is named rather than raising the band, which would
		# stop holding the other twenty-one.
		var ceiling := 44000 if co.id == &"iris_colt" else 24000
		assert_between(co.power_cost, 9000, ceiling, "%s power cost" % co.id)


## Every general's own numbers are written on its .tres. A balance pass reads
## data/, so a number that lives only as a script default is one nobody tuning
## the roster will ever find — the sibling of test_ai_profile.gd's rule that
## every tier writes every profile field, for the same reason.
##
## Scoped to what each subclass declares: the card fields CommanderType exports
## are the base's own, and some are meant to take its default — power_timing is
## BEFORE_ACTIONS for every general but one.
func test_every_commander_writes_its_own_doctrine_numbers() -> void:
	var shared := _stored_fields(CommanderType.new())
	var files := DirAccess.get_files_at(COMMANDER_DIR)
	files.sort()
	var checked := 0
	for file_name in files:
		if file_name.get_extension() != "tres":
			continue
		var path := "%s/%s" % [COMMANDER_DIR, file_name]
		var commander: CommanderType = load(path)
		var source: String = FileAccess.get_file_as_string(path)
		for field in _stored_fields(commander):
			if field in shared:
				continue
			checked += 1
			assert_true(
				source.contains("\n%s =" % field), "%s must explicitly write %s" % [path, field]
			)
	assert_gt(checked, 10, "the roster should carry its doctrine numbers as exports")


## The fields a .tres can actually store: an @export carries STORAGE, a plain
## script var does not, and demanding one of those in data would be unfixable.
static func _stored_fields(resource: Resource) -> Array[String]:
	var fields: Array[String] = []
	for property in resource.get_property_list():
		var usage := int(property.usage)
		if (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) and (usage & PROPERTY_USAGE_STORAGE):
			fields.append(property.name)
	return fields


## The reviewed 6 / 6 / 5 / 5 roster. Pinned so a half-added general — a script
## with no .tres, or a .tres with the wrong faction string — fails visibly.
func test_the_roster_has_the_reviewed_faction_counts() -> void:
	var counts: Dictionary = {}
	for co in Fixture.commander_db().all():
		if co.id == CommanderType.NEUTRAL_ID:
			continue
		counts[co.faction] = int(counts.get(co.faction, 0)) + 1
	assert_eq(counts.size(), 4, "four factions, got %s" % [counts.keys()])
	assert_eq(counts["Meridian Coalition"], 6)
	assert_eq(counts["Iron Dominion"], 6)
	assert_eq(counts["Aurora Compact"], 5)
	assert_eq(counts["Verdant League"], 5)
