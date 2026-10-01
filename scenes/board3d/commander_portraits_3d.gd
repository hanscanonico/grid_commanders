class_name CommanderPortraits3D
extends Node
## The one answer to which picture of a general a field shows while the 3D board
## is the chosen view: a still of their 3D figure, head and shoulders, standing
## in the pixel bust's inked window. `CommanderBust` asks `showing` and
## `still_for`; with the flat view chosen it draws the pixel art as before.
##
## Stills, not live renders: each (general, drawing) is shot once in a small
## world of its own, read back, kept, and the studio is freed once nothing is
## waiting — a menu pays no 3D cost per frame. Stills are shot to a budget per
## frame, so a page of twenty-three faces fills over a few frames rather than
## stalling one.

## How the stills are sampled: rendered well above the size they are drawn at,
## so they are minified, never magnified.
const FILTER := CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
const KEY_COLOUR := Color("#fff0dc")
const FILL_COLOUR := Color("#b9cdf0")
const AMBIENT := Color("#c2d0e6")
## The empty seat is nobody: the plain officer as a hologram, where the pixel art
## draws a silhouette.
const EMPTY_SEAT := Color("#9fb3c8")
## How long a frame may spend shooting stills before the rest wait for the next:
## at least one is shot every frame, however slow the machine.
const FRAME_BUDGET_USEC := 8000

static var _stills: Dictionary[String, Texture2D] = {}
static var _waiting: Dictionary[String, Array] = {}
static var _queue: Array[Array] = []
static var _studio: CommanderPortraits3D
## Held for the life of the game: Godot frees a material's shader with the last
## material using it, and building it again stalls a frame on the web.
static var _kept: Material

var _viewport: SubViewport
var _lens: Camera3D
var _actor: CommanderActor3D


## Whether fields show the 3D stills: the 3D view is chosen and there is a
## renderer to shoot them with.
static func showing() -> bool:
	return Settings.board_3d and DisplayServer.get_name() != "headless"


## The still of `commander` (null is the empty seat) as the whole bust or the
## face chip, or null while it is still to be shot — `ready` is called once it
## is, so the field can place it. A field asking again before then is not
## queued twice.
static func still_for(commander: CommanderType, whole: bool, ready: Callable) -> Texture2D:
	var variant := PortraitShot3D.BUST if whole else PortraitShot3D.FACE
	var id := CommanderType.NEUTRAL_ID if commander == null else commander.id
	var key := PortraitShot3D.key(id, variant)
	if _stills.has(key):
		return _stills[key]
	if not _waiting.has(key):
		_waiting[key] = []
		_queue.append([key, commander, variant])
	if not _waiting[key].has(ready):
		_waiting[key].append(ready)
	_open_studio()
	return null


static func _open_studio() -> void:
	if _studio != null:
		return
	if _kept == null:
		_kept = MeshKit.vertex_material()
		_kept.get_rid()
	_studio = CommanderPortraits3D.new()
	_studio.name = "CommanderPortraits3D"
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child.call_deferred(_studio)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_lens = Camera3D.new()
	_lens.projection = Camera3D.PROJECTION_ORTHOGONAL
	_lens.environment = _environment()
	_viewport.add_child(_lens)
	_lens.current = true
	_add_lights()


func _process(_delta: float) -> void:
	var began := Time.get_ticks_usec()
	while not _queue.is_empty() and Time.get_ticks_usec() - began < FRAME_BUDGET_USEC:
		var job: Array = _queue.pop_front()
		_pose(job[1], job[2])
		_finish(job)
	if _queue.is_empty():
		_studio = null
		queue_free()


## Stands the figure at rest in the lens. Every transform is handed to the
## renderer directly: a node's own reaches it only when the frame's
## notifications flush, and the still is drawn before that — a figure shot
## without it stands every part at its root, under the shot.
func _pose(commander: CommanderType, variant: StringName) -> void:
	_actor = CommanderActor3D.new()
	var id := CommanderType.NEUTRAL_ID if commander == null else commander.id
	var look := CommanderLooks3D.look_of(id)
	look[CommanderHead3D.CLOSE_UP] = true
	_actor.build(look, CommanderVisuals.theme_for(commander))
	if id == CommanderType.NEUTRAL_ID:
		_actor.set_hologram(EMPTY_SEAT)
	_actor.rotation_degrees.y = PortraitShot3D.YAW_DEG
	_viewport.add_child(_actor)
	_lens.size = PortraitShot3D.lens_height(variant)
	_lens.look_at_from_position(PortraitShot3D.eye(variant), PortraitShot3D.aim(variant))
	RenderingServer.camera_set_transform(_lens.get_camera_rid(), _lens.global_transform)
	for shape: VisualInstance3D in _viewport.find_children("*", "VisualInstance3D", true, false):
		RenderingServer.instance_set_transform(shape.get_instance(), shape.global_transform)
	_viewport.size = PortraitShot3D.pixels(variant)


func _finish(job: Array) -> void:
	var key: String = job[0]
	_stills[key] = _shoot(job[1], job[2])
	_actor.free()
	_actor = null
	for ready: Callable in _waiting[key]:
		if ready.is_valid():
			ready.call()
	_waiting.erase(key)


## One still of the posed figure, drawn now — `force_draw`, since a window the
## system has stopped drawing never draws its viewports — read back and laid
## over the faction window.
func _shoot(commander: CommanderType, variant: StringName) -> Texture2D:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	RenderingServer.force_draw(false)
	var figure := _viewport.get_texture().get_image()
	if figure == null or figure.is_empty():
		var whole := variant == PortraitShot3D.BUST
		return (
			CommanderVisuals.portrait_for(commander)
			if whole
			else CommanderVisuals.face_for(commander)
		)
	figure.convert(Image.FORMAT_RGBA8)
	var still := _window(variant, CommanderVisuals.theme_for(commander))
	still.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), Vector2i.ZERO)
	still.generate_mipmaps()
	return ImageTexture.create_from_image(still)


## The pixel bust's window behind the figure: an ink rule round the army's
## shadow tone, clear above it where the head breaks out.
static func _window(variant: StringName, theme: CommanderVisuals.FactionTheme) -> Image:
	var size := PortraitShot3D.pixels(variant)
	var still := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var frame := PortraitShot3D.window(variant)
	still.fill_rect(frame, CommanderFigure3D.INK)
	still.fill_rect(frame.grow(-PortraitShot3D.pen(variant)), theme.color_dark)
	return still


func _environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT
	env.ambient_light_energy = 0.25
	return env


## A warm key from the lens's upper left and a cool fill from the right, so the
## flat-shaded facets read as a solid head.
func _add_lights() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, 150.0, 0.0)
	key.light_color = KEY_COLOUR
	key.light_energy = 0.45
	key.shadow_enabled = true
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10.0, -140.0, 0.0)
	fill.light_color = FILL_COLOUR
	fill.light_energy = 0.2
	_viewport.add_child(fill)
