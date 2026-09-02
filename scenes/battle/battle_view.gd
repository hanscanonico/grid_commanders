class_name BattleView
extends RefCounted
## Draws battle state: terrain, unit sprites, fog, the two docked HUD bars, and
## the damage forecast — the board itself, in other words. The transient paint
## laid over it while a question is being asked belongs to BattleOverlays.
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
## Fog is enforced in the presentation layer rather than in the permissive sim.
## BattlePerspective decides what the viewer may see; this view only draws it.
##
## Battle assigns the node fields and then calls `setup`; the view is
## constructed with no arguments so it never holds a reference to Battle.

## The bottom bar's charged shortcut was pressed, relayed so Battle wires itself
## to the board's facade rather than into the bar's widget tree — the bars are
## rebuilt in code and a caller three fields deep breaks silently (COM-85).
signal fire_pressed

## The bottom bar's End Turn button was pressed, relayed for the same reason
## `fire_pressed` is.
signal end_turn_pressed

## A team-tinted cell's paint actually changed in `repaint_property` — a
## capture completing, or a fog-deferred one finally reaching the viewer.
## Relayed rather than acted on here, the same reason the two presses above
## are: the flourish over it belongs to BattleAnimator and the pennant it
## flashes to BattleOverlays, and this view only decides what the board itself
## shows.
signal property_flipped(cell: Vector2i)

const TILE := 16
## Terrain atlas cells are 4x the world grid so the generated property
## buildings keep their detail; TerrainLayer is scaled down to compensate.
## Must match sprite_generator's cell size (its atlas contract).
const TERRAIN_PX := 64
const ATLAS_PATH := "res://assets/tiles/terrain_atlas.png"
const ATLAS_SOURCE_ID := 0

const UNIT_SPRITE_SCENE := preload("res://scenes/battle/unit_sprite.tscn")

## The surface a property overlay stands on, under `terrain_layer`. The atlas
## ships its property columns transparent (TerrainDB.GROUND_ID), so a city drawn
## alone is a hole in the board; this layer is the ground the building sits on.
## It carries nothing else — every other terrain paints its own ground.
##
## A second layer rather than plains-in-the-base-and-property-on-top, because the
## property has to stay in `terrain_layer`: its atlas row is the owner's faction
## (`repaint_property`, `_last_seen_owner`, the fog pass) and moving it would put
## that row on a different layer from the one every other cell answers on, while
## `TerrainAutotiles` would have to start answering for a cell it has no family
## for. Under is the only side that costs nothing.
var ground_layer: TileMapLayer
var terrain_layer: TileMapLayer
## Painted beyond the map edges — a darkened continuation of the board that
## fills the screen when the camera is far enough out to show the whole map.
var backdrop_layer: TileMapLayer
var fog_layer: TileMapLayer
## Y-sorted, which is the single answer to how two unit sprites overlap: a
## sprite's position is its cell's centre, so a lower row draws over a higher
## one for free, mid-move and at rest alike. Nothing may set a per-unit
## `z_index` — that would be a second opinion the sort cannot see.
var units_root: Node2D
var cursor: Sprite2D
var camera: Camera2D
## The still the cut-in's entry flinch is played on, so the camera never leaves a
## whole rung of the zoom ladder. Down at rest and invisible at rest scale.
var punch: BoardPunch
## The docked bar below the board: the commander in hand, the unit under the
## cursor, the tile it stands on. Replaces the floating chip and corner panel.
var hud_bottom: HudBottomBar
## The attack forecast that floats beside the previewed cell. It owns its own
## lines; the view only decides whether it shows and where it lands.
var damage_preview: DamagePreview
## The docked bar above the board: day, side, doctrine, funds, key legend.
var hud_top: HudTopBar
## The first-match teaching strip. Transient by design — it retires itself for
## good once the loop has been performed once — so unlike the two bars it floats
## over the board and the camera is never framed around it.
var mission_strip: MissionStrip
## The campaign mission's terms, kept on the board while it is fought. Down for
## every skirmish — it asks CampaignSession and nothing else — so it floats for
## the same reason the strip does rather than being chrome the camera is framed
## around.
var mission_panel: MissionObjectivesPanel
## The touch build's third docked bar — null on a desktop build, where D5 says the
## mobile chrome is never constructed at all. `setup` is what installs it.
var mobile_dock: MobileDock

## Where the board sits on screen: the cursor's cell, the rung, the docking shift
## and the screen point of any cell. Handed the nodes it drives by `setup`, and
## the one writer of `camera.zoom` and `camera.offset` from there on.
var board_camera := BoardCamera.new()

## The transient flinch the cut-in's entry lays over the board — 1.0 at rest. It
## is a scale on a still of the board rather than on the camera, because the zoom
## ladder is whole rungs and a camera walked through 1.00 … 1.14 drops and doubles
## a different set of rows on every frame of the punch. `BoardPunch` is where that
## decision lives; this is the property the animator tweens and the cut-in's clock
## eases back out.
var punch_zoom := 1.0:
	set(value):
		punch_zoom = value
		if punch != null:
			punch.set_punch(value)

var db: TerrainDB
var map: MapData
var game: GameState
## The read-only viewer policy this renderer draws. Battle builds it from the
## same game and shares it with every presentation collaborator.
var perspective: BattlePerspective
## Who each side is and what it wears — resolved once at match setup from the
## commander picks (SideIdentity). Every team-to-paint and team-to-name answer
## the board draws comes from here; the sim keeps its team ints. Battle builds it
## and assigns it, like everything else the view draws with.
var identity: SideIdentity

var _sprites: Dictionary[Unit, UnitSprite] = {}
## Teams the computer plays, from `set_ai_teams`. The view only needs them to know
## whose controls it must not offer; Battle owns the list.
var _ai_teams: Array[int] = []


## Builds the tile sets from data and paints the opening board. Call once, after
## the node fields and `db`/`map`/`game` are set.
func setup() -> void:
	board_camera.camera = camera
	board_camera.cursor = cursor
	board_camera.map = map
	board_camera.mission_panel = mission_panel
	hud_bottom.identity = identity  # the bar names and tints sides through the same resolver
	hud_bottom.chart = game.damage_chart  # and asks the rules which weapons a unit owns
	hud_bottom.ground = db.ground()  # and paints a property chip on the same ground the board does
	hud_bottom.fire_pressed.connect(fire_pressed.emit)
	hud_bottom.end_turn_pressed.connect(end_turn_pressed.emit)
	mobile_dock = MobileDock.install(hud_bottom)
	# Whose actions the teaching strip may learn from — the computer plays through
	# the same events and must not retire a hint on the player's behalf — and
	# whether this board teaches at all, which is MapCatalog's answer (COM-122).
	# Nothing is drawn yet: `refresh_hud` decides whether the strip shows, and it
	# runs after a capture run has had its chance to pin the hints away.
	mission_strip.setup(_human_teams(), MapCatalog.teaches(map.source_path))
	# The card says whether there is a mission and whether its card is up; the top
	# bar's chip is what that answer is for. Wired here rather than read back in
	# refresh_hud, because O lowers the card between commands and a chip told only
	# once a command has settled would light a press late.
	mission_panel.card_changed.connect(hud_top.show_objectives_lens)
	terrain_layer.tile_set = _build_tile_set()
	# The terrain atlas is drawn at 4x the world grid (see TERRAIN_PX), so the
	# layer is scaled back down to keep one cell = TILE. Overlays and the cursor
	# stay at 1x and are unaffected.
	terrain_layer.scale = Vector2.ONE * (float(TILE) / float(TERRAIN_PX))
	backdrop_layer.tile_set = terrain_layer.tile_set
	backdrop_layer.scale = terrain_layer.scale
	ground_layer.tile_set = terrain_layer.tile_set
	ground_layer.scale = terrain_layer.scale
	fog_layer.tile_set = _build_fog_tile_set()
	# The one animated family. Hung on the layer that owns the tile set, so it
	# lives and dies with the board and the two layers sharing that set swell
	# with it.
	SeaBeat.attach(
		terrain_layer,
		terrain_layer.tile_set.get_source(TerrainAutotiles.Family.SEA) as TileSetAtlasSource
	)
	_paint_map()
	_paint_backdrop()
	_spawn_unit_sprites()
	board_camera.setup()


static func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell * TILE) + Vector2(TILE, TILE) / 2.0


## One cell of the terrain atlas, as a source rect: a terrain's `atlas_col` and
## the row an identity resolved. Asked by every surface that blits a cell outside
## the TileMap — the two cut-ins and the tile chip — because the atlas and its
## cell size are this class's, and a second copy of the arithmetic is how a bar
## comes to cut a cell the board has moved.
static func terrain_cell_region(column: int, row: int) -> Rect2:
	return Rect2(column * TERRAIN_PX, row * TERRAIN_PX, TERRAIN_PX, TERRAIN_PX)


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
	for family: int in TerrainAutotiles.SHEET_PATHS:
		tile_set.add_source(_autotile_source(family), family)
	return tile_set


## A source over one generated autotile sheet, cut on TerrainAutotiles' contact
## sheet contract, with a tile per variant that authority says the sheet holds,
## laid out where its atlas_coords says.
func _autotile_source(family: int) -> TileSetAtlasSource:
	var sheet := TileSetAtlasSource.new()
	sheet.texture = load(TerrainAutotiles.SHEET_PATHS[family])
	sheet.margins = Vector2i(TerrainAutotiles.SHEET_MARGIN, TerrainAutotiles.SHEET_MARGIN)
	sheet.separation = Vector2i(
		TerrainAutotiles.SHEET_SEPARATION, TerrainAutotiles.SHEET_SEPARATION
	)
	sheet.texture_region_size = Vector2i(TERRAIN_PX, TERRAIN_PX)
	for coords in TerrainAutotiles.sheet_cells(family):
		sheet.create_tile(coords)
	return sheet


## The fog gets its own tile rather than sharing BattleOverlays'.
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
	var ground := Vector2i(db.ground().atlas_col, 0)
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			if _paint_autotile(terrain_layer, cell):
				continue
			var terrain := map.terrain_at(cell)
			var row := identity.atlas_row(game.owner_at(cell)) if terrain.team_tinted else 0
			terrain_layer.set_cell(cell, ATLAS_SOURCE_ID, Vector2i(terrain.atlas_col, row))
			if terrain.is_property:
				ground_layer.set_cell(cell, ATLAS_SOURCE_ID, ground)


## Paints `cell` from its autotile family sheet, if it has one. False means the
## cell keeps a base-atlas tile and the caller picks its row.
func _paint_autotile(layer: TileMapLayer, cell: Vector2i) -> bool:
	var family := TerrainAutotiles.family(map, cell)
	if family == TerrainAutotiles.Family.NONE:
		return false
	var variant := TerrainAutotiles.variant(map, cell)
	layer.set_cell(cell, family, TerrainAutotiles.atlas_coords(family, variant))
	return true


## Fills a ring of cells beyond the map edges so that when the whole map is in
## view (see min_zoom) the rest of the screen reads as darkened out-of-bounds
## ground, not engine-clear void. TerrainAutotiles answers for an off-board cell
## by reading the nearest edge terrain, which is exactly the continuation this
## ring is, so a coastline, a road or a tree line runs off the board rather than
## changing style at the rim. Properties fall back to plains so no building
## appears to stand off the board. The ring is sized to the most min_zoom can
## expose, and the darkening is the layer's modulate in the scene.
func _paint_backdrop() -> void:
	var plains := db.by_id(&"plains")
	var map_px := Vector2(map.size() * TILE)
	var exposed := board_camera.viewport_size() / board_camera.min_zoom()
	var margin := Vector2i(
		ceili(maxf(0.0, (exposed.x - map_px.x) / 2.0) / TILE) + 1,
		ceili(maxf(0.0, (exposed.y - map_px.y) / 2.0) / TILE) + 1
	)
	for y in range(-margin.y, map.height + margin.y):
		for x in range(-margin.x, map.width + margin.x):
			var cell := Vector2i(x, y)
			if map.in_bounds(cell):
				continue
			if _paint_autotile(backdrop_layer, cell):
				continue
			var terrain := db.by_id(TerrainAutotiles.terrain_id(map, cell))
			if terrain.team_tinted:
				terrain = plains
			backdrop_layer.set_cell(cell, ATLAS_SOURCE_ID, Vector2i(terrain.atlas_col, 0))


## Recolors one property to its current owner, after a capture — but only for a
## cell the viewer can currently see. A capture inside the viewer's fog must not
## paint through the translucent fog layer (it would leak enemy expansion and
## income), so a hidden cell keeps its last-seen colour and the repaint is
## deferred to `refresh_fog`, which lands it the moment the viewer's vision
## reaches the cell.
func repaint_property(cell: Vector2i) -> void:
	if not perspective.can_see_cell(cell):
		return
	var terrain := map.terrain_at(cell)
	if not terrain.team_tinted:
		return
	var row := identity.atlas_row(game.owner_at(cell))
	# The one place a flip is known rather than assumed: the initial paint
	# (`_paint_map`) used this same formula, so a cell whose owner never
	# changed reads back the row it was already given, and only a real flip
	# differs from it.
	var flipped := terrain_layer.get_cell_atlas_coords(cell).y != row
	terrain_layer.set_cell(cell, ATLAS_SOURCE_ID, Vector2i(terrain.atlas_col, row))
	if flipped:
		property_flipped.emit(cell)


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


## Brings one sprite back in step with the sim, fog and faction colours included:
## both answers are written onto the sprite, which then draws itself from them.
##
## Deciding it here and storing it there is what makes it stick. A sprite that
## worked visibility out for itself would un-hide a fogged enemy every time
## anything redrew it — and `UnitSprite` redraws on three different calls — so
## the decision is made in one place and remembered rather than re-derived. The
## atlas row rides here for the same reason and from the same authority: whose
## colours a unit wears is `SideIdentity`'s answer, and a unit that changed army
## since it was drawn has to be asked again.
func refresh_sprite(unit: Unit) -> void:
	var sprite: UnitSprite = _sprites.get(unit)
	if sprite == null:
		return
	sprite.fogged = _is_fogged(unit)
	sprite.atlas_row = identity.atlas_row(unit.team)
	sprite.refresh()


## Whether the board currently hides `unit` from whoever is looking. The shared
## perspective owns the answer, including a hot-seat blackout hiding your own.
func _is_fogged(unit: Unit) -> bool:
	return not perspective.can_see_unit(unit)


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
		# The sim can outrun the sprite table between commands, so a unit here may
		# not have one yet — skip it rather than index blind.
		var sprite: UnitSprite = _sprites.get(unit)
		if sprite == null:
			continue
		sprite.set_active_team(team)


## Brings every sprite back in step with the sim in one pass, for the changes
## that touch more of the board than a caller can name unit by unit.
##
## Three of those. A death can take units the combat result never mentions —
## cargo goes down with its transport — so any sprite whose unit has left
## `game.units` is freed. A Command Power can heal or refuel a whole side at
## once, so every surviving sprite is redrawn rather than just the one that
## acted. And a command can *add* a unit nothing named — a scripted beat lands a
## relief column — so a unit on the board with no sprite gets one here. The pass
## is the board's reconciliation in both directions; a one-way one leaves an
## arrival invisible, which is a unit the player is attacked from an empty
## square by. Survivors go through `refresh_sprite`, so the pass re-applies fog
## instead of leaking whatever the last fog pass hid, and an arrival goes through
## `spawn_sprite_for`, which asks the same perspective before it draws anything.
##
## `fade_seconds` is a death's own parting fade for a unit this pass frees that
## nothing else already showed dying — cargo lost with its transport, chiefly.
## Zero is every other caller's answer: the pass runs after ordinary commands
## too (a build, a join, a power), and those must stay a still board's worth of
## change. `UnitSprite.die` is fire-and-forget here, the way a merged twin's
## fade already is in `animate_join` — the reconciliation itself must not wait
## on it.
func sync_sprites(fade_seconds: float = 0.0) -> void:
	for unit: Unit in _sprites.keys():
		if unit in game.units:
			refresh_sprite(unit)
			continue
		var sprite: UnitSprite = _sprites[unit]
		_sprites.erase(unit)
		sprite.die(_parting_fade(unit, sprite, fade_seconds))
	for unit: Unit in game.units:
		if not _sprites.has(unit):
			spawn_sprite_for(unit)


## Frees the sprites of whatever went down inside `carrier` — the riders the sim
## took off the board with it, which no combat result names and which only a
## reconciliation pass would otherwise reach.
##
## Asked for at the moment the transport's own death is shown, so the stack
## sinks together. `sync_sprites` runs at the end of the exchange instead, a
## whole death fade later, and riders reaching it there would stand up opaque on
## a tile the board had already emptied. Fire-and-forget on `_parting_fade`'s
## own terms: posed at the transport's cell, and silent where the viewer cannot
## see it.
func drop_cargo_of(carrier: Unit, fade_seconds: float) -> void:
	for unit: Unit in _sprites.keys():
		if unit.carrier != carrier or unit in game.units:
			continue
		var sprite: UnitSprite = _sprites[unit]
		_sprites.erase(unit)
		sprite.die(_parting_fade(unit, sprite, fade_seconds))


## How long a sprite this pass frees gets to fade, and where it fades from.
##
## A rider was drawn hidden for as long as it rode, so a fade left on it where
## it lies is a tween nobody can watch: it is stood on the transport's own last
## cell and un-hidden to go down with it. The viewer has to be able to see that
## cell — the fog rule the death blast asks of a kill it draws — and a rider
## lost out of sight goes without a fade, the way every freed sprite used to.
func _parting_fade(unit: Unit, sprite: UnitSprite, fade_seconds: float) -> float:
	if fade_seconds <= 0.0 or unit.carrier == null:
		return fade_seconds
	if not perspective.can_see_cell(unit.carrier.cell):
		return 0.0
	sprite.pose_at(unit.carrier.cell)
	return fade_seconds


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


# --- fog ---------------------------------------------------------------------


## Repaints the fog layer and unit visibility from the already-refreshed
## perspective. Called after every committed action and turn change, not per
## cursor move.
func refresh_fog() -> void:
	fog_layer.clear()
	if game.fog_enabled:
		for y in map.height:
			for x in map.width:
				var cell := Vector2i(x, y)
				if perspective.can_see_cell(cell):
					# In view: show the true owner. A capture the gate in
					# repaint_property deferred while the cell was fogged reveals
					# here, so the board never leaks an ownership change the viewer
					# has not scouted, yet shows the truth the instant it is seen.
					repaint_property(cell)
				else:
					fog_layer.set_cell(cell, ATLAS_SOURCE_ID, Vector2i.ZERO)
	for unit in game.units:
		refresh_sprite(unit)


## The owner the board tile at `cell` is currently painted for, recovered from its
## atlas row. For a cell in view this equals the live owner (the fog pass just
## repainted it); for a fogged cell it is the viewer's last-seen owner. The
## bar's tile card reads this instead of live truth on a hidden cell so its owner
## label names the same side the tile shows — never outing a capture out of sight.
func _last_seen_owner(cell: Vector2i) -> int:
	# An autotiled cell's atlas row is a mask variant, not a faction, and no
	# autotiled terrain is a property — only the base source's rows name one.
	if terrain_layer.get_cell_source_id(cell) != ATLAS_SOURCE_ID:
		return MapData.NEUTRAL
	var row: int = terrain_layer.get_cell_atlas_coords(cell).y
	for team in game.teams:
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
	hud_bottom.show_commander(game.commander_state(team), team in _ai_teams, identity.theme(team))
	# The strip reads its own progress out of the device preference, so this only
	# has to say "something changed" — and a turn boundary is when a step most
	# often did (COM-12).
	mission_strip.refresh()
	# The mission card reads the board it is describing, so it is handed the same
	# state everything else here draws from.
	mission_panel.refresh(game)


## Which seats the computer plays, from Battle, which owns the list. The view
## holds the list it is handed rather than a copy, so a seating Battle edits in
## place is the seating the bars read.
func set_ai_teams(teams: Array[int]) -> void:
	_ai_teams = teams


## What the bottom bar is currently printing about the unit under the cursor.
## Read back by the scenario driver's checks; the bar's own answer, so a readout
## that drifts from the rules is caught where it is shown.
func unit_order_line() -> String:
	return hud_bottom.unit_order_line()


## Lights the top bar's threat chip to match the lens on the board.
func refresh_threat_lens(on: bool) -> void:
	hud_top.show_threat_lens(on)


## The same for R's fire ring. Battle calls it from its `_range_shown` setter, so
## every site that clears the ring lights the chip down with it.
func refresh_range_lens(on: bool) -> void:
	hud_top.show_range_lens(on)


## Brings the chrome that answers to the interaction the player is now in up to
## date: the top bar's key legend, and whether the bottom bar's End Turn button
## may be pressed. Battle calls it from its `state` setter, so neither can fall
## out of step with the flow the way a per-call-site refresh eventually would,
## and both read the one context rather than each judging the turn for itself.
func refresh_keys(context: StringName) -> void:
	hud_top.show_keys(ControlHints.legend_for(context))
	hud_bottom.show_end_turn(BattleLegend.commands_board(context))
	if mobile_dock != null:
		mobile_dock.refresh(context)


## The sides a person is playing. One in a match against the computer, both in
## hot-seat, and none at all in a watched AI-versus-AI replay — where the strip
## then has nobody to teach and stays down.
func _human_teams() -> Array[int]:
	var out: Array[int] = []
	for team in game.teams:
		if team not in _ai_teams:
			out.append(team)
	return out


func refresh_panel(cell: Vector2i) -> void:
	var hovered := perspective.visible_unit_at(cell)  # hidden enemies stay hidden here too
	var carrying := ""
	if hovered != null:
		var cargo := game.cargo_of(hovered)
		if not cargo.is_empty():
			carrying = cargo[0].type.display_name
	# A capture in progress belongs to whoever is standing on the property, so it
	# stays hidden on a cell the viewer cannot see — otherwise the panel would out
	# an enemy capturing inside your fog.
	var capture_left: int = (
		game.capture_progress.get(cell, -1) if perspective.can_see_cell(cell) else -1
	)
	# The owner label follows the tile, not live truth: a property captured while
	# this cell was fogged keeps its last-seen owner until the viewer sees it, so
	# the panel never names a side change the board is still hiding.
	var owner: int = (
		game.owner_at(cell) if perspective.can_see_cell(cell) else _last_seen_owner(cell)
	)
	# The bar is docked outside the board, so there is no corner to flip to and no
	# tile to fade off: it never covers the cell it describes. Which cell that is
	# the board says for itself, with the cursor brackets already on it.
	hud_bottom.show_tile(
		map.terrain_at(cell),
		owner,
		game.current_team,
		capture_left,
		hovered,
		carrying,
		_allegiance_of(hovered),
		_range_band_of(hovered),
		_cover_stars_of(hovered, cell)
	)


## One word for whose side a unit is on, from the *viewer's* seat: "Ally" for
## another army standing with them, "Enemy" for anyone else, and nothing at all
## for their own units, which need no telling. Asked of the one hostility
## authority, so the bar and the commands can never disagree about who may be
## shot (four-players plan D2).
func _allegiance_of(unit: Unit) -> String:
	if unit == null:
		return ""
	var viewer := perspective.viewing_team()
	if unit.team == viewer:
		return ""
	return "Ally" if game.allied(unit.team, viewer) else "Enemy"


## The ring the bar prints as "RNG a-b". Asked of AttackRange, the one authority
## on how far a unit shoots, so the readout follows a doctrine that moves it —
## Rhea Sol's Grid Saturation — exactly as the fire overlay and AttackCommand do.
func _range_band_of(unit: Unit) -> Vector2i:
	if unit == null:
		return Vector2i.ZERO
	return AttackRange.band(game, unit)


## The cover this unit actually fights with on this tile, which is not always the
## tile's own: an aircraft flies over the ground and gets none of it. Asked of the
## same authority the damage formula and the AI planner ask, so the bar can never
## promise defence the shot then refuses.
func _cover_stars_of(unit: Unit, cell: Vector2i) -> int:
	if unit == null:
		return 0
	return CombatResolver.cover_stars(game, unit, cell)


## Shows the attack/counter forecast beside a cell. A null forecast — nothing
## worth previewing under the cursor — hides the panel. What the lines say is the
## panel's own; where they land is this view's, asked of `BoardCamera`.
func update_damage_preview(forecast: CombatSnapshot.Forecast, cell: Vector2i) -> void:
	damage_preview.visible = forecast != null and forecast.can_attack
	if not damage_preview.visible:
		return
	damage_preview.show_forecast(forecast)
	# Measured rather than guessed: the panel is as wide and as tall as its own
	# lines, and those vary with the numbers in them. It sits up and to the
	# right of the tile, and flips to its left rather than run off the screen.
	var panel := damage_preview.get_combined_minimum_size()
	var pos := board_camera.screen_pos_for_cell(cell) + Vector2(4.0, 6.0 - panel.y)
	if pos.x + panel.x > board_camera.viewport_size().x - 4.0:
		pos.x -= panel.x + 12.0
	# The forecast is one of the three things still allowed to float over the map,
	# but the bars are opaque: clamped into the board band it can never slide
	# under one and lose the numbers it exists to show.
	damage_preview.position = pos.max(Vector2(4, UiTheme.HUD_TOP_H + 4))


# --- cursor ------------------------------------------------------------------


## The cell the cursor is standing on, read back off the sprite the view owns.
## Battle holds the authoritative `cursor_cell`; this is for the view's own
## redraws, which must not have to ask for it.
func _cursor_cell() -> Vector2i:
	return Vector2i((cursor.position / float(TILE)).floor())
