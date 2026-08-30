class_name MapDefect
extends RefCounted
## One thing wrong with a board: the sentence its author reads, and the cells the
## sentence is about.
##
## The cells travel with the words because the only thing that knows which cell a
## complaint means is the rule that made the complaint. An editor that found them
## again by reading the sentence — or by re-running the same scan — would be a
## second opinion on *which* headquarters, and it would light the wrong one on
## exactly the boards the complaint is hardest to read on. An empty list is a
## complaint about the whole board rather than about any cell of it.
##
## Node-free like the rest of `core/`.

var text := ""
var cells: Array[Vector2i] = []


static func at(sentence: String, on: Array[Vector2i] = []) -> MapDefect:
	var defect := MapDefect.new()
	defect.text = sentence
	defect.cells = on
	return defect
