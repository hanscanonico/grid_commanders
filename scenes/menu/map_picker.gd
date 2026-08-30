class_name MapPicker
extends VBoxContainer
## The map picker: a scrollable four-up grid of live board thumbnails, the whole
## roster with its teaching board first (MapCatalog.ordered) — the dropdown is
## gone (MN2). The selected cell gets the raised cream surface, the meridian
## border and a ✓; scroll follows keyboard focus so every board is reachable
## without a mouse. A static caption beneath the viewport carries the
## decision-critical facts; each cell keeps the richer tooltip as optional detail.
##
## The boards the player drew themselves come after the shipped roster, badged
## Custom and otherwise ordinary cells: the same live thumbnail, the same
## selection, the same launch — a user map is a map file like any other, so
## nothing downstream of here learns where it came from. The Manage map link
## beside the caption is the one control they add, and it is up only while one of
## them is the board in hand — so a machine with none lays out as it did before.
## Behind it are rename, duplicate and delete, none of which decides anything:
## `UserMaps` owns which name is free, what a copy is called, and whether a
## rename may happen at all.
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
## The gap between cells, in both axes.
const GRID_GAP := 8
## How many boards a shelf row holds. Four rather than three since the setup panel
## grew its section headers: a shorter cell four-up shows six boards in the same
## viewport three-up showed four and a half, so the roster reads further down for
## less of the panel's fixed height.
const GRID_COLUMNS := 4
## The picker card's frame inset, read by its stylebox and by the content over it.
const CARD_PAD := 4
## A cell's picture. Every cell is this size — the Random cell draws a die in it —
## so the grid's rows and gutters are one shape whichever cell is in them.
const THUMB := Vector2(81.0 - 2 * CARD_PAD, 40)
## The Random cell's die: one pip, the air between two of them, and the frame's
## inset. Sized so the whole face lands well inside a cell's picture slot.
const DIE_PIP := 4
const DIE_PIP_GAP := 3
const DIE_PAD := 3
## Which of the 3x3 pip cells are inked — the five face, read left to right and
## top to bottom.
const DIE_FACE: Array[int] = [0, 2, 4, 6, 8]
## The layer the delete confirmation is drawn on. Its own canvas rather than a
## control in this column: the prompt covers the whole menu, and a full-screen
## page parented inside a panel row would be laid out by that row and drawn under
## the rows after it.
const CONFIRM_LAYER := 10
## Its two buttons, at a page footer's width rather than a menu stack's: they sit
## side by side, so neither may take the column.
const CONFIRM_BUTTON_W := 120
## The manage page's four, which stand in one row and so are narrower — the width
## of its longest word, `Duplicate`, and no more.
const MANAGE_BUTTON_W := 84

## The panel's header-right "name · size". Built here and parented by the setup
## panel's title bar, so the words and the label that sets them stay together.
var _map_header: Label
var _map_caption: Label
var _map_scroll: ScrollContainer
var _map_cells: Array[Button] = []
var _map_marks: Array[Label] = []
## The roll. Deliberately outside `_map_cells`, so the cell arrays stay aligned
## to `_maps` and nothing that walks the roster has to skip it: Random is an
## action that resolves to a board, never a selection state of its own.
var _random_cell: Button
var _rng := RandomNumberGenerator.new()
var _selected_map := 0
## The roster in menu order, parsed once so the tooltips, the header and the
## caption quote real numbers off the board rather than a hand-kept table.
var _maps: Array[MapData] = []
## The cells' container, kept because deleting a user map re-deals the shelf.
var _grid: GridContainer
## Kept for the same reason: a shelf re-read after a delete is re-parsed, and the
## databases are the menu's rather than this widget's.
var _terrain_db: TerrainDB
## The delete confirmation, or null while none is up.
var _confirm: CanvasLayer
## Its page, which is what a cancel press is asked about.
var _confirm_page: Control
## The way to Rename, Duplicate and Delete — up only while a board the player
## drew is in hand, since none of the three may be done to a shipped board.
var _manage_link: Button


## Parses the roster and draws the widget. Called before the picker is in the
## tree, like every other code-built control here; `reserve_caption` is the one
## measurement that has to wait for the tree.
func configure(db: TerrainDB) -> void:
	_terrain_db = db
	_maps = _roster()
	add_theme_constant_override("separation", 3)
	add_child(UiKit.section_header("Map"))

	_map_header = Label.new()
	_map_header.add_theme_font_override("font", UiTheme.stat())
	_map_header.add_theme_font_size_override("font_size", UiTheme.SIZE_STAT)
	_map_header.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	_map_header.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_map_scroll = ScrollContainer.new()
	# 126 before the seat strip took its lines of the panel's fixed height, and 80
	# before COM-254 measured it against what the picker shows. COM-258 gave the
	# ground back the other way: choosing a board is what this page is for, so the
	# viewport is a whole row of cells and half of the next, which is the shape
	# that says out loud there is more roster below. It is still the one control
	# here that scrolls by design, so it is still the one that gives ground when
	# the panel runs out of height.
	_map_scroll.custom_minimum_size = Vector2(0, 1.5 * _cell_height())
	_map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_map_scroll)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", GRID_GAP)
	_grid.add_theme_constant_override("v_separation", GRID_GAP)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_scroll.add_child(_grid)

	_fill_grid()
	_map_caption = UiKit.help_label("")
	_map_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_caption.max_lines_visible = MAP_CAPTION_LINES
	_map_caption.add_theme_constant_override("line_spacing", 1)

	# The link shares the caption's line rather than standing on a cell: a cell is
	# a picture of a board and the caption is where this picker talks about the
	# board in hand. It is hidden for every shipped board, and a hidden control
	# takes no space in a container — so a machine with no boards of its own lays
	# this row out exactly as it did before. One link and not three: links share
	# the caption's width, so a second would cost that caption a line on some
	# board, which is the COM-5 class again — a layout budget that depends on the
	# selection. The three actions live on the page it opens.
	var facts := HBoxContainer.new()
	facts.add_theme_constant_override("separation", UiTheme.GAP)
	facts.add_child(_map_caption)
	_manage_link = UiKit.text_link("Manage map")
	_manage_link.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_manage_link.pressed.connect(_ask_manage)
	UiKit.touchable(_manage_link)
	facts.add_child(_manage_link)
	add_child(facts)
	select(0)


## The shelf: the shipped roster in menu order, then the boards this player drew.
## A user map that will not parse, or that parses into a board nobody could play,
## is dropped with a pushed error rather than taking the menu down — the rule
## `MapCatalog.ordered` holds for a shipped board, one step further on, because
## a file in `user://maps` was written by a player and can be edited by hand.
func _roster() -> Array[MapData]:
	var maps := MapCatalog.ordered(_terrain_db)
	for name in UserMaps.list():
		var map := UserMaps.load_map(name, _terrain_db)
		if map == null:
			continue
		var errors := MapValidator.errors(map)
		if errors.is_empty():
			maps.append(map)
		else:
			push_error("map picker: '%s' is not playable — %s" % [name, errors[0]])
	return maps


## The cells for the shelf in hand: the roll first, then a cell per board.
func _fill_grid() -> void:
	if _maps.is_empty():
		push_error("map picker: no maps found in %s" % MapCatalog.MAPS_DIR)
	_random_cell = _make_random_cell()
	_grid.add_child(_random_cell)
	for i in _maps.size():
		_grid.add_child(_make_map_cell(i, _maps[i]))


## The title bar's half of the picker, handed over for the setup panel to parent.
func header_label() -> Label:
	return _map_header


## The roster, in the order the cells are in.
func maps() -> Array[MapData]:
	return _maps


## The largest board on the shelf — what the menu bakes its drifting backdrop
## from. Measured rather than read off the end of the roster: the boards the
## player drew come after the shipped ones, whatever size they are.
static func fullest(maps_on_shelf: Array[MapData]) -> MapData:
	var largest: MapData = null
	for map in maps_on_shelf:
		if largest == null or map.width * map.height > largest.width * largest.height:
			largest = map
	return largest


func _map_at(index: int) -> MapData:
	if index < 0 or index >= _maps.size():
		return null
	return _maps[index]


func selected_map() -> MapData:
	return _map_at(_selected_map)


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
	_refresh_facts()
	map_selected.emit(index)


## Selects a board and waits for the picker to settle on it: the scroll into view
## needs a laid-out tree, so a capture taken on the same frame photographs the
## board the shelf was showing before, and a shelf just re-dealt scrolls to where
## the old one stood. The dev captures and `_reload` are its two callers.
func show_map(index: int) -> void:
	select(index)
	await get_tree().process_frame
	if _selected_map < _map_cells.size():
		_map_scroll.ensure_control_visible(_map_cells[_selected_map])
	await get_tree().process_frame


## Header and persistent caption, read off the board itself so no hand-kept table
## can drift from it. Tooltips repeat the facts but are never required to choose.
func _refresh_facts() -> void:
	var map := selected_map()
	_manage_link.visible = map != null and is_custom(map)
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


## Whether a board is one the player drew. A fact about where the file is:
## `MapCatalog.USER_DIR` is the one writable place a board can come from, so the
## badge, the Remove link and the delete itself read the same answer.
static func is_custom(map: MapData) -> bool:
	return map.source_path.begins_with(MapCatalog.USER_DIR)


## The name a cell wears: the ✓ the selected cell alone carries, then the board,
## its teaching or Custom badge and its army count past a duel.
##
## The tick leads rather than trails because a cell's label is clipped to the cell
## (`ListRow.clipped`) and the boards with the longest names are exactly the ones
## whose badge runs past the edge — a trailing tick was the first thing to go, on
## the one cell that has to carry it.
static func cell_name(map: MapData, selected: bool) -> String:
	var name_text := MapCatalog.display_name(map.source_path)
	if MapCatalog.teaches(map.source_path):
		name_text += " · Tutorial"
	elif is_custom(map):
		name_text += " · Custom"
	if map.player_count() > 2:
		name_text += " · %dP" % map.player_count()
	return "✓ " + name_text if selected else name_text


## The caption `_refresh_facts` shows for `map`, factored out so the budget check
## can measure every board without touching `_selected_map`.
static func caption_text(map: MapData) -> String:
	var parts := [
		map.width,
		map.height,
		armies_label(map.player_count()),
		map.property_cells().size(),
		map.description,
	]
	return "%d×%d · %s · %d properties · %s" % parts


## "4 armies" for a board whose seats all have to be filled, "2–4 armies" for one
## where some may close (open-seats plan D4). A range rather than a count because a
## count is what the board deals and the shelf's widest capability is what a player
## scrolling the list is choosing between.
static func armies_label(seats: int) -> String:
	if seats <= SeatStrip.MIN_FILLED:
		return "%d armies" % seats
	return "%d–%d armies" % [SeatStrip.MIN_FILLED, seats]


## The board Random lands on: any in the roster but the teaching one, which a
## player asking for a surprise is not asking for, and but the one already in
## hand, which would read as a dead press. A pool that empties under both falls
## back to the whole roster, so a one-board install still rolls something.
static func random_index(maps: Array[MapData], current: int, rng: RandomNumberGenerator) -> int:
	var pool: Array[int] = []
	for i in maps.size():
		if i != current and not MapCatalog.teaches(maps[i].source_path):
			pool.append(i)
	if pool.is_empty():
		for i in maps.size():
			pool.append(i)
	if pool.is_empty():
		return -1
	return pool[rng.randi_range(0, pool.size() - 1)]


# --- cells -------------------------------------------------------------------


## A cell's height: its picture, the frame around it and the board's name beneath.
## Asked of the font rather than typed in, so the viewport's row and a half stays
## a row and a half if the face changes.
func _cell_height() -> float:
	return THUMB.y + 2 * CARD_PAD + UiTheme.display().get_height(UiTheme.SIZE_BODY) + 1


## One picker cell: a focusable button holding a live thumbnail and the board's
## name, and as tall as the two of them plus the frame, so a square board's
## picture no longer crosses it. The thumbnail is a truthful miniature — real
## terrain, real property colours — of the board this cell launches (plan D5).
func _make_map_cell(index: int, map: MapData) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(THUMB.x + 2 * CARD_PAD, _cell_height())
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

	# Clipped, because the name is the player's to choose: a board they called
	# something long would otherwise set its label at full width and paint straight
	# across the cells beside it. The header and the facts caption under the grid
	# still carry the whole name.
	var name_label := ListRow.clipped(Label.new())
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


## The roll's cell: the grid's first, so it is reachable without scrolling the
## viewport, and wearing the unselected cell's frame — it is never ticked,
## because pressing it leaves a real board selected.
##
## Laid out as every other cell is — a picture over a name on the same line — so
## the grid's first row is three pictures and three names rather than two of each
## and an empty outline. The picture is the die below, because the one thing this
## cell cannot show is a board.
func _make_random_cell() -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(THUMB.x + 2 * CARD_PAD, _cell_height())
	Tooltip.attach(
		button,
		"Picks a board for you.",
		"Any board but the tutorial and the one in hand",
		Tooltip.Side.BOTTOM
	)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 1)
	content.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, CARD_PAD
	)
	button.add_child(content)

	var die := _die_face()
	die.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(die)

	var label := Label.new()
	label.text = "Random"
	label.add_theme_font_override("font", UiTheme.display())
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	label.add_theme_color_override("font_color", UiTheme.INK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(label)
	UiTheme.make_decoration(content)

	# A soft outline rather than the selection's meridian one: a map cell reads as
	# a cell because it holds a picture and this one holds a word, so it needs a
	# frame to read as pressable — and it may never read as the board in hand.
	var box := _map_cell_box(Color(0, 0, 0, 0))
	box.border_color = UiTheme.BORDER_SOFT
	box.set_border_width_all(UiTheme.BORDER)
	button.add_theme_stylebox_override("normal", box)
	var hover := _map_cell_box(UiTheme.HOVER_WASH)
	hover.border_color = UiTheme.BORDER_SOFT
	hover.set_border_width_all(UiTheme.BORDER)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", box)
	button.add_theme_stylebox_override("focus", UiTheme.focus_box())
	# On press alone: a map cell selects on focus so the keyboard can preview the
	# roster, and a roll on focus would draw a new board on every arrow pass.
	button.pressed.connect(_roll_map)
	return button


## The roll's picture: a five-pip die face, built out of the shell's own boxes
## rather than drawn or typed as a glyph — the vendored faces carry no die
## character, and a `_draw` for one shape would be a whole class the picker is the
## only caller of.
func _die_face() -> Control:
	var centre := CenterContainer.new()
	var frame := PanelContainer.new()
	var box := UiTheme.bordered(UiTheme.PAPER, UiTheme.CONTROL_ACCENT, UiTheme.BORDER)
	box.set_corner_radius_all(UiTheme.RADIUS)
	box.set_content_margin_all(DIE_PAD)
	frame.add_theme_stylebox_override("panel", box)
	var pips := GridContainer.new()
	pips.columns = 3
	pips.add_theme_constant_override("h_separation", DIE_PIP_GAP)
	pips.add_theme_constant_override("v_separation", DIE_PIP_GAP)
	for cell in 9:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(DIE_PIP, DIE_PIP)
		if DIE_FACE.has(cell):
			pip.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.CONTROL_ACCENT))
		else:
			pip.add_theme_stylebox_override("panel", UiTheme.flat(Color(0, 0, 0, 0)))
		pips.add_child(pip)
	frame.add_child(pips)
	centre.add_child(frame)
	return centre


func _roll_map() -> void:
	select(random_index(_maps, _selected_map, _rng))


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


# --- the player's own boards -------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if _confirm_page != null and TransitionInput.dismissed_by_cancel(_confirm_page, event):
		_close_confirm()


## The confirmation: the board named, what deleting it costs, and the two ways
## out. A file the player painted is gone for good once it is off the disk, which
## is the one thing this page has to say before it does that.
func _ask_remove() -> void:
	var map := selected_map()
	if map == null or not is_custom(map):
		return
	var body := _open_page(
		"Delete %s?" % MapCatalog.display_name(map.source_path),
		"The map file is removed from this machine for good."
	)
	if body == null:
		return
	var remove := UiKit.action_button(
		"Delete", "", UiTheme.ButtonVariant.PRIMARY, null, CONFIRM_BUTTON_W
	)
	remove.pressed.connect(_remove.bind(map))
	body.add_child(_actions([remove], "Keep", CONFIRM_BUTTON_W))


## Everything that may be done to a board the player drew: rename it, take a copy
## of it, or delete it. `UserMaps` decides all three — the page types a name and
## reports what it is told, and a refused rename leaves the page open on the name
## that failed, exactly as the editor's save dialog does.
func _ask_manage() -> void:
	var map := selected_map()
	if map == null or not is_custom(map):
		return
	var body := _open_page(
		MapCatalog.display_name(map.source_path).to_upper(),
		"The name is the file's, and what --map= calls this board."
	)
	if body == null:
		return
	var field := UiKit.text_field("Name", UserMaps.MAX_NAME_LENGTH, CONFIRM_BUTTON_W)
	field.text = _user_name_of(map)
	field.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(field)
	var notice := UiKit.page_note("")
	notice.add_theme_color_override("font_color", UiTheme.DANGER)
	body.add_child(notice)

	var rename_now := func() -> void: _rename(map, field.text, notice)
	field.text_submitted.connect(func(_text: String) -> void: rename_now.call())
	var rename_button := UiKit.action_button(
		"Rename", "", UiTheme.ButtonVariant.PRIMARY, null, MANAGE_BUTTON_W
	)
	rename_button.pressed.connect(rename_now)

	var copy := UiKit.action_button(
		"Duplicate", "", UiTheme.ButtonVariant.SECONDARY, null, MANAGE_BUTTON_W
	)
	copy.pressed.connect(_duplicate)
	var remove := UiKit.action_button(
		"Delete", "", UiTheme.ButtonVariant.SECONDARY, null, MANAGE_BUTTON_W
	)
	remove.pressed.connect(
		func() -> void:
			_close_confirm()
			_ask_remove()
	)
	body.add_child(_actions([rename_button, copy, remove], "Close", MANAGE_BUTTON_W))
	# After the footer's own deferred grab, so the page opens on the name rather
	# than on the way out — this is the one page that is typed into.
	field.grab_focus.call_deferred()


func _rename(map: MapData, wanted: String, notice: Label) -> void:
	var error := UserMaps.rename(_user_name_of(map), wanted)
	if error != "":
		notice.text = error
		return
	_close_confirm()
	await _reload_on(UserMaps.slug(wanted))


## A second copy of the board in hand, under a free name of its own, and the
## selection lands on it — a duplicate is made to be drawn on, so the board the
## player then opens in the editor is the copy rather than the original.
func _duplicate() -> void:
	var map := selected_map()
	if map == null or not is_custom(map):
		return
	var copy := UserMaps.copy_name(_user_name_of(map))
	var error := UserMaps.copy_to(_user_name_of(map), copy)
	_close_confirm()
	if error != "":
		push_error("map picker: %s" % error)
		return
	await _reload_on(copy)


func _remove(map: MapData) -> void:
	_close_confirm()
	var error := UserMaps.delete(_user_name_of(map))
	if error != "":
		push_error("map picker: %s" % error)
	await _reload()


## The page every one of the three actions opens on, or null while one is
## already up. Its own canvas layer for the reason CONFIRM_LAYER names.
func _open_page(title: String, note: String) -> VBoxContainer:
	if _confirm != null:
		return null
	_confirm = CanvasLayer.new()
	_confirm.layer = CONFIRM_LAYER
	add_child(_confirm)
	_confirm_page = Control.new()
	_confirm_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(_confirm_page)
	UiKit.page_veil(_confirm_page)
	var body := UiKit.page_body(_confirm_page, UiTheme.GAP)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(UiKit.page_title(title))
	body.add_child(UiKit.page_note(note))
	return body


## The page's footer: the actions it was opened for, then the way out. The way out
## takes the focus, so a page opened by mistake is dismissed by the key already
## under the player's hand.
func _actions(buttons: Array[Button], cancel_text: String, width: int) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", UiTheme.GAP)
	for button in buttons:
		row.add_child(UiKit.touchable(button))
	var back := UiKit.action_button(cancel_text, "", UiTheme.ButtonVariant.GHOST, null, width)
	back.pressed.connect(_close_confirm)
	row.add_child(UiKit.touchable(back))
	back.grab_focus.call_deferred()
	return row


## The name a board the player drew is filed under — its own filename, which is
## what every `UserMaps` call takes.
static func _user_name_of(map: MapData) -> String:
	return map.source_path.get_file().trim_suffix(UserMaps.EXTENSION)


## Re-reads the shelf and lands on the board called `name`, or on where the
## selection was when the shelf no longer holds it.
func _reload_on(name: String) -> void:
	await _reload()
	for i in _maps.size():
		if _user_name_of(_maps[i]) == name:
			await show_map(i)
			return


func _close_confirm() -> void:
	if _confirm == null:
		return
	_confirm.queue_free()
	_confirm = null
	_confirm_page = null
	if _selected_map < _map_cells.size():
		_map_cells[_selected_map].grab_focus()


## Re-reads the shelf and re-deals the cells, the selection landing on the board
## that took the deleted one's place. The whole grid rather than the one cell:
## every cell after it has a new index, and a cell holding a stale one would
## select the wrong board.
func _reload() -> void:
	var wanted := _selected_map
	_maps = _roster()
	for cell in _grid.get_children():
		_grid.remove_child(cell)
		cell.queue_free()
	_map_cells.clear()
	_map_marks.clear()
	_fill_grid()
	# `show_map`'s wait, and for its reason: the fresh cells have no layout yet, so
	# a scroll asked for on this frame lands on where the old shelf was.
	await show_map(clampi(wanted, 0, _maps.size() - 1))
