extends GutTest
## The pause menu's Auto row — which seats a player has handed to the computer
## mid-match, and at what tier. Kept apart from test_save_codec.gd for the same
## reason its other siblings are: that file sits at the gdlint max-public-methods
## ceiling.


func _first_steps_state() -> GameState:
	var map := MapData.load_from_file("res://maps/first_steps.txt", Fixture.terrain_db())
	var state := GameState.create(map, Fixture.unit_db(), Fixture.chart())
	state.map_path = "res://maps/first_steps.txt"
	return state


func _encoded() -> Dictionary:
	return SaveCodec.encode(_first_steps_state(), [2] as Array[int])


func _decode(data: Dictionary) -> SaveCodec.LoadedMatch:
	return SaveCodec.decode(data, Fixture.terrain_db(), Fixture.unit_db(), Fixture.chart())


## Hands a seat to the computer mid-match, at a tier that need not match the
## match's own `difficulty` — so it has to round-trip on its own rather than
## riding along with that one flat field.
func test_auto_tiers_survive_the_round_trip() -> void:
	var auto_tiers: Dictionary[int, StringName] = {2: &"brutal"}
	var data := SaveCodec.encode(_first_steps_state(), [1, 2] as Array[int], &"normal", auto_tiers)
	assert_eq((data["auto_tiers"] as Dictionary)["2"], "brutal")
	var loaded := _decode(data)
	assert_not_null(loaded)
	assert_eq(loaded.auto_tiers, {2: &"brutal"} as Dictionary[int, StringName])


## Every save written before Auto existed carries no such key, and resumes
## with no seat on it — the same match those saves recorded.
func test_a_save_without_auto_tiers_resumes_with_none() -> void:
	var data := _encoded()
	assert_eq((data["auto_tiers"] as Dictionary).size(), 0, "a match nobody put on Auto")
	data.erase("auto_tiers")
	data["version"] = 9
	assert_eq(SaveCodec.validate(data), "", "version 9 knew no such key")
	var loaded := _decode(data)
	assert_not_null(loaded)
	assert_eq(loaded.auto_tiers.size(), 0)


## An Auto entry naming a team the save does not hand to the computer describes
## a match this save could not have recorded — Auto *is* an ai_teams entry a
## player toggled, never a second, independent list.
func test_an_auto_tier_for_a_team_not_on_ai_teams_is_refused() -> void:
	var data := _encoded()
	data["ai_teams"] = []
	data["auto_tiers"] = {"2": "hard"}
	assert_string_contains(SaveCodec.validate(data), "Auto")


## The tier id itself is only ever asked to be text — an id nobody recognises
## falls back to Normal by DifficultyDB's own rule, the same tolerance
## `difficulty` gets.
func test_an_auto_tier_that_is_not_text_is_refused() -> void:
	var data := _encoded()
	data["ai_teams"] = [2]
	data["auto_tiers"] = {"2": 7}
	assert_string_contains(SaveCodec.validate(data), "Auto tier for team 2")
