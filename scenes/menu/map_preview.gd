class_name MapPreview
extends VBoxContainer
## A board shown properly: its picture over its name. The map step's preview and the
## Players step's reminder of which board the match is on.

## The column this stands in, and its picture.
const WIDTH := 126
const THUMB := Vector2(WIDTH, 90)
const NAME_LINES_MAX := 2

var _picture := MapThumbnail.new()
var _name := Label.new()


func _init() -> void:
	add_theme_constant_override("separation", 3)
	custom_minimum_size.x = WIDTH
	add_child(_picture)
	_name.add_theme_font_override("font", UiTheme.display(true))
	_name.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBTITLE)
	_name.add_theme_color_override("font_color", UiTheme.INK)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.max_lines_visible = NAME_LINES_MAX
	add_child(_name)


## Shows `map` on its own roster: a four-army board's third and fourth HQs resolve to
## no theme under a duel's identity and would draw neutral grey.
func show_board(map: MapData) -> void:
	_picture.setup(map, UiTheme.menu_identity(map.player_count()), THUMB)
	_name.text = MapCatalog.display_name(map.source_path)


func clear() -> void:
	_picture.setup(null, null, THUMB)
	_name.text = ""
