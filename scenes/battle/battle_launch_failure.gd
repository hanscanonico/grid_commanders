class_name BattleLaunchFailure
extends CanvasLayer
## What the battle scene does when there is no match to build: say why, and offer
## the one thing still possible — the way out.
##
## `Battle` disables itself when `BattleSetup` hands back no match, which is what
## makes "nothing can reach a null map" true by construction rather than a null
## check per handler. That left a board nothing answered on — no key, no button,
## no Esc — and in an export build the pushed error goes only to a log the player
## never reads, so the only way out of a failed campaign resume or a stale replay
## was killing the application. This card is its own CanvasLayer at
## `PROCESS_MODE_ALWAYS`: it processes while the board does not, so the invariant
## keeps holding and the exit is there.

const LAYER := 10
const TITLE := "NO MATCH TO PLAY"


## The whole of what a launch with no match does. A capture run quits instead:
## nothing will ever drive it, and a headless run with no input to be inert
## against would otherwise sit here until `make smoke` timed it out. Non-zero,
## like a capture that fails its own gate.
static func present(battle: Battle, message: String) -> void:
	if ScreenshotUtil.requested() != "" or BattleCaptureBatch.requested() != "":
		battle.get_tree().quit(1)
		return
	var card := BattleLaunchFailure.new()
	card.process_mode = Node.PROCESS_MODE_ALWAYS
	card.layer = LAYER
	battle.add_child(card)
	card.show_failure(message, battle.exit.to_main_menu)


## Draws the sentence `BattleSetup` composed and wires the single button, which
## goes where `BattleExit` sends every other way out of a match.
func show_failure(message: String, on_leave: Callable) -> void:
	var page := Control.new()
	add_child(page)
	UiKit.page_veil(page)
	var body := UiKit.page_body(page, UiTheme.GAP)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(UiKit.page_title(TITLE))
	var note := UiKit.page_note(message)
	# A board path is most of some of these sentences, and the page is only as
	# wide as the window.
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(row)
	var button := UiKit.action_button("Main Menu", "", UiTheme.ButtonVariant.PRIMARY, null, 140)
	button.pressed.connect(on_leave)
	row.add_child(button)
	button.grab_focus.call_deferred()
