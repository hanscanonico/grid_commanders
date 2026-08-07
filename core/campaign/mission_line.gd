class_name MissionLine
extends Resource
## One line of a mission's briefing or debrief, and who says it.
##
## A campaign is a conversation between the generals fighting it, so a line
## carries its speaker rather than being narration with a name written into the
## words. That is what lets the briefing print the general's own name in their
## faction's colour, and it is why `speaker` is a **commander id** rather than a
## display name: the roster already owns what a general is called and what
## colour they wear, and a name typed into a hundred mission files is a hundred
## places for it to drift out of date.
##
## An empty speaker is narration — the card text a scene needs when nobody is
## talking ("The line goes dark end to end"). Deliberately the default, so a
## line that forgets to name anyone reads as the narrator rather than as a
## general nobody can identify.

## A commander id from `CommanderDB`, or "" for narration.
@export var speaker: StringName = &""
@export_multiline var text: String = ""


static func of(p_speaker: StringName, p_text: String) -> MissionLine:
	var line := MissionLine.new()
	line.speaker = p_speaker
	line.text = p_text
	return line


func is_narration() -> bool:
	return speaker == &""


## Why this line could not be spoken, or "". A speaker who is not on the roster
## is the failure worth catching: it prints as a blank name beside real dialogue,
## which looks like a rendering bug rather than a typo in a data file.
func definition_error(commander_db: CommanderDB) -> String:
	if text.strip_edges() == "":
		return "a line has no words"
	if speaker != &"" and not commander_db.has(speaker):
		return "'%s' speaks, but is not on the roster" % speaker
	return ""
