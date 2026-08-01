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
## `--demo=menu_setup_context` poses the hot-seat setup without leaving the menu.
## Its gate also proves that the tutorial board leads, its description is printed, every
## help line has copy, and AI difficulty follows the mode — it walks the mode back
## to one player and out again, because "disabled" photographs the same whether it
## can be undone or not. It measures the caption on every board for the same
## reason: the reserved lines must hold for a board this frame does not show.
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
const DEMO_ARG := "--demo"
const DEMO_WITH_SAVE := "menu_with_save"
const DEMO_NO_SAVE := "menu_no_save"
const DEMO_SETUP_CONTEXT := "menu_setup_context"
const DEMO_REPLAYS := "menu_replays"
const DEMO_MODES: Array[String] = [DEMO_WITH_SAVE, DEMO_NO_SAVE, DEMO_SETUP_CONTEXT, DEMO_REPLAYS]
## The day `menu_with_save` poses. Three digits because days are uncapped and the
## caption is set at micro size in the 122px action column — a capture that only
## ever photographs "DAY 4" proves nothing about a long campaign. The board it
## names is the roster's longest, handed in by the menu rather than typed here,
## in the tradition of `--co-select=<commander_id>`.
const POSED_SAVE_DAY := 128
## What `menu_replays` lists. The first is about as long as a real label gets —
## the widest board name against two of the longest commander names.
const POSED_REPLAY_LABELS: Array[String] = [
	"Steelworks · Cassian Rook vs Viktor Draeg",
	"Compass · Alina Ward vs Sable Wren",
	"Boot Camp · Player 1 vs CPU",
]

var _menu: Control
var _demo := ""
var _shot_path := ""


func _init(menu: Control) -> void:
	_menu = menu
	_shot_path = ScreenshotUtil.requested()
	_demo = CmdArgs.value(CmdArgs.user(), DEMO_ARG)
	# A smoke batch (--demos=, COM-118) supersedes both — the menu pair runs
	# inside the one-boot sweep, reached by a scene change.
	if BattleCaptureBatch.adopt(menu):
		_demo = BattleCaptureBatch.demo()
		_shot_path = BattleCaptureBatch.shot_path()


## Where this run's frame lands, batch or not, or "" on an ordinary launch —
## the menu asks this instead of ScreenshotUtil so a batched menu scenario
## pins and captures exactly as a --screenshot= one does.
func shot_path() -> String:
	return _shot_path


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


func poses_setup_context() -> bool:
	return _demo == DEMO_SETUP_CONTEXT


func poses_replays() -> bool:
	return _demo == DEMO_REPLAYS


## The recording list `menu_replays` poses, for the reason `posed_slot` poses a
## save: how many matches the machine that took the frame happens to have played
## is not something a capture may depend on. Long labels rather than tidy ones —
## the row is the widest thing on the page, and a frame that only ever
## photographed "Forge · Player 1 vs CPU" would prove nothing about a real one.
func posed_replays() -> Array[ReplayFile.Summary]:
	var posed: Array[ReplayFile.Summary] = []
	for i in POSED_REPLAY_LABELS.size():
		var summary := ReplayFile.Summary.new()
		summary.path = "user://replays/posed-%d%s" % [i, ReplayFile.EXTENSION]
		summary.label = POSED_REPLAY_LABELS[i]
		# Spelled the way a recording spells it — `Time.get_datetime_string_from_system`
		# — so the posed row is the shape of a real one. Only the *file* name mangles
		# the colons, and that never reaches the page.
		summary.recorded = "2026-08-0%dT19:06:48" % (i + 1)
		posed.append(summary)
	return posed


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


## Saves one frame and ends the run — a quit, or the batch's hand-off to the
## next scenario — after the chrome `chrome_source` names clears the frame check.
## A `--co-select` capture photographs the selection page over a hidden menu, so
## it hands in that page's own chrome instead: the menu's geometry is not what
## that picture claims.
##
## The chrome is asked for as a callable rather than handed over as a dictionary
## because the controls it names are not all the ones the screen ends up with: the
## seat strip re-deals its rows whenever the roster changes, so a list gathered at
## build time holds freed nodes by the time the shutter fires.
##
## The frame check goes in as the capture's gate rather than being run here, so it
## measures the settled layout the PNG is written from. A container that sorted
## its children a frame late would otherwise be measured small — or at zero size,
## which any frame trivially encloses — and the gate would pass on a layout that
## is not the one photographed.
##
## The setup-context check is the one that cannot: it *walks* the menu — every
## board's caption, the table with and without a computer at it — and each step
## re-deals the seat strip, freeing its rows and adding new ones. Run from inside
## the gate it left them unsorted at the moment the shutter fired, and the
## acceptance frame for the seat strip photographed bare panel (COM-48). So it
## runs here, on a settled frame of its own, and hands its verdict forward:
## ScreenshotUtil's settle then lays the restored strip out before the frame is
## written. The walk is not wrong; the picture was early.
func capture(path: String, chrome_source: Callable) -> void:
	var context_ok := true
	if poses_setup_context():
		for i in ScreenshotUtil.SETTLE_FRAMES:
			await _menu.get_tree().process_frame
		context_ok = bool(_menu.call("_setup_context_ready"))
	var gate := _capture_gate.bind(chrome_source, context_ok)
	await BattleCaptureBatch.finish_capture(_menu, path, gate)


## Deliberately not short-circuiting anywhere: a failed run should name every
## promise that broke, not just the first.
##
## `_fits` is not the whole gate because enclosure cannot tell blank from present.
## Rows a container has not sorted yet keep their minimum size and stack at its
## origin — inside every frame, and drawn in none of it — which is exactly how the
## seat strip came to be photographed as bare panel. So the strip is asked whether
## it is the table it was dealt, the way the commander sheet is (COM-48, FP4).
func _capture_gate(chrome_source: Callable, context_ok: bool) -> bool:
	var fits := _fits(chrome_source.call())
	var laid_out := bool(_menu.call("_seats_laid_out"))
	return fits and laid_out and context_ok


## Every named control lies fully inside the logical frame.
##
## The menu hands in its whole centered column, every seat row *and* its three
## primary actions.
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
