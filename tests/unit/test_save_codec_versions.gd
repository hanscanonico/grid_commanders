extends GutTest
## What a save of each version is entitled to be missing (COM-54).
##
## Eight fields have fallbacks in `decode`, and the fallback is for *age*: a save
## written before a field existed is entitled to the default. The two used to be
## indistinguishable from damage, so a key lost to a short write or a typo loaded a
## match that played differently — fog off, captures reset, both sides
## commander-less — and said nothing anywhere. Now the save's own version decides:
## below the version that introduced a key it is old, at or above it it is lost.
##
## Kept apart from test_save_codec.gd because these cases are about the *format's
## history* rather than about one save, and because that file sits at the gdlintrc
## max-public-methods ceiling.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


func _encoded() -> Dictionary:
	var map := MapData.load_from_file("res://maps/first_steps.txt", terrain_db)
	var state := GameState.create(map, unit_db, chart)
	state.map_path = "res://maps/first_steps.txt"
	return SaveCodec.encode(state, [2] as Array[int])


## A save at `version` with `key` taken off it.
func _without(key: String, version: int) -> Dictionary:
	var data := _encoded()
	data["version"] = version
	data.erase(key)
	return data


# --- a current save must carry what a current save writes ---------------------


func test_a_current_save_without_fog_is_refused() -> void:
	var data := _without("fog", SaveCodec.VERSION)
	assert_string_contains(SaveCodec.validate(data), "fog")
	assert_null(SaveCodec.decode(data, terrain_db, unit_db, chart))
	assert_push_error("is missing 'fog'")


func test_a_current_save_without_commanders_is_refused() -> void:
	var data := _without("commanders", SaveCodec.VERSION)
	assert_string_contains(SaveCodec.validate(data), "commanders")


func test_a_current_save_without_capture_progress_is_refused() -> void:
	assert_string_contains(
		SaveCodec.validate(_without("capture_progress", SaveCodec.VERSION)), "capture_progress"
	)


func test_a_current_save_without_a_dive_flag_is_refused() -> void:
	var data := _encoded()
	(data["units"] as Array)[0].erase("dived")
	assert_string_contains(SaveCodec.validate(data), "dived")


func test_a_current_save_without_a_carrier_field_is_refused() -> void:
	var data := _encoded()
	(data["units"] as Array)[0].erase("carrier")
	assert_string_contains(SaveCodec.validate(data), "carrier")


# --- and a block it carries has to be a block ---------------------------------


## Present is not the same as populated: the envelope check only asks whether the
## commander block is there, and an empty one is. Left unasked, it decoded to the
## reported symptom itself — both sides commander-less, loaded clean.
func test_a_current_save_with_an_empty_commander_block_is_refused() -> void:
	var data := _encoded()
	data["commanders"] = {}
	assert_string_contains(SaveCodec.validate(data), "commander for team 1")


func test_a_current_save_missing_one_sides_commander_is_refused() -> void:
	var data := _encoded()
	(data["commanders"] as Dictionary).erase("2")
	assert_string_contains(SaveCodec.validate(data), "commander for team 2")


## The same reasoning one level down: `encode` has written all three fields for as
## long as the block has existed, so a lost charge is a meter lost, not an old save.
func test_a_current_save_whose_commander_lost_its_charge_is_refused() -> void:
	var data := _encoded()
	(data["commanders"]["1"] as Dictionary).erase("charge")
	assert_string_contains(SaveCodec.validate(data), "'charge'")


# --- an older save is entitled to the defaults --------------------------------


## The other direction of the block rule: version 1 wrote no commanders at all, so
## it is never asked for one and still resumes as the no-commander match it was.
func test_a_version_1_save_with_no_commander_block_still_loads_neutral() -> void:
	var data := _without("commanders", 1)
	data.erase("difficulty")
	assert_eq(SaveCodec.validate(data), "", "version 1 knew no commander block")
	var loaded := SaveCodec.decode(data, terrain_db, unit_db, chart)
	assert_not_null(loaded)
	for team in GameState.TEAMS:
		assert_eq(loaded.state.commander_of(team).id, CommanderType.NEUTRAL_ID)
		assert_eq(loaded.state.commander_state(team).charge, 0, "and an empty meter")


## The whole point of the version gate: the same missing key that condemns a
## version 3 save is unremarkable in the version that predates it.
func test_a_version_1_save_may_lack_commanders_and_the_dive_flag() -> void:
	var data := _encoded()
	data["version"] = 1
	data.erase("commanders")
	data.erase("difficulty")
	for entry: Dictionary in data["units"] as Array:
		entry.erase("dived")
	assert_eq(SaveCodec.validate(data), "", "version 1 knew none of those keys")
	var loaded := SaveCodec.decode(data, terrain_db, unit_db, chart)
	assert_not_null(loaded)
	assert_eq(loaded.difficulty, &"normal")
	assert_false(loaded.state.units[0].dived)


## `difficulty` is the one key that arrived between versions without a bump of its
## own, so version 2 is the newest one entitled to be without it — and version 3 is
## the first that must have it.
func test_difficulty_is_optional_through_version_2_and_required_at_3() -> void:
	assert_eq(SaveCodec.validate(_without("difficulty", 2)), "", "version 2 may predate the key")
	assert_string_contains(SaveCodec.validate(_without("difficulty", 3)), "difficulty")


func test_a_version_2_save_may_lack_the_dive_flag_but_not_commanders() -> void:
	var data := _encoded()
	data["version"] = 2
	data.erase("difficulty")
	for entry: Dictionary in data["units"] as Array:
		entry.erase("dived")
	assert_eq(SaveCodec.validate(data), "", "version 2 had commanders but no dive flag")
	data.erase("commanders")
	assert_string_contains(SaveCodec.validate(data), "commanders")


## The counterpart every rejection set needs: the save the game actually writes is
## complete, so the table above cannot be demanding a key nothing produces.
func test_a_freshly_encoded_save_carries_everything_its_version_promises() -> void:
	assert_eq(SaveCodec.validate(_encoded()), "")
	for key: String in SaveCodec.OPTIONAL_KEY_VERSIONS:
		assert_has(_encoded(), key, "encode must write every key its version claims")
	for key: String in SaveCodec.OPTIONAL_UNIT_KEY_VERSIONS:
		assert_has((_encoded()["units"] as Array)[0] as Dictionary, key)
	for key: String in SaveCodec.REQUIRED_COMMANDER_KEYS:
		for team in GameState.TEAMS:
			assert_has(_encoded()["commanders"][str(team)] as Dictionary, key)
