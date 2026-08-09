class_name CampaignInterlude
extends Resource
## The page between two blocks of a campaign: what the run of missions that just
## closed cost, and what the war did about it.
##
## The briefing's and the debrief's third sibling, and deliberately the same kind
## of thing: a list of `MissionLine`s with speakers, drawn by `MissionSpeech`, so
## a general talking between acts is drawn exactly as one talking before a
## battle. It has no board, no objective and no outcome — the menu shows it on
## the way back from the mission that closed the block and then opens the hub.
##
## Its lines carry CD4's `requires` / `unless` conditions rather than a second
## kind of variant, which is what lets a block that went badly read differently
## from one that went well. That is the whole of its branching: an interlude
## decides nothing and only ever says something.

## The block this follows, counting from 0 over `CampaignDefinition.block_titles`.
@export var after_block: int = 0
## What the page is called, over the words. Empty is a page with no header.
@export var title: String = ""
@export var lines: Array[MissionLine] = []


## Every fact this page reads the war for, for the campaign-wide check that some
## mission writes it — `MissionDefinition.read_flags`' shape, at the width a page
## of dialogue has.
func read_flags() -> Array[StringName]:
	var read: Array[StringName] = []
	for line: MissionLine in lines:
		if line == null:
			continue
		for condition: FlagCondition in line.conditions():
			read.append(condition.flag)
	return read


## Why this page could not be shown, or "". A page with nothing to say is the
## slip worth catching: the block closes, the menu opens a page, and the player
## presses Continue on an empty screen.
func definition_error(commander_db: CommanderDB) -> String:
	if lines.is_empty():
		return "the interlude after block %d has nothing to say" % after_block
	var error := MissionLine.list_error(lines, commander_db, true)
	return "" if error == "" else "the interlude after block %d: %s" % [after_block, error]
