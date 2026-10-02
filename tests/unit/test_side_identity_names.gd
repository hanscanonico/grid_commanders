extends GutTest
## What the faction-identity resolver calls each side once two or more share a
## faction (playtest SK-07/ED-23): the faction name stays, and every later side of
## it carries a numeral, so the turn banner and the owner labels never name two
## armies alike. Kept apart from test_side_identity.gd, which sits at the
## max-public-methods ceiling.

const MERIDIAN := "Meridian Coalition"
const IRON := "Iron Dominion"
const AURORA := "Aurora Compact"


func _co(faction: String) -> CommanderType:
	var commander := CommanderType.new()
	commander.faction = faction
	return commander


func _resolve(faction_1: String, faction_2: String) -> SideIdentity:
	return SideIdentity.resolve({1: _co(faction_1), 2: _co(faction_2)})


func test_four_mirror_sides_are_all_named_apart() -> void:
	var identity := SideIdentity.resolve(
		{1: _co(MERIDIAN), 2: _co(MERIDIAN), 3: _co(MERIDIAN), 4: _co(MERIDIAN)}
	)
	var names: Array[String] = []
	for team in [1, 2, 3, 4]:
		names.append(identity.display_name(team))
	assert_eq(
		names, [MERIDIAN, MERIDIAN + " II", MERIDIAN + " III", MERIDIAN + " IV"] as Array[String]
	)


func test_short_name_keeps_the_mirror_numeral() -> void:
	var identity := _resolve(MERIDIAN, MERIDIAN)
	assert_eq(identity.short_name(1), "Meridian")
	assert_eq(identity.short_name(2), "Meridian II")


func test_short_name_of_a_generic_side_is_its_ordinal() -> void:
	var identity := _resolve("", IRON)
	assert_eq(identity.short_name(1), "First")
	assert_eq(identity.short_name(2), "Iron")


func test_distinct_factions_carry_no_numeral() -> void:
	var identity := _resolve(MERIDIAN, AURORA)
	assert_eq(identity.display_name(2), AURORA)
