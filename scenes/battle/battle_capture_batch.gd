class_name BattleCaptureBatch
extends RefCounted
## FS2/FS3 (COM-117, COM-118): the smoke sweep runs in one process — this
## class is how. tools/smoke_scenarios.sh passes the whole sweep as
## `--demos=a,b+fog,c@the_straits,…` with a shared `--shots-dir=`; each entry
## carries its own boot facts (`+fog` in the mode name, `@<map>` appended), a
## scene reload between scenarios is a fresh Battle in the same window, and
## the `menu_` pair runs through a scene change — so the whole sweep is one
## window rather than one per scenario (the point of the exercise — see the
## focus-steal plan).
##
## The queue lives in statics rather than on any instance: each scenario gets
## a fresh scene and with it a fresh driver (BattleScenarioDriver or
## MenuCaptureDriver), and statics are what survive the reloads in between. A
## non-batch capture passes through `finish_capture` unchanged, so both
## drivers have one ending either way.

const DEMOS_ARG := "--demos"
const SHOTS_DIR_ARG := "--shots-dir"
const SCENARIO_TIMEOUT_ARG := "--scenario-timeout"
## The `+fog` suffix is the sweep's label convention — the mode name is the
## label and the capture filename; the demo is what is left once it comes off,
## exactly as tools/smoke_scenarios.sh spells it for a single scenario. A
## `@<map>` suffix after the mode carries the entry's board (FS3, COM-118);
## it is a boot fact, never part of the label or the filename.
const FOG_SUFFIX := "+fog"
const MAP_SEPARATOR := "@"
## The two scenes a batch entry can call for. A `menu_` mode runs on the main
## menu, everything else on the battle scene; crossing between them is a scene
## change in the same window, which is what keeps the whole sweep one boot.
const MENU_PREFIX := "menu_"
const MENU_SCENE := "res://scenes/menu/main_menu.tscn"
const BATTLE_SCENE := "res://scenes/battle/battle.tscn"

static var _modes := PackedStringArray()
static var _index := 0
static var _dir := ""
static var _timeout := 0.0
static var _active := false


## The queue this process was launched with, or "" outside a batch — asked the
## way ScreenshotUtil.requested() is asked, and for the same reason. A batch
## carries no `--screenshot=` of its own, so anything guarding on "is this run
## here to be photographed?" has to ask both.
static func requested() -> String:
	return CmdArgs.value(CmdArgs.user(), DEMOS_ARG)


## Whether this process runs a batch, parsing the queue off the command line
## the first time it is asked. Every way into a batch goes through here: the
## first scenario's boot facts are read by `scenario_args()` before any driver
## exists to adopt it, so the parse cannot live in `adopt` alone or entry #1
## would boot on the process-level flags the sweep no longer passes. Reloads
## after the first find the queue already standing and take the next mode off
## it.
static func _adopted() -> bool:
	if _active:
		return true
	var args := CmdArgs.user()
	var demos := CmdArgs.value(args, DEMOS_ARG)
	if demos == "":
		return false
	_active = true
	_modes = demos.split(",")
	_index = 0
	_dir = CmdArgs.value(args, SHOTS_DIR_ARG)
	_timeout = float(CmdArgs.value(args, SCENARIO_TIMEOUT_ARG))
	return true


## Adopts the current batch scenario, when the command line carries a queue;
## answers whether it did. Called from either driver's _init so the scene's own
## capture pinning (game speed, the hint set) reads the current scenario's
## demo — and the per-scenario deadline (risk R3) is armed here for the same
## reason: a batch process is alive as long as *any* scenario progresses, so
## the budget has to live where the stuck scenario's name is known.
static func adopt(battle: Node) -> bool:
	if not _adopted():
		return false
	if _timeout > 0.0:
		var timer := battle.get_tree().create_timer(_timeout)
		timer.timeout.connect(_deadline.bind(_index, demo(), battle.get_tree()))
	return true


## The current entry's mode — the label half, with any `@<map>` boot fact off.
static func _mode() -> String:
	return _modes[_index].get_slice(MAP_SEPARATOR, 0)


## The demo the current batch scenario runs — its mode minus the label suffix.
static func demo() -> String:
	return _mode().trim_suffix(FOG_SUFFIX)


## Where the current scenario's capture lands: the mode name is the filename,
## colons to dashes, exactly as the sweep spells it for a single scenario.
static func shot_path() -> String:
	return _dir.path_join(_mode().replace(":", "-") + ".png")


## The command line the current scenario boots with. Outside a batch it is the
## process's own; inside one, the process-level --map/--fog are replaced by the
## current entry's, so `MatchRequest.apply_cmdline` reads per-scenario boot
## facts through the unchanged CLI grammar (FS3, COM-118).
static func scenario_args() -> PackedStringArray:
	var args := CmdArgs.user()
	if not _adopted():
		return args
	var out := PackedStringArray()
	for arg in args:
		if arg == "--fog" or arg.begins_with("--map="):
			continue
		out.append(arg)
	if _mode().ends_with(FOG_SUFFIX):
		out.append("--fog")
	var entry: String = _modes[_index]
	if entry.contains(MAP_SEPARATOR):
		out.append("--map=" + entry.get_slice(MAP_SEPARATOR, 1))
	return out


## The one capture ending. Mid-batch saves the frame and hands the window to
## the next scenario — a reload when it plays on the same scene, a scene
## change when the sweep crosses between the battle and the menu (FS3); the
## last scenario of a batch — and every non-batch capture — saves and quits as
## always. `gate` is the menu capture's chrome check, passed through to the
## same shutter the single-scenario path uses.
static func finish_capture(node: Node, path: String, gate := Callable()) -> void:
	if not _active or _index >= _modes.size() - 1:
		await ScreenshotUtil.capture_and_quit(node, path, gate)
		return
	var leaving_menu := demo().begins_with(MENU_PREFIX)
	if not await ScreenshotUtil.save_frame(node, path, gate):
		node.get_tree().quit(1)
		return
	_index += 1
	var err: Error
	if demo().begins_with(MENU_PREFIX) == leaving_menu:
		err = node.get_tree().reload_current_scene()
	else:
		var scene := MENU_SCENE if demo().begins_with(MENU_PREFIX) else BATTLE_SCENE
		err = node.get_tree().change_scene_to_file(scene)
	if err != OK:
		push_error("smoke batch: could not stage the scene for '%s'" % _modes[_index])
		node.get_tree().quit(1)


## R3's deadline, fired by the tree: a batch scenario still on stage past its
## budget fails the group by name. The sweep then re-runs the group's
## scenarios one process each (R2), where the stuck one meets the shell's own
## per-scenario timeout and message.
static func _deadline(index: int, mode: String, tree: SceneTree) -> void:
	if not _active or _index != index:
		return
	push_error("smoke batch: scenario '%s' exceeded its %ss deadline" % [mode, _timeout])
	tree.quit(1)
