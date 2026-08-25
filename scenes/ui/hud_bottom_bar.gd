class_name HudBottomBar
extends PanelContainer
## The docked strip below the board: everything that changes as the cursor moves.
## The commander in hand on the left — portrait, name, power name, charge meter
## with its cost readout and the charged shortcut — then the unit under the
## cursor, then the tile it is standing on.
##
## Replaces the floating commander chip and the corner terrain panel (the HUD
## handoff, `.lavish/hud/SPEC.md`). Docked and opaque, so nothing here can sit on
## a tile the player is trying to read; and fixed at UiTheme.HUD_BOTTOM_H whatever
## it is showing, so the board's viewport is a constant.
##
## **Empty is empty.** With no unit under the cursor the unit and terrain thirds
## go blank and the bar keeps its height — a bar that grew and shrank as the
## cursor moved would slide the map under it, which is worse than one that is
## sometimes half empty.
##
## Presentation only. The occupant arrives already gated for fog by
## BattleView.refresh_panel, which nulls a unit the viewer cannot see before this
## ever gets it, and the sprites come from the system's own resolvers —
## UnitSprite.texture_for and CommanderVisuals.portrait_for — so faction tint and
## the exhausted grey are never a second opinion held here.

## The charged shortcut was pressed. The bar owns the button and says what
## happened to it; what a press means is Battle's, through BattleView.
signal fire_pressed

## The End Turn button was pressed. Same contract as `fire_pressed`: the bar owns
## the button, what a press means is Battle's.
signal end_turn_pressed

const MAX_DEFENSE_STARS := 4
const CLASS_LABELS: Dictionary = {
	TerrainType.FOOT: "Foot",
	TerrainType.BOOT: "Boot",
	TerrainType.TIRES: "Tires",
	TerrainType.TREADS: "Treads",
	TerrainType.AIR: "Air",
	TerrainType.SHIP: "Ship",
	TerrainType.LANDER: "Lander",
}

## How each side is named and tinted. Battle resolves it once and BattleView
## hands it over, so the bar tints a unit through the same resolver the board does.
var identity: SideIdentity

## The rules' own weapon tables, handed over by BattleView. The bar asks them
## whether a unit owns an infinite-ammo secondary rather than reading the
## presentation key that only says how one looks.
var chart: DamageChart

## What a property overlay stands on (TerrainDB.GROUND_ID), handed over by
## BattleView. The atlas draws a building with alpha around it, so the chip
## composites the same ground under it the board paints beneath the cell.
var ground: TerrainType

var _built := false
## The charged shortcut, kept on the bar so the fire control sits with the
## readiness it reflects — the same contract the floating chip had. A press
## leaves here as `fire_pressed`; nobody outside the bar reaches the Button.
var _fire_button: Button
## Ending the turn without opening a menu first — the most repeated action in a
## match, kept on the bar that is always up. Greyed rather than hidden off the
## player's turn, so the terrain chip beside it never slides.
var _end_turn_button: Button
var _portrait_field: Panel
var _co_name: Label
var _power_name: Label
var _meter_fill: Panel
var _meter_frame: Panel
var _charge_label: Label

var _unit_data: Control
var _unit_icon: TextureRect
var _unit_name: Label
var _unit_sub: Label
var _pips: HpPips
var _fuel_label: Label
var _ammo_label: Label

var _terrain_icon: TextureRect
## The building standing on `_terrain_icon`'s ground, for a property cell. Empty
## for every other terrain, which draws its own ground in the icon itself.
var _terrain_building: TextureRect
var _terrain_name: Label
var _terrain_def: Label


func _ready() -> void:
	_build()


func _build() -> void:
	custom_minimum_size = Vector2(0, UiTheme.HUD_BOTTOM_H)
	add_theme_stylebox_override("panel", UiTheme.hud_bar_box(true))
	# Chrome swallows the pointer, stated rather than inherited from Control's
	# default: the board renders behind the bars, so an event that fell through to
	# Battle._unhandled_input would move the game cursor onto a covered cell. The
	# Fire button is a child and keeps its own hit-testing.
	mouse_filter = Control.MOUSE_FILTER_STOP

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.HUD_GAP)
	add_child(row)
	row.add_child(UiTheme.hud_spacer(UiTheme.HUD_PAD - UiTheme.HUD_GAP))
	_build_commander(row)
	row.add_child(UiTheme.hud_divider(UiTheme.HUD_BOTTOM_RULE_H))
	# The unit block is the row's one expanding child, so the free width of the bar
	# lands on the order line rather than sitting empty to its right. It is also
	# what keeps the terrain chip pinned to the right edge whether or not there is
	# a unit to describe — which is why it is blanked rather than hidden when the
	# cursor steps off a unit: an invisible child is no child at all to a container,
	# and the chip would slide left.
	_build_unit(row)
	_build_terrain(row)
	row.add_child(UiTheme.hud_divider(UiTheme.HUD_BOTTOM_RULE_H))
	_build_end_turn(row)
	row.add_child(UiTheme.hud_spacer(UiTheme.HUD_PAD - UiTheme.HUD_GAP))

	_built = true


func _build_commander(row: HBoxContainer) -> void:
	# Neutral until `bind` puts the side's own general and faction on it. The chip
	# is smaller than a bust, so the kit shows the face crop here.
	_portrait_field = UiKit.commander_bust(
		null, Vector2(UiTheme.HUD_PORTRAIT, UiTheme.HUD_PORTRAIT), UiKit.NO_FIELD
	)
	_portrait_field.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_portrait_field)

	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", UiTheme.HUD_GAP_TIGHT)
	block.custom_minimum_size = Vector2(UiTheme.HUD_CO_MIN_W, 0)
	block.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(block)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UiTheme.HUD_GAP_SNUG)
	block.add_child(head)
	_co_name = UiTheme.hud_label("", UiTheme.SIZE_STAT, UiTheme.WHITE)
	head.add_child(_co_name)
	_power_name = UiTheme.hud_label("", UiTheme.SIZE_STAT, UiTheme.INK_3)
	_power_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_power_name)

	var meter_row := HBoxContainer.new()
	meter_row.add_theme_constant_override("separation", UiTheme.HUD_GAP_SNUG)
	block.add_child(meter_row)
	_meter_frame = Panel.new()
	_meter_frame.custom_minimum_size = UiTheme.HUD_METER
	_meter_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_meter_frame.add_theme_stylebox_override(
		"panel", UiTheme.bordered(UiTheme.SLATE_900, UiTheme.HARD_BORDER)
	)
	meter_row.add_child(_meter_frame)
	# The fill is a child of the trough rather than a ProgressBar so the meter is
	# one flat rectangle inside a hard ink frame, with no engine-drawn rounding.
	_meter_fill = Panel.new()
	_meter_fill.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.AMMO))
	_meter_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_meter_frame.add_child(_meter_fill)

	_charge_label = UiTheme.hud_label("", UiTheme.SIZE_STAT, UiTheme.INK_3)
	meter_row.add_child(_charge_label)
	_fire_button = Button.new()
	_fire_button.text = "FIRE"
	_fire_button.focus_mode = Control.FOCUS_NONE
	# Cream rather than the side's own fill, for the reason the faction chip above
	# takes the -light value: this bar is slate, and Iron's hue sits close enough to
	# it that a tinted button disappears into the chrome it stands on.
	UiTheme.apply_button(_fire_button, UiTheme.ButtonVariant.SECONDARY, null, UiTheme.SIZE_BODY)
	_fire_button.pressed.connect(fire_pressed.emit)
	meter_row.add_child(_fire_button)


func _build_end_turn(row: HBoxContainer) -> void:
	_end_turn_button = Button.new()
	_end_turn_button.text = ControlHints.END_TURN_CHIP
	_end_turn_button.focus_mode = Control.FOCUS_NONE
	_end_turn_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Cream for the reason the Fire button is: this bar is slate, and a side-tinted
	# button disappears into the chrome it stands on.
	UiTheme.apply_button(_end_turn_button, UiTheme.ButtonVariant.SECONDARY, null, UiTheme.SIZE_BODY)
	_end_turn_button.disabled = true  # until a state says the board is the player's
	_end_turn_button.pressed.connect(end_turn_pressed.emit)
	row.add_child(_end_turn_button)


func _build_unit(row: HBoxContainer) -> void:
	var block := HBoxContainer.new()
	block.add_theme_constant_override("separation", UiTheme.HUD_GAP)
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(block)

	_unit_icon = TextureRect.new()
	_unit_icon.custom_minimum_size = Vector2(UiTheme.HUD_UNIT_ICON, UiTheme.HUD_UNIT_ICON)
	_unit_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_unit_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_unit_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_unit_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	block.add_child(_unit_icon)

	var data := VBoxContainer.new()
	data.add_theme_constant_override("separation", UiTheme.HUD_GAP_TIGHT)
	data.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	data.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_child(data)
	_unit_data = data

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UiTheme.HUD_GAP_SNUG)
	data.add_child(head)
	_unit_name = UiTheme.hud_label("", UiTheme.SIZE_STAT, UiTheme.WHITE)
	head.add_child(_unit_name)
	_unit_sub = UiTheme.hud_label("", UiTheme.SIZE_STAT, UiTheme.INK_3)
	_unit_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unit_sub.clip_text = true
	head.add_child(_unit_sub)

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", UiTheme.HUD_GAP_WIDE)
	data.add_child(stats)
	_pips = HpPips.new()
	stats.add_child(_pips)
	_fuel_label = UiTheme.hud_label("", UiTheme.SIZE_STAT, UiTheme.PAPER_2)
	stats.add_child(_fuel_label)
	_ammo_label = UiTheme.hud_label("", UiTheme.SIZE_STAT, UiTheme.PAPER_2)
	stats.add_child(_ammo_label)


func _build_terrain(row: HBoxContainer) -> void:
	var block := HBoxContainer.new()
	block.add_theme_constant_override("separation", UiTheme.HUD_GAP_WIDE)
	block.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(block)

	_terrain_icon = TextureRect.new()
	_terrain_icon.custom_minimum_size = Vector2(UiTheme.HUD_TILE_ICON, UiTheme.HUD_TILE_ICON)
	_terrain_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_terrain_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_terrain_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	block.add_child(_terrain_icon)

	# Both sources are one square atlas cell, so filling the icon's rect lands the
	# building on its ground exactly as the board's two layers do.
	_terrain_building = TextureRect.new()
	_terrain_building.texture_filter = _terrain_icon.texture_filter
	_terrain_building.expand_mode = _terrain_icon.expand_mode
	_terrain_building.stretch_mode = _terrain_icon.stretch_mode
	_terrain_building.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain_building.set_anchors_preset(Control.PRESET_FULL_RECT)
	_terrain_icon.add_child(_terrain_building)

	var data := VBoxContainer.new()
	data.add_theme_constant_override("separation", UiTheme.HUD_GAP_HAIR)
	data.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	block.add_child(data)
	_terrain_name = UiTheme.hud_label("", UiTheme.SIZE_STAT, UiTheme.WHITE)
	data.add_child(_terrain_name)
	_terrain_def = UiTheme.hud_label("", UiTheme.SIZE_STAT, UiTheme.INK_3)
	data.add_child(_terrain_def)


# --- the commander third ------------------------------------------------------


## Brings the left third in step with the side in hand. `is_ai` drops the Fire
## button for a computer commander — a charged AI fills its meter, but the click
## would be refused — and names it in the readout, so a full meter the viewing
## player cannot fire says so instead of advertising a shortcut that does nothing.
##
## `theme` is the side's *resolved* theme, handed over by BattleView rather than
## re-derived from the commander, so a mirror match wears the borrowed colour its
## army wears on the board (COM-18).
##
## The power name sits beside the meter it charges and the readout under it is
## the live charge against `power_cost`; the doctrine is the *top* bar's, which
## is the split the shipped build had backwards.
func show_commander(
	co_state: CommanderState, is_ai: bool, theme: CommanderVisuals.FactionTheme
) -> void:
	if not _built:
		return
	var commander := co_state.type
	# A side playing without a power keeps the portrait and name — this is docked
	# chrome with a fixed footprint, so hiding the block would leave a hole rather
	# than reclaim anything. Only the meter and its controls go.
	var powered := commander.has_power()
	UiKit.bind_bust(_portrait_field, commander, theme.color_light)
	_co_name.text = commander.display_name.to_upper()
	_power_name.text = commander.power_name.to_upper() if powered else ""
	_meter_frame.visible = powered
	_charge_label.visible = powered
	if not powered:
		_fire_button.visible = false
		return

	var ratio := 1.0 if co_state.power_active or co_state.is_ready() else co_state.charge_ratio()
	_meter_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_meter_fill.size = Vector2(UiTheme.HUD_METER.x * ratio, UiTheme.HUD_METER.y)
	_meter_fill.position = Vector2.ZERO
	# Amber is the charge colour in this design system; the active state takes the
	# capture green so a running power reads differently from a full one.
	_meter_fill.add_theme_stylebox_override(
		"panel", UiTheme.flat(UiTheme.CAPTURE if co_state.power_active else UiTheme.AMMO)
	)
	if co_state.power_active:
		_charge_label.text = "ACTIVE"
		_charge_label.add_theme_color_override("font_color", UiTheme.CAPTURE)
	elif co_state.is_ready():
		# F is the player's shortcut, so a computer commander's full meter names its
		# owner instead of a key that would be refused (COM-18's AI-control line).
		_charge_label.text = "READY · AI" if is_ai else "READY · F"
		_charge_label.add_theme_color_override("font_color", UiTheme.AMMO)
	else:
		_charge_label.text = "%d / %d" % [co_state.charge, commander.power_cost]
		_charge_label.add_theme_color_override("font_color", UiTheme.INK_3)
	_fire_button.visible = co_state.is_ready() and not is_ai
	_fire_button.disabled = not co_state.is_ready() or is_ai


## Whether the End Turn button may be pressed. `offered` is BattleLegend's answer
## about the board's own context, so the button is live in exactly the two rest
## states the player commands from and dead over a computer turn, a handoff, an
## open menu or a cut-in.
func show_end_turn(offered: bool) -> void:
	if not _built:
		return
	_end_turn_button.disabled = not offered


# --- the unit and terrain thirds ----------------------------------------------


## Single entry point per hovered tile; `unit` is null on an empty or fogged
## tile, and that is what blanks the right two thirds. `carrying` names the cargo
## when the unit is a loaded transport.
##
## `range_band` is the ring the unit really fires in — AttackRange's answer,
## resolved by BattleView, never the pair printed on the unit type. A doctrine may
## widen it (Rhea Sol's Grid Saturation), and a bar reading the type would print a
## range the fire ring and AttackCommand both disagree with.
##
## `cover_stars` is what this unit really fights with on this tile — CombatResolver's
## answer, resolved by BattleView — which is not the tile's own for an aircraft.
func show_tile(
	terrain: TerrainType,
	owner_team: int,
	active_team: int,
	capture_left: int = -1,
	unit: Unit = null,
	carrying: String = "",
	allegiance: String = "",
	range_band: Vector2i = Vector2i.ZERO,
	cover_stars: int = 0
) -> void:
	if not _built:
		return
	_show_unit(
		unit, carrying, active_team, allegiance, range_band, cover_stars, terrain.defense_stars
	)
	_show_terrain(terrain, owner_team, capture_left)


## The order line as it currently reads, for the scenario that checks what the
## bar is showing rather than what it was handed — the same read-back seam
## CutsceneSide.drawn_unit_row is. Empty while no unit is under the cursor.
func unit_order_line() -> String:
	if not _built or not _unit_data.visible:
		return ""
	return _unit_sub.text


func _show_unit(
	unit: Unit,
	carrying: String,
	active_team: int,
	allegiance: String,
	range_band: Vector2i,
	cover_stars: int,
	tile_stars: int
) -> void:
	# The block itself stays in the row — it is the expanding child holding the
	# terrain chip against the right edge — so an empty tile blanks its contents
	# rather than hiding the block.
	_unit_icon.visible = unit != null
	_unit_data.visible = unit != null
	if unit == null:
		return
	_unit_icon.texture = UnitSprite.tile_texture_for(unit.type, identity.atlas_row(unit.team))
	# The board's own exhausted scrim, borrowed rather than redefined: a unit
	# that has acted looks the same in the bar as it does on the tile.
	var waited := unit.acted and unit.team == active_team
	_unit_icon.material = UnitSprite.acted_scrim() if waited else null
	_unit_name.text = unit.type.display_name
	_unit_sub.text = _order_line(
		unit, carrying, waited, allegiance, range_band, cover_stars, tile_stars
	)
	_pips.set_hp(unit.displayed_hp())
	_fuel_label.text = "FUEL %d/%d" % [unit.fuel, unit.type.max_fuel]
	_ammo_label.visible = unit.type.max_ammo > 0
	if chart != null and chart.has_secondary(unit.type.id):
		_ammo_label.text = "MAIN %d/%d · MG ∞" % [unit.ammo, unit.type.max_ammo]
	else:
		_ammo_label.text = "AMMO %d/%d" % [unit.ammo, unit.type.max_ammo]


## Movement class first, then whatever the unit is currently doing — the order
## state the player is about to act on. The class is the tile-cost vocabulary the
## terrain speaks, so naming it here is what lets the bar drop the move-cost row
## the old panel carried.
func _order_line(
	unit: Unit,
	carrying: String,
	waited: bool,
	allegiance: String,
	range_band: Vector2i,
	cover_stars: int,
	tile_stars: int
) -> String:
	var parts := PackedStringArray()
	# Whose it is, before what it is: with four armies on the board a colour alone
	# stopped answering "can I shoot that?", and the answer is the viewer's rather
	# than the tile's. Empty for the viewer's own units, which need no telling.
	if allegiance != "":
		parts.append(allegiance.to_upper())
	parts.append(String(CLASS_LABELS.get(unit.type.move_class, "")).to_upper())
	if range_band.x > 1:
		parts.append("RNG %d-%d" % [range_band.x, range_band.y])
	# The terrain chip still reads the tile's own stars, because the tile really
	# has them; this says the unit standing there does not get them.
	if cover_stars == 0 and tile_stars > 0:
		parts.append("NO COVER")
	if unit.dived:
		parts.append("DIVED")
	if unit.running_dry():
		parts.append("LOW FUEL")
	if carrying != "":
		parts.append("CARRYING %s" % carrying.to_upper())
	parts.append("WAITED" if waited else "READY")
	return " · ".join(parts)


func _show_terrain(terrain: TerrainType, owner_team: int, capture_left: int) -> void:
	var standing := terrain.is_property and ground != null
	_terrain_icon.texture = _terrain_texture(ground if standing else terrain, owner_team)
	_terrain_building.texture = _terrain_texture(terrain, owner_team) if standing else null
	_terrain_name.text = terrain.display_name.to_upper()
	var line := "DEF %s" % _stars(terrain.defense_stars)
	if terrain.is_property:
		line += " · %s" % identity.display_name(owner_team).to_upper()
	if capture_left >= 0:
		line += " · CAP %d" % capture_left
	_terrain_def.text = line


func _stars(count: int) -> String:
	if count <= 0:
		return "0"
	var filled := mini(count, MAX_DEFENSE_STARS)
	return "★".repeat(filled) + "☆".repeat(MAX_DEFENSE_STARS - filled)


## The same artwork the board draws: one cell of the terrain atlas, in the
## owner's resolved faction row (rows 1+ exist only when team_tinted). The atlas
## and its cell size are asked of BattleView, which owns them, rather than
## mirrored here — a mirror is how a bar comes to draw a cell the board has moved.
func _terrain_texture(terrain: TerrainType, owner_team: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = load(BattleView.ATLAS_PATH)
	var row: int = identity.atlas_row(owner_team) if terrain.team_tinted else 0
	var px := BattleView.TERRAIN_PX
	atlas.region = Rect2(terrain.atlas_col * px, row * px, px, px)
	return atlas
