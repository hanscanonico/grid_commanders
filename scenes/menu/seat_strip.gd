class_name SeatStrip
extends VBoxContainer
## Who sits at the table and who stands with whom (COM-48, four-players plan D6).
##
## One row per seat the board deals — who plays it, how well the computer plays it
## and a side badge — plus the one-tap groupings on a board that seats four. It
## replaces the two mode buttons the menu used to be able to express a match with,
## which between them said only "one of you" or "two of you" and nothing at all
## about sides.
##
## How many rows there are is the **board's** answer and how they group is the
## **match's** (plan D1), so this takes a roster and hands back four facts:
## `seats()`, `ai_teams()`, `sides()` and `seat_difficulty()`. It decides none of
## them for itself and knows nothing about maps, saves or launching.
##
## The tier is per seat rather than per match (COM-225): a four-army board can now
## be one Easy opponent and two Difficult ones, which is what the panel's single
## Difficulty segment could not say. That segment is gone — two controls writing
## one fact is the drift a single authority exists to prevent — and the tier a seat
## carries is only ever which `AIProfile` weighs its moves, never a cheat
## (difficulty plan D2).
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
## does own — the widget shape comes from `UiKit` (`_seat_row`) and the colour
## from `SideIdentity` (`_accent_for`).
const _SEAT_SEGMENT_HEIGHT := 16
## The air either side of a tier chip's word, over `UiTheme.segment_box`'s own 2px
## margins — so the longest tier name fits inside the chip rather than being
## clipped by it. Its own constant beside the height for the same reason that one
## is: it is a size this file owns, because the chip is measured rather than
## stretched (`_widest_tier`), and every pixel it takes comes off "Human" beside
## it.
const _TIER_CHIP_PAD := 6.0
## The roster every preset is written for. A smaller board can express only one of
## them, so there the row is built and dead rather than absent.
const PRESET_SEATS := 4
## How far back a preset row with nothing live on it is faded, over the disabled
## dress its buttons already wear. A size this file owns for the reason the segment
## height is: it is the fade of one row of this strip and not a shell token, and
## `UiTheme` has no recipe for a group that is dead whole.
const _DEAD_ROW_TINT := Color(1.0, 1.0, 1.0, 0.6)
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
## restacks everything under it and makes the duel panel a different screen. Where
## *every* preset is refused the row greys **as a unit** and says why once
## (`preset_refusal`) — five dead buttons under a live heading read as five choices
## the board turned down, one of them "Duel" on a board that is already a duel.
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
## The liveries the seats will wear, resolved over the seats that **play** from
## the one authority the board and the footer chips also read (`SideIdentity`,
## faction-identity D1) — so P2's row is P2's colour rather than everyone's. No
## commander is picked at set-up, so this is that authority's fallback order for
## this roster, which is exactly what the match resolves if nobody picks one.
## Re-resolved whenever the table changes, because closing a seat changes which
## seats are being resolved over.
var _identity: SideIdentity = SideIdentity.resolve({})
## The line under a dead preset row, hidden while the row is live — so a board that
## offers a preset lays out exactly as it did before this label existed.
var _preset_reason: Label
## Per seat, parallel to `_seats`: that row's three runs of buttons — who plays
## the seat, its side badges (one per letter in SIDE_LABELS) and its tier chip.
## Held so every in-place change repaints through `_repaint_seats` rather than
## rebuilding: a rebuild frees the very button whose `pressed` is running, which
## on a preset press left a keyboard player with no focus owner. They are also
## what lets a control be greyed rather than removed — Empty on a table at its
## minimum, the letters the board does not seat and every letter of a closed row
## (an empty seat brings no army and stands on no side, and a lit badge there
## said the opposite in the one place the eye goes to check).
var _who_buttons: Array[Array] = []
var _side_buttons: Array[Array] = []
## The tiers a seat cycles through, gentlest first, and per seat the one it is on.
## Read off `DifficultyDB` by the caller rather than typed in here, so the chip can
## never offer a tier that does not ship.
var _tiers: Array[Difficulty] = []
var _tier: Array[int] = []
## Per seat: the tier chip. Held so it can be relabelled on a press and greyed for
## a seat the computer is not playing, the same way the Empty button is.
var _tier_buttons: Array[Button] = []


## Sets the tiers the chips cycle through — the one thing about a row the strip
## reads off neither `UiKit`, `UiTheme` nor `SideIdentity`, because the roster of
## tiers is `DifficultyDB`'s and only the caller (the menu) holds it.
func configure(tiers: Array[Difficulty] = []) -> void:
	_tiers = tiers


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
		_tier.append(_default_tier())
	_who.resize(count)
	_tier.resize(count)
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


## team -> tier id, over the seats the **computer** plays — what
## `MatchRequest.seat_difficulty` takes. A human or closed seat brings no planner,
## so it names no tier: the chip on such a row is dead and its value is whatever
## the seat last carried, which is a state to keep and not a match fact to state.
func seat_difficulty() -> Dictionary:
	var tiers: Dictionary = {}
	for i in _seats.size():
		if _who[i] == Seat.CPU and _tier[i] < _tiers.size():
			tiers[_seats[i]] = _tiers[_tier[i]].id
	return tiers


## Whether the tier chip on the seat at `index` is live — true exactly while the
## computer plays that seat. The generalisation of "Difficulty is dimmed while no
## computer is seated" (COM-19) to a table where each seat answers for itself, and
## public because the setup-context capture walks the table rather than
## photographing one arrangement of it.
func tier_operable(index: int) -> bool:
	return index >= 0 and index < _who.size() and _who[index] == Seat.CPU


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


## Why the preset row is dead on a board of `seats_dealt`, or "" while any preset
## is live. The presets are written for a four-seat table, so a smaller board
## refuses all five at once, so the row answers once rather than five times
## (COM-233). Static and pure on `normalised_sides`' terms, so the copy and the
## rule it states are checked without a scene.
static func preset_refusal(seats_dealt: int) -> String:
	return "" if seats_dealt >= PRESET_SEATS else "Presets need four seats"


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
	_set_seat(index, Seat.HUMAN if human else Seat.CPU)


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


## Whether the seat at `index` may be closed: only while at least `MIN_FILLED`
## armies would be left at the table. False for every seat of a duel board, which
## is why every Empty button on one is built dead.
func _can_close(index: int) -> bool:
	if index < 0 or index >= _who.size():
		return false
	if _who[index] == Seat.EMPTY:
		return true  # already closed; re-closing takes nobody off the table
	return seats().size() > MIN_FILLED


## How many sides the *filled* seats stand on. A closed seat brings no side to the
## table, so counting it would let three armies on one side read as a match.
func _distinct_sides() -> int:
	var seen: Dictionary = {}
	for i in _seats.size():
		if _who[i] != Seat.EMPTY:
			seen[_side[i]] = true
	return seen.size()


## What has to be true again after the table changes: the sides re-packed over
## whoever is left, the Empty buttons greyed where closing one more would take
## the table below a match, and every row repainted in the livery its seat wears
## now — a table that has just lost a seat is a different roster, and the
## identity is resolved over the seats that play.
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
	for i in _who_buttons.size():
		var empty: Button = _who_buttons[i][Seat.EMPTY]
		empty.disabled = not _can_close(i)
	for i in _tier_buttons.size():
		_tier_buttons[i].disabled = not tier_operable(i)
	for i in _side_buttons.size():
		var stands := _who[i] != Seat.EMPTY
		for letter in _side_buttons[i].size():
			var badge: Button = _side_buttons[i][letter]
			badge.disabled = not stands or letter >= _seats.size()
	_repaint_seats()


## Every row in the colour its own army wears, and one selected fill per row: the
## seat's word, its tier chip and its side letter all take the same accent, so
## "selected" reads as one state rather than three. A dead control still wears it
## — `UiKit.style_segment` mixes the *same* accent toward paper for its disabled
## dress, which is the pale chip on a seat the computer does not play, and the
## fade is the difference between live and dead rather than a second fill.
##
## The strip paints its own rows because a row's accent is not fixed at build
## time: closing a seat re-resolves the whole table's liveries, so the paint has
## to be able to run again over buttons that already exist.
func _repaint_seats() -> void:
	_resolve_identity()
	for i in _seats.size():
		var accent := _accent_for(i)
		_paint_run(_who_buttons[i], _who[i], accent)
		# No letter lit on a closed seat: it brings no army and stands on no side.
		_paint_run(_side_buttons[i], _side[i] if _who[i] != Seat.EMPTY else -1, accent)
		UiKit.style_segment(_tier_buttons[i], true, false, accent)


## The liveries for the table as it now stands, over the seats that play — the
## roster the match itself will resolve over. `UiTheme` keeps the answer, so
## asking again after every tap costs nothing.
func _resolve_identity() -> void:
	_identity = UiTheme.menu_identity_of(seats())


## The livery the seat at `index` wears. A closed seat is in no roster, so the
## identity answers neutral for it — grey, which is what an army that is not
## coming should look like.
func _accent_for(index: int) -> Color:
	return _identity.theme(_seats[index]).color


## One run of segments, with `selected` lit and the rest paper. -1 lights none.
static func _paint_run(buttons: Array[Button], selected: int, accent: Color) -> void:
	for i in buttons.size():
		UiKit.style_segment(buttons[i], i == selected, i > 0, accent)


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_who_buttons.clear()
	_side_buttons.clear()
	_tier_buttons.clear()
	_resolve_identity()  # the rows are built in their liveries, then repainted in them
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
	_preset_reason = UiKit.help_label("")
	add_child(_preset_reason)
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
	row.add_theme_constant_override("separation", 2)
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
		_accent_for(index),
		"",
		"",
		func(choice: int) -> void: _set_seat(index, choice),
		who_buttons,
		[],
		_SEAT_SEGMENT_HEIGHT
	)
	# A third choice on the same line is a third word to fit, and the seat's words
	# are the long ones — "Human" clipped to "Huma" at an even split. The badges are
	# single letters and can spare the room.
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.size_flags_stretch_ratio = 2.0
	row.add_child(who)
	_who_buttons.append(who_buttons)
	row.add_child(_tier_chip(index))
	var badges := PackedStringArray()
	for label: String in SIDE_LABELS:
		badges.append(label)
	var side_buttons: Array[Button] = []
	var side := UiKit.segment(
		"",
		badges,
		_side[index],
		_accent_for(index),
		"",
		"",
		func(choice: int) -> void: _set_side(index, choice),
		side_buttons,
		[],
		_SEAT_SEGMENT_HEIGHT
	)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# The badges are single letters where the seat's words are five, so the row's
	# spare width goes to the words: a run of four letters reads at this share and
	# "Human" does not survive an even split.
	side.size_flags_stretch_ratio = 0.8
	row.add_child(side)
	_side_buttons.append(side_buttons)
	return row


## How well the computer plays this seat: one chip, cycling through the tiers
## gentlest-first and showing the one in hand. A chip rather than a segment
## because four tier names to a row do not fit the panel's fixed frame — and it is
## the same button `UiKit.style_segment` dresses the seat and side runs with, so a
## row still reads as one control per fact.
##
## Sized to the longest tier name rather than sharing the row's stretch, because
## every pixel it takes past that comes off "Human" and "Empty" beside it — a row
## that let it expand clipped both to three letters.
##
## Built on every row of every board and greyed where the computer is not playing
## that seat (COM-224, and the COM-19 rule the panel's one Difficulty segment used
## to carry): a chip that vanished with the seat's owner would restack the row.
## Greyed, it wears the row's own accent faded — the one selected fill of
## `_repaint_seats`, not a second tint.
func _tier_chip(index: int) -> Button:
	var chip := Button.new()
	chip.clip_text = true
	chip.custom_minimum_size = Vector2(_widest_tier(), _SEAT_SEGMENT_HEIGHT)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_font_override("font", UiTheme.display())
	chip.add_theme_font_size_override("font_size", UiTheme.SIZE_SEGMENT)
	chip.text = _tier_label(index)
	UiKit.style_segment(chip, true, false, _accent_for(index))
	Tooltip.attach(
		chip,
		"How well the computer plays this seat",
		"Tap to cycle · a tier never cheats",
		Tooltip.Side.BOTTOM
	)
	chip.pressed.connect(_cycle_tier.bind(index))
	UiKit.touchable(chip)
	_tier_buttons.append(chip)
	return chip


## How wide a chip has to be for the longest tier name to fit inside it, measured
## in the font it is drawn in rather than guessed at — the roster of tiers is
## data, so a fifth one with a longer name widens the chip by itself.
func _widest_tier() -> float:
	var widest := 0.0
	for tier in _tiers:
		widest = maxf(
			widest,
			(
				UiTheme
				. display()
				. get_string_size(
					tier.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_SEGMENT
				)
				. x
			)
		)
	return widest + _TIER_CHIP_PAD


## The tier the seat at `index` is on, as the chip prints it.
func _tier_label(index: int) -> String:
	if _tiers.is_empty() or index >= _tier.size():
		return ""
	return _tiers[_tier[index] % _tiers.size()].display_name


## Which tier a fresh seat opens on: the shipped default, wherever it sits in the
## menu order, so a table nobody tunes is the match every launch played before a
## seat could carry a tier of its own.
func _default_tier() -> int:
	for i in _tiers.size():
		if _tiers[i].id == Difficulty.DEFAULT_ID:
			return i
	return 0


func _cycle_tier(index: int) -> void:
	if _tiers.is_empty() or index >= _tier.size():
		return
	_tier[index] = (_tier[index] + 1) % _tiers.size()
	_tier_buttons[index].text = _tier_label(index)
	changed.emit()


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
	# board gets the same row, dead whole and answered by one line under it.
	var reason := preset_refusal(_seats.size())
	var offered := reason.is_empty()
	# One fade over the whole row rather than five disabled boxes side by side: the
	# heading, the buttons and their frames go back together, which is what makes the
	# reason under them read as the row's and not as the last button's.
	_presets.modulate = Color.WHITE if offered else _DEAD_ROW_TINT
	var heading := UiKit.micro_label("TABLE")
	if not offered:
		# Set in the reason line's own ink, so the dead row reads as heading, buttons
		# and answer together rather than as a live heading over five refusals.
		heading.add_theme_color_override("font_color", UiTheme.NEUTRAL)
	_presets.add_child(heading)
	for preset: Dictionary in PRESETS:
		var button := Button.new()
		button.text = String(preset["label"])
		# The segmented control's own size: a preset row sits directly under the
		# seat/side segments it sets in one tap, at the same density.
		UiTheme.apply_button(button, UiTheme.ButtonVariant.SECONDARY, null, UiTheme.SIZE_SEGMENT)
		button.disabled = not offered
		Tooltip.attach(
			button, String(preset["help"]) if offered else reason, "", Tooltip.Side.BOTTOM
		)
		button.pressed.connect(func() -> void: _apply_preset(preset))
		_presets.add_child(button)
	_preset_reason.text = reason.to_upper()
	_preset_reason.visible = not offered


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
	var pattern: Array = preset["sides"]
	for i in mini(_side.size(), pattern.size()):
		_side[i] = int(pattern[i])
	_settle_seats()
	changed.emit()


## The one writer for who sits at `index` — the segment control and `set_human`
## both come through here, so a refusal reads the same whichever door it arrived
## by. The Empty button is greyed rather than absent when the table is at its
## minimum, so a press can still arrive — from a keyboard, or from the frame
## before `_settle_seats` ran — and is answered by putting the row back.
func _set_seat(index: int, who: int) -> void:
	if index < 0 or index >= _who.size():
		return
	if who == Seat.EMPTY and not _can_close(index):
		_repaint_seats()
		return
	_who[index] = who
	_settle_seats()
	changed.emit()


func _set_side(index: int, side: int) -> void:
	_side[index] = side
	_repaint_seats()
	changed.emit()
