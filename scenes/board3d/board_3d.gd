class_name Board3D
extends Node3D
## The battle drawn in three dimensions: a second board over the same match,
## flipped with the flat one by V or the view chip over End Turn.
##
## It is a view of the 2D board, never of the sim. The flat board keeps drawing
## underneath — taken off the screen by the window's canvas cull mask, not
## stopped — so every rule it follows reaches this board as a result to copy:
## terrain from MapData, built once; a property's owner off TerrainLayer's atlas
## row, which already holds the fog's last-seen owner; units off their sprites
## (UnitMirror3D), so every walk, lunge, fade and scripted beat plays here too;
## fog off FogLayer's painted cells; and the flat marks — ranges, the path arrow,
## pips, flashes, callouts — rendered from above into a texture the ground wears.
## Nothing here asks a rule question and nothing here writes back.
##
## Built on first use, so a player who never flips pays nothing for it.

## Canvas visibility bits. The Battle node draws on BOARD_ROOT, so dropping that
## bit from the window's cull mask takes the whole flat board off the screen and
## leaves the HUD's CanvasLayers alone. The layers this board replaces draw on
## SOLID alone, which keeps them out of the overlay texture while the flat marks,
## still on the default bit, go in.
const BOARD_ROOT := 2
const SOLID := 8
const DEFAULT_BIT := 1
## The overlay texture's resolution, capped so a four-army board stays inside
## what a phone's GPU will allocate.
const OVERLAY_PX_PER_CELL := 48
const OVERLAY_MAX_PX := 2048
const TERRAIN_SHADER := preload("res://scenes/board3d/terrain_3d.gdshader")
const BACKGROUND := Color("#1a2130")
const TABLE := Color("#262d3b")

## Nobody's buildings wear bare stone rather than the neutral grey, which sat a
## step off Iron's charcoal at full zoom-out: an owned roof is an army's colour,
## an unowned one plainly none.
static var _unclaimed := CommanderVisuals.FactionTheme.new(
	&"unclaimed", "", Color("#b7b3a9"), Color("#918d84"), Color("#d2cec5"), Color.BLACK
)

var active := false

var _view: BattleView
var _map: MapData
var _built := false
var _camera: BoardCamera3D
var _environment: WorldEnvironment
var _units: UnitMirror3D
var _cursor: BoardCursor3D
var _overlay: SubViewport
var _fog_image: Image
var _fog_texture: ImageTexture
var _fog_dirty := true
var _owners_dirty := true
var _prop_material: ShaderMaterial
var _cinema: DialogueCinema3D
var _sun: DirectionalLight3D
var _stage: CutinStage3D
var _combat: CombatCutin3D
var _capture: CaptureCutin3D
var _properties: Dictionary[Vector2i, Node3D] = {}
var _property_rows: Dictionary[Vector2i, int] = {}
var _clock := 0.0


## Hangs a board on the battle scene that owns `view`'s nodes and stands it up
## in whichever view the player last chose.
static func install(view: BattleView, host: Node2D) -> Board3D:
	var board := Board3D.new()
	board.name = "Board3D"
	host.add_child(board)
	board.setup(view)
	return board


func setup(view: BattleView) -> void:
	_view = view
	_map = view.map
	var host := get_parent() as CanvasItem
	host.visibility_layer = BOARD_ROOT
	for solid: CanvasItem in [
		view.backdrop_layer,
		view.ground_layer,
		view.terrain_layer,
		view.fog_layer,
		view.units_root,
		view.cursor,
	]:
		solid.visibility_layer = SOLID
	view.fog_repainted.connect(_mark_fog)
	view.terrain_layer.changed.connect(_mark_owners)
	Settings.board_view_changed.connect(_on_view_changed)
	set_process(false)
	visible = false
	_on_view_changed()


## The window outlives the battle, so leaving one with the 3D board up must not
## leave the next scene drawn with BOARD_ROOT culled.
func _exit_tree() -> void:
	get_viewport().canvas_cull_mask |= BOARD_ROOT


## V flips the board from anywhere in the battle — a watched match, a paused one,
## the computer's turn — and C and B turn the 3D one a quarter each way. Under a
## cinematic all three hold still: it has the lens, and the flat board has no
## cinematic to hand the scene to.
func _unhandled_input(event: InputEvent) -> void:
	var view_key := (
		event.is_action_pressed(&"toggle_view")
		or event.is_action_pressed(&"turn_view_left")
		or event.is_action_pressed(&"turn_view_right")
	)
	if view_key and (_cinema != null and _cinema.rolling or _stage != null and _stage.rolling):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"toggle_view"):
		Settings.set_board_3d(not Settings.board_3d)
	elif active and event.is_action_pressed(&"turn_view_left"):
		_camera.turn(-1)
	elif active and event.is_action_pressed(&"turn_view_right"):
		_camera.turn(1)
	else:
		return
	get_viewport().set_input_as_handled()


## A screen direction as a board step: up always walks away from the camera, so
## the arrow keys keep their sense whichever side of the board is being looked
## from. The identity on the flat board.
func turned(direction: Vector2i) -> Vector2i:
	if not active:
		return direction
	return BoardSpace3D.turned(direction, _camera.quarters)


## The cinematic dialogue is played in, built with the board. Asked only while
## the board is up.
func cinema() -> DialogueCinema3D:
	return _cinema


## The set the 3D cut-ins are played on, built on the first one. Asked only
## while the board is up.
func cutin_stage() -> CutinStage3D:
	if _stage == null:
		_stage = CutinStage3D.new()
		add_child(_stage)
		var ground: Array[Material] = [ground_material(false, null, null, Vector2.ONE)]
		_stage.setup(_camera.camera, _sun, _hud_layer(), _view.db, ground)
	return _stage


## The combat cut-in played on the stage, built on the first one.
func combat_cut_in() -> CombatCutin3D:
	if _combat == null:
		_combat = CombatCutin3D.new()
		_combat.name = "CombatCutin3D"
		_combat.view = _view
		_combat.stage = cutin_stage()
		add_child(_combat)
	return _combat


## The capture cut-in played on the stage, built on the first one.
func capture_cut_in() -> CaptureCutin3D:
	if _capture == null:
		_capture = CaptureCutin3D.new()
		_capture.name = "CaptureCutin3D"
		_capture.view = _view
		_capture.stage = cutin_stage()
		add_child(_capture)
	return _capture


## Whether a press went to the cinematic playing now — the one route a press
## reaches it by, ahead of every blocking card.
func consume_cinema_press(event: InputEvent) -> bool:
	return _cinema != null and _cinema.consume_press(event)


## The cell under a screen point, walked down the ray from the camera until it
## meets a cell's surface — so a click on a mountain's shoulder picks the
## mountain, not the plain behind it. May be off the board; the caller checks.
func pick(screen: Vector2) -> Vector2i:
	var lens := _camera.camera
	var from := lens.project_ray_origin(screen)
	var along := lens.project_ray_normal(screen)
	if along.y > -0.01:
		return Vector2i(-1, -1)
	var high := BoardSpace3D.PICK_CEILING + 0.02
	var low := BoardSpace3D.SEA_TOP - 0.02
	var t := (high - from.y) / along.y
	var t_end := (low - from.y) / along.y
	while t <= t_end:
		var point := from + along * t
		var cell := BoardSpace3D.cell_at(Vector2(point.x, point.z))
		if point.y <= BoardSpace3D.pick_top(_map, cell):
			return cell
		t += 0.02
	var floor_point := from + along * t_end
	return BoardSpace3D.cell_at(Vector2(floor_point.x, floor_point.z))


## Where a cell's top-right corner lands on screen, in the terms
## `BoardCamera.screen_pos_for_cell` answers the flat board in, so a menu or a
## callout opens beside the cell it is about. Asked of where the camera is
## heading, not where it is mid-glide.
func screen_of(cell: Vector2i) -> Vector2:
	var lens := _resting_probe()
	var corner := _surface(cell) + lens.global_basis.x * 0.5 + Vector3.UP * 0.35
	return lens.unproject_position(corner) + Vector2(6, 0)


## Where a cell's middle lands on screen, as the camera will come to rest.
func screen_of_centre(cell: Vector2i) -> Vector2:
	return _resting_probe().unproject_position(_surface(cell))


## The screen rect a cell's top covers as the camera will come to rest, so an
## overlay can step aside of it the way it does of a flat-board cell.
func screen_rect_of(cell: Vector2i) -> Rect2:
	_resting_probe()
	return _camera.screen_rect_of(cell, BoardSpace3D.pick_top(_map, cell))


## The probe re-posed on the cursor now: a menu often opens the same frame the
## cursor jumped (a tap on a base, a scripted confirm), before `_process` has
## moved the probe after it.
func _resting_probe() -> Camera3D:
	_frame_lens()
	_camera.pose_probe(_focus(), _view.camera.zoom.x)
	return _camera.probe


## Tells the camera where it frames the board: the band the HUD bars leave, cut
## below the tutorial strip while it shows, and whether the rung is the floor
## that shows all of the board. The strip's own `visible`, not its tree's: a
## cut-in or a story scene hides the whole HUD layer, and the board behind it
## must not re-frame and glide back when the layer returns.
func _frame_lens() -> void:
	var band := MobileDock.board_band(get_viewport().get_visible_rect().size)
	var strip := _view.mission_strip
	if strip != null and strip.visible:
		var below := strip.get_global_rect().end.y
		band = Rect2(band.position.x, below, band.size.x, band.end.y - below)
	_camera.band = band
	_camera.whole = _view.camera.zoom.x <= _view.board_camera.min_zoom() + 0.001


func _on_view_changed() -> void:
	var on := Settings.board_3d
	if on and not _built:
		_build()
		_warm_cut_ins.call_deferred()
	active = on
	visible = on
	set_process(on)
	var window := get_viewport()
	if on:
		window.canvas_cull_mask &= ~BOARD_ROOT
	else:
		window.canvas_cull_mask |= BOARD_ROOT
	if not _built:
		return
	if not on:
		_cinema.cut()
		if _stage != null:
			_stage.leave()
	_camera.camera.current = on
	_environment.environment = _make_environment() if on else null
	_overlay.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	)
	if on:
		_frame_lens()
		_camera.snap(_focus(), _view.camera.zoom.x)
		_cursor.snap(_focus())


func _process(delta: float) -> void:
	_clock += delta
	if _fog_dirty:
		_fog_dirty = false
		_refresh_fog()
	if _owners_dirty:
		_owners_dirty = false
		_refresh_owners()
	var focus := _focus()
	if _cinema.rolling:
		_cinema.advance(delta)
	if not _cinema.directs_lens():
		_frame_lens()
		_camera.follow(delta, focus, _view.camera.zoom.x, _view.board_camera.shake_offset)
	_units.sync(delta, _camera.camera.global_basis)
	_cursor.visible = _view.cursor.visible and not _cinema.rolling and not _stage_on_air()
	_cursor.follow(delta, focus, _clock)


func _stage_on_air() -> bool:
	return _stage != null and _stage.on_air


func _focus() -> Vector3:
	var plane := BoardSpace3D.plane_of(_view.cursor.position)
	return Vector3(plane.x, BoardSpace3D.stand_at(_map, plane), plane.y)


func _surface(cell: Vector2i) -> Vector3:
	var centre := BoardSpace3D.cell_centre(cell)
	return Vector3(centre.x, BoardSpace3D.pick_top(_map, cell), centre.y)


func _mark_fog() -> void:
	_fog_dirty = true


func _mark_owners() -> void:
	_owners_dirty = true


# --- building the board ------------------------------------------------------


## Deferred past the frame that built the board, so the whole scene is in place
## and a flip straight back to 2D has had its say. A capture poses its own cut-in
## on the stage, which the stand-ins would draw over, so it goes without; so does
## a player with battle animations off, who would pay the stalls for nothing.
func _warm_cut_ins() -> void:
	if active and Settings.battle_animations and not BattleScenarioDriver.requested():
		CutinWarmup3D.run(self, _view)


func _build() -> void:
	_built = true
	_build_overlay()
	_fog_image = Image.create_empty(_map.width, _map.height, false, Image.FORMAT_L8)
	_fog_texture = ImageTexture.create_from_image(_fog_image)
	var meshes := TerrainMesher3D.build(_map)
	_add_mesh(meshes[0], _terrain_material(false))
	if meshes[1] != null:
		_add_mesh(meshes[1], _terrain_material(true))
	_prop_material = _terrain_material(false)
	_add_table()
	_units = UnitMirror3D.new()
	_units.map = _map
	_units.sprites_root = _view.units_root
	add_child(_units)
	_cursor = BoardCursor3D.new()
	add_child(_cursor)
	var lens := Camera3D.new()
	var probe := Camera3D.new()
	add_child(lens)
	add_child(probe)
	_camera = BoardCamera3D.new(lens, probe)
	_camera.bounds = Rect2(Vector2.ZERO, Vector2(_map.size()))
	_add_sun()
	_environment = WorldEnvironment.new()
	add_child(_environment)
	_cinema = DialogueCinema3D.new()
	_cinema.name = "DialogueCinema3D"
	# The layer the HUD's bars are drawn on: a cinematic takes the chrome off the
	# screen along with them.
	_cinema.setup(_camera, _map, _hud_layer())
	add_child(_cinema)


## The flat marks, rendered from straight above into a texture one board-cell
## per OVERLAY_PX_PER_CELL. It shares the window's 2D world, so it draws the very
## nodes the flat board draws, and its cull mask admits the Battle node and the
## default bit while turning away everything on SOLID.
func _build_overlay() -> void:
	var px := mini(OVERLAY_PX_PER_CELL, OVERLAY_MAX_PX / maxi(_map.width, _map.height))
	_overlay = SubViewport.new()
	_overlay.size = _map.size() * px
	_overlay.transparent_bg = true
	_overlay.disable_3d = true
	_overlay.canvas_cull_mask = DEFAULT_BIT | BOARD_ROOT
	# In the tree before the world is shared: a canvas transform is set on the
	# canvas the viewport is attached to, and it attaches on entering.
	add_child(_overlay)
	_overlay.world_2d = get_viewport().world_2d
	_overlay.canvas_transform = Transform2D.IDENTITY.scaled(
		Vector2.ONE * float(px) / BoardSpace3D.PX_PER_CELL
	)


## The HUD's bars' layer: a cinematic or a cut-in on the stage takes the chrome
## off the screen along with them.
func _hud_layer() -> CanvasLayer:
	return _view.hud_top.get_parent() as CanvasLayer


func _terrain_material(water: bool) -> ShaderMaterial:
	return ground_material(water, _overlay.get_texture(), _fog_texture, Vector2(_map.size()))


## The ground's material: the mesh's own colours, with `overlay`'s flat marks
## and `fog`'s cells laid over the `cells` of a board. The cut-in stage wears it
## with neither, so its ground is the board's ground and nothing on it.
static func ground_material(
	water: bool, overlay: Texture2D, fog: Texture2D, cells: Vector2
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	material.set_shader_parameter(&"overlay", overlay)
	material.set_shader_parameter(&"fog_cells", fog)
	material.set_shader_parameter(&"map_cells", cells)
	material.set_shader_parameter(&"overlay_strength", 1.0 if overlay != null else 0.0)
	material.set_shader_parameter(&"water", water)
	return material


func _add_mesh(mesh: ArrayMesh, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	add_child(instance)


## A dark table the diorama stands on, far enough out to fill any view.
func _add_table() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	var table := MeshInstance3D.new()
	table.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = TABLE
	material.roughness = 1.0
	table.material_override = material
	table.position = Vector3(_map.width / 2.0, BoardSpace3D.SLAB_BOTTOM - 0.01, _map.height / 2.0)
	add_child(table)


func _add_sun() -> void:
	var sun := DirectionalLight3D.new()
	_sun = sun
	# Low from the west-north-west, so a shadow falls to the right of what casts
	# it — beside it on screen, where a sun behind the camera would hide it.
	sun.rotation_degrees = Vector3(-48, -115, 0)
	sun.light_color = Color("#fff6ea")
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	add_child(sun)


func _make_environment() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#c3cfe6")
	env.ambient_light_energy = 0.35
	return env


# --- what changes while it is played -----------------------------------------


func _refresh_fog() -> void:
	_fog_image.fill(Color.BLACK)
	for cell in _view.fog_layer.get_used_cells():
		if _map.in_bounds(cell):
			_fog_image.set_pixelv(cell, Color.WHITE)
	_fog_texture.update(_fog_image)


## Rebuilds each property whose paint changed on the flat board: a capture, a
## fog-deferred flip landing, a scripted defection. The row is the flat board's
## answer, so a capture made out of sight keeps its last-seen colours here too.
func _refresh_owners() -> void:
	for cell in _map.property_cells():
		var row := _view.terrain_layer.get_cell_atlas_coords(cell).y
		if _property_rows.get(cell, -2) == row:
			continue
		_property_rows[cell] = row
		if _properties.has(cell):
			_properties[cell].queue_free()
		var theme := (
			_unclaimed if row == SideIdentity.NEUTRAL_ROW else SideIdentity.theme_for_row(row)
		)
		var building := PropertyModels3D.build(_map.terrain_at(cell).id, theme)
		_dress(building)
		var centre := BoardSpace3D.cell_centre(cell)
		building.position = Vector3(centre.x, BoardSpace3D.LAND_TOP, centre.y)
		add_child(building)
		_properties[cell] = building


## Puts a building on the ground's own material, so the fog darkens it and a
## range laid over its cell reads on its roof.
func _dress(node: Node) -> void:
	var geometry := node as GeometryInstance3D
	if geometry != null:
		geometry.material_override = _prop_material
	for child in node.get_children():
		_dress(child)
