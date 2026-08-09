extends Node
## Loops one background music track at a time: Music.play(&"parade").
## Missing streams are silently skipped so headless runs and fresh checkouts
## (before `make music`) never break — the Sfx contract. Asking for the track
## already playing is a no-op, so a scene states its theme unconditionally in
## _ready and a rematch never restarts the music mid-phrase.

const MUSIC_DIR := "res://assets/music"
const NAMES: Array[StringName] = [&"parade", &"advance"]

var _streams: Dictionary = {}
var _player: AudioStreamPlayer
var _current: StringName = &""


func _ready() -> void:
	for track in NAMES:
		var path := "%s/%s.wav" % [MUSIC_DIR, track]
		if ResourceLoader.exists(path):
			var stream: AudioStreamWAV = load(path)
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_end = stream.data.size() / 2  # 16-bit mono: two bytes a frame
			_streams[track] = stream
	_player = AudioStreamPlayer.new()
	add_child(_player)


func play(track: StringName, volume_db: float = -10.0) -> void:
	if track == _current and _player.playing:
		return
	_current = track
	var stream: AudioStream = _streams.get(track)
	if stream == null:
		_player.stop()
		return
	_player.stream = stream
	_player.volume_db = volume_db
	_player.play()


func stop() -> void:
	_current = &""
	_player.stop()
