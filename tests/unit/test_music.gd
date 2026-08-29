extends GutTest
## The Music autoload's contract: one looping track at a time, faded rather than
## cut, a track already playing is left alone, and anything it cannot load is
## silently skipped.
##
## Music is an autoload rather than a Node-free class, which is normally outside
## what tests/ targets. It earns MatchConfig's exception the same way as
## CampaignSession: the singleton is up for the whole run and reachable without
## a scene, and what a scene asks of it — `play` in `_ready`, `stop` at victory —
## is exactly what these tests are about.
##
## The bars and the tempo each track was composed at, in the sibling
## audio_generator repo (`make audio` installs its renders as Ogg Vorbis).
## A loop is seamless only if the file is a whole number of beats long, so the
## length is pinned here rather than eyeballed — and it is what says the codec
## kept every sample frame.
const TEMPOS := {&"parade": 104.0, &"advance": 132.0}
const BARS := 32


func after_each() -> void:
	Music.stop(0.0)


func _players() -> Array[Node]:
	return Music.find_children("", "AudioStreamPlayer", false, false)


func _playing() -> Array[Node]:
	return _players().filter(func(player: AudioStreamPlayer) -> bool: return player.playing)


func _voice(track: StringName) -> AudioStreamPlayer:
	var path := "res://assets/music/%s.ogg" % track
	for player: AudioStreamPlayer in _playing():
		if player.stream != null and player.stream.resource_path == path:
			return player
	return null


func test_each_shipped_track_plays_and_loops_its_whole_length() -> void:
	for track: StringName in Music.NAMES:
		Music.play(track)
		var player := _voice(track)
		assert_not_null(player, "%s should be playing" % track)
		var stream := player.stream as AudioStreamOggVorbis
		assert_true(stream.loop, "%s should loop" % track)
		assert_eq(stream.loop_offset, 0.0, "%s should loop from the top" % track)


func test_each_track_is_a_whole_number_of_bars() -> void:
	for track: StringName in Music.NAMES:
		Music.play(track)
		var beats: float = _voice(track).stream.get_length() * TEMPOS[track] / 60.0
		assert_almost_eq(beats, float(BARS * 4), 0.001, "%s should be %d bars" % [track, BARS])


func test_restating_the_playing_track_is_a_no_op() -> void:
	Music.play(&"parade")
	await wait_seconds(0.1)
	Music.play(&"parade", -30.0)  # a rematch stating its theme must not restart it
	assert_eq(_playing().size(), 1, "the second call should not have opened a player")
	assert_gt(_voice(&"parade").get_playback_position(), 0.0, "the phrase should have kept running")


func test_the_battle_theme_crossfades_over_the_menu_theme() -> void:
	Music.play(&"parade")
	await wait_seconds(Music.CROSSFADE_SEC)
	Music.play(&"advance")
	assert_eq(_playing().size(), 2, "both themes should sound while they cross")
	assert_gt(
		_voice(&"parade").volume_db,
		Music.SILENT_DB,
		"the outgoing theme should still be audible at the seam"
	)
	await wait_seconds(Music.CROSSFADE_SEC + 0.1)
	assert_null(_voice(&"parade"), "the menu theme should have faded out")
	assert_almost_eq(_voice(&"advance").volume_db, Music.LEVEL_DB, 0.01)


func test_stop_fades_out_and_lets_the_track_start_again() -> void:
	Music.play(&"advance")
	await wait_seconds(Music.CROSSFADE_SEC)
	Music.stop(0.3)  # the victory fanfare comes up as the theme goes down
	assert_not_null(_voice(&"advance"), "the fade should still be sounding")
	await wait_seconds(0.4)
	assert_eq(_playing().size(), 0, "the fade should have ended in silence")
	Music.play(&"advance")
	assert_not_null(_voice(&"advance"), "a fresh match should start the theme again")


func test_a_missing_track_is_silently_skipped() -> void:
	Music.play(&"parade")
	Music.play(&"nothing_was_generated")  # a track no release ever shipped
	await wait_seconds(Music.STOP_FADE_SEC + 0.1)
	assert_eq(_playing().size(), 0, "an absent stream should leave every player silent")


func test_the_fade_curve_holds_equal_power() -> void:
	assert_eq(Music.fade_level_db(-4.0, 1.0), -4.0, "the end of a fade is the asked-for level")
	assert_eq(Music.fade_level_db(-4.0, 0.0), Music.SILENT_DB, "the start of a fade is silence")
	var crossed := 0.25  # any point through a crossfade: one leg in, the other out
	var rising := db_to_linear(Music.fade_level_db(0.0, crossed))
	var falling := db_to_linear(Music.fade_level_db(0.0, 1.0 - crossed))
	assert_almost_eq(
		rising * rising + falling * falling, 1.0, 0.001, "the two legs should sum to constant power"
	)
