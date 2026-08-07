class_name MissionSpeech
extends RefCounted
## How a spoken mission line is drawn: the general's name in their faction's
## colour, above their words.
##
## One authority because two screens say the same thing — the briefing before a
## battle and the debrief after it — and a campaign whose two halves rendered
## dialogue differently would read as two different games. The name and the
## colour are asked of `CommanderDB` and `CommanderVisuals`, which already own
## them, so a line names a general exactly as every other surface does.

## The width a line is laid out in. Both callers are reading columns rather than
## banners, so the measure belongs here with the rest of the shape.
const WIDTH := 420


## One line, spoken or narrated, ready to add to a container.
static func render(line: MissionLine, commanders: CommanderDB) -> Control:
	if line.is_narration():
		return paragraph(line.text)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_name_of(line.speaker, commanders))
	box.add_child(paragraph(line.text))
	return box


## A block of body copy at the shared width — the narrator's voice, and what a
## speaker's words sit in.
static func paragraph(text: String, dim: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiTheme.display())
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	if dim:
		label.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(WIDTH, 0)
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return label


static func _name_of(speaker: StringName, commanders: CommanderDB) -> Label:
	var commander := commanders.by_id(speaker)
	var label := Label.new()
	label.text = commander.display_name.to_upper()
	label.add_theme_font_override("font", UiTheme.stat(true))
	label.add_theme_font_size_override("font_size", UiTheme.SIZE_MICRO)
	label.add_theme_color_override("font_color", CommanderVisuals.theme_for(commander).color)
	label.custom_minimum_size = Vector2(WIDTH, 0)
	return label
