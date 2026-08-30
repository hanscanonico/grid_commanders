class_name MapHistory
extends RefCounted
## What the map editor can take back: one step per stroke of the brush.
##
## A step is a whole snapshot of the draft rather than the edit that made it —
## a `MapDocument.copy()`, taken when a stroke ends. A board is small enough
## that a copy costs nothing, and an inverse edit per brush would be a second
## account of what painting does, wrong in exactly the corner nobody tested.
##
## The unit of a step is the *stroke*, not the cell: a drag that crosses forty
## cells is one press of Undo, because it was one thing the author did. Who says
## a stroke ended is the caller — only the hand on the board knows when a finger
## lifted — so this class is told, never guesses.
##
## Node-free like the rest of `core/`.

## How many strokes stand behind the draft at most. Deep enough that an author
## never reaches the end of it in practice, shallow enough that the copies stay
## a rounding error.
const DEPTH := 100

## The draft as of the last stroke that landed — what Undo restores *from* and
## Redo restores *to*.
var _present: MapDocument
var _past: Array[MapDocument] = []
var _future: Array[MapDocument] = []


## Starts over on `doc`: this is the board now, with nothing behind it. Opening
## or creating a draft calls it; saving one does not.
func begin(doc: MapDocument) -> void:
	_present = doc.copy()
	_past.clear()
	_future.clear()


## A stroke landed on `doc`. The board as it stood before it goes behind, and
## the redo tail goes: a new stroke is a different future from the one that was
## undone away.
func record(doc: MapDocument) -> void:
	if _present == null:
		begin(doc)
		return
	_past.append(_present)
	if _past.size() > DEPTH:
		_past.pop_front()
	_present = doc.copy()
	_future.clear()


func can_undo() -> bool:
	return not _past.is_empty()


func can_redo() -> bool:
	return not _future.is_empty()


## Puts the stroke before this one back into `doc`, and whether there was one.
func undo(doc: MapDocument) -> bool:
	if not can_undo():
		return false
	_future.append(_present)
	_present = _past.pop_back()
	doc.adopt(_present)
	return true


## Puts back the stroke the last undo took away, and whether there was one.
func redo(doc: MapDocument) -> bool:
	if not can_redo():
		return false
	_past.append(_present)
	_present = _future.pop_back()
	doc.adopt(_present)
	return true
