class_name DialogueCinema3D
extends Node3D
## The 3D board's dialogue. Where the flat board raises a card — a scripted
## beat's lines, the briefing read again, a Command Power's quote — the 3D board
## plays a cinematic: the letterbox slides in, the lens flies to whoever is
## speaking and swings round them while their portrait is projected over their
## post and their words are typed out; a narrated line is an establishing shot
## of the board, or of what the beat just put on it. A Command Power cuts in
## under a flash to a swoop round the general, sends two shockwaves across the
## field and lands the power's name as a title.
##
## Presentation only, like the card it stands in for: handed the words and the
## posts (`DialogueCast`), it decides nothing. The moves are authored in seconds
## at the default tier and played at `GameSpeed.cutscene_rate()`, as the
## cut-ins are; how long a line holds is `GameSpeed.speech_seconds` of that
## line, the card's own reading time; and on a still board (`BoardBeat.still()`)
## the lens cuts, the words land whole and the bars snap.
##
## A press finishes the words being typed, or moves to the next line; Esc skips
## to the end. Board3D builds it and drives it from its own `_process`, so it
## only ever runs with the 3D board on screen.

signal finished

enum Kind { CLOSE, WIDE, POWER }

## Seconds at the default tier.
const GLIDE_SECONDS := 1.0
const GLIDE_ARC := 0.12
const BARS_SECONDS := 0.45
const HOLO_SECONDS := 0.6
## The screen starts rising once the lens is this far into its glide.
const HOLO_CUE := 0.5
## Letters a second: quicker than anyone reads, so the typing is a flourish and
## the hold after it is the reading time.
const TYPE_RATE := 45.0
## Time left to finish reading once the last letter lands, at the least.
const READ_TAIL := 1.1
## The Command Power: the bars snap in under the flash, the words start as the
## screen comes up, the title lands once they are typed and is given time to be
## read, and two shockwaves roll out across the board.
const POWER_BARS_SECONDS := 0.2
const FLASH_SECONDS := 0.4
const POWER_WORDS_AT := 0.5
const TITLE_SECONDS := 0.2
const TITLE_READ := 1.4
const SHOCK_AT: Array[float] = [0.3, 0.55]
const SHOCK_SECONDS := 1.4
const SHOCK_WIDTH := 0.03
const SHOCK_STRENGTH := 1.4
const SHOCK_LIFT := 0.02
const POWER_HOLO_SIZE := 1.3
## Above the HUD's layer, which is hidden while this plays, and level with the
## cut-ins', which never play at the same time.
const FRAME_LAYER := 3
const NOWHERE := Vector2i(-1, -1)

var rolling := false

var _camera: BoardCamera3D
var _map: MapData
var _hud: CanvasLayer
var _hud_was_visible := true
var _frame: CinemaFrame
var _takes: Array[Take] = []
var _index := 0
var _t := 0.0
var _clock := 0.0
var _bars := 0.0
var _bars_seconds := BARS_SECONDS
var _closing := false
var _revealed := false
var _from: CinemaPose3D
var _shot: CinemaShot3D
var _holos: Dictionary[StringName, SpeakerHolo3D] = {}
var _presence: Dictionary[StringName, float] = {}
var _shocks: Array[Shock] = []


## One line of a cinematic and everything its timeline needs, worked out before
## it plays.
class Take:
	var kind: DialogueCinema3D.Kind
	var speaker: CommanderType
	var words := ""
	## The ground point the shot frames, and how far back a wide shot stands.
	var post := Vector3.ZERO
	var reach := 0.0
	var off_board := false
	var side := 1
	## The same voice as the take before, so the lens carries on round them.
	var continues := false
	var glide := 0.0
	var words_at := 0.0
	var type_seconds := 0.0
	var ends_at := 0.0
	var eyebrow := ""
	var title := ""
	var blurb := ""

	func typed_at() -> float:
		return words_at + type_seconds

	## Which projector this take lights: one per voice, and a larger one of its
	## own for a Command Power.
	func holo_key() -> StringName:
		if speaker == null:
			return &""
		var power := kind == DialogueCinema3D.Kind.POWER
		return StringName("%s%s" % [speaker.id, ":power" if power else ""])


## A shockwave rolling out from a post, and when it started.
class Shock:
	var node: MeshInstance3D
	var material: ShaderMaterial
	var born := 0.0


func setup(camera: BoardCamera3D, map: MapData, hud: CanvasLayer) -> void:
	_camera = camera
	_map = map
	_hud = hud


## Plays a spoken beat, or the briefing read again, and returns once it has
## finished and the bars are out.
func play_lines(cast: DialogueCast) -> void:
	if rolling:
		await finished
	var takes := _takes_of(cast)
	if takes.is_empty():
		return
	_bars_seconds = BARS_SECONDS
	await _roll(takes)


## Plays a Command Power's activation for `commander`, fired from `post`.
func play_power(commander: CommanderType, quote: String, post: Vector2i) -> void:
	if rolling:
		await finished
	var take := Take.new()
	take.kind = Kind.POWER
	take.speaker = commander
	take.words = "“%s”" % quote if not quote.is_empty() else ""
	take.post = _ground(_on_board(post))
	take.eyebrow = "%s · COMMAND POWER" % commander.display_name.to_upper()
	take.title = commander.power_name.to_upper()
	take.blurb = commander.power_text
	var rate := Settings.speed.cutscene_rate()
	var still := BoardBeat.still()
	take.words_at = 0.0 if still else POWER_WORDS_AT / rate
	take.type_seconds = 0.0 if still else take.words.length() / TYPE_RATE
	var landed := take.typed_at() + (0.0 if still else (TITLE_SECONDS + TITLE_READ) / rate)
	take.ends_at = maxf(Settings.speed.power_banner_seconds(), landed)
	_bars_seconds = POWER_BARS_SECONDS
	await _roll([take])


## Whether the cinematic has the lens: from the first frame until the last line
## is done, after which the board's own camera glides home while the bars leave.
func directs_lens() -> bool:
	return rolling and not _closing


## Claims a press made while the cinematic plays: it finishes the words being
## typed, or moves on a line; Esc skips to the end. A press while the bars are
## leaving is swallowed, so it cannot land on the board they uncover.
func consume_press(event: InputEvent) -> bool:
	if not rolling or not TransitionInput.is_press(event):
		return false
	if _closing:
		return true
	if event.is_action_pressed(&"ui_cancel"):
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
	var step := delta * Settings.speed.cutscene_rate()
	_clock += delta
	var bars_to := 0.0 if _closing else 1.0
	_bars = bars_to if still else move_toward(_bars, bars_to, step / _bars_seconds)
	_advance_holos(step, still)
	_advance_shocks()
	if _closing:
		_frame.pose(_bars, 1.0, false, 1.0, 0.0, _clock)
		if _bars <= 0.0 and _dark():
			_finish()
		return
	_t += delta
	var take := _takes[_index]
	_camera.direct(_pose_of(take))
	_spawn_shocks(take)
	var typed := 1.0
	if not _revealed and take.type_seconds > 0.0:
		typed = _since(take.words_at) / take.type_seconds
	var title := 1.0
	if not _revealed and not still:
		title = _since(take.typed_at()) / (TITLE_SECONDS / _rate())
	var flash := 0.0
	if take.kind == Kind.POWER and not still:
		flash = 1.0 - _t / (FLASH_SECONDS / _rate())
	_frame.pose(_bars, typed, typed >= 1.0, title, flash, _clock)
	if _t >= take.ends_at:
		_next()


func _roll(takes: Array[Take]) -> void:
	_takes = takes
	_clock = 0.0
	_closing = false
	_bars = 0.0
	rolling = true
	_frame_up()
	_begin(0)
	await finished


func _begin(index: int) -> void:
	_index = index
	_t = 0.0
	_revealed = false
	var take := _takes[index]
	_from = _camera.pose_now()
	var bearing := _bearing()
	match take.kind:
		Kind.CLOSE:
			if take.continues:
				_shot = CinemaShot3D.more(_from, take.side)
			else:
				_shot = CinemaShot3D.close(take.post, bearing, take.side)
		Kind.WIDE:
			_shot = CinemaShot3D.wide(take.post, take.reach, bearing)
		Kind.POWER:
			_shot = CinemaShot3D.power(take.post, bearing)
	_raise_holo(take)
	_frame.say(take.speaker, take.words)
	if take.kind == Kind.POWER:
		_frame.show_title(
			take.eyebrow, take.title, take.blurb, CommanderVisuals.theme_for(take.speaker)
		)
	else:
		_frame.hide_title()


func _pose_of(take: Take) -> CinemaPose3D:
	if _t < take.glide:
		return CinemaPose3D.glide(_from, _shot.start, _t / take.glide, GLIDE_ARC)
	return _shot.pose_at(_t - take.glide)


func _next() -> void:
	if _index + 1 < _takes.size():
		_begin(_index + 1)
	else:
		_close()


func _close() -> void:
	_closing = true


func _finish() -> void:
	for holo: SpeakerHolo3D in _holos.values():
		holo.queue_free()
	_holos.clear()
	_presence.clear()
	for shock in _shocks:
		shock.node.queue_free()
	_shocks.clear()
	_frame.visible = false
	_hud.visible = _hud_was_visible
	rolling = false
	_closing = false
	finished.emit()


# --- the takes ---------------------------------------------------------------


func _takes_of(cast: DialogueCast) -> Array[Take]:
	var takes: Array[Take] = []
	var sides: Dictionary[StringName, int] = {}
	var rate := Settings.speed.cutscene_rate()
	var still := BoardBeat.still()
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
			take.kind = Kind.CLOSE
			take.speaker = cast.commanders.by_id(line.speaker)
			var post: Vector2i = cast.posts.get(line.speaker, NOWHERE)
			take.off_board = post == NOWHERE
			take.post = _ground(_on_board(cast.home if take.off_board else post))
			if not sides.has(line.speaker):
				var alternate := 1 if sides.size() % 2 == 0 else -1
				sides[line.speaker] = CinemaShot3D.side_facing(
					take.post, Vector2(_map.size()) / 2.0, _bearing(), alternate
				)
			take.side = sides[line.speaker]
			take.continues = (
				previous != null
				and previous.kind == Kind.CLOSE
				and previous.speaker == take.speaker
			)
		take.glide = 0.0 if still or take.continues else GLIDE_SECONDS / rate
		take.words_at = take.glide
		take.type_seconds = 0.0 if still else take.words.length() / TYPE_RATE
		if cast.untimed:
			take.ends_at = INF
		else:
			var read := take.typed_at() + (0.0 if still else READ_TAIL)
			var hold := take.glide + Settings.speed.speech_seconds(take.words.length())
			take.ends_at = maxf(read, hold)
		takes.append(take)
		previous = take
	return takes


func _frame_wide(take: Take, subject: Array[Vector2i]) -> void:
	if subject.is_empty():
		var middle := Vector2(_map.size()) / 2.0
		take.post = Vector3(middle.x, BoardSpace3D.LAND_TOP, middle.y)
		take.reach = CinemaShot3D.board_reach(_map.size())
		return
	var middle := CinemaShot3D.middle_of(subject)
	take.post = Vector3(middle.x, BoardSpace3D.LAND_TOP, middle.y)
	take.reach = CinemaShot3D.subject_reach(subject)


# --- what stands on the board ------------------------------------------------


func _raise_holo(take: Take) -> void:
	var key := take.holo_key()
	if key == &"" or _holos.has(key):
		return
	var size := POWER_HOLO_SIZE if take.kind == Kind.POWER else 1.0
	var tint := CommanderVisuals.theme_for(take.speaker).color_light
	var holo := SpeakerHolo3D.make(take.speaker, tint, size, take.off_board)
	holo.position = take.post
	add_child(holo)
	_holos[key] = holo
	_presence[key] = 0.0


## The screen of whoever is speaking comes up as the lens arrives on them;
## every other screen goes dark.
func _advance_holos(step: float, still: bool) -> void:
	var wanted := &""
	if not _closing:
		var take := _takes[_index]
		if take.continues or _t >= take.glide * HOLO_CUE:
			wanted = take.holo_key()
	for key: StringName in _holos:
		var target := 1.0 if key == wanted else 0.0
		var now := target if still else move_toward(_presence[key], target, step / HOLO_SECONDS)
		_presence[key] = now
		_holos[key].pose(now, _clock)


func _dark() -> bool:
	for key: StringName in _presence:
		if _presence[key] > 0.0:
			return false
	return true


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
	shock.material = SpeakerHolo3D.glow_material(
		SpeakerHolo3D.GLOW_RING, CommanderVisuals.theme_for(take.speaker).color_light, reach
	)
	shock.material.set_shader_parameter(&"width", SHOCK_WIDTH)
	shock.material.set_shader_parameter(&"bounds", Vector4(0, 0, _map.width, _map.height))
	shock.node = MeshInstance3D.new()
	shock.node.mesh = plane
	shock.node.material_override = shock.material
	shock.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shock.node.position = take.post + Vector3.UP * SHOCK_LIFT
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
