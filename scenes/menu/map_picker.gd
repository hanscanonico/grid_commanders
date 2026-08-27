class_name MapPicker
extends VBoxContainer
## The map picker: a scrollable two-up grid of live board thumbnails, the whole
## roster with its teaching board first (MapCatalog.ordered) — the dropdown is
## gone (MN2). The selected cell gets the raised cream surface, the meridian
## border and a ✓; scroll follows keyboard focus so every board is reachable
## without a mouse. A static caption beneath the viewport carries the
## decision-critical facts; each cell keeps the richer tooltip as optional detail.
##
## Its own widget rather than the menu's (COM-38), the shape SeatStrip already is:
## the roster, the selection and every word read off it are one piece of state,
## and the menu asks it rather than keeping a second copy. What the picker says
## reaches the panel two ways — `header_label`, the title bar's "name · size",
## which the panel hosts and this class words; and `map_selected`, which is how
## the seat strip learns the board deals a different number of armies.

## The board in hand changed. How many seats there are is the board's answer
## (four-players D1), so the menu re-deals the strip off this rather than off
## anything the player set.
signal map_selected(index: int)

## Lines reserved for the selected board's caption. The words change with the
## selection; the height may not (UX-recovery D2), so the panel is as tall on the
## longest description as on the shortest.
const MAP_CAPTION_LINES := 2
## The picker card's frame inset, read by its stylebox and by the content over it.
const CARD_PAD := 4

## The panel's header-right "name · size". Built here and parented by the setup
## panel's title bar, so the words and the label that sets them stay together.
var _map_header: Label
var _map_caption: Label
var _map_scroll: ScrollContainer
var _map_cells: Array[Button] = []
var _map_marks: Array[Label] = []
var _selected_map := 0
## The roster in menu order, parsed once so the tooltips, the header and the
## caption quote real numbers off the board rather than a hand-kept table.
var _maps: Array[MapData] = []


## Parses the roster and draws the widget. Called before the picker is in the
## tree, like every other code-built control here; `reserve_caption` is the one
## measurement that has to wait for the tree.
func configure(db: TerrainDB) -> void:
	_maps = MapCatalog.ordered(db)
	add_theme_constant_override("separation", 3)
	add_child(UiKit.micro_label("Map"))

	_map_header = Label.new()
	_map_header.add_theme_font_override("font", UiTheme.stat())
	_map_header.add_theme_font_size_override("font_size", UiTheme.SIZE_STAT)
	_map_header.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	_map_header.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_map_scroll = ScrollContainer.new()
	# 126 before the seat strip took its lines of the panel's fixed height, and 80
	# before COM-254 measured it against what the picker shows: one whole cell and
	# its name. It is the one control here that scrolls by design, so it is the one
	# that gives ground — down to its own content, and no further.
	_map_scroll.custom_minimum_size = Vector2(0, 76)
	_map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_map_scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_scroll.add_child(grid)

	if _maps.is_empty():
		push_error("map picker: no maps found in %s" % MapCatalog.MAPS_DIR)
	for i in _maps.size():
		grid.add_child(_make_map_cell(i, _maps[i]))
	_map_caption = UiKit.help_label("")
	_map_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_caption.max_lines_visible = MAP_CAPTION_LINES
	_map_caption.add_theme_constant_override("line_spacing", 1)
	add_child(_map_caption)
	select(0)


## The title bar's half of the picker, handed over for the setup panel to parent.
func header_label() -> Label:
	return _map_header


## The roster, in the order the cells are in.
func maps() -> Array[MapData]:
	return _maps


func map_at(index: int) -> MapData:
	if index < 0 or index >= _maps.size():
		return null
	return _maps[index]


func selected_map() -> MapData:
	return map_at(_selected_map)


## The facts line under the grid. Named in the menu's capture chrome and read
## back by its setup-context gate, which checks the selection off the screen
## rather than off the state that drew it.
func caption() -> Label:
	return _map_caption


## Picks a board: repaints the cells (the selected one raised, red-bordered and
## ✓-marked), updates the header-right name·size, and scrolls the choice into
## view so keyboard focus never lands on an off-screen cell.
func select(index: int) -> void:
	if index < 0 or index >= _maps.size():
		return
	_selected_map = index
	for i in _map_cells.size():
		_style_map_cell(_map_cells[i], _map_marks[i], i, i == index)
	if index < _map_cells.size():
		_map_scroll.ensure_control_visible(_map_cells[index])
	refresh_facts()
	map_selected.emit(index)


## Dev captures only: selects a board and waits for the picker to settle on it.
## The picker scrolls the selection into view, which needs a laid-out tree — a
## capture on the same frame photographs the board it was showing before.
func show_map(index: int) -> void:
	select(index)
	await get_tree().process_frame
	if _selected_map < _map_cells.size():
		_map_scroll.ensure_control_visible(_map_cells[_selected_map])
	await get_tree().process_frame


## Header and persistent caption, read off the board itself so no hand-kept table
## can drift from it. Tooltips repeat the facts but are never required to choose.
func refresh_facts() -> void:
	var map := selected_map()
	if map == null:
		_map_header.text = ""
		_map_caption.text = ""
		return
	_map_header.text = (
		"%s · %d×%d" % [MapCatalog.display_name(map.source_path), map.width, map.height]
	)
	_map_caption.text = caption_text(map)


## Pins the caption's height to its reserved lines, asked of the label itself
## rather than typed in as a pixel count, so a font or spacing change carries the
## reservation with it. Called once the whole menu is in the tree: a Control
## resolves its fonts through the tree, so measured before that the label answers
## with the default theme's line height instead of its own.
func reserve_caption() -> void:
	var words := _map_caption.text
	_map_caption.text = "X\n".repeat(MAP_CAPTION_LINES - 1) + "X"
	_map_caption.custom_minimum_size = Vector2(0, _map_caption.get_combined_minimum_size().y)
	_map_caption.text = words


## No board may cost the panel a line the reserved caption does not have — the
## COM-5 class again, where the layout budget quietly depended on the selection.
## Measured on the live label's text alone; `_selected_map` and the seat strip
## the menu would otherwise re-deal per board (COM-48's capture workaround) stay
## put. Read back by MainMenu.setup_context_ready; a capture-driver seam.
func caption_budget_holds() -> bool:
	var passed := true
	var words := _map_caption.text
	for i in _maps.size():
		_map_caption.text = caption_text(_maps[i])
		if _map_caption.get_line_count() > MAP_CAPTION_LINES:
			push_error(
				(
					"main menu setup context: %s wraps its caption to %d lines"
					% [MapCatalog.display_name(_maps[i].source_path), _map_caption.get_line_count()]
				)
			)
			passed = false
	_map_caption.text = words
	return passed


# --- the words, without the widget -------------------------------------------


## The name a cell wears: the board, its teaching badge, its army count past a
## duel, and the ✓ the selected cell alone carries.
static func cell_name(map: MapData, selected: bool) -> String:
	var name_text := MapCatalog.display_name(map.source_path)
	if MapCatalog.teaches(map.source_path):
		name_text += " · Tutorial"
	if map.player_count() > 2:
		name_text += " · %dP" % map.player_count()
	if selected:
		name_text += " ✓"
	return name_text


## The caption `refresh_facts` shows for `map`, factored out so the budget check
## can measure every board without touching `_selected_map`.
static func caption_text(map: MapData) -> String:
	var parts := [
		map.width,
		map.height,
		armies_label(map.player_count()),
		map.property_cells().size(),
		map.description,
	]
	return ("%d×%d · %s · %d properties · %s" % parts).to_upper()


## "4 armies" for a board whose seats all have to be filled, "2–4 armies" for one
## where some may close (open-seats plan D4). A range rather than a count because a
## count is what the board deals and the shelf's widest capability is what a player
## scrolling the list is choosing between.
static func armies_label(seats: int) -> String:
	if seats <= SeatStrip.MIN_FILLED:
		return "%d armies" % seats
	return "%d–%d armies" % [SeatStrip.MIN_FILLED, seats]


# --- cells -------------------------------------------------------------------


## One picker cell: a focusable button holding a live thumbnail and the board's
## name, and as tall as the two of them plus the frame, so a square board's
## picture no longer crosses it. The thumbnail is a truthful miniature — real
## terrain, real property colours — of the board this cell launches (plan D5).
func _make_map_cell(index: int, map: MapData) -> Button:
	const THUMB := Vector2(132.0 - 2 * CARD_PAD, 60)
	var button := Button.new()
	var name_height := UiTheme.display().get_height(UiTheme.SIZE_BODY)
	button.custom_minimum_size = THUMB + Vector2(2 * CARD_PAD, 2 * CARD_PAD + name_height + 1)
	# The cell is a single control describing itself, so it is its own trigger —
	# the micro-label rule guards *group* controls, where hovering to reach a
	# segment would fire an explanation of the group.
	Tooltip.attach(
		button,
		map.description,
		"%d×%d · %d properties" % [map.width, map.height, map.property_cells().size()],
		Tooltip.Side.BOTTOM
	)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 1)
	content.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, CARD_PAD
	)
	button.add_child(content)

	var thumb := MapThumbnail.new()
	# The board's own roster, never the two-seat default: a four-army board's third
	# and fourth HQs resolve to no theme under a duel's identity and would draw
	# neutral grey, so the picker would show a duel where the match seats four.
	thumb.setup(map, UiTheme.menu_identity(map.player_count()), THUMB)
	thumb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(thumb)

	var name_label := Label.new()
	name_label.text = cell_name(map, false)
	name_label.add_theme_font_override("font", UiTheme.display())
	name_label.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	name_label.add_theme_color_override("font_color", UiTheme.INK)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(name_label)
	UiTheme.make_decoration(content)

	button.focus_entered.connect(select.bind(index))
	button.pressed.connect(select.bind(index))
	_map_cells.append(button)
	_map_marks.append(name_label)
	return button


func _style_map_cell(cell: Button, name_label: Label, index: int, selected: bool) -> void:
	var meridian := UiTheme.menu_identity().theme(1)
	var box := _map_cell_box(UiTheme.PAPER_RAISED if selected else Color(0, 0, 0, 0))
	if selected:
		box.border_color = meridian.color
		box.set_border_width_all(UiTheme.PANEL_BORDER)
		UiTheme.hard_shadow(box)
	cell.add_theme_stylebox_override("normal", box)
	var hover := box if selected else _map_cell_box(UiTheme.HOVER_WASH)
	cell.add_theme_stylebox_override("hover", hover)
	cell.add_theme_stylebox_override("pressed", box)
	cell.add_theme_stylebox_override("focus", UiTheme.focus_box())
	name_label.text = cell_name(_maps[index], selected)
	name_label.add_theme_color_override("font_color", UiTheme.INK if selected else UiTheme.NEUTRAL)


## The map picker cell's shared frame: a flat fill, a whisker of rounding and the
## grid's even inset. `_style_map_cell` layers a border and shadow on top when the
## cell is selected; the hover wash and the unselected rest state need neither.
func _map_cell_box(fill: Color) -> StyleBoxFlat:
	var box := UiTheme.flat(fill)
	box.set_corner_radius_all(UiTheme.RADIUS)
	box.set_content_margin_all(CARD_PAD)
	return box
