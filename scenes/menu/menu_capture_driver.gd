class_name MenuCaptureDriver
extends RefCounted
## Dev-only: parses the main menu's capture command line, poses the save slot the
## asked-for mode wants, and gates the frame before it is written.
##
## The battle scene's BattleScenarioDriver in miniature, and for the same reasons:
## it depends on the menu, nothing on the menu's own path depends on it, and it
## keeps the capture apparatus out of a screen that is already long. It drives no
## flow — the menu has one screen and no scripted route through it — so what is
## left is the two things a menu capture needs that a battle capture does not.
##
## First, the slot. `--demo=menu_with_save` poses a resumable match and
## `--demo=menu_no_save` poses none, both through `MainMenu._refresh_continue`'s
## ordinary path with a real `SaveCodec.Summary`. Neither reads nor writes the
## `user://save.json` of the machine taking the picture: the menu's shape must not
## depend on whether this machine has a match in progress, so neither may the
## capture that proves it.
##
## Second, the gate. An overflowing menu renders a perfectly good picture, so a
## smoke scenario that only proved a frame was written would have sailed straight
## past COM-5 — where a save's presence pushed the title off the top of the
## 640×360 frame and Quit off the bottom, and every returning player met a
## visibly broken primary menu while a fresh install never did. `check` measures
## the chrome instead, in the tradition of the cut-in modes reading their atlas
## rows back off the posed art rather than trusting the frame.

## Spelled exactly like the battle scene's, and routed by `make smoke`: a mode
## whose name begins `menu_` boots this screen instead of the board.
const DEMO_ARG := "--demo="
const DEMO_WITH_SAVE := "menu_with_save"
const DEMO_NO_SAVE := "menu_no_save"
const DEMO_MODES: Array[String] = [DEMO_WITH_SAVE, DEMO_NO_SAVE]
## The day `menu_with_save` poses. Three digits because days are uncapped and the
## caption is set at micro size in the 122px action column — a capture that only
## ever photographs "DAY 4" proves nothing about a long campaign. The board it
## names is the roster's longest, handed in by the menu rather than typed here,
## in the tradition of `--co-select=<commander_id>`.
const POSED_SAVE_DAY := 128

var _menu: Control
var _demo := ""


func _init(menu: Control) -> void:
	_menu = menu
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(DEMO_ARG):
			_demo = arg.get_slice("=", 1)


## True when the command line named a mode this driver does not implement, and
## has already said so. The caller aborts the run: the battle driver's rule, that
## a misspelled mode fails rather than quietly photographing some other frame
## under the acceptance mode's name.
func rejected() -> bool:
	if _demo == "" or DEMO_MODES.has(_demo):
		return false
	push_error("main menu: unknown demo mode: %s" % _demo)
	return true


## True when a capture mode owns the save slot, so the menu must ask this driver
## what the slot holds instead of reading the disk.
func poses_slot() -> bool:
	return DEMO_MODES.has(_demo)


## The slot the current mode poses: a resumable match on `menu_with_save`, and
## null — an empty slot — on `menu_no_save`, whatever the running machine has
## saved. The match named is on the roster's longest-named board, so the posed
## caption is the widest the shipped maps can actually produce.
func posed_slot(maps: Array[MapData]) -> SaveCodec.Summary:
	if _demo != DEMO_WITH_SAVE:
		return null
	var summary := SaveCodec.Summary.new()
	summary.day = POSED_SAVE_DAY
	var width := 0
	for map in maps:
		var length := MapCatalog.display_name(map.source_path).length()
		if length > width:
			width = length
			summary.map_path = map.source_path
	return summary


## Saves one frame and quits — after `chrome` clears the frame check, if it was
## given any. A `--co-select` capture photographs the selection page over a
## hidden menu and passes none: the menu's own geometry is not what that picture
## claims.
##
## The check goes in as the capture's gate rather than being run here, so it
## measures the settled layout the PNG is written from. A container that sorted
## its children a frame late would otherwise be measured small — or at zero size,
## which any frame trivially encloses — and the gate would pass on a layout that
## is not the one photographed.
func capture(path: String, chrome: Dictionary) -> void:
	var gate := Callable() if chrome.is_empty() else _fits.bind(chrome)
	await ScreenshotUtil.capture_and_quit(_menu, path, gate)


## Every named control lies fully inside the logical frame.
##
## The menu hands in its whole centered column *and* its four primary actions.
## The column is the load-bearing check: a too-tall one is centered into an
## offset that runs off both ends at once, so its individual children are poor
## witnesses — the wordmark's own rect sat at exactly y=0 in a build whose title
## was visibly sheared, because the header row's icon took the overflow. Naming
## the actions as well is what makes a failure say which promise broke.
func _fits(chrome: Dictionary) -> bool:
	var frame := _menu.get_viewport_rect()
	var fits := true
	for label: String in chrome:
		# Deliberately not short-circuiting: one failed run should name every
		# control that left the frame, not just the first.
		fits = _control_fits(label, chrome[label], frame) and fits
	return fits


func _control_fits(label: String, control: Control, frame: Rect2) -> bool:
	var rect := control.get_global_rect()
	if frame.encloses(rect):
		return true
	push_error(
		"main menu overflows: %s occupies %s, outside the %s frame" % [label, rect, frame.size]
	)
	return false
