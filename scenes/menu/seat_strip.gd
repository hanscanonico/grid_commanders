class_name SeatStrip
extends VBoxContainer
## Who sits at the table and who stands with whom (COM-48, four-players plan D6).
##
## One row per seat the board deals — who plays it and a side badge — plus the
## one-tap groupings on a board that seats four. It replaces the two mode buttons
## the menu used to be able to express a match with, which between them said only
## "one of you" or "two of you" and nothing at all about sides.
##
## How many rows there are is the **board's** answer and how they group is the
## **match's** (plan D1), so this takes a roster and hands back three facts:
## `seats()`, `ai_teams()` and `sides()`. It decides none of them for itself and
## knows nothing about maps, saves or launching.
##
## A seat's third state is **Empty** (open-seats plan D4), and closing one is
## allowed only while at least two seats would stay filled — so a duel board's
## seats never close and neither do the last two of any board. The **rule** is that;
## its **presentation** is that every board builds the same row and greys what it
## refuses (COM-224). A control that appears and disappears with the board made the
## panel a different screen per map, and a dead button says "not on this board"
## where an absent one says nothing at all.
##
## The defaults are the old one-click paths: every seat open, seat 1 human, every
## other seat the computer's, and every army its own side. A duel therefore sets up
## in exactly the clicks it always did — the strip is something to ignore until you
## want it.

signal changed

## Who is in a seat. `EMPTY` is the seat nobody takes: the army never enters the
## match at all, so its start dissolves to neutral ground the others fight over.
enum Seat { HUMAN, CPU, EMPTY }

## The labels a seat cycles through, indexed by `Seat`.
const SEAT_LABELS: Array[String] = ["Human", "CPU", "Empty"]
## Side badges, in the order a seat cycles through them. Letters rather than
## faction names because a side is a grouping and not a livery: two armies on
## side A each keep their own colours (plan D5).
const SIDE_LABELS: Array[String] = ["A", "B", "C", "D"]
## The smallest table that is a match, which is also `GameState.MIN_SEATS` — the
## sim refuses a smaller one, and this is the menu never offering to build it.
const MIN_FILLED := GameState.MIN_SEATS
## The seat/side rows' segment-button height, against `UiKit.segment`'s default of
## 18: two rows share a line here where a stand-alone group gets one to itself, and
## the panel's height budget is real (`_seat_row`), so the strip is the one caller
## that asks for a row a size denser. Named because it is the one size this file
## does own — the colour and the widget shape both come from `UiKit` (`configure`
## and `_seat_row`).
const _SEAT_SEGMENT_HEIGHT := 16
## The roster every preset is written for. A smaller board can express only one of
## them, so there the row is built and dead rather than absent.
const PRESET_SEATS := 4
## The one-tap tables, each of them a seating *and* a grouping — the two facts a
## row would otherwise take four taps to say between them. Offered only on a board
## that seats four, because they are the only rosters where more than one of
## either exists: three armies can be a free-for-all or a 2v1, which the badges
## already express in one tap.
##
## `seats` is per seat and may be shorter than the board (nothing is closed past
## its end); `sides` is the grouping the filled seats stand in. Every preset
## carries both, so each button produces the table its tooltip promises whatever
## seating was in hand — "2v2" pressed after "Duel" is still four armies in two
## pairs, not two survivors packed onto one side. Duel fills the opposite-seat
## pair, which §4's authoring convention makes the fair one on every four-seat
## board, and Three-way drops the last seat.
##
## The row is built on every board and greyed where the board deals fewer than
## four seats, for the reason the Empty button is (COM-224): a row that vanishes
## restacks everything under it and makes the duel panel a different screen.
const PRESETS: Array[Dictionary] = [
	{
		"label": "Free-for-all",
		"sides": [0, 1, 2, 3],
		"seats": [Seat.HUMAN, Seat.CPU, Seat.CPU, Seat.CPU],
		"help": "Every army for itself",
	},
	{
		"label": "2v2",
		"sides": [0, 1, 0, 1],
		"seats": [Seat.HUMAN, Seat.CPU, Seat.CPU, Seat.CPU],
		"help": "Seats 1+3 against 2+4",
	},
	{
		"label": "3v1",
		"sides": [0, 0, 0, 1],
		"seats": [Seat.HUMAN, Seat.CPU, Seat.CPU, Seat.CPU],
		"help": "Seats 1+2+3 against 4",
	},
	{
		"label": "Duel",
		"sides": [0, 1, 2, 3],
		"seats": [Seat.HUMAN, Seat.EMPTY, Seat.CPU, Seat.EMPTY],
		"help": "Seats 1 and 3 alone; 2 and 4 stay empty",
	},
	{
		"label": "Three-way",
		"sides": [0, 1, 2, 3],
		"seats": [Seat.HUMAN, Seat.CPU, Seat.CPU, Seat.EMPTY],
		"help": "Seats 1, 2 and 3; seat 4 stays empty",
	},
]

var _seats: Array[int] = []
## Per seat, parallel to `_seats`: who plays it (a `Seat`), and which side it
## stands on (an index into SIDE_LABELS).
var _who: Array[int] = []
var _side: Array[int] = []
var _rows: GridContainer
var _presets: HBoxContainer
## Per seat, parallel to `_seats`: how to repaint that row's two segments without
## rebuilding the strip. A rebuild frees the very button whose `pressed` is
## running — which on a preset press left a keyboard player with no focus owner —
## so every in-place change repaints through these instead.
var _who_restyle: Array[Callable] = []
var _side_restyle: Array[Callable] = []
## Per seat: the Empty button. Held so the "closing this would leave too few" rule
## can grey it in place, for the same reason the restyles exist — the strip is
## never rebuilt under a press.
var _empty_buttons: Array[Button] = []
## Per seat: that row's side badges, one entry per letter in SIDE_LABELS. Held so
## the letters the board does not seat, and every letter of a closed row, can be
## greyed rather than removed: an empty seat brings no army and stands on no side,
## and a lit badge there said the opposite in the one place the eye goes to check.
var _side_buttons: Array[Array] = []
var _accent: Color = Color.WHITE


## Sets the seat rows' accent, the one thing about them the strip does not read
## off `UiKit` or `UiTheme` itself — a seat button's colour is the match's faction,
## which only the caller (the menu) knows.
func configure(accent: Color) -> void:
	_accent = accent


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
	while _who.size() < count:
		# Seat 1 is the player, everyone after it the computer: the old "1 Player
		# VS AI" default, which is what keeps a duel a one-click set-up. Every seat
		# the board deals starts open — closing one is always something asked for.
		_who.append(Seat.HUMAN if _who.is_empty() else Seat.CPU)
		_side.append(_side.size())
	_who.resize(count)
	_who = reopened_seats(_who, _closable())
	_side = normalised_sides(_side, count)
	_rebuild()


## The seats this match fills, in seat order — what `MatchRequest.seats` takes.
## Every seat the board deals, unless somebody closed one.
func seats() -> Array[int]:
	var filled: Array[int] = []
	for i in _seats.size():
		if _who[i] != Seat.EMPTY:
			filled.append(_seats[i])
	return filled


## The seats the computer plays, in seat order — what `MatchRequest.ai_teams`
## takes. A closed seat is nobody's, the computer's included.
func ai_teams() -> Array[int]:
	var computers: Array[int] = []
	for i in _seats.size():
		if _who[i] == Seat.CPU:
			computers.append(_seats[i])
	return computers


## team -> side id, or **empty for a free-for-all**. Empty rather than one side
## per army on purpose: that is what `GameState.allied` reads as "every army its
## own side", and it is the value every match had before groupings existed, so a
## free-for-all stages byte-identically to a match set up before this strip.
##
## Over the filled seats only. A closed seat is not an army standing alone, it is
## an army that never played, and a grouping naming one describes a different match
## — which `BattleSetup` refuses rather than half-applies.
func sides() -> Dictionary:
	var grouped: Dictionary = {}
	var filled := 0
	for i in _seats.size():
		if _who[i] == Seat.EMPTY:
			continue
		grouped[_seats[i]] = _side[i]
		filled += 1
	return {} if _distinct_sides() == filled else grouped


## Whether the strip describes a match that can be played: at least two armies at
## the table, and somebody opposed. Everyone on one side is a board with nobody to
## fight, which the sim would resolve as an immediate victory.
func valid() -> bool:
	return seats().size() >= MIN_FILLED and _distinct_sides() >= 2


## Why the strip is refusing, or "" when it is not. Shown rather than silently
## disabling Start, because a greyed control with no reason is the affordance
## this menu has already been burned by once (COM-19).
func refusal() -> String:
	if valid():
		return ""
	if seats().size() < MIN_FILLED:
		return "Seat at least two armies"
	return "Give at least two sides somebody to fight"


## How many seats the board dealt.
func seat_count() -> int:
	return _seats.size()


## The row control per seat, in seat order — empty before a roster is dealt. The
## capture gate names each one so a seat row that left the frame refuses the
## picture: a row is what a seat *is* on screen, and the strip's own rect outlives
## its rows by a sort, so measuring the container proved nothing.
func rows() -> Array[Control]:
	var named: Array[Control] = []
	if _rows == null:
		return named
	for child in _rows.get_children():
		named.append(child as Control)
	return named


## Why this strip is not the table it was dealt, or "" when it is — the sibling of
## `CommanderInfoSheet.layout_error`, and there for the same reason: a blank
## control writes a perfectly healthy PNG.
##
## The frame check cannot answer this one. A row the grid has not sorted yet keeps
## its minimum size and sits at the grid's origin, so it is enclosed by every frame
## and drawn in none of it — every seat stacked on one spot, which is precisely
## what a strip re-dealt after the settle photographed as bare panel (COM-48).
## Overlap is therefore the honest question, and it costs no state: rows the
## container has laid out occupy their own ground.
func layout_error() -> String:
	var laid := rows()
	if laid.size() != _seats.size():
		return "the seat strip laid out %d rows for %d seats" % [laid.size(), _seats.size()]
	for i in laid.size():
		var rect := laid[i].get_global_rect()
		if not rect.has_area():
			return "seat row %d occupies nothing (%s)" % [i + 1, rect]
		for j in range(i + 1, laid.size()):
			if rect.intersects(laid[j].get_global_rect()):
				return (
					"seat rows %d and %d overlap at %s, so the strip is not laid out"
					% [i + 1, j + 1, rect]
				)
	return ""


## Seats or unseats a person at `index`. Public because the setup-context capture
## walks the table rather than photographing one arrangement of it — the same
## reason the difficulty rule is asked of the seats and not of a mode flag.
func set_human(index: int, human: bool) -> void:
	set_seat(index, Seat.HUMAN if human else Seat.CPU)


## Puts `who` in the seat at `index`. Refuses to close the seat when that would
## leave too few armies to play — the same rule the Empty button is greyed by, held
## here as well because this is the door the capture driver comes in through.
func set_seat(index: int, who: int) -> void:
	if index < 0 or index >= _who.size():
		return
	if who == Seat.EMPTY and not can_close(index):
		return
	_who[index] = who
	if index < _who_restyle.size():
		_who_restyle[index].call(who)
	_settle_seats()
	changed.emit()


## Whether the seat at `index` may be closed: only while at least `MIN_FILLED`
## armies would be left at the table. False for every seat of a duel board, which
## is why one is never offered an Empty button at all.
func can_close(index: int) -> bool:
	if index < 0 or index >= _who.size():
		return false
	if _who[index] == Seat.EMPTY:
		return true  # already closed; re-closing takes nobody off the table
	return seats().size() > MIN_FILLED


## Applies PRESETS[index]. Public for the dev capture that photographs the strip
## in each grouping; the preset buttons call the same path.
func apply_preset_at(index: int) -> void:
	if index < 0 or index >= PRESETS.size():
		return
	_apply_preset(PRESETS[index])


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


## The seating `who_in` becomes once the roster has shrunk under it: closed seats
## reopened to the computer — the default everywhere past seat 1 — until the table
## is a match again, and every one of them reopened when the board is not
## `closable`, because such a board's Empty buttons are all dead and a seat closed
## there would be state nothing on screen could undo: greying Start with the one
## control that would answer for it refusing the press. Static and pure on the
## same terms as `normalised_sides`, so the shrink path is checked without a
## scene (CLAUDE.md, Testing).
static func reopened_seats(who_in: Array[int], closable: bool) -> Array[int]:
	var settled: Array[int] = []
	var filled := 0
	for seat in who_in:
		settled.append(seat)
		if seat != Seat.EMPTY:
			filled += 1
	for i in settled.size():
		if settled[i] == Seat.EMPTY and (not closable or filled < MIN_FILLED):
			settled[i] = Seat.CPU
			filled += 1
	return settled


## How many sides the *filled* seats stand on. A closed seat brings no side to the
## table, so counting it would let three armies on one side read as a match.
func _distinct_sides() -> int:
	var seen: Dictionary = {}
	for i in _seats.size():
		if _who[i] != Seat.EMPTY:
			seen[_side[i]] = true
	return seen.size()


## What has to be true again after the table changes: the sides re-packed over
## whoever is left, and the Empty buttons greyed where closing one more would take
## the table below a match.
##
## The re-pack is the same fix `normalised_sides` was written for and for the same
## reason — closing a seat shrinks the table exactly as picking a smaller board
## does, and a 3v1 whose lone army just left is otherwise three seats on one side
## with Start greyed and nothing on screen explaining which tap caused it.
func _settle_seats() -> void:
	var filled: Array[int] = []
	var standing: Array[int] = []
	for i in _seats.size():
		if _who[i] != Seat.EMPTY:
			filled.append(i)
			standing.append(_side[i])
	var settled := normalised_sides(standing, filled.size())
	for i in filled.size():
		_side[filled[i]] = settled[i]
		if filled[i] < _side_restyle.size():
			_side_restyle[filled[i]].call(settled[i])
	for i in _empty_buttons.size():
		_empty_buttons[i].disabled = not can_close(i)
	for i in _side_buttons.size():
		var stands := _who[i] != Seat.EMPTY
		if not stands:
			_side_restyle[i].call(-1)  # no letter lit: a closed seat is on no side
		for letter in _side_buttons[i].size():
			var badge: Button = _side_buttons[i][letter]
			badge.disabled = not stands or letter >= _seats.size()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_who_restyle.clear()
	_side_restyle.clear()
	_empty_buttons.clear()
	_side_buttons.clear()
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
	_settle_seats()  # the Empty buttons only exist to be greyed once they are built


## One seat on one line: a label, who plays it, and which side it stands on.
##
## Built off `UiKit.segment` with no caption (an empty `micro` hands back the
## bordered run bare) because the captioned form stacks a label above every
## control, and four of those do not fit the panel's fixed height — so a seat
## button still looks exactly like a difficulty button without the caption it has
## no room for.
##
## Every choice is built on every board and greyed where that board refuses it
## (COM-224): Empty on a table already at its minimum, and the letters of a side
## the board does not seat. So a row is the same control at the same widths
## whatever the map deals, and how many rows there are is the only thing a board
## changes about this strip.
func _seat_row(index: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := UiKit.micro_label("P%d" % _seats[index])
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)
	var choices := PackedStringArray()
	for label: String in SEAT_LABELS:
		choices.append(label)
	var who_buttons: Array[Button] = []
	var who := UiKit.segment(
		"",
		choices,
		_who[index],
		_accent,
		"",
		"",
		func(choice: int) -> void: _set_seat(index, choice),
		who_buttons,
		_who_restyle,
		_SEAT_SEGMENT_HEIGHT
	)
	# A third choice on the same line is a third word to fit, and the seat's words
	# are the long ones — "Human" clipped to "Huma" at an even split. The badges are
	# single letters and can spare the room.
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.size_flags_stretch_ratio = 2.0
	row.add_child(who)
	_empty_buttons.append(who_buttons[Seat.EMPTY])
	var badges := PackedStringArray()
	for label: String in SIDE_LABELS:
		badges.append(label)
	var side_buttons: Array[Button] = []
	var side := UiKit.segment(
		"",
		badges,
		_side[index],
		_accent,
		"",
		"",
		func(choice: int) -> void: _set_side(index, choice),
		side_buttons,
		_side_restyle,
		_SEAT_SEGMENT_HEIGHT
	)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(side)
	_side_buttons.append(side_buttons)
	return row


## Whether this board could ever offer a seat to close: only one seating more than
## the minimum table can, because the last two seats never close. What it decides
## is the *state* a shrinking roster settles into (`reopened_seats`), never whether
## a button is built — every board builds all three.
func _closable() -> bool:
	return _seats.size() > MIN_FILLED


func _refresh_presets() -> void:
	for child in _presets.get_children():
		_presets.remove_child(child)
		child.queue_free()
	# Only a four-seat board has more than one table worth a shortcut; every other
	# board gets the same row, inert, so nothing under it moves.
	var offered := _seats.size() >= PRESET_SEATS
	_presets.add_child(UiKit.micro_label("TABLE"))
	for preset: Dictionary in PRESETS:
		var button := Button.new()
		button.text = String(preset["label"])
		# The segmented control's own size: a preset row sits directly under the
		# seat/side segments it sets in one tap, at the same density.
		UiTheme.apply_button(button, UiTheme.ButtonVariant.SECONDARY, null, UiTheme.SIZE_SEGMENT)
		button.disabled = not offered
		Tooltip.attach(button, String(preset["help"]), "", Tooltip.Side.BOTTOM)
		button.pressed.connect(func() -> void: _apply_preset(preset))
		_presets.add_child(button)


## Repaints in place rather than rebuilding: a preset is applied from the `pressed`
## of one of the strip's own buttons, and freeing that button mid-signal releases
## focus with nothing to give it back to — a keyboard or gamepad player pressing
## "2v2" was left with no focus owner at all.
##
## The seating goes on first and the grouping after it, because the sides are
## re-packed over whoever is left: applying them the other way round would settle a
## grouping across seats the same tap was about to close.
func _apply_preset(preset: Dictionary) -> void:
	var seating: Array = preset.get("seats", [])
	for i in mini(_who.size(), seating.size()):
		_who[i] = int(seating[i])
	for i in mini(_who_restyle.size(), _who.size()):
		_who_restyle[i].call(_who[i])
	var pattern: Array = preset["sides"]
	for i in mini(_side.size(), pattern.size()):
		_side[i] = int(pattern[i])
	_settle_seats()
	changed.emit()


func _set_seat(index: int, who: int) -> void:
	# The Empty button is greyed rather than absent when the table is at its
	# minimum, so a press can still arrive here — from a keyboard, or from the
	# frame before `_settle_seats` ran — and is answered by putting the row back.
	if who == Seat.EMPTY and not can_close(index):
		if index < _who_restyle.size():
			_who_restyle[index].call(_who[index])
		return
	_who[index] = who
	_settle_seats()
	changed.emit()


func _set_side(index: int, side: int) -> void:
	_side[index] = side
	changed.emit()
