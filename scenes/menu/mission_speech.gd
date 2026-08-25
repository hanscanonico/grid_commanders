class_name MissionSpeech
extends RefCounted
## How a spoken mission line is drawn: the general's bust in their faction's
## field, their name in their faction's colour, and their words beside them.
##
## One authority because four surfaces say the same thing — the briefing, the
## debrief, the interlude and the in-battle speech card — and a campaign whose
## halves rendered dialogue differently would read as two different games. The
## name, the colour and the portrait are asked of `CommanderDB` and
## `CommanderVisuals`, which already own them, so a line names a general exactly
## as every other surface does.

## The width a line is laid out in. Both callers are reading columns rather than
## banners, so the measure belongs here with the rest of the shape. A spoken
## line's bust and gap come out of the same measure, so a spoken block and a
## narrated paragraph read as one column.
const WIDTH := 420
## The square a speaker's bust is fitted into, beside their words.
const BUST := 28
const _BUST_GAP := 6


## One line, spoken or narrated, ready to add to a container.
static func render(line: MissionLine, commanders: CommanderDB) -> Control:
	if line.is_narration():
		return paragraph(line.text)
	var commander := commanders.by_id(line.speaker)
	var words_width := WIDTH - BUST - _BUST_GAP
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 0)
	copy.add_child(_name_of(commander, words_width))
	copy.add_child(paragraph(line.text, false, words_width))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _BUST_GAP)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(bust_of(commander))
	row.add_child(copy)
	return row


## A block of body copy at the shared width — the narrator's voice, and what a
## speaker's words sit in.
static func paragraph(text: String, dim: bool = false, width: int = WIDTH) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.display())
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	if dim:
		label.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(width, 0)
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return label


static func _name_of(commander: CommanderType, width: int) -> Label:
	var label := Label.new()
	label.text = commander.display_name.to_upper()
	label.add_theme_font_override("font", UiTheme.stat(true))
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_STAT)
	label.add_theme_color_override("font_color", CommanderVisuals.theme_for(commander).color)
	label.custom_minimum_size = Vector2(width, 0)
	return label


## The speaker's bust for a spoken line, at the column's scale by default and at
## whatever square a caller names. The shape is `UiKit.commander_bust`'s, which
## every surface that shows a commander shares; what is this column's is the
## darkened field, dim enough that the words beside it stay the brightest thing
## in the block.
static func bust_of(commander: CommanderType, square: int = BUST) -> Control:
	var tint := CommanderVisuals.theme_for(commander).color.darkened(0.6)
	var field := UiKit.commander_bust(commander, Vector2(square, square), tint)
	field.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return field
