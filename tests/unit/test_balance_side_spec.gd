extends GutTest
## The `<commander>:<tier>` grammar, which its own header calls out as the thing
## two callers must agree on: the headless Lab scores a matchup and the battle
## scene boots the same one for watch mode. A spec parsed two ways is a spec that
## eventually disagrees — so the grammar is pinned here rather than measured by a
## watched match going somewhere unexpected.
##
## In scope for the usual reason: BalanceSideSpec is a RefCounted under
## tools/balance/, Node-free so GUT can drive it.

var commanders: CommanderDB
var tiers: DifficultyDB


func before_each() -> void:
	commanders = Fixture.commander_db()
	tiers = DifficultyDB.load_default()


func _parse(text: String) -> BalanceSideSpec:
	return BalanceSideSpec.parse(text, commanders, tiers)


## Both halves are optional and each defaults on its own, so all four shapes of
## the grammar are one table.
func test_each_half_defaults_on_its_own() -> void:
	var cases := {
		"": [CommanderType.NEUTRAL_ID, Difficulty.DEFAULT_ID],
		"gideon_holt": [&"gideon_holt", Difficulty.DEFAULT_ID],
		":hard": [CommanderType.NEUTRAL_ID, &"hard"],
		"gideon_holt:hard": [&"gideon_holt", &"hard"],
	}
	for text: String in cases:
		var spec := _parse(text)
		assert_eq(spec.error, "", "'%s' should parse" % text)
		assert_eq(spec.commander, cases[text][0], "'%s' commander" % text)
		assert_eq(spec.tier, cases[text][1], "'%s' tier" % text)


func test_the_omitted_flag_is_the_neutral_side_on_the_shipped_planner() -> void:
	var spec := _parse(BalanceSideSpec.DEFAULT_TEXT)
	assert_eq(spec.error, "")
	assert_eq(spec.commander, CommanderType.NEUTRAL_ID, "'none' is the absence of a doctrine")
	assert_eq(spec.tier, Difficulty.DEFAULT_ID)
	assert_eq(_parse("gideon_holt").commander, &"gideon_holt", "and a named one is seated")


## Every way the grammar is refused, each naming what it choked on. A spec that
## failed keeps its defaults rather than half of what was typed.
func test_every_refusal_says_what_it_choked_on() -> void:
	var cases := {
		"a:b:c": "expected <commander>:<tier>, got 'a:b:c'",
		"gideon_holtz": "unknown commander 'gideon_holtz'",
		":nightmare": "unknown difficulty tier 'nightmare'",
	}
	for text: String in cases:
		var spec := _parse(text)
		assert_eq(spec.error, cases[text], "'%s' should be refused" % text)
		assert_eq(spec.commander, CommanderType.NEUTRAL_ID, "'%s' leaves the default" % text)
		assert_eq(spec.tier, Difficulty.DEFAULT_ID, "'%s' leaves the default" % text)


## The mistyped-commander case is the one the ids are checked for at all:
## CommanderDB's lookup is deliberately forgiving, so an unchecked id would
## become neutral and the run would score the wrong matchup and say nothing.
func test_a_mistyped_commander_is_refused_rather_than_played_as_neutral() -> void:
	assert_true(commanders.by_id(&"gideon_holtz").id == CommanderType.NEUTRAL_ID, "db forgives")
	assert_ne(_parse("gideon_holtz").error, "", "the spec does not")


func test_surrounding_space_is_not_part_of_an_id() -> void:
	var spec := _parse("  gideon_holt : hard  ")
	assert_eq(spec.error, "")
	assert_eq(spec.commander, &"gideon_holt")
	assert_eq(spec.tier, &"hard")


## The round-trip claim in text()'s own comment: a run directory named after a
## spec has to name the same matchup when it is read back.
func test_text_round_trips_through_parse() -> void:
	for text: String in ["", "gideon_holt", ":hard", "sable_wren:easy"]:
		var spec := _parse(text)
		var again := _parse(spec.text())
		assert_eq(again.error, "", "'%s' round-trip" % text)
		assert_eq(again.commander, spec.commander, "'%s' commander round-trip" % text)
		assert_eq(again.tier, spec.tier, "'%s' tier round-trip" % text)
		assert_eq(again.text(), spec.text(), "'%s' text round-trip" % text)


## The canonical forms. slug() names a directory on disk, so it may not carry the
## colon; text() is the grammar itself and must.
func test_the_two_written_forms_are_the_canonical_ones() -> void:
	var spec := _parse("gideon_holt:hard")
	assert_eq(spec.text(), "gideon_holt:hard")
	assert_eq(spec.slug(), "gideon_holt-hard")
	assert_eq(_parse("").text(), BalanceSideSpec.DEFAULT_TEXT)
	assert_eq(_parse("").slug(), "none-normal")
