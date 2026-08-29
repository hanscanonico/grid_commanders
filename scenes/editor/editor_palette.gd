class_name EditorPalette
extends PanelContainer
## The brush: every terrain the `TerrainDB` holds, each row wearing the art the
## board will paint with it and the name the game calls it.
##
## Built from the database rather than listed, so a terrain added under
## `data/terrain/` is in the author's hand the moment the file exists — the same
## reason the build menu asks `TerrainType.builds` instead of naming a factory.
## A row's swatch is one cell of a board rather than a hand-cut atlas region: a
## property column ships as a transparent overlay, and `MapThumbnail` is already
## the one thing that knows to stand it on its ground.

signal picked(terrain: TerrainType)

## A swatch is one board cell, shown at the size the HUD shows a tile at.
const SWATCH := UiTheme.HUD_TILE_ICON
## Two pixels of plate above and below the swatch.
const ROW_HEIGHT := SWATCH + 4
## A row's words from its plate's edges.
const ROW_INSET := 3

var _terrains: Array[TerrainType] = []
var _buttons: Array[Button] = []
var _labels: Array[Label] = []
var _selected := 0


## Ground first, then the properties, each group by name: a board is laid down
## as a surface and the buildings are put on it, which is the order it is painted
## in. One order, stated here, so the palette a test reads is the palette the
## page shows.
static func ordering(db: TerrainDB) -> Array[TerrainType]:
	var terrains := db.all()
	terrains.sort_custom(
		func(a: TerrainType, b: TerrainType) -> bool:
			if a.is_property != b.is_property:
				return b.is_property
			return a.display_name < b.display_name
	)
	return terrains


## Stocks the palette from the database and selects its first brush.
func configure(db: TerrainDB) -> void:
	_terrains = ordering(db)
	add_theme_stylebox_override("panel", UiTheme.dark_panel_box())

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	add_child(col)

	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", UiTheme.header_box(UiTheme.SLATE_700))
	var heading := UiKit.micro_label("Terrain")
	heading.add_theme_color_override("font_color", UiTheme.WHITE)
	header.add_child(heading)
	col.add_child(header)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 1)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in _terrains.size():
		rows.add_child(_build_row(i, db))
	var frame := UiKit.vscroll()
	frame.add_child(rows)
	# A scrolling frame asks for no height of its own, so the list takes the
	# column's slack explicitly or the palette lays out as a bare panel.
	var padded := UiKit.pad(frame, ROW_INSET, ROW_INSET)
	padded.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(padded)
	_restyle()


## The brush in hand.
func selected() -> TerrainType:
	return _terrains[_selected] if _selected < _terrains.size() else null


## Puts a brush in hand from outside a press — the keyboard's route through the
## palette, and how the page opens on a brush at all.
func select(index: int) -> void:
	if index < 0 or index >= _terrains.size():
		return
	_selected = index
	_restyle()
	picked.emit(_terrains[_selected])


func _build_row(index: int, db: TerrainDB) -> Button:
	var terrain := _terrains[index]
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	button.tooltip_text = terrain.display_name
	button.pressed.connect(func() -> void: select(index))
	var face := ListRow.face(ROW_INSET)
	face.add_child(_swatch(terrain, db))
	var label := ListRow.cell(terrain.display_name.to_upper(), UiTheme.WHITE)
	face.add_child(label)
	button.add_child(face)
	UiKit.touchable(button)
	_buttons.append(button)
	_labels.append(label)
	return button


## One cell of a board holding nothing but this terrain, drawn by the renderer
## the board itself draws through.
func _swatch(terrain: TerrainType, db: TerrainDB) -> Control:
	var swatch := MapThumbnail.new()
	swatch.setup(
		MapData.parse("[terrain]\n%s\n" % terrain.symbol, db),
		UiTheme.menu_identity(),
		Vector2(SWATCH, SWATCH)
	)
	return swatch


## The selected row wears the cream plate every chosen thing in this game wears;
## the rest are ghosts.
func _restyle() -> void:
	for i in _buttons.size():
		var chosen := i == _selected
		var variant := UiTheme.ButtonVariant.SECONDARY if chosen else UiTheme.ButtonVariant.GHOST
		UiTheme.apply_button(_buttons[i], variant, null, UiTheme.SIZE_BUTTON)
		_labels[i].add_theme_color_override("font_color", UiTheme.INK if chosen else UiTheme.WHITE)
