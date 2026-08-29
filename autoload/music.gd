extends Node
## Loops one background music track at a time: Music.play(&"parade").
## Two players ping-pong, so a new track fades up over the old one fading out
## rather than cutting it mid-phrase, and stop() fades out under the victory
## fanfare. The tweens are the autoload's own — a scene change can never orphan
## one. Missing streams are silently skipped so a headless run or a stripped
## build never breaks — the Sfx contract. Asking for the track
## already playing is a no-op, so a scene states its theme unconditionally in
## _ready and a rematch never restarts the music mid-phrase.
## How loud the game plays is Settings' and lives on the master bus; nothing
## here writes anything but volume_db on its own two players.

const MUSIC_DIR := "res://assets/music"
const NAMES: Array[StringName] = [&"parade", &"advance"]

## The tracks render at about -21 dBFS RMS, so -4 dB plays them near -25 dBFS —
## still some 20 dB under the combat SFX peaks, which is loud enough to hear on
## a laptop speaker and quiet enough never to stand over a shot.
const LEVEL_DB := -4.0
## Two players: one holds the outgoing track while the other fades up.
const PLAYERS := 2
const CROSSFADE_SEC := 0.6
const STOP_FADE_SEC := 0.4

## Quiet enough to be silence, loud enough to stay a finite number the curve can
## work in: linear_to_db(0.0) is -inf, which no tween can ramp from.
const SILENT_DB := -60.0

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _fades: Array[Tween] = []
var _active: int = 0
var _current: StringName = &""


func _ready() -> void:
	for track in NAMES:
		var path := "%s/%s.ogg" % [MUSIC_DIR, track]
		if ResourceLoader.exists(path):
			var stream: AudioStreamOggVorbis = load(path)
			stream.loop = true
			_streams[track] = stream
	_fades.resize(PLAYERS)
	for i in PLAYERS:
		var player := AudioStreamPlayer.new()
		player.volume_db = SILENT_DB
		add_child(player)
		_players.append(player)


## The level a leg of a fade sits at, `progress` of the way in. Gain follows a
## quarter sine, so the two legs of a crossfade sum to constant power where a
## straight db ramp would dip audibly in the middle.
static func fade_level_db(peak_db: float, progress: float) -> float:
	var gain := sin(clampf(progress, 0.0, 1.0) * PI / 2.0)
	return maxf(SILENT_DB, peak_db + linear_to_db(gain))


func play(track: StringName, volume_db: float = LEVEL_DB) -> void:
	if track == _current and _players[_active].playing:
		return
	var stream: AudioStream = _streams.get(track)
	if stream == null:
		stop()
		return
	_current = track
	_fade_out(_active, CROSSFADE_SEC)
	_active = PLAYERS - 1 - _active
	var player := _players[_active]
	player.stream = stream
	player.volume_db = SILENT_DB
	player.play()
	_ramp(_active, volume_db, CROSSFADE_SEC, true)


func stop(fade: float = STOP_FADE_SEC) -> void:
	_current = &""
	for i in _players.size():
		_fade_out(i, fade)


func _fade_out(index: int, duration: float) -> void:
	_ramp(index, _players[index].volume_db, duration, false)


func _ramp(index: int, peak_db: float, duration: float, rising: bool) -> void:
	var player := _players[index]
	var running: Tween = _fades[index]
	if running != null:
		running.kill()
		_fades[index] = null
	if not rising and not player.playing:
		return
	if duration <= 0.0:
		player.volume_db = fade_level_db(peak_db, 1.0 if rising else 0.0)
		if not rising:
			player.stop()
		return
	var tween := create_tween()
	_fades[index] = tween
	tween.tween_method(
		func(t: float) -> void: player.volume_db = fade_level_db(peak_db, t if rising else 1.0 - t),
		0.0,
		1.0,
		duration
	)
	if not rising:
		tween.tween_callback(player.stop)
