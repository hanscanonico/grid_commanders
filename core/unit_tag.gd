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
			return "unit tag '%s' names two units" % tag
		seen[tag] = true
	return ""
