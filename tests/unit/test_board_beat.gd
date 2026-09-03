extends GutTest
## BoardBeat's own suite: the disjointness the four looping cadences (five
## since S9) are held to. `test_move_frames.gd` and
## `test_terrain_autotiles_beat.gd` each check the cadence their own clip
## cares about against its neighbours; this is the one place every pair is
## checked against every other, so growing a sixth animated family means
## growing the table here rather than trusting N separate files to have
## covered N*(N-1)/2 pairs between them.

var _opened_at: GameSpeed


func before_each() -> void:
	_opened_at = Settings.speed


func after_each() -> void:
	Settings.speed = _opened_at


## The four terrain and unit clips read a fixed, authored cadence at every
## tier; only the move clip's is tier-scaled (`BoardBeat.move_ms`), so it is
## the one read fresh inside the loop below rather than named beside the rest.
func _cadences() -> Dictionary[String, int]:
	return {
		"ambient": BoardBeat.AMBIENT_MS,
		"move": BoardBeat.move_ms(),
		"sea": BoardBeat.SEA_MS,
		"rivers": BoardBeat.RIVER_MS,
		"shoals": BoardBeat.SHOAL_MS,
	}


## No two of the board's five cadences may divide or multiply one another at
## any tier — the whole board turning over on one tick would read as a
## stutter rather than as five separate motions.
func test_the_five_cadences_share_no_tick_pairwise_at_every_tier() -> void:
	for id: StringName in [GameSpeed.DEFAULT_ID, &"quick", &"instant"]:
		Settings.speed = GameSpeed.by_id(id)
		var cadences := _cadences()
		var names := cadences.keys()
		for i in names.size():
			for j in range(i + 1, names.size()):
				var a: int = cadences[names[i]]
				var b: int = cadences[names[j]]
				assert_ne(a % b, 0, "%s: %s (%d) divides %s (%d)" % [id, names[j], b, names[i], a])
				assert_ne(b % a, 0, "%s: %s (%d) divides %s (%d)" % [id, names[i], a, names[j], b])
