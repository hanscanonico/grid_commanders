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
## Whether the row is read off the disk (`refresh_from_disk`) or handed a posed
## slot (`refresh`) stays the menu's decision; this class reads no autoload and no
## command line.
##
## Two things can be waiting: the skirmish slot, and a campaign mission saved
## mid-battle into its war's profile. Continue offers whichever was saved last
## and its caption says which — "Day 4 · Scrimmage" or "Five Flags 02 · Day 1" —
## and a campaign mission is resumed by the campaign's own Resume, never by a
## second way of loading one. The skirmish slot itself is never written by a
## campaign, so what it holds keeps one meaning.


## A campaign mission waiting on the board it was saved with.
class Waiting:
	extends RefCounted

	var campaign_id: StringName
	## "Five Flags 02 · Day 1".
	var label: String
	var saved_at: int


## The air the card keeps around the button and the line under it.
const CARD_PAD := 3

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
## The campaign mission Continue resumes instead of the slot, or null.
var _waiting: Waiting
## Hands a war's id to the campaign's own Resume, which answers whether it found
## a board to resume.
var _on_resume_mission: Callable


func _init(into: VBoxContainer, on_resume: Callable, on_resume_mission: Callable) -> void:
	_on_resume = on_resume
	_on_resume_mission = on_resume_mission
	# One card, not two floating rows. The button and the line under it are a title
	# and its subtitle — "Continue" alone says nothing about which match — and a
	# caption left standing loose in the action column read as another orphan of the
	# rail rather than as this button's own words.
	var card := PanelContainer.new()
	# Flat and thin-edged: a card groups, it is not pressed, so the hard shadow
	# stays the button's inside it.
	var box := UiTheme.bordered(UiTheme.SLATE_800, UiTheme.HARD_BORDER, UiTheme.BORDER)
	box.set_content_margin_all(CARD_PAD)
	card.add_theme_stylebox_override("panel", box)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	card.add_child(body)
	into.add_child(card)

	# The one filled row under Start: resuming is the action a returning player came
	# for, so it outranks the two offers below it and stays a step under the match
	# it must not compete with.
	_button = UiKit.action_button("Continue", "", UiTheme.ButtonVariant.SECONDARY, null)
	_button.pressed.connect(_press)
	body.add_child(_button)
	# What Continue resumes, on its own line rather than as the button's inline
	# suffix: "Day 12 · The Straits" is longer than the 122px action stack can set
	# at button size. It is metadata about the button above it, not a control —
	# hence muted ink and no dotted rule. `refresh` sets the words.
	# Deliberately not wrapped: how tall this card stands may not depend on whether
	# there is a match to come back to (UX-recovery D2), and a wrapped subtitle is a
	# card one line taller on exactly the boards with the longest names.
	_caption = UiKit.help_label("")
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# A touch build prints a refusal's reason here too, and a codec's reason is
	# wider than the column: trimmed, it cannot push the menu off the canvas, and
	# the tip still carries it whole.
	_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	body.add_child(_caption)
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
	_waiting = null
	_render()


## `refresh` off this machine's disk: the skirmish slot, and the campaign mission
## saved last, which Continue offers in the slot's place when it is the later of
## the two.
func refresh_from_disk() -> void:
	_slot = SaveGame.status()
	_waiting = null
	var mission := waiting_mission()
	var slot_named := _slot.state == SaveGame.Slot.State.READABLE
	if mission != null and (not slot_named or mission.saved_at > SaveGame.saved_at()):
		_waiting = mission
	_render()


## The campaign mission saved most recently across every war, or null.
static func waiting_mission() -> Waiting:
	var latest: Waiting = null
	for campaign: CampaignDefinition in CampaignDB.load_default().all():
		var mission := campaign.mission(CampaignProfile.saved_mission(campaign.id))
		if mission == null:
			continue
		var summary := SaveCodec.summarize(CampaignProfile.load_battle(campaign.id))
		var waiting := Waiting.new()
		waiting.campaign_id = campaign.id
		waiting.label = (
			"%s %02d · Day %d"
			% [
				campaign.title,
				campaign.missions.find(mission) + 1,
				summary.day if summary != null else 1
			]
		)
		waiting.saved_at = CampaignProfile.saved_at(campaign.id)
		if latest == null or waiting.saved_at > latest.saved_at:
			latest = waiting
	return latest


func _render() -> void:
	if _waiting != null:
		_button.disabled = false
		_caption.text = _waiting.label
		_caption.add_theme_color_override("font_color", UiTheme.NEUTRAL)
		_tip.set_copy("Resume the campaign mission", "Picks up the board it was saved on")
		return
	if _slot.state == SaveGame.Slot.State.ABSENT:
		_refuse("No saved match", "Nothing saved yet", "Save during a battle")
		return
	# The codec's words when the slot itself will not read, the press's when the save
	# was nameable and would not open.
	var refusal := _slot.reason if _slot.state == SaveGame.Slot.State.UNREADABLE else _refusal
	if refusal != "":
		_refuse("Saved match unreadable", "That save cannot be opened", refusal)
		return
	_button.disabled = false
	_caption.text = _slot.summary.label()
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
	# A board that went missing since the menu opened is not offered again: the
	# disk is read afresh, and the row says what is left.
	if _waiting != null:
		if not _on_resume_mission.call(_waiting.campaign_id):
			refresh_from_disk()
		return
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
