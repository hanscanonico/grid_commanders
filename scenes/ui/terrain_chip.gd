class_name TerrainChip
extends HBoxContainer
## The tile under the cursor, as the bottom bar's right-hand third: one atlas
## cell of artwork, the terrain's name, and the line that reads its defense, its
## owner and how much capturing is left.
##
## Presentation only, and it decides nothing: the terrain, the owner and the
## capture count are handed over by HudBottomBar, which was handed them already
## gated for fog.
##
## A property is drawn ground-then-building, the composite the board's two tile
## layers paint — the atlas draws a building with alpha around it, so the chip
## stands it on the same default ground (`bind`'s `p_ground`, TerrainDB.ground()).

const MAX_DEFENSE_STARS := 4

## How each side is named and tinted, and the ground a property stands on. Both
## are handed over through `bind` rather than resolved here, so the chip tints a
## cell through the same resolver the board does.
var _identity: SideIdentity
var _ground: TerrainType

var _icon: TextureRect
## The building standing on `_icon`'s ground, for a property cell. Empty for
## every other terrain, which draws its own ground in the icon itself.
var _building: TextureRect
var _name: Label
var _def: Label


func _ready() -> void:
	add_theme_constant_override("separation", UiTheme.HUD_GAP_WIDE)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(UiTheme.HUD_TILE_ICON, UiTheme.HUD_TILE_ICON)
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_icon)

	# Both sources are one square atlas cell, so filling the icon's rect lands the
	# building on its ground exactly as the board's two layers do.
	_building = TextureRect.new()
	_building.texture_filter = _icon.texture_filter
	_building.expand_mode = _icon.expand_mode
	_building.stretch_mode = _icon.stretch_mode
	_building.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_building.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.add_child(_building)

	var data := VBoxContainer.new()
	data.add_theme_constant_override("separation", UiTheme.HUD_GAP_HAIR)
	data.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(data)
	_name = UiTheme.hud_label("", UiTheme.SIZE_STAT, UiTheme.WHITE)
	data.add_child(_name)
	_def = UiTheme.hud_label("", UiTheme.SIZE_STAT, UiTheme.INK_3)
	data.add_child(_def)


## The two things the chip cannot resolve for itself. Assignment only, so the
## bar may call it before or after the chip is in the tree.
func bind(p_identity: SideIdentity, p_ground: TerrainType) -> void:
	_identity = p_identity
	_ground = p_ground


## Single entry point per hovered tile. `capture_left` is negative when nothing
## is being captured there.
func show_terrain(terrain: TerrainType, owner_team: int, capture_left: int) -> void:
	if _icon == null:
		return
	var standing := terrain.is_property and _ground != null
	_icon.texture = _terrain_texture(_ground if standing else terrain, owner_team)
	_building.texture = _terrain_texture(terrain, owner_team) if standing else null
	_name.text = terrain.display_name.to_upper()
	var line := "DEF %s" % _stars(terrain.defense_stars)
	if terrain.is_property:
		line += " · %s" % _identity.display_name(owner_team).to_upper()
	if capture_left >= 0:
		line += " · CAP %d" % capture_left
	_def.text = line


func _stars(count: int) -> String:
	if count <= 0:
		return "0"
	return UiKit.star_bar(count, MAX_DEFENSE_STARS)


## The same artwork the board draws: one cell of the terrain atlas, in the
## owner's resolved faction row (rows 1+ exist only when team_tinted). The atlas
## and its cell size are asked of BattleView, which owns them, rather than
## mirrored here — a mirror is how a bar comes to draw a cell the board has moved.
func _terrain_texture(terrain: TerrainType, owner_team: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = load(BattleView.ATLAS_PATH)
	var row: int = _identity.atlas_row(owner_team) if terrain.team_tinted else 0
	atlas.region = BattleView.terrain_cell_region(terrain.atlas_col, row)
	return atlas
