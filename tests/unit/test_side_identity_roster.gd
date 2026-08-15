extends GutTest
## The faction-identity resolver at three and four armies (COM-47, four-players
## plan FP4/D5).
##
## Kept apart from test_side_identity.gd because that file sits at the gdlintrc
## max-public-methods ceiling, and because these cases ask a different question:
## its subject is the resolution *table* for a duel, this one is the invariant the
## table has to keep once a board can seat four — every side its own colour, none
## of them neutral, and the atlas rows injective, which is what
## `BattleView._last_seen_owner` reads a fogged tile's owner back out of.

const MERIDIAN := "Meridian Coalition"
const IRON := "Iron Dominion"
const AURORA := "Aurora Compact"
const VERDANT := "Verdant League"


func _co(faction: String) -> CommanderType:
	var commander := CommanderType.new()
	commander.faction = faction
	return commander


func _key(identity: SideIdentity, team: int) -> StringName:
	return identity.theme(team).key


## Every side on a board wears its own colour, and none of them wears neutral —
## the invariant this file's subject has always claimed and could not keep once a
## third army existed. Asserted over N rather than over a pair, so it holds for
## every roster the rules can seat.
func _assert_all_distinct(identity: SideIdentity, teams: Array) -> void:
	var seen: Dictionary = {}
	for team: int in teams:
		var key := _key(identity, team)
		assert_ne(key, CommanderVisuals.NEUTRAL_KEY, "team %d must not wear neutral" % team)
		assert_false(
			seen.has(key), "team %d wears %s, which another side already has" % [team, key]
		)
		seen[key] = true
		var row := identity.atlas_row(team)
		assert_ne(row, SideIdentity.NEUTRAL_ROW, "team %d must not draw in the neutral row" % team)
	assert_eq(seen.size(), teams.size(), "one colour per side")


func _resolve_n(factions: Array) -> SideIdentity:
	var picks: Dictionary = {}
	for i in factions.size():
		picks[i + 1] = _co(factions[i])
	return SideIdentity.resolve(picks)


func test_four_commander_less_armies_each_get_a_colour() -> void:
	# The case that used to run the two-key fallback dry: seats 3 and 4 answered
	# neutral, indistinguishable from unowned ground.
	var identity := _resolve_n(["", "", "", ""])
	_assert_all_distinct(identity, [1, 2, 3, 4])
	assert_eq(_key(identity, 1), &"meridian", "and the first two are still red then blue")
	assert_eq(_key(identity, 2), &"aurora")


func test_three_armies_sharing_one_faction_still_wear_three_colours() -> void:
	# A triple mirror: two of them have to borrow, and there is enough to borrow.
	var identity := _resolve_n([IRON, IRON, IRON])
	_assert_all_distinct(identity, [1, 2, 3])
	assert_eq(_key(identity, 1), &"iron", "the first claimant keeps its own faction")


func test_four_armies_sharing_one_faction_still_wear_four_colours() -> void:
	var identity := _resolve_n([VERDANT, VERDANT, VERDANT, VERDANT])
	_assert_all_distinct(identity, [1, 2, 3, 4])
	assert_eq(_key(identity, 1), &"verdant")


func test_four_distinct_factions_each_keep_their_own() -> void:
	var identity := _resolve_n([MERIDIAN, AURORA, IRON, VERDANT])
	_assert_all_distinct(identity, [1, 2, 3, 4])
	assert_eq(_key(identity, 3), &"iron", "a faction side never borrows")
	assert_eq(_key(identity, 4), &"verdant")


func test_a_mix_of_factions_and_commander_less_sides_stays_distinct() -> void:
	# The awkward shape: faction sides claim first, then the commander-less ones
	# take what is left — so the second pass has to see what the first took.
	_assert_all_distinct(_resolve_n([IRON, "", VERDANT, ""]), [1, 2, 3, 4])
	_assert_all_distinct(_resolve_n(["", MERIDIAN, "", AURORA]), [1, 2, 3, 4])
	_assert_all_distinct(_resolve_n([AURORA, AURORA, "", ""]), [1, 2, 3, 4])


## The reverse map in BattleView._last_seen_owner reads a painted atlas row back
## to a team, so distinct colours is not enough — the rows have to be injective,
## and none of them may collide with the neutral row an unowned property draws in.
func test_every_side_draws_in_its_own_atlas_row() -> void:
	for factions: Array in [["", "", "", ""], [IRON, IRON, IRON, IRON], [MERIDIAN, "", IRON, ""]]:
		var identity := _resolve_n(factions)
		var rows: Dictionary = {}
		for team in [1, 2, 3, 4]:
			var row := identity.atlas_row(team)
			assert_false(rows.has(row), "row %d is worn twice in %s" % [row, factions])
			rows[row] = true
		assert_eq(rows.size(), 4, "four sides, four rows: %s" % [factions])


## Every general on the roster belongs to one of the four tabs the selection page
## deals. `CommanderVisuals.key_for_faction` answers neutral for a faction it was
## never taught, and the select page draws its Random pick from the whole roster:
## a general whose `.tres` spelled its faction wrong would still be drawable and
## would land on no tab at all, which is the ticket COM-227 closed reopening
## itself quietly.
func test_every_general_belongs_to_a_faction_tab() -> void:
	var tabs: Array[StringName] = []
	for theme: CommanderVisuals.FactionTheme in CommanderVisuals.faction_themes():
		tabs.append(theme.key)
	for commander in Fixture.commander_db().all():
		if commander.id == CommanderType.NEUTRAL_ID:
			continue
		var key := CommanderVisuals.key_for_faction(commander.faction)
		assert_true(
			tabs.has(key),
			"%s names faction '%s', which is on no tab" % [commander.id, commander.faction]
		)
