class_name CutinStage3D
extends Node3D
## The set the 3D cut-ins are played on: its own lens, sky, lights and ground,
## stood far off the board in the same world, so it renders through the window's
## own viewport at full resolution — a SubViewport would be the 640x360 canvas,
## pixelated.
##
## A director dresses it per cut-in (`plot`, `squad`, `dress`), frames it every
## frame (`frame`), takes the lens with `enter` and hands it back to the board
## with `leave`; `clear` strips the last cut-in's dressing. It decides nothing:
## what stands on it and when is the director's, off its own clock.
##
## Built by `Board3D` on the first 3D cut-in and freed with it.

## Where the set stands: far enough off the board that neither lens can see
## the other's world past its far plane.
const ORIGIN := Vector3(0.0, 0.0, -400.0)
const FOV_DEG := 34.0
const FAR := 400.0
const KEY_COLOUR := Color("#fff0dc")
const FILL_COLOUR := Color("#b9cdf0")
const AMBIENT := Color("#c2d0e6")

## True while a 3D cut-in is playing, from its first frame to its last — the
## board holds `V`, `C` and `B` under it, as it does under a story scene.
var rolling := false
## True while the stage has the lens.
var on_air := false
var camera: Camera3D

var _board_lens: Camera3D
var _board_sun: DirectionalLight3D
var _hud: CanvasLayer
var _hud_was_visible := true
var _db: TerrainDB
var _materials: Array[Material] = []
var _dressing: Node3D


## `board_lens` gets the lens back on `leave`; the board's own sun is put out
## while the stage has the lens, which lights itself; `hud` goes off the screen
## with it. `ground` holds the board's land and water materials.
func setup(
	board_lens: Camera3D,
	board_sun: DirectionalLight3D,
	hud: CanvasLayer,
	db: TerrainDB,
	ground: Array[Material]
) -> void:
	_board_lens = board_lens
	_board_sun = board_sun
	_hud = hud
	_db = db
	_materials = ground
	name = "CutinStage3D"
	position = ORIGIN
	visible = false
	camera = Camera3D.new()
	camera.fov = FOV_DEG
	camera.near = 0.1
	camera.far = FAR
	camera.environment = _environment()
	add_child(camera)
	add_child(StageBackdrop3D.build())
	_add_lights()
	_dressing = Node3D.new()
	_dressing.name = "Dressing"
	add_child(_dressing)


## Takes the lens and the screen. Safe to call every frame.
func enter() -> void:
	if on_air:
		return
	on_air = true
	visible = true
	camera.current = true
	_board_sun.visible = false
	_hud_was_visible = _hud.visible
	_hud.visible = false


## Hands the lens and the screen back to the board. Safe to call every frame.
func leave() -> void:
	if not on_air:
		return
	on_air = false
	visible = false
	_board_sun.visible = true
	_hud.visible = _hud_was_visible
	_board_lens.current = true


## Frees everything the last cut-in stood on the stage.
func clear() -> void:
	for child in _dressing.get_children():
		_dressing.remove_child(child)
		child.queue_free()


## Stands one side's ground: `terrain` the cell's, `ground` what the squad
## stands on, `owner` a property's theme, `side` -1 left of the seam or +1 right.
func plot(
	terrain: TerrainType, ground: TerrainType, owner: CommanderVisuals.FactionTheme, side: int
) -> StagePlot3D:
	var built := StagePlot3D.new()
	_dressing.add_child(built)
	built.setup(terrain, ground, owner, _db, side, _materials)
	return built


## Stands a squad of `posted` figures of `type` on `on`, `standing` of which
## survive.
func squad(
	type: UnitType,
	theme: CommanderVisuals.FactionTheme,
	posted: int,
	standing: int,
	on: StagePlot3D
) -> StageSquad3D:
	var built := StageSquad3D.new()
	_dressing.add_child(built)
	built.setup(type, theme, posted, standing, on)
	return built


## Adds anything else a director stands on the stage for one cut-in (its
## effects), freed with the rest by `clear`.
func dress(node: Node3D) -> void:
	_dressing.add_child(node)


## Stands the lens at `eye` looking at `target`, both in the stage's frame.
func frame(eye: Vector3, target: Vector3) -> void:
	if eye.is_equal_approx(target):
		return
	camera.look_at_from_position(to_global(eye), to_global(target), Vector3.UP)


## A stage point on the screen, for a label pinned over it.
func screen_of(point: Vector3) -> Vector2:
	return camera.unproject_position(to_global(point))


## Whether a stage point is in front of the lens at all.
func sees(point: Vector3) -> bool:
	return not camera.is_position_behind(to_global(point))


func _environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = StageBackdrop3D.HORIZON
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT
	env.ambient_light_energy = 0.3
	env.fog_enabled = true
	env.fog_light_color = StageBackdrop3D.HORIZON
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.0
	return env


## A warm key from the lens's front left, casting, and a cool fill from behind
## the stage so the far side of a hull is not black.
func _add_lights() -> void:
	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.rotation_degrees = Vector3(-42.0, -32.0, 0.0)
	key.light_color = KEY_COLOUR
	key.light_energy = 0.78
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = Vector3(-28.0, 150.0, 0.0)
	fill.light_color = FILL_COLOUR
	fill.light_energy = 0.22
	add_child(fill)
