extends GutTest
## What a save of each version is entitled to be missing, and what it has to be
## holding when it is not (COM-54).
##
## Eight fields have fallbacks in `decode`, and the fallback is for *age*: a save
## written before a field existed is entitled to the default. The two used to be
## indistinguishable from damage, so a key lost to a short write or a typo loaded a
## match that played differently — fog off, captures reset, both sides
## commander-less — and said nothing anywhere. Now the save's own version decides:
## below the version that introduced a key it is old, at or above it it is lost — or,
## present and holding the wrong kind of value, damaged, which a coercion would
## otherwise have turned back into the very default the version rules out.
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


# --- and what it carries has to be the kind of thing it carried ---------------


## Presence was only half of it: a key holding the wrong kind of value is the same
## field lost, wearing a typo, and `decode`'s coercions turn every one of these into a
## plausible default rather than a refusal — `bool("no")` is true, `int("2")` is 2 and
## an `ai_teams` that is not a list is no computer opponent at all.
func test_a_current_save_holding_the_wrong_kind_of_value_is_refused() -> void:
	var wrong := {
		"fog": "yes",
		"winner": "nobody",
		"capture_progress": {},
		"ai_teams": 2,
		"commanders": [],
		"difficulty": 3,
		"map_path": 7,
		"day": "four",
		"current_team": "red",
		"funds": [],
		"rng_state": true,
		"owners": {},
		"units": "none",
	}
	for key: String in wrong:
		var data := _encoded()
		data[key] = wrong[key]
		assert_string_contains(SaveCodec.validate(data), key)


## The two the key tables could not reach, because neither is a record of named fields.
##
## `rng_state` is text on purpose — a 64-bit state does not survive JSON's one number
## type — so its shape is satisfied by any text at all, and `int()` reads whatever is
## left of a damaged one as 0: a seed nobody rolled, and every shot for the rest of the
## match landing differently than the match the save recorded. The purse is keyed by
## side rather than by field name, and a side whose money is a word resumes broke.
func test_the_fields_a_key_table_could_not_reach_are_asked_too() -> void:
	var data := _encoded()
	data["rng_state"] = "somewhere in the middle"
	assert_string_contains(SaveCodec.validate(data), "rng_state")
	data = _encoded()
	data["funds"]["2"] = "plenty"
	assert_string_contains(SaveCodec.validate(data), "funds for team 2")


## Every field of every entry list, on one table and one walk — the unit fields that were
## exempt by construction while the list was presence-only, the two the version gate
## already reached, and the cell lists nothing asked at all.
##
## `int("full")` is a unit resuming dry; `int("here")` is 0, and (0, 0) is a cell every
## board has, so a property quietly moved to the corner rather than being refused. And
## `acted` is the `bool()` hazard again, one line from the commander flag: a String is
## truthy while `bool()` refuses one outright, so a quoted flag is either a unit that
## cannot move on the turn it resumes into or a rebuild that stops half way.
func test_every_entry_field_is_shaped_the_way_its_table_says() -> void:
	var units := {
		"type": 5,
		"team": "red",
		"x": "0",
		"hp": "hurt",
		"fuel": "full",
		"acted": "false",
		"carrier": "none",
		"dived": "surfaced",
	}
	for key: String in units:
		var data := _encoded()
		(data["units"] as Array)[0][key] = units[key]
		assert_string_contains(SaveCodec.validate(data), "unit entry's '%s'" % key)
	var data_owners := _encoded()
	(data_owners["owners"] as Array)[0]["team"] = "red"
	assert_string_contains(SaveCodec.validate(data_owners), "owner entry's 'team'")
	var data_progress := _encoded()
	data_progress["capture_progress"] = [{"x": 0, "y": 0, "points": "nearly"}]
	assert_string_contains(SaveCodec.validate(data_progress), "capture progress entry's 'points'")


## The block's own fields, by the reasoning that reached them one level down: a charge
## that is not a number is a meter lost, and an id that is not a string resolves to a
## general nobody has, which is that side commander-less.
##
## `"active": "false"` is the one a later reader will want to simplify away, so it is
## spelled out. A String is truthy in GDScript — the assertion below is the trap itself —
## while `bool()` refuses one outright, so the same quoted flag reads as a power that is
## up or takes the rebuild down mid-match, depending only on which spelling reads it.
## A power's state is what the sim plays the next turn under, which makes this the worst
## of the three rather than the pedantic one.
func test_a_commander_field_holding_the_wrong_kind_of_value_is_refused() -> void:
	var wrong := {"id": 3, "charge": "full", "active": "false"}
	for key: String in wrong:
		var data := _encoded()
		data["commanders"]["1"][key] = wrong[key]
		assert_string_contains(SaveCodec.validate(data), "'%s'" % key)
	var quoted: Variant = "false"
	assert_true(true if quoted else false, "a saved 'false' is true wherever it is read")


## The list is a list of *numbers*: `["2"]` survives `is Array` and then coerces to
## team 0, which is nobody, so the side it named plays itself.
func test_an_ai_teams_list_of_things_that_are_not_numbers_is_refused() -> void:
	var data := _encoded()
	data["ai_teams"] = ["2"]
	assert_string_contains(SaveCodec.validate(data), "ai_teams")


## Which sides those numbers may name is `board_error`'s, with the turn and the
## winner — so it takes a board to answer, and the save is refused on the way in
## rather than on the way past `validate`.
func test_a_computer_side_that_does_not_play_is_refused() -> void:
	var data := _encoded()
	data["ai_teams"] = [9]
	assert_eq(SaveCodec.validate(data), "", "a list of numbers is all this one asks")
	assert_null(SaveCodec.decode(data, terrain_db, unit_db, chart))
	assert_push_error("team 9")


# --- an older save is entitled to the defaults --------------------------------


## A shape rule is a version rule too. Firing one on a save too old to have written
## the field would be the same bug in the other direction: version 2's units carried
## no dive flag, so whatever a stray key holds there, it is not damage this codec can
## claim to have detected.
##
## Which is exactly why it must not be *read* either. Unshaped and still coerced, that
## stray key was the age rule turned into a crash — `bool()` will not take a String — so
## the save decodes, and the flag version 2 never wrote reads as the surface it was.
func test_a_shape_rule_does_not_reach_a_save_too_old_for_the_field() -> void:
	var data := _encoded()
	data["version"] = 2
	data.erase("difficulty")
	(data["units"] as Array)[0]["dived"] = "surfaced"
	assert_eq(SaveCodec.validate(data), "", "version 2 knew no dive flag to demand a shape of")
	var loaded := SaveCodec.decode(data, terrain_db, unit_db, chart)
	assert_not_null(loaded, "nor one to read")
	assert_false(loaded.state.units[0].dived)


## The other direction of the block rule: version 1 wrote no commanders at all, so
## it is never asked for one and still resumes as the no-commander match it was.
func test_a_version_1_save_with_no_commander_block_still_loads_neutral() -> void:
	var data := _without("commanders", 1)
	data.erase("difficulty")
	assert_eq(SaveCodec.validate(data), "", "version 1 knew no commander block")
	var loaded := SaveCodec.decode(data, terrain_db, unit_db, chart)
	assert_not_null(loaded)
	for team in loaded.state.teams:
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
##
## Which cuts both ways, and is why this is the one field shaped outside its own version.
## Optional is not the same as ignored: a version 2 save written after the key arrived
## holds a real tier, so it resumes at that tier rather than at Normal — and a version 2
## save holding something that is not a tier id at all is damage wherever it sits, not an
## older save exercising a right.
func test_difficulty_is_optional_through_version_2_and_required_at_3() -> void:
	assert_eq(SaveCodec.validate(_without("difficulty", 2)), "", "version 2 may predate the key")
	assert_string_contains(SaveCodec.validate(_without("difficulty", 3)), "difficulty")
	var data := _encoded()
	data["version"] = 2
	data["difficulty"] = "hard"
	assert_eq(SaveCodec.validate(data), "", "a version 2 save may carry one all the same")
	var loaded := SaveCodec.decode(data, terrain_db, unit_db, chart)
	assert_not_null(loaded)
	assert_eq(loaded.difficulty, &"hard", "and the match resumes at the tier it was played at")
	data["difficulty"] = {}
	assert_string_contains(SaveCodec.validate(data), "difficulty")


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
	for key: String in SaveSchema.KEY_RULES:
		assert_has(_encoded(), key, "encode must write every key its version claims")
	for key: String in SaveSchema.UNIT_KEY_RULES:
		assert_has((_encoded()["units"] as Array)[0] as Dictionary, key)
	for key: String in SaveSchema.COMMANDER_KEY_RULES:
		for team: int in _encoded()["teams"] as Array:
			assert_has(_encoded()["commanders"][str(team)] as Dictionary, key)
