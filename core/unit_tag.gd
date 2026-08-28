class_name UnitTag
extends RefCounted
## What a name a board gives a unit may be, stated once.
##
## `Unit.tag` reaches the board by two routes — a map's `[units]` row and a save's
## unit list — and a rule either of them kept an opinion of its own about is a rule
## the other could contradict, which is the shape `LoadCommand.carriage_error` is
## already in: a hand-edited save must not be able to seat a board state the parser
## would have refused.
##
## An empty tag is the ordinary unnamed unit and is always legal, so neither a board
## nor a save is held to naming anything.

const _TAKEN := "unit tag '%s' names two units"


## "" when `tag` may name a unit, else why it may not. An identifier because a tag
## is authored in a `.tres` beside code.
static func name_error(tag: StringName) -> String:
	if tag == &"" or String(tag).is_valid_ascii_identifier():
		return ""
	return "unit tag '%s' is not an identifier" % tag


## "" when no two of `tags` are the same name, else why they may not be. A tag
## naming two units names neither — an objective asking whether it still stands
## would have two answers.
static func duplicate_error(tags: Array[StringName]) -> String:
	var seen: Dictionary = {}
	for tag: StringName in tags:
		if tag == &"":
			continue
		if seen.has(tag):
			return _TAKEN % tag
		seen[tag] = true
	return ""


## "" when `tag` is free beside the names already `taken`, else why it is not.
## `duplicate_error` answers for a whole list at once, which is what a decoded
## save hands it; a parser reading one row at a time is asking about one name,
## and asking the list question per row rescans every earlier name into a fresh
## dictionary. Same refusal, same words, so neither door can grow its own wording.
static func taken_error(tag: StringName, taken: Array[StringName]) -> String:
	if tag == &"":
		return ""
	for other: StringName in taken:
		if other == tag:
			return _TAKEN % tag
	return ""
