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
##
## A line may also carry a condition on the consequence ledger, which is how a
## briefing reads differently after a different mission five. That is for the
## words **around** a fight — the briefing and the debrief — and
## `MissionDefinition.story_error` refuses it on a scripted beat's lines: a
## recording re-issues the beat and must speak the same words, and a beat the war
## decides is a beat with a `Flag` trigger.

## A commander id from `CommanderDB`, or "" for narration.
@export var speaker: StringName = &""
@export_multiline var text: String = ""

@export_group("The war so far")
## How the consequence ledger must read for these words to be said, or null for
## the line every player hears. This is what makes a briefing different after a
## different mission five.
@export var requires: FlagCondition
## How it must **not** read. Both may be set, which says "this, unless that".
@export var unless: FlagCondition


static func of(p_speaker: StringName, p_text: String) -> MissionLine:
	var line := MissionLine.new()
	line.speaker = p_speaker
	line.text = p_text
	return line


func is_narration() -> bool:
	return speaker == &""


## Is this line said, on the ledger as it stands? A line with no condition always
## is, which is what leaves every mission authored before the ledger rendering
## exactly as it did.
func is_spoken(ledger: CampaignState) -> bool:
	if requires != null and not requires.holds(ledger):
		return false
	return unless == null or not unless.holds(ledger)


func is_conditional() -> bool:
	return requires != null or unless != null


## The bands on the war this line reads, in no order — the one place the pair is
## walked, so a caller checking them and a caller gathering the names they ask
## after cannot come to disagree about which of them count.
func conditions() -> Array[FlagCondition]:
	var read: Array[FlagCondition] = []
	for condition: FlagCondition in [requires, unless]:
		if condition != null:
			read.append(condition)
	return read


## The lines of a briefing or a debrief that are actually said, in the order they
## were authored — the one filter, because two screens print these words.
##
## **Each line is included on its own**: there are no alternative groups, so two
## readings of one beat are two adjacent lines with opposite conditions and an
## author reads the list top to bottom. A group would need a second construct to
## say which member is the default, and a set whose conditions all fail would
## then have to fall back to something nobody wrote.
static func spoken(lines: Array[MissionLine], ledger: CampaignState) -> Array[MissionLine]:
	var said: Array[MissionLine] = []
	for line: MissionLine in lines:
		if line != null and line.is_spoken(ledger):
			said.append(line)
	return said


## Why one of these lines could not be spoken, or "". The one walk over a list of
## them, because four things hold a list — a briefing, a debrief, a scripted beat
## and an interlude — and `variants_allowed` is the single thing they differ on:
## a beat's lines are re-issued by a recording and must speak the same words, so
## a beat the war decides is a beat with a `Flag` trigger.
##
## A list whose every member is gated is refused, because `spoken` filters the
## set and there is deliberately no fallback member: on a route where none of the
## conditions holds the page renders wordless, and the player presses Continue on
## an empty briefing, debrief or interlude.
static func list_error(
	lines: Array[MissionLine], commander_db: CommanderDB, variants_allowed: bool
) -> String:
	var always_said := false
	for line: MissionLine in lines:
		if line == null:
			return "an empty story line"
		if line.is_conditional() and not variants_allowed:
			return "a line the ledger gates; gate the beat with a Flag trigger instead"
		var error := line.definition_error(commander_db)
		if error != "":
			return error
		always_said = always_said or not line.is_conditional()
	if not lines.is_empty() and not always_said:
		return (
			"every line here is gated by the ledger; "
			+ "one of them has to be the words every player hears"
		)
	return ""


## Why this line could not be spoken, or "". A speaker who is not on the roster
## is the failure worth catching: it prints as a blank name beside real dialogue,
## which looks like a rendering bug rather than a typo in a data file.
func definition_error(commander_db: CommanderDB) -> String:
	if text.strip_edges() == "":
		return "a line has no words"
	if speaker != &"" and not commander_db.has(speaker):
		return "'%s' speaks, but is not on the roster" % speaker
	for condition: FlagCondition in conditions():
		var error := condition.definition_error()
		if error != "":
			return error
	return ""
