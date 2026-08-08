class_name Seating
extends RefCounted
## The seating/roster arithmetic `GameState.create` and `SaveCodec` both answer
## through (COM-184): which seats a match fills, what a reduced roster leaves
## standing, and where each army began. Pure and static, over a map and a list of
## seat numbers — nothing here holds a running board, which is what lets a save
## being decoded ask the same questions `create` does about a match that has not
## started yet.


## The first seat a seating names twice, or 0 — no board deals seat 0 — when it
## names none twice.
##
## A repeat is refused rather than absorbed, even though the roster it would have
## produced is the right one: it is a seating nobody could have meant, `_filled_seats`
## would silently make it mean something, and the count check would then report a
## short roster for a list that names enough seats. It is also what a save is held to
## (`SaveCodec._is_seatable`), and two authorities answering "is this a legal seating"
## differently is how the two drift apart.
static func _repeated_seat(seats: Array[int]) -> int:
	var seen: Dictionary[int, bool] = {}
	for team in seats:
		if seen.has(team):
			return team
		seen[team] = true
	return 0


## The seats a seating names that the board never dealt, in the order named. Empty
## `seats` names nothing and so misses nothing.
##
## Refusing on these rather than quietly dropping them is the same decision as
## refusing a seating that leaves one army: `--seats=` is typed by hand, and a typo
## that narrows the roster in silence launches a different match than the one asked
## for — which is the failure nobody would think to look for.
static func _unseated(roster: Array[int], seats: Array[int]) -> Array[int]:
	var unknown: Array[int] = []
	for team in seats:
		if not roster.has(team):
			unknown.append(team)
	return unknown


## The board's roster narrowed to the seats a match fills, in seat order. Empty
## `seats` is every one of them; every seat named is one the board deals, which
## `_unseated` has already answered for.
##
## Never a renumber: closing seat 2 of four leaves `[1, 3, 4]`, because `[owners]`,
## `[units]`, the liveries and the commander picks are all keyed by the seat's own
## number. Turn order is roster order over what is left, and the day still wraps on
## the roster, so a gap costs nothing — both read the list by index.
static func _filled_seats(roster: Array[int], seats: Array[int]) -> Array[int]:
	if seats.is_empty():
		return roster
	var filled: Array[int] = []
	for team in roster:
		if seats.has(team):
			filled.append(team)
	return filled


## The board's starting ownership with the vacant seats' ground opened up. A
## property nobody at the table owns is neutral rather than absent from the board:
## it is the prize a reduced match is played over.
static func _owners_of(map: MapData, roster: Array[int]) -> Dictionary[Vector2i, int]:
	var owners := map.initial_owners()
	for cell: Vector2i in owners.keys():
		if not roster.has(owners[cell]):
			owners.erase(cell)
	return owners


## Where each of `roster` starts: `team -> HQ cell`, for the seats a board deals an
## HQ. **The one derivation of a home HQ**, shared by `GameState.create` and by the
## codec reading a save written before the field existed — which is exact, because
## such a save always played the board's full roster and every army still began on
## the HQ its map file gave it.
##
## Read off the map rather than off a running board on purpose: mid-match, a
## conqueror owns the HQ it took as well as the one it started on, so "the HQ this
## team owns" stops being a question with one answer. The map's answer never moves.
##
## Cells are walked in sorted order so a board that hands one seat two HQs still
## names the same home every time it is loaded.
static func home_hqs(map: MapData, roster: Array[int]) -> Dictionary[int, Vector2i]:
	var owners := map.initial_owners()
	var cells: Array[Vector2i] = []
	for cell: Vector2i in owners:
		cells.append(cell)
	cells.sort()
	var homes: Dictionary[int, Vector2i] = {}
	for cell in cells:
		var team: int = owners[cell]
		if not homes.has(team) and roster.has(team) and map.terrain_at(cell).is_headquarters:
			homes[team] = cell
	return homes
