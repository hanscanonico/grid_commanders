class_name SeatStrip
extends VBoxContainer
## Who sits at the table and who stands with whom (COM-48, four-players plan D6):
## the Players step's Mode row and one row per seat the board deals.
##
## How many rows there are is the **board's** answer and how they group is the
## **match's** (plan D1), so this takes a roster and hands back four facts:
## `seats()`, `ai_teams()`, `sides()` and `seat_difficulty()`, plus who commands
## each seat (`generals`). It decides none of them for itself and knows nothing
## about maps, saves or launching.
##
## A row is one selector and one general. The selector walks every answer to "who
## plays this seat" (`next_player`), because who plays and how well are one question
## with one control; a tier is still only ever which `AIProfile` weighs a seat's
## moves, never a cheat (difficulty plan D2). A seat's third state is **Empty**
## (open-seats plan D4), which the walk steps over while closing the seat would leave
## fewer than two armies.
##
## Grouping is the Mode row's. The side letters only show under Custom, or for a
## table no Mode describes (`shows_sides`): they say the same fact a Mode says, one
## seat at a time, and most matches never want them. A duel gets neither.
##
## Each row's general (`SeatGeneralChip`) asks the menu to open the commander page
## for that one seat (`general_requested`), and the pick comes back through
## `seat_generals`. A seat nobody picked for plays with no commander.
##
## The defaults: every seat open, seat 1 human, every other seat the computer's, and
## every army its own side, so a match can be started without touching this at all.

signal changed
## The general chip on `seat`'s row was pressed; `chip` is where focus goes back.
signal general_requested(seat: int, chip: Control)

## Who is in a seat. `EMPTY` is the seat nobody takes: the army never enters the
## match at all, so its start dissolves to neutral ground the others fight over.
enum Seat { HUMAN, CPU, EMPTY }

## Side badges, in the order a seat cycles through them. Letters rather than
## faction names because a side is a grouping and not a livery: two armies on
## side A each keep their own colours (plan D5).
const SIDE_LABELS: Array[String] = ["A", "B", "C", "D"]
## The smallest table that is a match, which is also `GameState.MIN_SEATS` — the
## sim refuses a smaller one, and this is the menu never offering to build it.
const MIN_FILLED := GameState.MIN_SEATS
## A seat row's height: a general's whole face chip inside the row's border.
const ROW_H := 35
## The side letters' width: four single letters, with room to aim at each.
const SIDE_RUN_W := 72.0
## How far back a closed seat's general is faded: its pick survives for later.
const _CLOSED_TINT := Color(1.0, 1.0, 1.0, 0.6)
## The "P1" label's width, since a pixel face sets 1 narrower than 2 and the rows
## below it would not line up.
const _SEAT_LABEL_W := 16.0
## The selector's mark, so it reads as a control that steps.
const _CYCLE_MARK := " ▸"
## The air either side of the selector's longest word.
const _SELECTOR_PAD := 14.0
const _CUSTOM_LABEL := "Custom"
const _CUSTOM_HELP := "Choose each army's side yourself"
## The one-tap tables, each of them a seating *and* a grouping. `seats` is per seat;
## `sides` is the grouping the filled seats stand in. Every preset carries both, so
## "2v2" pressed after "Duel" is still four armies in two pairs. Duel fills the
## opposite-seat pair, which the maps' authoring convention makes the fair one on
## every four-seat board. Asked for through `presets_for`.
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
const THREE_SEAT_PRESETS: Array[Dictionary] = [
	{
		"label": "Free-for-all",
		"sides": [0, 1, 2],
		"seats": [Seat.HUMAN, Seat.CPU, Seat.CPU],
		"help": "Every army for itself",
	},
	{
		"label": "2v1",
		"sides": [0, 0, 1],
		"seats": [Seat.HUMAN, Seat.CPU, Seat.CPU],
		"help": "Seats 1+2 against 3",
	},
]

var _seats: Array[int] = []
## Per seat, parallel to `_seats`: who plays it (a `Seat`), and which side it
## stands on (an index into SIDE_LABELS).
var _who: Array[int] = []
var _side: Array[int] = []
var _rows: VBoxContainer
var _presets: HBoxContainer
## The Mode buttons in `presets_for` order — held so the one the table in hand
## matches can be lit on every repaint, like a segment's choice.
var _preset_buttons: Array[Button] = []
var _custom_button: Button
## Custom was pressed, so the letters stay up even over a table a Mode describes.
var _custom_chosen := false
## The liveries the seats will wear, resolved over the seats that **play** from
## the one authority the board and the footer chips also read (`SideIdentity`,
## faction-identity D1) — so P2's row is P2's colour rather than everyone's. No
## commander is picked at set-up, so this is that authority's fallback order for
## this roster, which is exactly what the match resolves if nobody picks one.
## Re-resolved whenever the table changes, because closing a seat changes which
## seats are being resolved over.
var _identity: SideIdentity = SideIdentity.resolve({})
## Per seat: the selector, and the side letters with their run. Held so every
## in-place change repaints rather than rebuilds: a rebuild frees the very button
## whose `pressed` is running, which left a keyboard player with no focus owner.
var _player_buttons: Array[Button] = []
var _side_buttons: Array[Array] = []
var _side_runs: Array[Control] = []
## The tiers a seat walks through, gentlest first, and per seat the one it is on.
## Read off `DifficultyDB` by the caller rather than typed in here, so the selector
## can never offer a tier that does not ship.
var _tiers: Array[Difficulty] = []
var _tier: Array[int] = []
## Who commands each seat the board deals. Read freely; written through
## `seat_generals`, so the rows repaint and the table reports a change.
var generals := SeatGenerals.new()
## The roster the chips resolve a general from, loaded once in `configure`.
var _db: CommanderDB
## Per seat: the general chip ending its row.
var _general_chips: Array[SeatGeneralChip] = []
## Per seat: the "P1" label at the head of its row. Held because it is the row's
## identity swatch — it is set in the livery that seat's army wears, and a table
## that has just lost a seat is a different roster (`_repaint_seats`).
var _seat_labels: Array[Label] = []


## Sets the tiers the selectors walk through — the one thing about a row the strip
## reads off neither `UiKit`, `UiTheme` nor `SideIdentity`, because the roster of
## tiers is `DifficultyDB`'s and only the caller holds it.
func configure(tiers: Array[Difficulty] = []) -> void:
	_tiers = tiers
	_db = CommanderDB.load_default()


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
	_custom_chosen = false
	generals.keep(count)
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
## so it names no tier: what it last carried is a state to keep, not a match fact.
func seat_difficulty() -> Dictionary:
	var tiers: Dictionary = {}
	for i in _seats.size():
		if _who[i] == Seat.CPU and _tier[i] < _tiers.size():
			tiers[_seats[i]] = _tiers[_tier[i]].id
	return tiers


## Sits generals down — a pick from the commander page, or the remembered ones
## (`MenuSetupMemory.generals`) — over the seats this board deals.
func seat_generals(picks: Dictionary) -> void:
	generals.assign(picks, _seats.size())
	_repaint_seats()
	changed.emit()


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


## The table as the menu remembers it between visits (`MenuSetupMemory`): who sits
## where, the sides, and each seat's tier by id — an id rather than an index, so a
## tier added later cannot shift what a remembered seat plays at.
func table() -> Dictionary:
	var tiers: Array[String] = []
	for i in _tier.size():
		tiers.append(String(_tiers[_tier[i]].id) if _tier[i] < _tiers.size() else "")
	return {"who": _who.duplicate(), "sides": _side.duplicate(), "tiers": tiers}


## Sits a remembered `table` back down when it was set on a board dealing as many
## seats as this one; any other table was a different match and is left alone.
## Settled like any tap, so a stored seating this board cannot play is reopened
## rather than trusted.
func seat_table(remembered: Dictionary) -> void:
	var who: Array = remembered.get("who", [])
	var sides: Array = remembered.get("sides", [])
	var tiers: Array = remembered.get("tiers", [])
	if who.size() != _seats.size() or sides.size() != _seats.size():
		return
	for i in _seats.size():
		_who[i] = clampi(int(who[i]), Seat.HUMAN, Seat.EMPTY)
		_side[i] = clampi(int(sides[i]), 0, _seats.size() - 1)
		_tier[i] = _tier_index(str(tiers[i]) if i < tiers.size() else "")
	_who = reopened_seats(_who, _closable())
	_settle_seats()
	changed.emit()


## The COM-19 rule walked rather than photographed, for the setup-context
## capture: a seat only a person is in names no tier, and seating a computer there
## brings one back. Starts from, and ends on, the all-human table that capture poses.
func tier_rule_holds() -> bool:
	var passed := true
	if not ai_teams().is_empty():
		push_error("main menu setup context: the all-human table is not the posed state")
		passed = false
	var last := seat_count() - 1
	set_human(last, false)
	if not seat_difficulty().has(_seats[last]):
		push_error("main menu setup context: a CPU seat names no tier")
		passed = false
	set_human(last, true)
	if seat_difficulty().has(_seats[last]):
		push_error("main menu setup context: a human seat still names a tier")
		passed = false
	return passed


## Seats or unseats a person at `index`. Public because the setup-context capture
## walks the table rather than photographing one arrangement of it — the same
## reason the difficulty rule is asked of the seats and not of a mode flag.
func set_human(index: int, human: bool) -> void:
	_set_seat(index, Seat.HUMAN if human else Seat.CPU)


## Applies a Mode by index. Public for the dev capture that photographs the strip
## in each grouping; the Mode buttons call the same path.
func apply_preset_at(index: int) -> void:
	var presets := presets_for(_seats.size())
	if index < 0 or index >= presets.size():
		return
	_apply_preset(presets[index])


## Presses Custom. Public for the dev capture that photographs the side letters.
func choose_custom() -> void:
	_custom_chosen = true
	_repaint_seats()
	changed.emit()


## The Modes a board of `seats_dealt` offers: none on a duel, whose two armies have
## only one way to stand.
static func presets_for(seats_dealt: int) -> Array[Dictionary]:
	if seats_dealt == 4:
		return PRESETS
	if seats_dealt == 3:
		return THREE_SEAT_PRESETS
	var none: Array[Dictionary] = []
	return none


## Whether the side letters are up: under Custom, or over a table of three or more
## armies no Mode describes, where nothing else on screen would say who is allied.
## Never on a duel board.
static func shows_sides(who: Array[int], sides: Array[int], custom_chosen: bool) -> bool:
	if presets_for(who.size()).is_empty():
		return false
	if custom_chosen:
		return true
	var filled := who.size() - who.count(Seat.EMPTY)
	return filled > MIN_FILLED and preset_matching(who, sides) < 0


## Where the selector goes from `who` on tier `tier`: a person, each computer tier
## gentlest first, then nobody unless the seat may not close, then round again.
static func next_player(who: int, tier: int, tier_count: int, closable: bool) -> Array[int]:
	if who == Seat.HUMAN:
		return [Seat.CPU, 0]
	if who == Seat.CPU and tier + 1 < tier_count:
		return [Seat.CPU, tier + 1]
	if who == Seat.CPU and closable:
		return [Seat.EMPTY, tier]
	return [Seat.HUMAN, tier]


## What the selector prints for a seat.
static func player_label(who: int, tier_name: String) -> String:
	match who:
		Seat.HUMAN:
			return "Human" + _CYCLE_MARK
		Seat.CPU:
			return "CPU %s%s" % [tier_name, _CYCLE_MARK]
	return "Empty" + _CYCLE_MARK


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


## Which of `presets_for` the table `who` / `sides` is, or -1 for none (SK-22). A table
## is its seating and its grouping — which seats are filled and who stands with
## whom — not who plays each seat, so a 2v2 with two people at it is still the
## 2v2. Static and pure on `normalised_sides`' terms.
static func preset_matching(who: Array[int], sides: Array[int]) -> int:
	var presets := presets_for(who.size())
	var table := _grouping(who, sides)
	for i in presets.size():
		var preset_who: Array[int] = []
		preset_who.assign(presets[i]["seats"])
		var preset_sides: Array[int] = []
		preset_sides.assign(presets[i]["sides"])
		if _grouping(preset_who, preset_sides) == table:
			return i
	return -1


## Per seat, -1 for a closed one and otherwise its side, numbered in the order
## the filled seats first stand on it — so two groupings that differ only in
## their letters read the same.
static func _grouping(who: Array[int], sides: Array[int]) -> Array[int]:
	var numbered: Dictionary = {}
	var grouping: Array[int] = []
	for i in who.size():
		if who[i] == Seat.EMPTY:
			grouping.append(-1)
			continue
		if not numbered.has(sides[i]):
			numbered[sides[i]] = numbered.size()
		grouping.append(int(numbered[sides[i]]))
	return grouping


## The seating `who_in` becomes once the roster has shrunk under it: closed seats
## reopened to the computer — the default everywhere past seat 1 — until the table
## is a match again, and every one of them reopened when the board is not
## `closable`, because no selector on such a board could undo a closed seat. Static and pure on the
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
## armies would be left at the table. False for every seat of a duel board.
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
## whoever is left — closing a seat shrinks the table exactly as picking a smaller
## board does, and a 3v1 whose lone army just left is otherwise three seats on one
## side with Start greyed — and every row repainted in the livery its seat wears now.
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
	# Greyed rather than hidden: a closed seat keeps its pick for later.
	for i in _general_chips.size():
		_set_live(_general_chips[i], _who[i] != Seat.EMPTY)
		_general_chips[i].modulate = Color.WHITE if _who[i] != Seat.EMPTY else _CLOSED_TINT
	for i in _side_buttons.size():
		var stands := _who[i] != Seat.EMPTY
		for letter in _side_buttons[i].size():
			_set_live(_side_buttons[i][letter], stands and letter < _seats.size())
	_repaint_seats()


## Greys a control and takes it out of the focus walk in one stroke: a keyboard
## player who lands on a dead button presses Enter at nothing (SK-23).
static func _set_live(button: Button, live: bool) -> void:
	button.disabled = not live
	button.focus_mode = Control.FOCUS_ALL if live else Control.FOCUS_NONE


## Every row painted in two vocabularies. **Who plays a seat is chrome**, so the
## selector fills in `UiTheme.CONTROL_ACCENT` for a person and stays paper otherwise;
## **which army a seat is** is the only thing a faction hue says here, so it is spent
## on the side letters and on the seat's own P-label. The strip paints its own rows
## because closing a seat re-resolves the whole table's liveries.
func _repaint_seats() -> void:
	_resolve_identity()
	var letters_up := shows_sides(_who, _side, _custom_chosen)
	for i in _seats.size():
		var livery := _accent_for(i)
		_player_buttons[i].text = player_label(_who[i], _tier_name(i))
		_paint_selector(_player_buttons[i], _who[i])
		_side_runs[i].visible = letters_up
		# No letter lit on a closed seat: it brings no army and stands on no side.
		_paint_run(_side_buttons[i], _side[i] if _who[i] != Seat.EMPTY else -1, livery)
		_seat_labels[i].add_theme_color_override(
			"font_color", livery if _who[i] != Seat.EMPTY else UiTheme.NEUTRAL_DARK
		)
		var commander := _db.by_id(generals.of(_seats[i])) if _db != null else null
		_general_chips[i].show_general(commander, livery)
	var lit := -1 if letters_up else preset_matching(_who, _side)
	for i in _preset_buttons.size():
		_paint_preset(_preset_buttons[i], i == lit)
	if _custom_button != null:
		_paint_preset(_custom_button, letters_up)


## The selector in the row's bordered dress: filled for a person, paper for the
## computer, and faded words for a seat nobody takes.
static func _paint_selector(selector: Button, who: int) -> void:
	var human := who == Seat.HUMAN
	var box := UiTheme.bordered(
		UiTheme.CONTROL_ACCENT if human else UiTheme.PAPER,
		UiTheme.HARD_BORDER,
		UiTheme.BORDER,
		true
	)
	for state: StringName in [&"normal", &"hover", &"pressed"]:
		selector.add_theme_stylebox_override(state, box)
	selector.add_theme_stylebox_override("focus", UiTheme.focus_box())
	var ink := UiTheme.WHITE if human else UiTheme.INK
	if who == Seat.EMPTY:
		ink = UiTheme.NEUTRAL_DARK
	for state: StringName in [
		&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"
	]:
		selector.add_theme_color_override(state, ink)


## A Mode button in the quiet dress, filled with the chrome accent when it is the
## table in hand.
static func _paint_preset(button: Button, lit: bool) -> void:
	UiTheme.apply_button(button, UiTheme.ButtonVariant.SECONDARY, null, UiTheme.SIZE_BODY)
	if not lit:
		return
	var box := button.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	box.bg_color = UiTheme.CONTROL_ACCENT
	for state: StringName in [&"normal", &"hover", &"pressed"]:
		button.add_theme_stylebox_override(state, box)
	for state: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color"]:
		button.add_theme_color_override(state, UiTheme.WHITE)
	button.add_theme_color_override(&"font_focus_color", UiTheme.WHITE)


## The liveries for the table as it now stands, over the seats that play and the
## generals picked for them — what the match itself will resolve. With no general
## picked `UiTheme` keeps the answer, so asking again after every tap costs nothing.
func _resolve_identity() -> void:
	var picks: Dictionary = {}
	var any_general := false
	for seat in seats():
		var id := generals.of(seat)
		any_general = any_general or CommanderPicks.is_general(id)
		picks[seat] = _db.by_id(id) if _db != null and CommanderPicks.is_general(id) else null
	_identity = SideIdentity.resolve(picks) if any_general else UiTheme.menu_identity_of(seats())


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
	_player_buttons.clear()
	_side_buttons.clear()
	_side_runs.clear()
	_general_chips.clear()
	_seat_labels.clear()
	_resolve_identity()  # the rows are built in their liveries, then repainted in them
	add_theme_constant_override("separation", 5)
	_presets = HBoxContainer.new()
	_presets.add_theme_constant_override("separation", 3)
	add_child(_presets)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 3)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_rows)
	for i in _seats.size():
		_rows.add_child(_seat_row(i))
	_refresh_presets()
	_settle_seats()


## One seat on one line: a label, who plays it, the side letters when they are up,
## and the general commanding it.
func _seat_row(index: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := UiKit.micro_label("P%d" % _seats[index])
	name_label.custom_minimum_size.x = _SEAT_LABEL_W
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)
	_seat_labels.append(name_label)
	row.add_child(_player_selector(index))
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
		ROW_H - 4
	)
	side.custom_minimum_size.x = SIDE_RUN_W
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(side)
	_side_buttons.append(side_buttons)
	_side_runs.append(side)
	var chip := SeatGeneralChip.new(ROW_H)
	chip.pressed.connect(func() -> void: general_requested.emit(_seats[index], chip))
	row.add_child(chip)
	_general_chips.append(chip)
	return row


## Who plays this seat, one press a step (`next_player`). Sized to the longest thing
## it can say, so walking it never moves the row.
func _player_selector(index: int) -> Button:
	var selector := Button.new()
	selector.clip_text = true
	selector.custom_minimum_size = Vector2(_widest_player(), ROW_H)
	selector.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	selector.add_theme_font_override("font", UiTheme.display())
	selector.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	Tooltip.attach(
		selector,
		"Who plays this seat",
		"Press to change · a tier never cheats",
		Tooltip.Side.BOTTOM
	)
	selector.pressed.connect(_step_player.bind(index))
	UiKit.touchable(selector)
	_player_buttons.append(selector)
	return selector


func _widest_player() -> float:
	var widest := 0.0
	for tier in _tiers:
		var words := player_label(Seat.CPU, tier.display_name)
		widest = maxf(
			widest,
			(
				UiTheme
				. display()
				. get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SIZE_BODY)
				. x
			)
		)
	return widest + _SELECTOR_PAD


## The tier the seat at `index` is on, as the selector prints it.
func _tier_name(index: int) -> String:
	if _tiers.is_empty() or index >= _tier.size():
		return ""
	return _tiers[_tier[index] % _tiers.size()].display_name


## Where the tier `id` sits in the menu order, or the default's place for an id
## no tier answers to.
func _tier_index(id: String) -> int:
	for i in _tiers.size():
		if String(_tiers[i].id) == id:
			return i
	return _default_tier()


## Which tier a fresh seat opens on: the shipped default, wherever it sits in the
## menu order.
func _default_tier() -> int:
	for i in _tiers.size():
		if _tiers[i].id == Difficulty.DEFAULT_ID:
			return i
	return 0


func _step_player(index: int) -> void:
	var next := next_player(_who[index], _tier[index], _tiers.size(), _can_close(index))
	_tier[index] = next[1]
	_set_seat(index, next[0])


## Whether this board could ever offer a seat to close: only one seating more than
## the minimum table can, because the last two seats never close.
func _closable() -> bool:
	return _seats.size() > MIN_FILLED


## The Mode row, up only on a board with more than one way to group.
func _refresh_presets() -> void:
	_preset_buttons.clear()
	_custom_button = null
	var presets := presets_for(_seats.size())
	_presets.visible = not presets.is_empty()
	if presets.is_empty():
		return
	var heading := UiKit.micro_label("MODE")
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_presets.add_child(heading)
	for preset: Dictionary in presets:
		var button := _mode_button(String(preset["label"]), String(preset["help"]))
		button.pressed.connect(func() -> void: _apply_preset(preset))
		_preset_buttons.append(button)
	_custom_button = _mode_button(_CUSTOM_LABEL, _CUSTOM_HELP)
	_custom_button.pressed.connect(choose_custom)


func _mode_button(label: String, help: String) -> Button:
	var button := Button.new()
	button.text = label
	_paint_preset(button, false)
	Tooltip.attach(button, help, "", Tooltip.Side.BOTTOM)
	UiKit.touchable(button)
	_presets.add_child(button)
	return button


## Repaints in place rather than rebuilding: a preset is applied from the `pressed`
## of one of the strip's own buttons, and freeing that button mid-signal releases
## focus with nothing to give it back to — a keyboard or gamepad player pressing
## "2v2" was left with no focus owner at all.
##
## The seating goes on first and the grouping after it, because the sides are
## re-packed over whoever is left: applying them the other way round would settle a
## grouping across seats the same tap was about to close.
func _apply_preset(preset: Dictionary) -> void:
	_custom_chosen = false
	var seating: Array = preset.get("seats", [])
	for i in mini(_who.size(), seating.size()):
		_who[i] = int(seating[i])
	var pattern: Array = preset["sides"]
	for i in mini(_side.size(), pattern.size()):
		_side[i] = int(pattern[i])
	_settle_seats()
	changed.emit()


## The one writer for who sits at `index`. A press can still ask for a seat that may
## no longer close, from the frame before the table settled, and is answered by
## putting the row back.
func _set_seat(index: int, who: int) -> void:
	if index < 0 or index >= _who.size():
		return
	if who == Seat.EMPTY and not _can_close(index):
		_repaint_seats()
		return
	_who[index] = who
	_settle_seats()
	changed.emit()


## A letter pressed is Custom chosen, so landing on a table some Mode describes does
## not take the letters away from under the player's finger.
func _set_side(index: int, side: int) -> void:
	_custom_chosen = true
	_side[index] = side
	_repaint_seats()
	changed.emit()
