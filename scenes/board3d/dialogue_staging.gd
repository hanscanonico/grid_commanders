class_name DialogueStaging
extends RefCounted
## How a general acts out a line in a 3D cinematic, read off the words alone.
##
## The campaign's lines carry a speaker and their words and nothing else — no
## stage directions — so the performance is inferred from how a line is written:
## an exclamation is a raised fist or a pointed finger, a question a shrug, a
## trailing ellipsis a sigh, a laugh a laugh, an order acknowledged a salute. A
## line with none of those is plain talk. A cue is a whole word, and an
## acknowledgement or a refusal opens the line: "I stayed" is no "aye", and "at
## once" mid-sentence is no order taken. Pure, so the same words are always
## acted the same way — a replay speaks and gestures exactly as the match did.

## The emote that pops over a speaker's head as their line opens, or none.
const EXCLAIM := &"!"
const ASK := &"?"
const TRAIL := &"..."
const NO_EMOTE := &""

const _LAUGHS: Array[String] = ["ha!", "haha", "ha ha", "heh"]
const _SALUTES: Array[String] = ["yes, sir", "yes sir", "understood", "at once", "aye"]
const _REFUSALS: Array[String] = ["no.", "no,", "never", "not a chance"]


## The clip a speaker plays while saying `words` (an `ActorPose3D` clip name).
## `beat` is how many lines this speaker has said before in the scene, so two
## exclamations in a row alternate the fist and the pointed finger.
static func gesture_for(words: String, beat: int = 0) -> StringName:
	var said := words.strip_edges().to_lower()
	if _mentions(said, _LAUGHS):
		return &"laugh"
	if _opens_with(said, _SALUTES):
		return &"salute"
	if _opens_with(said, _REFUSALS):
		return &"shake"
	if said.ends_with("...") or said.ends_with("…"):
		return &"sigh"
	if said.ends_with("?"):
		return &"shrug"
	if said.contains("!"):
		return &"fist" if beat % 2 == 0 else &"point"
	return &"talk"


## The emote a line opens with: "!" for an exclamation, "?" for a question, "..."
## for a line that trails off; none for plain talk.
static func emote_for(words: String) -> StringName:
	var said := words.strip_edges()
	if said.ends_with("...") or said.ends_with("…"):
		return TRAIL
	if said.ends_with("?"):
		return ASK
	if said.contains("!"):
		return EXCLAIM
	return NO_EMOTE


static func _mentions(said: String, cues: Array[String]) -> bool:
	for cue in cues:
		var at := said.find(cue)
		while at >= 0:
			if _whole_word(said, at, cue.length()):
				return true
			at = said.find(cue, at + 1)
	return false


static func _opens_with(said: String, cues: Array[String]) -> bool:
	for cue in cues:
		if said.begins_with(cue) and _whole_word(said, 0, cue.length()):
			return true
	return false


static func _whole_word(said: String, at: int, length: int) -> bool:
	var before := said.substr(at - 1, 1) if at > 0 else ""
	return not _is_letter(before) and not _is_letter(said.substr(at + length, 1))


static func _is_letter(character: String) -> bool:
	return character.to_lower() != character.to_upper()
