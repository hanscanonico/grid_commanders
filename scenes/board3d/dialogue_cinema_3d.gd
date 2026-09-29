class_name DialogueCinema3D
extends Node3D
## The 3D board's story scenes. Where the flat board raises a card — a scripted
## beat's lines, the briefing read again, a Command Power's quote — the 3D board
## stages a scene the way a tactics RPG plays its story: the story theme comes
## in, the letterbox slides in, each general steps out of their HQ as a little
## figure (`CommanderActor3D`) and acts their line out in a window pointing at
## them (`DialogueWindow`) — a raised fist for an exclamation, a shrug for a
## question — while the lens cuts between them. A general with no army on this
## board is projected at the viewer's post, and the narrator speaks over an
## establishing shot. A mission's opening fades up from black on its title card
## and plays the briefing. A Command Power is a limit break: the general stands
## in a pillar of light and raises a fist, two shockwaves roll across the field
## and the power's name slams in.
##
## Presentation only, like the card it stands in for: handed the words and the
## posts (`DialogueCast`), it decides nothing, and how a line is acted is read
## off its words (`DialogueStaging`). The moves are authored in seconds at the
## default tier and played at `GameSpeed.cutscene_rate()`, as the cut-ins are;
## how long a line holds is `GameSpeed.speech_seconds` of that line, the card's
## own reading time; and on a still board (`BoardBeat.still()`) the lens cuts,
## the words land whole, nobody walks and the bars snap.
##
## A press finishes the words being typed, or moves to the next line; cancel
## skips to the end. Board3D builds it and drives it from its own `_process`,
## so it only ever runs with the 3D board on screen.

signal finished

enum Kind { TITLE, SPEAKER, WIDE, POWER }

## Seconds at the default tier.
const GLIDE_SECONDS := 1.0
const GLIDE_ARC := 0.12
## A flight at least this many cells long is heard as well as seen.
const WHOOSH_CELLS := 3.0
const BARS_SECONDS := 0.45
## A mission's opening: out of black, and the title card held over the
## establishing shot.
const FADE_SECONDS := 1.4
const CARD_IN := Vector2(0.6, 1.3)
const CARD_OUT := Vector2(3.4, 4.0)
const TITLE_SECONDS := 4.2
const TITLE_DRIFT_REACH := 1.1
## A general steps out of their HQ, then speaks.
const ENTER_SECONDS := 0.8
const SETTLE_SECONDS := 0.15
const WINDOW_SECONDS := 0.14
## Letters a second: quicker than anyone reads, so the typing is a flourish and
## the hold after it is the reading time. A blip every few letters.
const TYPE_RATE := 45.0
const BLIP_EVERY := 3
const BLIP_DB := -10.0
## Time left to finish reading once the last letter lands, at the least.
const READ_TAIL := 1.1
const EMOTE_SECONDS := 1.3
const EMOTE_LIFT := 0.12
## Where a general stands on their post: stepping out of the building toward
## the lens, from just inside the door to the edge of the cell.
const DOOR := 0.1
const MARK := 0.46
## A general with no army on this board, projected: a little larger than life,
## on a low projector beside the post rather than on it, since the post's own
## general may step out onto the same spot. The projection flickers out while
## somebody else speaks.
const HOLO_SCALE := 1.25
const HOLO_BESIDE := 0.55
const HOLO_FADE_SECONDS := 0.35
const HOLO_RADIUS := 0.26
const HOLO_BEAM := 0.35
## The Command Power: the general appears under the flash, raises a fist into
## the rising pillar, two shockwaves roll out, then the quote and the title.
const POWER_BARS_SECONDS := 0.2
const FLASH_SECONDS := 0.45
const POWER_FIST_AT := 0.3
const PILLAR_SECONDS := 0.5
const PILLAR_RADIUS := 0.34
const PILLAR_HEIGHT := 3.2
const POWER_WORDS_AT := 1.0
const POWER_TITLE_SECONDS := 0.2
const TITLE_READ := 1.4
const SHOCK_AT: Array[float] = [0.55, 0.8]
const SHOCK_SECONDS := 1.4
const SHOCK_WIDTH := 0.03
const SHOCK_STRENGTH := 1.4
const SHOCK_LIFT := 0.02
## The theme a scene is played under; the match's own comes back after it.
const THEME := &"council"
## Above the HUD's layer, which is hidden while this plays, and level with the
## cut-ins', which never play at the same time.
const FRAME_LAYER := 3

var rolling := false

var _camera: BoardCamera3D
var _map: MapData
var _hud: CanvasLayer
var _hud_was_visible := true
var _music_was := &""
var _frame: CinemaFrame
var _takes: Array[Take] = []
var _index := 0
var _t := 0.0
var _clock := 0.0
var _delta := 0.0
var _bars := 0.0
var _bars_seconds := BARS_SECONDS
var _closing := false
var _revealed := false
var _acted := false
var _blips := 0
var _from: CinemaPose3D
var _shot: CinemaShot3D
var _actors: Dictionary[StringName, Actor] = {}
var _emote: EmoteBubble3D
var _emote_at := 0.0
var _shocks: Array[Shock] = []


## One line of a scene, or its title card, and everything its timeline needs,
## worked out before it plays.
class Take:
	var kind: DialogueCinema3D.Kind
	var speaker: CommanderType
	var words := ""
	## The actor who says it, the post they stand on and whether they are
	## projected there rather than standing on it.
	var actor := &""
	var post := Vector2i.ZERO
	var projected := false
	## A wide shot's focus on the ground, and how far back it stands.
	var focus := Vector3.ZERO
	var reach := 0.0
	var side := 1
	var near := false
	var steps_out := false
	var gesture := &"talk"
	var emote := &""
	var glide := 0.0
	var window_at := 0.0
	var words_at := 0.0
	var type_seconds := 0.0
	var ends_at := 0.0
	var eyebrow := ""
	var title := ""
	var blurb := ""

	func typed_at() -> float:
		return words_at + type_seconds


## A general standing on the board for the length of a scene.
class Actor:
	var figure: CommanderActor3D
	## The projector a projected general stands on, or the pillar of a power.
	var light: Projector3D
	var door := Vector3.ZERO
	var mark := Vector3.ZERO
	var scale := 1.0
	var projected := false
	## How far a projection is switched on: it fades while somebody else speaks.
	var shown := 1.0
	## When they started stepping out; negative until they do.
	var out_at := -1.0
	var clip := &"idle"
	var clip_at := 0.0
	var light_at := -1.0


## A shockwave rolling out from a post, and when it started.
class Shock:
	var node: MeshInstance3D
	var material: ShaderMaterial
	var born := 0.0


func setup(camera: BoardCamera3D, map: MapData, hud: CanvasLayer) -> void:
	_camera = camera
	_map = map
	_hud = hud


## Plays a spoken beat, the briefing read again or a mission's opening, and
## returns once it has finished and the bars are out.
func play_lines(cast: DialogueCast) -> void:
	if rolling:
		await finished
	var takes := _takes_of(cast)
	if takes.is_empty():
		return
	_bars_seconds = BARS_SECONDS
	await _roll(takes, true)


## Plays a Command Power's activation for `commander`, fired from `post`.
func play_power(commander: CommanderType, quote: String, post: Vector2i) -> void:
	if rolling:
		await finished
	var take := Take.new()
	take.kind = Kind.POWER
	take.speaker = commander
	take.words = "“%s”" % quote if not quote.is_empty() else ""
	take.actor = StringName("%s:power" % commander.id)
	take.post = _on_board(post)
	take.eyebrow = "%s · COMMAND POWER" % commander.display_name.to_upper()
	take.title = commander.power_name.to_upper()
	take.blurb = commander.power_text
	var still := BoardBeat.still()
	take.window_at = 0.0 if still else POWER_WORDS_AT / _rate()
	take.words_at = take.window_at + (0.0 if still else WINDOW_SECONDS / _rate())
	take.type_seconds = 0.0 if still else take.words.length() / TYPE_RATE
	var read := 0.0 if still else (POWER_TITLE_SECONDS + TITLE_READ) / _rate()
	take.ends_at = maxf(Settings.speed.power_banner_seconds(), take.typed_at() + read)
	_bars_seconds = POWER_BARS_SECONDS
	Sfx.play(&"power_sting")
	await _roll([take], false)


## Whether the cinematic has the lens: from the first frame until the last line
## is done, after which the board's own camera glides home while the bars leave.
func directs_lens() -> bool:
	return rolling and not _closing


## Claims a press made while the cinematic plays: it finishes the words being
## typed, or moves on a line; cancel skips to the end. A press while the bars
## are leaving is swallowed, so it cannot land on the board they uncover.
func consume_press(event: InputEvent) -> bool:
	if not rolling or not TransitionInput.is_press(event):
		return false
	if _closing:
		return true
	if event.is_action_pressed(&"cancel"):
		_close()
		return true
	if not _revealed and _t < _takes[_index].typed_at():
		_revealed = true
	else:
		_next()
	return true


## Ends at once, with no bars to slide out: the board is leaving the screen.
func cut() -> void:
	if rolling:
		_finish()


## One frame of the cinematic. Board3D calls it while `rolling`.
func advance(delta: float) -> void:
	var still := BoardBeat.still()
	_delta = delta
	_clock += delta
	var bars_to := 0.0 if _closing else 1.0
	_bars = bars_to if still else move_toward(_bars, bars_to, delta * _rate() / _bars_seconds)
	_advance_shocks()
	if _closing:
		_advance_actors(_bars)
		_frame.pose_bars(_bars, 0.0, 0.0)
		_frame.pose_window(0.0, 1.0, false, Vector2.ZERO, false, _clock)
		if _bars <= 0.0:
			_finish()
		return
	_t += delta
	var take := _takes[_index]
	_camera.direct(_pose_of(take))
	_perform(take)
	_advance_actors(1.0)
	_pose_frame(take, still)
	if _t >= take.ends_at:
		_next()


func _roll(takes: Array[Take], themed: bool) -> void:
	_takes = takes
	_clock = 0.0
	_closing = false
	_bars = 0.0
	rolling = true
	_frame_up()
	_music_was = Music.current()
	if themed and _music_was != THEME:
		Music.play(THEME)
	_begin(0)
	await finished


func _begin(index: int) -> void:
	_index = index
	_t = 0.0
	_revealed = false
	_acted = false
	_blips = 0
	var take := _takes[index]
	_from = _camera.pose_now()
	var bearing := _bearing()
	match take.kind:
		Kind.TITLE, Kind.WIDE:
			_shot = CinemaShot3D.wide(take.focus, take.reach, bearing)
		Kind.SPEAKER:
			var actor := _cast(take)
			var eyes := actor.figure.face_height() * actor.scale
			_shot = CinemaShot3D.actor(actor.mark, eyes, bearing, take.side, take.near)
			if take.steps_out:
				actor.out_at = _clock + take.glide * 0.5
		Kind.POWER:
			var actor := _cast(take)
			actor.out_at = _clock
			var eyes := actor.figure.face_height() * actor.scale
			_shot = CinemaShot3D.limit(actor.mark, eyes, bearing)
	if take.glide > 0.0 and _from.target.distance_to(_shot.start.target) >= WHOOSH_CELLS:
		Sfx.play(&"cut_whoosh")
	_frame.say(take.speaker, take.words)
	if take.kind == Kind.TITLE:
		_frame.show_card(take.title, take.blurb)
	if take.kind == Kind.POWER:
		_frame.show_power(
			take.eyebrow, take.title, take.blurb, CommanderVisuals.theme_for(take.speaker)
		)
	else:
		_frame.hide_power()


func _pose_of(take: Take) -> CinemaPose3D:
	if _t < take.glide:
		return CinemaPose3D.glide(_from, _shot.start, _t / take.glide, GLIDE_ARC)
	return _shot.pose_at(_t - take.glide)


## What the speaker does as their words come: the gesture their line calls for,
## the emote over their head, a blip for every few letters typed; a power's
## general raises a fist into the pillar as it rises.
func _perform(take: Take) -> void:
	var actor: Actor = _actors.get(take.actor)
	if take.kind == Kind.POWER and actor != null and actor.light_at < 0.0:
		if _t >= POWER_FIST_AT / _rate():
			actor.light_at = _clock
			_act(actor, &"fist")
	if not _acted and _t >= take.window_at and not take.words.is_empty():
		_acted = true
		Sfx.play(&"window_open")
		if actor != null and take.kind == Kind.SPEAKER:
			_act(actor, take.gesture)
			if take.emote != &"":
				_pop(actor, take.emote)
	var letters := _frame.letters_at(_typed(take))
	if take.speaker != null and letters / BLIP_EVERY > _blips:
		_blips = letters / BLIP_EVERY
		Sfx.play(&"text_blip", BLIP_DB)
	_spawn_shocks(take)


func _pose_frame(take: Take, still: bool) -> void:
	var fade := 0.0
	var card := 0.0
	if take.kind == Kind.TITLE and not still:
		fade = 1.0 - _t / FADE_SECONDS
		card = minf(_ramp(CARD_IN), 1.0 - _ramp(CARD_OUT))
	var flash := 0.0
	if take.kind == Kind.POWER and not still:
		flash = 1.0 - _t / (FLASH_SECONDS / _rate())
	_frame.pose_bars(_bars, fade, flash)
	_frame.pose_card(card)
	var open := 0.0
	if not take.words.is_empty():
		open = 1.0 if still else _since(take.window_at) / (WINDOW_SECONDS / _rate())
	var typed := _typed(take)
	var actor: Actor = _actors.get(take.actor)
	var anchored := actor != null and take.kind == Kind.SPEAKER
	var anchor := Vector2.ZERO
	if anchored:
		var head := actor.figure.to_global(actor.figure.head_top())
		anchored = not _camera.camera.is_position_behind(head)
		anchor = _camera.camera.unproject_position(head)
	_frame.pose_window(open, typed, typed >= 1.0 and open >= 1.0, anchor, anchored, _clock)
	var title := 1.0
	if not _revealed and not still:
		title = _since(take.typed_at()) / (POWER_TITLE_SECONDS / _rate())
	_frame.pose_power(title)
	if _emote != null:
		_emote.pose(_clock - _emote_at, EMOTE_SECONDS)


func _typed(take: Take) -> float:
	if _revealed:
		return 1.0
	if take.type_seconds <= 0.0:
		return 1.0 if _t >= take.words_at else 0.0
	return clampf(_since(take.words_at) / take.type_seconds, 0.0, 1.0)


func _next() -> void:
	if _index + 1 < _takes.size():
		_begin(_index + 1)
	else:
		_close()


func _close() -> void:
	_closing = true


func _finish() -> void:
	for actor: Actor in _actors.values():
		actor.figure.queue_free()
		if actor.light != null:
			actor.light.queue_free()
	_actors.clear()
	if _emote != null:
		_emote.queue_free()
		_emote = null
	for shock in _shocks:
		shock.node.queue_free()
	_shocks.clear()
	_frame.visible = false
	_frame.hide_power()
	_hud.visible = _hud_was_visible
	if Music.current() != _music_was:
		if _music_was == &"":
			Music.stop()
		else:
			Music.play(_music_was)
	rolling = false
	_closing = false
	finished.emit()


# --- the takes ---------------------------------------------------------------


func _takes_of(cast: DialogueCast) -> Array[Take]:
	var takes: Array[Take] = []
	var still := BoardBeat.still()
	if not cast.title.is_empty() and not still:
		takes.append(_title_take(cast))
	var sides: Dictionary[StringName, int] = {}
	var said: Dictionary[StringName, int] = {}
	var previous: Take = null
	for line: MissionLine in cast.lines:
		if line == null:
			continue
		var take := Take.new()
		take.words = line.text
		if line.is_narration():
			take.kind = Kind.WIDE
			_frame_wide(take, cast.subject)
		else:
			_stage_speaker(take, line, cast, sides, said, previous)
		var travels := previous == null or previous.kind != take.kind or previous.post != take.post
		take.glide = GLIDE_SECONDS / _rate() if travels and not still else 0.0
		var entrance := ENTER_SECONDS if take.steps_out else SETTLE_SECONDS
		take.window_at = 0.0 if still else take.glide + entrance / _rate()
		take.words_at = take.window_at + (0.0 if still else WINDOW_SECONDS / _rate())
		take.type_seconds = 0.0 if still else take.words.length() / TYPE_RATE
		if cast.untimed:
			take.ends_at = INF
		else:
			var read := take.typed_at() + (0.0 if still else READ_TAIL)
			var hold := take.words_at + Settings.speed.speech_seconds(take.words.length())
			take.ends_at = maxf(read, hold)
		takes.append(take)
		previous = take
	return takes


func _title_take(cast: DialogueCast) -> Take:
	var take := Take.new()
	take.kind = Kind.TITLE
	take.title = cast.title
	take.blurb = cast.place
	var middle := Vector2(_map.size()) / 2.0
	take.focus = Vector3(middle.x, BoardSpace3D.LAND_TOP, middle.y)
	take.reach = CinemaShot3D.board_reach(_map.size()) * TITLE_DRIFT_REACH
	take.window_at = INF
	take.words_at = INF
	take.ends_at = TITLE_SECONDS / _rate()
	return take


func _stage_speaker(
	take: Take,
	line: MissionLine,
	cast: DialogueCast,
	sides: Dictionary[StringName, int],
	said: Dictionary[StringName, int],
	previous: Take
) -> void:
	take.kind = Kind.SPEAKER
	take.speaker = cast.commanders.by_id(line.speaker)
	var post: Vector2i = cast.posts.get(line.speaker, DialogueCast.NOWHERE)
	take.projected = post == DialogueCast.NOWHERE
	take.post = _on_board(cast.home if take.projected else post)
	take.actor = StringName("%s%s" % [line.speaker, ":holo" if take.projected else ""])
	if not sides.has(line.speaker):
		var alternate := 1 if sides.size() % 2 == 0 else -1
		sides[line.speaker] = CinemaShot3D.side_facing(
			_ground(take.post), Vector2(_map.size()) / 2.0, _bearing(), alternate
		)
	take.side = sides[line.speaker]
	var beat: int = said.get(line.speaker, 0)
	said[line.speaker] = beat + 1
	take.steps_out = beat == 0 and not take.projected and not BoardBeat.still()
	var again := previous != null and previous.actor == take.actor
	take.near = beat > 0 and not (again and previous.near)
	take.gesture = DialogueStaging.gesture_for(line.text, beat)
	take.emote = DialogueStaging.emote_for(line.text)


func _frame_wide(take: Take, subject: Array[Vector2i]) -> void:
	if subject.is_empty():
		var middle := Vector2(_map.size()) / 2.0
		take.focus = Vector3(middle.x, BoardSpace3D.LAND_TOP, middle.y)
		take.reach = CinemaShot3D.board_reach(_map.size())
		return
	var middle := CinemaShot3D.middle_of(subject)
	take.focus = Vector3(middle.x, BoardSpace3D.LAND_TOP, middle.y)
	take.reach = CinemaShot3D.subject_reach(subject)


# --- the generals on the board -----------------------------------------------


## The actor `take` is said by, stood on the board the first time they are
## needed: on their post's edge nearest the lens, stepping out of the building
## behind them, or projected there over a disc of light.
func _cast(take: Take) -> Actor:
	if _actors.has(take.actor):
		return _actors[take.actor]
	var actor := Actor.new()
	var toward := Vector3(sin(_bearing()), 0.0, cos(_bearing()))
	var ground := _ground(take.post)
	actor.door = ground + toward * DOOR
	actor.mark = ground + toward * MARK
	actor.figure = CommanderActor3D.make(take.speaker)
	var tint := CommanderVisuals.theme_for(take.speaker).color_light
	if take.projected:
		actor.projected = true
		actor.scale = HOLO_SCALE
		actor.figure.set_hologram(tint)
		actor.mark += Vector3(cos(_bearing()), 0.0, -sin(_bearing())) * HOLO_BESIDE
		actor.door = actor.mark
		actor.out_at = _clock
		actor.light = Projector3D.make(tint, HOLO_RADIUS, HOLO_BEAM, false)
		actor.light_at = _clock
	elif take.kind == Kind.POWER:
		actor.door = actor.mark
		actor.light = Projector3D.make(tint, PILLAR_RADIUS, PILLAR_HEIGHT, true)
	actor.figure.scale = Vector3.ONE * actor.scale
	actor.figure.position = actor.door
	add_child(actor.figure)
	if actor.light != null:
		actor.light.position = actor.mark
		add_child(actor.light)
	_actors[take.actor] = actor
	return actor


func _act(actor: Actor, clip: StringName) -> void:
	actor.clip = clip
	actor.clip_at = _clock


func _pop(actor: Actor, emote: StringName) -> void:
	if _emote != null:
		_emote.queue_free()
	_emote = EmoteBubble3D.make(emote)
	var head := actor.figure.head_top() * actor.scale
	_emote.position = actor.mark + head + Vector3.UP * EMOTE_LIFT
	add_child(_emote)
	_emote_at = _clock
	Sfx.play(&"emote_pop")


## Walks, turns and poses every actor for this frame: a general stepping out
## walks from the door to their mark and fades in on the threshold; one who is
## out faces the lens and plays their clip. `presence` fades everyone as the
## scene closes.
func _advance_actors(presence: float) -> void:
	var still := BoardBeat.still()
	var eye := _camera.camera.global_position
	var speaking: StringName = &"" if _closing else _takes[_index].actor
	for key: StringName in _actors:
		var actor := _actors[key]
		if actor.projected:
			var wanted := 1.0 if key == speaking else 0.0
			var step := _delta * _rate() / HOLO_FADE_SECONDS
			actor.shown = wanted if still else move_toward(actor.shown, wanted, step)
		var figure := actor.figure
		if actor.out_at < 0.0 or _clock < actor.out_at:
			figure.visible = false
			continue
		figure.visible = true
		var out := 1.0 if still else clampf((_clock - actor.out_at) / ENTER_SECONDS, 0.0, 1.0)
		figure.position = actor.door.lerp(actor.mark, smoothstep(0.0, 1.0, out))
		figure.set_alpha(minf(clampf(out * 3.0, 0.0, 1.0), presence * actor.shown))
		var walking := out < 1.0
		var facing := actor.mark + (actor.mark - actor.door) if walking else eye
		facing.y = figure.position.y
		if figure.position.distance_to(facing) > 0.01:
			figure.look_at(facing, Vector3.UP)
		if walking:
			figure.pose(&"walk", _clock - actor.out_at)
		else:
			figure.pose(actor.clip, _clock - actor.clip_at)
		if actor.light != null:
			var lit := 0.0
			if actor.light_at >= 0.0:
				var rise := (_clock - actor.light_at) / (PILLAR_SECONDS / _rate())
				lit = 1.0 if still else clampf(rise, 0.0, 1.0)
			actor.light.pose(lit * presence * actor.shown, _clock)


func _spawn_shocks(take: Take) -> void:
	if take.kind != Kind.POWER or BoardBeat.still():
		return
	while _shocks.size() < SHOCK_AT.size() and _t >= SHOCK_AT[_shocks.size()] / _rate():
		_shocks.append(_shock_at(take))


func _shock_at(take: Take) -> Shock:
	var reach := Vector2(_map.size()).length() + 2.0
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * reach * 2.0
	var shock := Shock.new()
	shock.material = Projector3D.glow_material(
		Projector3D.GLOW_RING, CommanderVisuals.theme_for(take.speaker).color_light, reach
	)
	shock.material.set_shader_parameter(&"width", SHOCK_WIDTH)
	shock.material.set_shader_parameter(&"bounds", Vector4(0, 0, _map.width, _map.height))
	shock.node = MeshInstance3D.new()
	shock.node.mesh = plane
	shock.node.material_override = shock.material
	shock.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shock.node.position = _ground(take.post) + Vector3.UP * SHOCK_LIFT
	shock.born = _clock
	add_child(shock.node)
	return shock


func _advance_shocks() -> void:
	for shock in _shocks:
		var out := clampf((_clock - shock.born) / (SHOCK_SECONDS / _rate()), 0.0, 1.0)
		shock.material.set_shader_parameter(&"radius", out)
		shock.material.set_shader_parameter(&"strength", (1.0 - out) * SHOCK_STRENGTH)
		shock.node.visible = out < 1.0


# --- the frame ---------------------------------------------------------------


func _frame_up() -> void:
	if _frame == null:
		var layer := CanvasLayer.new()
		layer.layer = FRAME_LAYER
		add_child(layer)
		_frame = CinemaFrame.new()
		layer.add_child(_frame)
	_frame.visible = true
	_hud_was_visible = _hud.visible
	_hud.visible = false


# --- arithmetic --------------------------------------------------------------


func _since(at: float) -> float:
	return clampf(_t - at, 0.0, INF)


## How far through the window `span` (seconds at the default tier) the take is.
func _ramp(span: Vector2) -> float:
	return clampf((_t * _rate() - span.x) / (span.y - span.x), 0.0, 1.0)


## The bearing the board is looked at from, in whole quarter turns.
func _bearing() -> float:
	return _camera.quarters * PI / 2.0


static func _rate() -> float:
	return Settings.speed.cutscene_rate()


## A cell on the board to frame: `cell`, or the board's middle when it is none.
func _on_board(cell: Vector2i) -> Vector2i:
	return cell if _map.in_bounds(cell) else _map.size() / 2


func _ground(cell: Vector2i) -> Vector3:
	var centre := BoardSpace3D.cell_centre(cell)
	return Vector3(centre.x, BoardSpace3D.ground_top(_map.terrain_at(cell).id), centre.y)
