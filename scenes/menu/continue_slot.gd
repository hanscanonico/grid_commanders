class_name ContinueSlot
extends RefCounted
## The main menu's Continue row: the button, the line under it naming what would
## be resumed, its tip, and the press that opens the save.
##
## `MenuCampaignFlow`'s shape — a collaborator holding one coherent slice of a
## screen that was getting wide — and split off `MainMenu` for the same reason:
## the menu is a *setup* page, and whether there is a match to come back to is a
## different question from which board and how much fog.
##
## The slot is handed its `SaveGame.Slot` rather than fetching one, so whether
## that is the disk or a posed capture stays the menu's decision; this class
## reads no autoload and no command line.

## The slot as it was last handed over, so a press that fails to open the save can
## re-say the row without asking the menu where slots come from.
var _slot := SaveGame.Slot.absent()
## Why the last press could not open the save, or "" while none has failed. A save
## the caption could name may still be one `decode` refuses, and the press is the
## only place that is found out, so the refusal is kept for the next render.
var _refusal := ""
var _button: Button
## The Silkscreen line under the button naming what it resumes — "DAY 4 ·
## SCRIMMAGE".
var _caption: Label
var _tip: Tooltip
var _on_resume: Callable


func _init(into: VBoxContainer, on_resume: Callable) -> void:
	_on_resume = on_resume
	# The one filled row under Start: resuming is the action a returning player came
	# for, so it outranks the two offers below it and stays a step under the match
	# it must not compete with.
	_button = UiKit.action_button("Continue", "", UiTheme.ButtonVariant.SECONDARY, null)
	_button.pressed.connect(_press)
	into.add_child(_button)
	# What Continue resumes, on its own line rather than as the button's inline
	# suffix: "DAY 12 · THE STRAITS" is longer than the 122px action stack can set
	# at button size, and a micro-label under the control is the panel's own idiom.
	# It is metadata about the button above it, not a control — hence muted ink and
	# no dotted rule. `refresh` sets the words.
	_caption = UiKit.micro_label("")
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	into.add_child(_caption)
	# The tip hangs off the button itself: a disabled control still answers the
	# pointer, so the one control here that can be disabled is also the one place
	# the explanation is always reachable.
	_tip = Tooltip.attach(_button, "", "", Tooltip.Side.BOTTOM)


## The button itself, for the menu's capture chrome and its focus walk.
func button() -> Button:
	return _button


## Names the saved match under the button, so the menu alone answers "is this the
## match I meant?" — the whole point of labelling the slot. The day and board are
## read off the save envelope's own keys (SaveGame.status); nothing is rebuilt,
## and the save format is untouched.
##
## Three captions, because the slot has three answers: a player told "no saved
## match" about a save the disk truncated is told they never had one (COM-121).
## A damaged save disables Continue like an empty slot does, and says why in the
## codec's own words rather than in the codec's log.
func refresh(slot: SaveGame.Slot) -> void:
	_slot = slot
	_render()


func _render() -> void:
	if _slot.state == SaveGame.Slot.State.ABSENT:
		_refuse("NO SAVED MATCH", "Nothing saved yet", "Save in battle from the map menu")
		return
	# The codec's words when the slot itself will not read, the press's when the save
	# was nameable and would not open.
	var refusal := _slot.reason if _slot.state == SaveGame.Slot.State.UNREADABLE else _refusal
	if refusal != "":
		_refuse("SAVED MATCH UNREADABLE", "That save cannot be opened", refusal)
		return
	_button.disabled = false
	_caption.text = _slot.summary.label().to_upper()
	# Muted, because it is a note about the button above it rather than something to
	# press — but not the dimmer NEUTRAL_DARK, which is barely legible out here.
	_caption.add_theme_color_override("font_color", UiTheme.NEUTRAL)
	# The caption already names the day and board, so the tip does not repeat them.
	_tip.set_copy("Resume the saved match", "Its own board and commanders apply")


## Continue with nothing to offer: the dim NEUTRAL_DARK of PRESS START, because it
## explains a disabled button and must not read as loudly as a match waiting to be
## resumed.
func _refuse(caption: String, tip: String, detail: String) -> void:
	_button.disabled = true
	_caption.text = UiKit.caption_with_reason(caption, detail)
	_caption.add_theme_color_override("font_color", UiTheme.NEUTRAL_DARK)
	_tip.set_copy(tip, detail)


## The saved match applies its own map, commanders and AI sides — and is opened
## here, on the press, rather than on every boot: naming a save opens no board, so
## one the caption named can still be one `decode` refuses. Staging that anyway
## boots the battle scene onto the fresh match the request also states, on
## whatever board the picker is showing, with nothing said (COM-121).
func _press() -> void:
	var chart: DamageChart = load(DamageChart.DEFAULT_PATH)
	var loaded := SaveGame.load_game(
		TerrainDB.load_default(),
		UnitDB.load_default(),
		chart,
		SaveGame.SAVE_PATH,
		CommanderDB.load_default()
	)
	if loaded == null:
		# Which of the two it is the log says; a player can act on either.
		_refusal = "Its board may have changed, or the file is damaged"
		_render()
		return
	_on_resume.call()
