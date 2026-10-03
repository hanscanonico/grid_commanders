class_name UnitIcons3D
extends Node
## The one answer to which picture of a unit a menu row shows: a still of its 3D
## model while the 3D board is the chosen view, the board's pixel tile
## otherwise. `BattleMenus.build_actions` asks `icon_for`.
##
## Stills, not live renders, on `CommanderPortraits3D`'s mechanics: each (unit,
## army, size) is shot once in a small world of its own, read back, kept, and
## the studio is freed once nothing waits. A still not shot yet answers with the
## tile and is queued, so a menu never waits on one; `warm` queues an army's
## whole roster as the board comes up, so the first menu opened has them.

const KEY_COLOUR := Color("#fff6ea")
const FILL_COLOUR := Color("#b9cdf0")
const AMBIENT := Color("#c3cfe6")
## How long a frame may spend shooting stills before the rest wait for the next:
## at least one is shot every frame, however slow the machine.
const FRAME_BUDGET_USEC := 8000

static var _stills: Dictionary[String, Texture2D] = {}
static var _queued: Dictionary[String, bool] = {}
static var _queue: Array[Array] = []
static var _studio: UnitIcons3D
## Held for the life of the game: Godot frees a material's shader with the last
## material using it, and building it again stalls a frame on the web.
static var _kept: Material

var _viewport: SubViewport
var _lens: Camera3D
var _model: Node3D


## Whether rows show the 3D stills: the 3D view is chosen and there is a
## renderer to shoot them with.
static func showing() -> bool:
	return Settings.board_3d and DisplayServer.get_name() != "headless"


## The icon of `type` in the army drawn on atlas `row`, in the view being played.
static func icon_for(type: UnitType, row: int) -> Texture2D:
	if showing():
		var key := UnitStillShot3D.key(type.id, row, _side())
		if _stills.has(key):
			return _stills[key]
		_ask(type.id, row)
	return UnitSprite.tile_texture_for(type, row)


## Queues a still of every type in `types` for the army on atlas `row`.
static func warm(types: Array[UnitType], row: int) -> void:
	if not showing():
		return
	for type in types:
		_ask(type.id, row)


static func _ask(type_id: StringName, row: int) -> void:
	var side := _side()
	var key := UnitStillShot3D.key(type_id, row, side)
	if _stills.has(key) or _queued.has(key):
		return
	_queued[key] = true
	_queue.append([key, type_id, row, side])
	_open_studio()


## The menu's icon slot in screen pixels, at the window's present scale.
static func _side() -> int:
	var root := (Engine.get_main_loop() as SceneTree).root
	return UnitStillShot3D.pixels(root.get_final_transform().get_scale().x)


static func _open_studio() -> void:
	if _studio != null:
		return
	if _kept == null:
		_kept = MeshKit.vertex_material()
		_kept.get_rid()
	_studio = UnitIcons3D.new()
	_studio.name = "UnitIcons3D"
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
		_pose(job[1], job[2], job[3])
		var still := _shoot(job[3])
		if still != null:
			_stills[job[0]] = still
		_queued.erase(job[0])
		_model.free()
		_model = null
	if _queue.is_empty():
		_studio = null
		queue_free()


## Stands the model in the lens. Every transform is handed to the renderer
## directly: a node's own reaches it only when the frame's notifications flush,
## and the still is drawn before that.
func _pose(type_id: StringName, row: int, side: int) -> void:
	_model = UnitModels3D.build(type_id, SideIdentity.theme_for_row(row))
	_viewport.add_child(_model)
	var bounds := _bounds_of(_model)
	_lens.size = UnitStillShot3D.lens_height(bounds)
	_lens.look_at_from_position(UnitStillShot3D.eye(bounds), UnitStillShot3D.aim(bounds))
	RenderingServer.camera_set_transform(_lens.get_camera_rid(), _lens.global_transform)
	for shape: VisualInstance3D in _model.find_children("*", "VisualInstance3D", true, false):
		RenderingServer.instance_set_transform(shape.get_instance(), shape.global_transform)
	_viewport.size = Vector2i.ONE * side * UnitStillShot3D.SUPERSAMPLE


## The box round every part of `model`, a rotor included, in the model's space.
static func _bounds_of(model: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var box := part.transform * part.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds


## One still of the posed model, drawn now — `force_draw`, since a window the
## system has stopped drawing never draws its viewports — then filtered down to
## the slot's size. Null on a failed read, so the row keeps its tile.
func _shoot(side: int) -> Texture2D:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	RenderingServer.force_draw(false)
	var still := _viewport.get_texture().get_image()
	if still == null or still.is_empty():
		return null
	still.convert(Image.FORMAT_RGBA8)
	still.resize(side, side, Image.INTERPOLATE_LANCZOS)
	_unpremultiply(still)
	return ImageTexture.create_from_image(still)


## The viewport's clear is transparent black, so an edge pixel comes back with
## its colour scaled by its coverage; dividing it out keeps the silhouette's
## rim its own colour instead of a dark fringe.
static func _unpremultiply(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.0 and pixel.a < 1.0:
				pixel.r = minf(pixel.r / pixel.a, 1.0)
				pixel.g = minf(pixel.g / pixel.a, 1.0)
				pixel.b = minf(pixel.b / pixel.a, 1.0)
				image.set_pixel(x, y, pixel)


func _environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT
	env.ambient_light_energy = 0.35
	return env


## A warm key from above the lens's left and a cool fill from its right, so the
## flat-shaded facets read as a solid body at icon size.
func _add_lights() -> void:
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50.0, -40.0, 0.0)
	key.light_color = KEY_COLOUR
	key.light_energy = 0.8
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, 120.0, 0.0)
	fill.light_color = FILL_COLOUR
	fill.light_energy = 0.25
	_viewport.add_child(fill)
