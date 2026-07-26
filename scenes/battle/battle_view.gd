class_name BattleView
extends RefCounted
## Draws battle state: terrain, unit sprites, movement and attack overlays,
## fog, the two docked HUD bars, and the damage forecast.
##
## The HUD is chrome outside the map, not slabs on top of it: a fixed-height bar
## above the board and one below, with the board's viewport computed from what
## they leave over. Only transient, self-dismissing things — the forecast, the
## action menu, the banners — are still drawn over terrain.
##
## Reads simulation state to present it and never mutates it — no commands, no
## rules, no turn flow. Battle owns the flow and tells the view what to draw.
## The view never calls back into Battle, so the dependency runs one way and a
## renderer can never quietly become a second rules engine.
##
## Fog is enforced here rather than in the sim, which stays permissive:
## `Vision` decides what a team can see, and the view refuses to draw the rest.
## Battle picks *whose* eyes to use and passes the team in.
##
## Battle assigns the node fields and then calls `setup`; the view is
## constructed with no arguments so it never holds a reference to Battle.

const TILE := 16
## Terrain atlas cells are 4x the world grid so the PixVoxel property buildings
## keep their detail; TerrainLayer is scaled down to compensate.
const TERRAIN_PX := 64
const ATLAS_PATH := "res://assets/tiles/terrain_atlas.png"
const OVERLAY_PATH := "res://assets/tiles/overlay.png"
const ATLAS_SOURCE_ID := 0

const UNIT_SPRITE_SCENE := preload("res://scenes/battle/unit_sprite.tscn")

var terrain_layer: TileMapLayer
## Painted beyond the map edges — a darkened continuation of the board that
## fills the screen when the camera is far enough out to show the whole map.
var backdrop_layer: TileMapLayer
var move_overlay: TileMapLayer
var attack_overlay: TileMapLayer
var fog_layer: TileMapLayer
var path_line: Line2D
var units_root: Node2D
var cursor: Sprite2D
var camera: Camera2D
## The docked bar below the board: the commander in hand, the unit under the
## cursor, the tile it stands on. Replaces the floating chip and corner panel.
var hud_bottom: HudBottomBar
var damage_preview: PanelContainer
var atk_label: Label
var counter_label: Label
## The forecast's third line: the target's HP before and after, the luck-free
## attack percentage as secondary detail, and the note that luck can move where
## inside the span it lands.
var outcome_label: Label
## The docked bar above the board: day, side, doctrine, funds.
var hud_top: HudTopBar

## The transient jitter the animator lays over the board's docking shift. Set —
## and tweened — by BattleAnimator.shake_camera rather than written to the
## camera, so the two can never be the same property's second owner; see
## `_apply_board_offset`, which composes both and is the only writer.
var shake_offset := Vector2.ZERO:
	set(value):
		shake_offset = value
		if camera != null:
			_apply_board_offset()

var db: TerrainDB
var map: MapData
var game: GameState
## Who each side is and what it wears — resolved once at match setup from the
## commander picks (SideIdentity). Every team-to-paint and team-to-name answer
## the board draws comes from here; the sim keeps its team ints. Battle builds it
## and assigns it, like everything else the view draws with.
var identity: SideIdentity
## Teams the computer plays. The view only needs them to know whose controls it
## must not offer; Battle owns the list and hands it over, as with everything.
var ai_teams: Array[int] = []

var _sprites: Dictionary = {}  # Unit -> UnitSprite
## Cells the viewing team can see; refreshed by `refresh_fog` after commits.
var _visible_cells: Dictionary = {}
## Whose eyes the board is drawn from; set by the same pass. Starts on the
## opening team, which is who is looking before the first fog refresh runs.
var _viewing_team: int = GameState.TEAMS[0]
## True while a hot-seat handoff blacks the board out for everyone; set by the
## same pass, and the one case where even your own units are hidden.
var _blacked_out := false


## Builds the tile sets from data and paints the opening board. Call once, after
## the node fields and `db`/`map`/`game` are set.
func setup() -> void:
	hud_bottom.identity = identity  # the bar names and tints sides through the same resolver
	terrain_layer.tile_set = _build_tile_set()
	# The terrain atlas is drawn at 4x the world grid (see TERRAIN_PX), so the
	# layer is scaled back down to keep one cell = TILE. Overlays and the cursor
	# stay at 1x and are unaffected.
	terrain_layer.scale = Vector2.ONE * (float(TILE) / float(TERRAIN_PX))
	backdrop_layer.tile_set = terrain_layer.tile_set
	backdrop_layer.scale = terrain_layer.scale
	move_overlay.tile_set = _build_overlay_tile_set()
	attack_overlay.tile_set = move_overlay.tile_set
	fog_layer.tile_set = _build_fog_tile_set()
	_paint_map()
	_paint_backdrop()
	_spawn_unit_sprites()
	_apply_camera_limits()


static func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell * TILE) + Vector2(TILE, TILE) / 2.0


# --- terrain -----------------------------------------------------------------


## The TileSet is derived from TerrainDB at runtime: one atlas column per
## terrain, team-colored rows for properties. No hand-maintained .tres TileSet.
func _build_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TERRAIN_PX, TERRAIN_PX)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load(ATLAS_PATH)
	atlas.texture_region_size = Vector2i(TERRAIN_PX, TERRAIN_PX)
	for terrain in db.all():
		atlas.create_tile(Vector2i(terrain.atlas_col, 0))
		if terrain.team_tinted:
			# Rows 1-4, one per faction — a property can be owned by any side, and
			# which faction row that side draws in is the resolver's call, not the
			# owner int. The atlas carries all four (FI1); this registers them.
			for row in range(1, SideIdentity.FACTION_ROWS + 1):
				atlas.create_tile(Vector2i(terrain.atlas_col, row))
	tile_set.add_source(atlas, ATLAS_SOURCE_ID)
	return tile_set


func _build_overlay_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load(OVERLAY_PATH)
	atlas.texture_region_size = Vector2i(TILE, TILE)
	atlas.create_tile(Vector2i.ZERO)
	tile_set.add_source(atlas, ATLAS_SOURCE_ID)
	return tile_set


## The fog gets its own tile rather than sharing the move/attack overlay's.
## `overlay.png` carries a brighter one-pixel border, which is what rings a single
## range cell — but painted across a whole fogged region that border becomes a
## grid of dark outlines around every cell, and the shroud reads as a field of
## hard-edged boxes instead of one drawn-down curtain. A flat, seam-free cell
## closes the region up; its colour and depth stay the FogLayer's modulate.
func _build_fog_tile_set() -> TileSet:
	var image := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(image)
	atlas.texture_region_size = Vector2i(TILE, TILE)
	atlas.create_tile(Vector2i.ZERO)
	tile_set.add_source(atlas, ATLAS_SOURCE_ID)
	return tile_set


func _paint_map() -> void:
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var terrain := map.terrain_at(cell)
			var row := identity.atlas_row(game.owner_at(cell)) if terrain.team_tinted else 0
			terrain_layer.set_cell(cell, ATLAS_SOURCE_ID, Vector2i(terrain.atlas_col, row))


## Fills a ring of cells beyond the map edges so that when the whole map is in
## view (see min_zoom) the rest of the screen reads as darkened out-of-bounds
## ground, not engine-clear void. Each cell extends its nearest edge terrain;
## properties fall back to plains so no building appears to stand off the board.
## The ring is sized to the most min_zoom can expose, and the darkening is the
## layer's modulate in the scene — the tiles themselves are the terrain atlas.
func _paint_backdrop() -> void:
	var plains := db.by_id(&"plains")
	var map_px := Vector2(map.size() * TILE)
	var exposed := _viewport_size() / min_zoom()
	var margin := Vector2i(
		ceili(maxf(0.0, (exposed.x - map_px.x) / 2.0) / TILE) + 1,
		ceili(maxf(0.0, (exposed.y - map_px.y) / 2.0) / TILE) + 1
	)
	for y in range(-margin.y, map.height + margin.y):
		for x in range(-margin.x, map.width + margin.x):
			if x >= 0 and x < map.width and y >= 0 and y < map.height:
				continue
			var src := Vector2i(clampi(x, 0, map.width - 1), clampi(y, 0, map.height - 1))
			var terrain := map.terrain_at(src)
			if terrain.team_tinted:
				terrain = plains
			backdrop_layer.set_cell(Vector2i(x, y), ATLAS_SOURCE_ID, Vector2i(terrain.atlas_col, 0))


## Recolors one property to its current owner, after a capture — but only for a
## cell the viewer can currently see. A capture inside the viewer's fog must not
## paint through the translucent fog layer (it would leak enemy expansion and
## income), so a hidden cell keeps its last-seen colour and the repaint is
## deferred to `refresh_fog`, which lands it the moment the viewer's vision
## reaches the cell.
func repaint_property(cell: Vector2i) -> void:
	if not _can_see_cell(cell):
		return
	var terrain := map.terrain_at(cell)
	if terrain.team_tinted:
		terrain_layer.set_cell(
			cell,
			ATLAS_SOURCE_ID,
			Vector2i(terrain.atlas_col, identity.atlas_row(game.owner_at(cell)))
		)


# --- unit sprites ------------------------------------------------------------


func _spawn_unit_sprites() -> void:
	for unit in game.units:
		spawn_sprite_for(unit)


func spawn_sprite_for(unit: Unit) -> void:
	var sprite: UnitSprite = UNIT_SPRITE_SCENE.instantiate()
	units_root.add_child(sprite)
	sprite.fogged = _is_fogged(unit)
	sprite.setup(unit, game.current_team, identity.atlas_row(unit.team))
	_sprites[unit] = sprite


func sprite_for(unit: Unit) -> UnitSprite:
	return _sprites.get(unit)


## Brings one sprite back in step with the sim, fog included: the answer is
## written onto the sprite, which then draws itself from it.
##
## Deciding it here and storing it there is what makes it stick. A sprite that
## worked visibility out for itself would un-hide a fogged enemy every time
## anything redrew it — and `UnitSprite` redraws on three different calls — so
## the decision is made in one place and remembered rather than re-derived.
func refresh_sprite(unit: Unit) -> void:
	var sprite: UnitSprite = _sprites.get(unit)
	if sprite == null:
		return
	sprite.fogged = _is_fogged(unit)
	sprite.refresh()


## Whether the board currently hides `unit` from whoever is looking. Vision owns
## the rule; the blackout is the view's own, since a hot-seat handoff hides even
## your own units.
func _is_fogged(unit: Unit) -> bool:
	return _blacked_out or not can_see_unit(unit)


## Hands the sprite over and stops tracking the unit, for callers that animate
## a departure themselves (a merged-away twin, a unit dying in combat). The
## caller owns the returned sprite from here on.
func release_sprite(unit: Unit) -> UnitSprite:
	var sprite: UnitSprite = _sprites.get(unit)
	_sprites.erase(unit)
	return sprite


## Re-tints every sprite for the team about to play. Safe to call outside a fog
## pass: setting the team redraws the sprite, and a redraw keeps whatever
## `refresh_sprite` last decided about seeing it.
func set_active_team(team: int) -> void:
	for unit in game.units:
		_sprites[unit].set_active_team(team)


## Brings every sprite back in step with the sim in one pass, for the changes
## that touch more of the board than a caller can name unit by unit.
##
## Two of those. A death can take units the combat result never mentions —
## cargo goes down with its transport — so any sprite whose unit has left
## `game.units` is freed. And a Command Power can heal or refuel a whole side at
## once, so every surviving sprite is redrawn rather than just the one that
## acted. Survivors go through `refresh_sprite`, so the pass re-applies fog
## instead of leaking whatever the last fog pass hid.
func sync_sprites() -> void:
	for unit: Unit in _sprites.keys():
		if unit in game.units:
			refresh_sprite(unit)
			continue
		var sprite: UnitSprite = _sprites[unit]
		_sprites.erase(unit)
		sprite.queue_free()


## Re-resolves the match's [SideIdentity] from the sim's current commander picks
## and repaints everything that wears a side's colour — the property tiles, every
## unit sprite, and both HUD bars.
##
## Call this when the commanders changed behind the scene's back, which in
## practice means a dev scenario staging a commander onto an already-built board:
## a staged commander then recolours its army the way it would in a real match
## (plan R3). Real play never needs it — commanders are fixed before the board is
## ever drawn, so `_build_view`'s resolve is the only one.
func restage_identity() -> void:
	identity = SideIdentity.for_game(game)
	hud_bottom.identity = identity
	_paint_map()
	for unit: Unit in _sprites:
		var sprite: UnitSprite = _sprites[unit]
		sprite.fogged = _is_fogged(unit)
		sprite.setup(unit, game.current_team, identity.atlas_row(unit.team))
	refresh_hud()
	# The tile card names the side that owns the hovered property, so a restage has
	# to redraw it too. It used to be able to skip this: the old corner panel was
	# only up while the cursor was moving, and the next move refreshed it. A docked
	# bar is always up, and a stale one sits there naming the previous side beside
	# a top bar already naming the new one.
	refresh_panel(_cursor_cell())


# --- overlays ----------------------------------------------------------------


## Highlights reachable cells — a unit's movement range, or where a transport
## could unload. An empty list clears the overlay, so callers never need a
## separate "and now hide it" call.
func paint_move_overlay(cells: Array[Vector2i]) -> void:
	move_overlay.clear()
	for cell in cells:
		move_overlay.set_cell(cell, ATLAS_SOURCE_ID, Vector2i.ZERO)


## Highlights the cells a unit may fire at. Empty clears, as above.
func paint_attack_overlay(cells: Array[Vector2i]) -> void:
	attack_overlay.clear()
	for cell in cells:
		attack_overlay.set_cell(cell, ATLAS_SOURCE_ID, Vector2i.ZERO)


## Traces the planned route. A path too short to draw clears the line.
func update_path_line(path: Array[Vector2i]) -> void:
	path_line.clear_points()
	if path.size() < 2:
		return
	for cell in path:
		path_line.add_point(cell_center(cell))


# --- fog ---------------------------------------------------------------------


## Recomputes visibility and repaints the fog layer plus unit visibility.
## Called after every committed action and turn change (not per cursor move).
## With fog off the layer stays clear and nothing is ever hidden; when
## `blacked_out` (a hot-seat handoff) nobody may look and the board is hidden
## entirely.
##
## Only the *cells* are worked out here. Each sprite is then redrawn through
## `refresh_sprite`, which is where hiding a unit is decided — for this pass and
## for every other one.
func refresh_fog(viewing_team: int, blacked_out: bool) -> void:
	fog_layer.clear()
	_viewing_team = viewing_team
	_blacked_out = blacked_out
	_visible_cells = {}
	if game.fog_enabled:
		if not blacked_out:
			_visible_cells = Vision.visible_cells(game, viewing_team)
		for y in map.height:
			for x in map.width:
				var cell := Vector2i(x, y)
				if _visible_cells.has(cell):
					# In view: show the true owner. A capture the gate in
					# repaint_property deferred while the cell was fogged reveals
					# here, so the board never leaks an ownership change the viewer
					# has not scouted, yet shows the truth the instant it is seen.
					repaint_property(cell)
				else:
					fog_layer.set_cell(cell, ATLAS_SOURCE_ID, Vector2i.ZERO)
	for unit in game.units:
		refresh_sprite(unit)


## Whether the viewing team can see a unit — the question to ask before drawing
## or targeting one. Deliberately not "can it see that cell": a doctrine can hide
## a unit standing somewhere the viewer sees perfectly well, so the two came
## apart. Vision owns the rule, as it owns every other one; this only supplies
## the cells already computed for the fog pass.
func can_see_unit(unit: Unit) -> bool:
	return Vision.can_see_unit(game, _viewing_team, unit, _visible_cells)


## The unit on `cell` the viewing team can actually see, or null when the tile
## reads empty to them — a fogged enemy included. The panel and the menu-opening
## decisions ask this instead of `game.unit_at` so a hidden occupant can't change
## what a click offers and turn an apparently-empty cell into a free fog probe.
## The sim stays the authority on what lands there: a build onto a secretly
## occupied cell is still refused by BuildCommand.validate.
func _visible_unit_at(cell: Vector2i) -> Unit:
	var unit := game.unit_at(cell)
	if unit != null and not can_see_unit(unit):
		return null
	return unit


## Adjacent cells where `transport` (previewed at `dest`) could set `passenger`
## down: the transport must be somewhere it can unload from, the passenger must be
## able to stand on the cell, and the cell must hold no friendly and no visible
## enemy. The vacated origin counts as free, and a hidden enemy is left to foil the
## drop on apply rather than shown here, which would reveal it. A per-passenger
## query because a Lander's two riders need not share a move class. Underscored
## for the same reason as `_can_see_cell` below: Battle is the only caller and
## the view is at its public-method ceiling.
func _drop_cells(transport: Unit, dest: Vector2i, passenger: Unit) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if passenger == null or not transport.type.can_unload_from(map.terrain_at(dest).id):
		return cells
	for dir in MovementResolver.DIRECTIONS:
		var cell := dest + dir
		var terrain := map.terrain_at(cell)
		if terrain == null or not terrain.is_passable(passenger.type.move_class):
			continue
		var occupant := game.unit_at(cell)
		if occupant != null and occupant != transport and can_see_unit(occupant):
			continue
		cells.append(cell)
	return cells


## The transport's cargo that has at least one legal drop cell from `dest`, in load
## order. Empty when nothing aboard can step off here — which is how Battle knows
## whether to offer a Drop, and per passenger so each gets its own menu row.
## Underscored with its sibling above; Battle is the only caller.
func _droppable_passengers(transport: Unit, dest: Vector2i) -> Array[Unit]:
	var droppable: Array[Unit] = []
	for passenger in game.cargo_of(transport):
		if not _drop_cells(transport, dest, passenger).is_empty():
			droppable.append(passenger)
	return droppable


## Whether the viewing team may see activity on `cell` — the single authority in
## the view for cell-scoped visibility, as `can_see_unit` is for a unit. Ask it
## before disclosing anything a hidden unit could be doing on the tile, such as a
## capture in progress or (later) a fresh owner. With fog off every cell is
## visible; during a hot-seat blackout none is; otherwise it is whatever the last
## fog pass computed. Kept distinct from `can_see_unit` because a cell can be
## visible while a doctrine hides the unit standing on it, and vice versa.
## Underscored because it is the view's own; BattleAiRunner reaches in for it the
## same way it reaches into Battle's private flow, so as not to add a 21st public
## method here. It is still the one place the answer is computed — re-derive it
## nowhere else.
func _can_see_cell(cell: Vector2i) -> bool:
	if not game.fog_enabled:
		return true
	if _blacked_out:
		return false
	return _visible_cells.has(cell)


## The owner the board tile at `cell` is currently painted for, recovered from its
## atlas row. For a cell in view this equals the live owner (the fog pass just
## repainted it); for a fogged cell it is the viewer's last-seen owner. The
## bar's tile card reads this instead of live truth on a hidden cell so its owner
## label names the same side the tile shows — never outing a capture out of sight.
func _last_seen_owner(cell: Vector2i) -> int:
	var row: int = terrain_layer.get_cell_atlas_coords(cell).y
	for team in GameState.TEAMS:
		if identity.atlas_row(team) == row:
			return team
	return MapData.NEUTRAL


# --- HUD and panels ----------------------------------------------------------


func refresh_hud() -> void:
	var team := game.current_team
	var commander := game.commander_state(team).type
	# The doctrine — the always-on passive — is the top bar's line, and the power
	# name belongs beside the meter it charges. The shipped HUD printed the power
	# name in the doctrine's place, which read as a passive the side did not have.
	hud_top.show_turn(
		game.day,
		identity.theme(team),
		identity.display_name(team),
		commander.doctrine_text,
		game.funds[team]
	)
	# The commander block belongs to whoever's turn it is. It drops its meter for a
	# side with no power, and greys its Fire button for a computer commander — a
	# charged AI still fills the meter, but the click would be refused. The theme is
	# the side's resolved one rather than the commander's own, so a mirror match
	# wears the same borrowed colour here that its army wears on the board.
	hud_bottom.show_commander(game.commander_state(team), team in ai_teams, identity.theme(team))


func refresh_panel(cell: Vector2i) -> void:
	var hovered := _visible_unit_at(cell)  # hidden enemies stay hidden in the panel too
	var carrying := ""
	if hovered != null:
		var cargo := game.cargo_of(hovered)
		if not cargo.is_empty():
			carrying = cargo[0].type.display_name
	# A capture in progress belongs to whoever is standing on the property, so it
	# stays hidden on a cell the viewer cannot see — otherwise the panel would out
	# an enemy capturing inside your fog.
	var capture_left: int = game.capture_progress.get(cell, -1) if _can_see_cell(cell) else -1
	# The owner label follows the tile, not live truth: a property captured while
	# this cell was fogged keeps its last-seen owner until the viewer sees it, so
	# the panel never names a side change the board is still hiding.
	var owner: int = game.owner_at(cell) if _can_see_cell(cell) else _last_seen_owner(cell)
	# The bar is docked outside the board, so there is no corner to flip to and no
	# tile to fade off: it never covers the cell it describes. Which cell that is
	# the board says for itself, with the cursor brackets already on it.
	hud_bottom.show_tile(
		map.terrain_at(cell), owner, game.current_team, capture_left, hovered, carrying
	)


## Shows the attack/counter forecast beside a cell. A null forecast — nothing
## worth previewing under the cursor — hides the panel.
##
## It speaks HP out of 10, the unit every other HP display in the game speaks
## (UX recovery plan D4): the percentages it used to print read like a hit
## chance and made the player convert mid-fight. Every number here was handed
## over by the forecast — this method formats and never computes, which is the
## cut-in's "replays, never decides" rule applied to text.
func update_damage_preview(forecast: CombatResolver.Forecast, cell: Vector2i) -> void:
	damage_preview.visible = forecast != null and forecast.can_attack
	if not damage_preview.visible:
		return
	atk_label.text = (
		"Deal %s HP"
		% _hp_span(
			forecast.defender_hp_before - forecast.defender_hp_after_max,
			forecast.defender_hp_before - forecast.defender_hp_after_min
		)
	)
	counter_label.text = (
		(
			"Take %s HP"
			% _hp_span(
				forecast.attacker_hp_before - forecast.attacker_hp_after_max,
				forecast.attacker_hp_before - forecast.attacker_hp_after_min
			)
		)
		if forecast.counter_damage >= 0
		else "No counter"
	)
	# The target's own before/after, so the player reads the outcome without
	# subtracting, and the one line that admits the roll exists at all. The
	# luck-free attack percentage rides along dimmed, demoted to the secondary
	# detail plan D4 allows it to be: a chip attack worth less than a displayed
	# HP reads "Deal 0 HP" up top, and this is where it says it landed anyway.
	outcome_label.text = (
		"Target %d → %s HP · %d%% · luck included"
		% [
			forecast.defender_hp_before,
			_hp_span(forecast.defender_hp_after_min, forecast.defender_hp_after_max),
			forecast.attack_damage
		]
	)
	# Measured rather than guessed: the panel is as wide and as tall as its own
	# lines, and those now vary with the numbers in them. It sits up and to the
	# right of the tile, and flips to its left rather than run off the screen.
	var panel := damage_preview.get_combined_minimum_size()
	var pos := screen_pos_for_cell(cell) + Vector2(4.0, 6.0 - panel.y)
	if pos.x + panel.x > _viewport_size().x - 4.0:
		pos.x -= panel.x + 12.0
	# The forecast is one of the three things still allowed to float over the map,
	# but the bars are opaque: clamped into the board band it can never slide
	# under one and lose the numbers it exists to show.
	damage_preview.position = pos.max(Vector2(4, UiTheme.HUD_TOP_H + 4))


## "5" for a certain outcome, "5–6" for one luck can move. Both bounds are the
## forecast's; this only chooses how to say them.
func _hp_span(low: int, high: int) -> String:
	return str(low) if low == high else "%d–%d" % [low, high]


# --- cursor and camera geometry ----------------------------------------------


## Moves the cursor sprite and the camera that follows it. The interaction
## state that hangs off a cursor move stays in Battle.
func move_cursor_to(cell: Vector2i) -> void:
	cursor.position = cell_center(cell)
	camera.position = cursor.position


## The cell the cursor is standing on, read back off the sprite the view owns.
## Battle holds the authoritative `cursor_cell`; this is for the view's own
## redraws, which must not have to ask for it.
func _cursor_cell() -> Vector2i:
	return Vector2i((cursor.position / float(TILE)).floor())


func set_zoom(zoom: float) -> void:
	camera.zoom = Vector2(zoom, zoom)
	_apply_board_offset()
	_apply_camera_limits()


## Slides the camera so the cell it is centred on lands in the middle of the
## *board band* — the strip between the two docked HUD bars — rather than the
## middle of the window, which the bottom bar's larger height would put low.
##
## The bars are chrome outside the map, so the board's viewport is the window
## minus their combined height, computed from constants that never change while a
## match is running (hud handoff SPEC, "Fixed heights"). Applied on zoom because
## Camera2D.offset is world units: the same screen inset is a different world
## distance at each zoom level, and re-deriving it here is what keeps the band
## centred without the camera ever re-laying-out mid-turn.
##
## **`camera.offset` has one writer, and this is it.** The docking shift and the
## combat shake are two different things that both want that property; a shake
## written straight to the camera settles at Vector2.ZERO and takes the docking
## shift down with it, leaving the board half a bar low for the rest of the
## match. So the shake is asked for through `shake_offset` and composed here.
## Anything else that wants to move the camera belongs in this sum too.
func _apply_board_offset() -> void:
	var inset := float(UiTheme.HUD_TOP_H - UiTheme.HUD_BOTTOM_H) / 2.0
	camera.offset = Vector2(0, -inset / camera.zoom.y) + shake_offset


## The furthest out the player may zoom: just far enough that the whole map is
## in view, with the backdrop filling whatever the map's aspect leaves over. On
## a map smaller than the viewport this sits above the default zoom, so a small
## map starts at its floor. Battle owns the zoom level and clamps against this.
func min_zoom() -> float:
	var map_px := Vector2(map.size() * TILE)
	var view := _board_viewport_size()
	return minf(view.x / map_px.x, view.y / map_px.y)


## Camera limits pin the view inside the map. On an axis where the view shows
## more than the whole map they expand just enough to centre it instead,
## splitting the exposed backdrop evenly. Floor/ceil keeps the limit span at
## least the visible extent, so the camera is never pushed against one edge.
##
## The vertical limits carry one extra term. Godot clamps the camera against the
## *rendered* rect, which is the whole window, while the strip a player can
## actually see is the board band; pushing the limits out by half the bars' world
## height makes the engine's clamp land on the band's edges instead, so the board
## still reaches the chrome rather than stopping short of it and showing a seam
## of backdrop.
func _apply_camera_limits() -> void:
	var map_px := Vector2(map.size() * TILE)
	var extra := ((_board_viewport_size() / camera.zoom.x - map_px) / 2.0).max(Vector2.ZERO)
	var hidden := float(UiTheme.HUD_BARS_H) / (2.0 * camera.zoom.y)
	camera.limit_left = floori(-extra.x)
	camera.limit_top = floori(-extra.y - hidden)
	camera.limit_right = ceili(map_px.x + extra.x)
	camera.limit_bottom = ceili(map_px.y + extra.y + hidden)


func _viewport_size() -> Vector2:
	return cursor.get_viewport().get_visible_rect().size


## The strip of window the board actually gets: everything the two docked HUD
## bars do not cover. Derived from constants, so it answers the same on every
## call in a match and the camera is never re-framed mid-turn.
func _board_viewport_size() -> Vector2:
	return _viewport_size() - Vector2(0, UiTheme.HUD_BARS_H)


func screen_pos_for_cell(cell: Vector2i) -> Vector2:
	var world := cell_center(cell) + Vector2(TILE, -TILE) / 2.0
	return (world - _screen_center()) * camera.zoom + _viewport_size() / 2.0 + Vector2(6, 0)


## The world point the middle of the screen shows. Anchored to the camera's
## target (unsmoothed) position so UI placed during a camera glide lands where
## the view settles, not where it happens to be.
##
## `camera.offset` is part of the answer: it is what pushes the board down into
## the band between the bars, so a transient overlay measured against the screen
## centre has to carry the same shift or it would sit a bar's height off the tile
## it points at.
func _screen_center() -> Vector2:
	return _camera_target() + camera.offset


func _camera_target() -> Vector2:
	var view_size := _viewport_size()
	return Vector2(
		clampf(
			camera.position.x,
			camera.limit_left + view_size.x / (2.0 * camera.zoom.x),
			camera.limit_right - view_size.x / (2.0 * camera.zoom.x)
		),
		clampf(
			camera.position.y,
			camera.limit_top + view_size.y / (2.0 * camera.zoom.y),
			camera.limit_bottom - view_size.y / (2.0 * camera.zoom.y)
		)
	)
