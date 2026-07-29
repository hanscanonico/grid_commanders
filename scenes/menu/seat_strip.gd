class_name SeatStrip
extends VBoxContainer
## Who sits at the table and who stands with whom (COM-48, four-players plan D6).
##
## One row per seat the board deals — a Human/CPU choice and a side badge — plus
## the one-tap groupings on a board that seats four. It replaces the two mode
## buttons the menu used to be able to express a match with, which between them
## said only "one of you" or "two of you" and nothing at all about sides.
##
## How many rows there are is the **board's** answer and how they group is the
## **match's** (plan D1), so this takes a roster and hands back two facts:
## `ai_teams()` and `sides()`. It decides neither of them for itself and knows
## nothing about maps, saves or launching.
##
## The defaults are the old one-click paths: seat 1 human, every other seat the
## computer's, and every army its own side. A duel therefore sets up in exactly
## the clicks it always did — the strip is something to ignore until you want it.

signal changed

## Side badges, in the order a seat cycles through them. Letters rather than
## faction names because a side is a grouping and not a livery: two armies on
## side A each keep their own colours (plan D5).
const SIDE_LABELS: Array[String] = ["A", "B", "C", "D"]
## The grouping presets, as the side each seat takes. Offered only on a board
## that seats four, because they are the only rosters where more than one
## grouping exists — three armies can be a free-for-all or a 2v1, which the
## badges already express in one tap.
const PRESETS: Array[Dictionary] = [
	{"label": "Free-for-all", "sides": [0, 1, 2, 3], "help": "Every army for itself"},
	{"label": "2v2", "sides": [0, 1, 0, 1], "help": "Seats 1+3 against 2+4"},
	{"label": "3v1", "sides": [0, 0, 0, 1], "help": "Seats 1+2+3 against 4"},
]

var _seats: Array[int] = []
## Per seat, parallel to `_seats`: whether a person plays it, and which side it
## stands on (an index into SIDE_LABELS).
var _human: Array[bool] = []
var _side: Array[int] = []
var _rows: GridContainer
var _presets: HBoxContainer
## Per seat, parallel to `_seats`: how to repaint that row's two segments without
## rebuilding the strip. A rebuild frees the very button whose `pressed` is
## running — which on a preset press left a keyboard player with no focus owner —
## so every in-place change repaints through these instead.
var _human_restyle: Array[Callable] = []
var _side_restyle: Array[Callable] = []
var _accent: Color = Color.WHITE
var _style_segment: Callable
var _micro_label: Callable


## Wires the strip to the menu's own segment styling, so a seat button looks
## exactly like a difficulty button and this file defines no colours of its own.
func configure(accent: Color, style_segment: Callable, micro: Callable) -> void:
	_accent = accent
	_style_segment = style_segment
	_micro_label = micro


## Deals the strip for a board that seats `count` armies, keeping each seat's
## choices where they still exist. Called whenever the selected map changes,
## which is the only thing that can change how many seats there are.
func set_roster(count: int) -> void:
	var seats: Array[int] = []
	for i in count:
		seats.append(i + 1)
	if seats == _seats:
		return
	_seats = seats
	while _human.size() < count:
		# Seat 1 is the player, everyone after it the computer: the old "1 Player
		# VS AI" default, which is what keeps a duel a one-click set-up.
		_human.append(_human.is_empty())
		_side.append(_side.size())
	_human.resize(count)
	_side = normalised_sides(_side, count)
	_rebuild()


## The seats the computer plays, in seat order — what `MatchRequest.ai_teams`
## takes.
func ai_teams() -> Array[int]:
	var computers: Array[int] = []
	for i in _seats.size():
		if not _human[i]:
			computers.append(_seats[i])
	return computers


## team -> side id, or **empty for a free-for-all**. Empty rather than one side
## per army on purpose: that is what `GameState.allied` reads as "every army its
## own side", and it is the value every match had before groupings existed, so a
## free-for-all stages byte-identically to a match set up before this strip.
func sides() -> Dictionary:
	var grouped: Dictionary = {}
	for i in _seats.size():
		grouped[_seats[i]] = _side[i]
	return {} if _distinct_sides() == _seats.size() else grouped


## Whether the strip describes a match that can be played: somebody has to be
## opposed. Everyone on one side is a board with nobody to fight, which the sim
## would resolve as an immediate victory.
func valid() -> bool:
	return _seats.size() >= 2 and _distinct_sides() >= 2


## Why the strip is refusing, or "" when it is not. Shown rather than silently
## disabling Start, because a greyed control with no reason is the affordance
## this menu has already been burned by once (COM-19).
func refusal() -> String:
	if valid():
		return ""
	return "Give at least two sides somebody to fight"


## How many seats the board dealt.
func seat_count() -> int:
	return _seats.size()


## Seats or unseats a person at `index`. Public because the setup-context capture
## walks the table rather than photographing one arrangement of it — the same
## reason the difficulty rule is asked of the seats and not of a mode flag.
func set_human(index: int, human: bool) -> void:
	if index < 0 or index >= _human.size():
		return
	_human[index] = human
	if index < _human_restyle.size():
		_human_restyle[index].call(0 if human else 1)
	changed.emit()


## Applies PRESETS[index]. Public for the dev capture that photographs the strip
## in each grouping; the preset buttons call the same path.
func apply_preset_at(index: int) -> void:
	if index < 0 or index >= PRESETS.size():
		return
	_apply_preset(PRESETS[index]["sides"])


## The sides `count` seats stand on once the roster has changed under them: the
## surviving values re-packed into a dense 0..n-1 range, falling back to the
## default — every army its own side — when what is left has nobody to fight.
##
## Shrinking a roster is why both halves exist, and clamping to a constant
## answered neither: the first three seats of a 3v1 leave a duel with both armies
## on side A, where Start greys with "give at least two sides somebody to fight"
## on an ordinary two-army board, and a seat left on side C leaves a badge row of
## two with nothing selected, because a row draws as many badges as the board
## seats. Static and pure so that path is checkable without a scene, on the terms
## `MatchRequest` and `TransitionInput` are (CLAUDE.md, Testing).
static func normalised_sides(sides_in: Array[int], count: int) -> Array[int]:
	var packed: Dictionary = {}
	var settled: Array[int] = []
	for i in count:
		var stood_on: int = sides_in[i] if i < sides_in.size() else i
		if not packed.has(stood_on):
			packed[stood_on] = packed.size()
		settled.append(int(packed[stood_on]))
	if count >= 2 and packed.size() < 2:
		settled.clear()
		for i in count:
			settled.append(i)
	return settled


func _distinct_sides() -> int:
	var seen: Dictionary = {}
	for i in _seats.size():
		seen[_side[i]] = true
	return seen.size()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_human_restyle.clear()
	_side_restyle.clear()
	add_theme_constant_override("separation", 3)
	# Two seats to a line: a duel is one row, the height the panel already had, and
	# a four-army board costs one extra line rather than three. The setup panel
	# fits a fixed frame and refuses to overflow it (`_chrome`), so the strip has
	# to earn its space.
	_rows = GridContainer.new()
	_rows.columns = 2
	_rows.add_theme_constant_override("h_separation", 8)
	_rows.add_theme_constant_override("v_separation", 3)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_rows)
	for i in _seats.size():
		_rows.add_child(_seat_row(i))
	_presets = HBoxContainer.new()
	_presets.add_theme_constant_override("separation", 4)
	add_child(_presets)
	_refresh_presets()


## One seat on one line: a label, who plays it, and which side it stands on.
##
## Built here rather than through the panel's `_build_segment` because that one
## stacks a caption above every control, and four of those do not fit the panel's
## fixed height. Only the *styling* is borrowed, so a seat button still looks
## exactly like a difficulty button.
func _seat_row(index: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label: Label = _micro_label.call("P%d" % _seats[index])
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)
	row.add_child(
		_segment(
			PackedStringArray(["Human", "CPU"]),
			0 if _human[index] else 1,
			func(choice: int) -> void: _set_human(index, choice == 0),
			_human_restyle
		)
	)
	var badges := PackedStringArray()
	for label: String in SIDE_LABELS.slice(0, maxi(2, _seats.size())):
		badges.append(label)
	row.add_child(
		_segment(
			badges, _side[index], func(choice: int) -> void: _set_side(index, choice), _side_restyle
		)
	)
	return row


## A run of joined toggle buttons, styled by the panel so it matches every other
## segmented control on the screen. `restyle_sink` collects the callable that
## moves the highlight, so a change made anywhere else — a preset, the capture
## pose — repaints this run rather than rebuilding the strip around it.
func _segment(
	labels: PackedStringArray,
	selected: int,
	on_select: Callable,
	restyle_sink: Array[Callable] = []
) -> Control:
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var run := HBoxContainer.new()
	run.add_theme_constant_override("separation", 0)
	frame.add_child(run)
	var buttons: Array[Button] = []
	for i in labels.size():
		var seg := Button.new()
		seg.text = labels[i]
		seg.toggle_mode = true
		seg.clip_text = true
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.custom_minimum_size = Vector2(0, 16)
		seg.add_theme_font_override("font", UiTheme.display())
		seg.add_theme_font_size_override("font_size", UiTheme.SIZE_SEGMENT)
		run.add_child(seg)
		buttons.append(seg)
	var restyle := func(index: int) -> void:
		for i in buttons.size():
			_style_segment.call(buttons[i], i == index, i > 0, _accent)
	restyle.call(selected)
	restyle_sink.append(restyle)
	for i in labels.size():
		buttons[i].pressed.connect(
			func() -> void:
				restyle.call(i)
				on_select.call(i)
		)
	return frame


func _refresh_presets() -> void:
	for child in _presets.get_children():
		_presets.remove_child(child)
		child.queue_free()
	# Only a four-seat board has more than one grouping worth a shortcut.
	if _seats.size() < 4:
		return
	var caption: Label = _micro_label.call("GROUPING")
	_presets.add_child(caption)
	for preset: Dictionary in PRESETS:
		var button := Button.new()
		button.text = String(preset["label"])
		button.add_theme_font_size_override("font_size", 9)
		button.tooltip_text = String(preset["help"])
		var pattern: Array = preset["sides"]
		button.pressed.connect(func() -> void: _apply_preset(pattern))
		_presets.add_child(button)


## Repaints in place rather than rebuilding: a preset is applied from the `pressed`
## of one of the strip's own buttons, and freeing that button mid-signal releases
## focus with nothing to give it back to — a keyboard or gamepad player pressing
## "2v2" was left with no focus owner at all.
func _apply_preset(pattern: Array) -> void:
	for i in mini(_side.size(), pattern.size()):
		_side[i] = int(pattern[i])
	for i in mini(_side_restyle.size(), _side.size()):
		_side_restyle[i].call(_side[i])
	changed.emit()


func _set_human(index: int, human: bool) -> void:
	_human[index] = human
	changed.emit()


func _set_side(index: int, side: int) -> void:
	_side[index] = side
	changed.emit()
