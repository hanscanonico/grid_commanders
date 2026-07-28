class_name BattleCaptureBatch
extends RefCounted
## FS2 (COM-117): the smoke sweep boots one process per boot configuration —
## scene · fog · map — and this class is how one process runs the whole group.
## tools/smoke_scenarios.sh passes the group as `--demos=a,b,c` with a shared
## `--shots-dir=`; every scenario in a group shares its boot facts, so a scene
## reload between scenarios is a fresh Battle in the same window rather than a
## fresh window stealing focus (the point of the exercise — see the
## focus-steal plan's FS2).
##
## The queue lives in statics rather than on any instance: each scenario gets
## a fresh Battle and with it a fresh BattleScenarioDriver, and statics are
## what survive the reloads in between. A non-batch capture passes through
## `finish_capture` unchanged, so the driver has one ending either way.

const DEMOS_ARG := "--demos"
const SHOTS_DIR_ARG := "--shots-dir"
const SCENARIO_TIMEOUT_ARG := "--scenario-timeout"
## The `+fog` suffix is the sweep's label convention — the mode name is the
## label and the capture filename; the demo is what is left once it comes off,
## exactly as tools/smoke_scenarios.sh spells it for a single scenario.
const FOG_SUFFIX := "+fog"

static var _modes := PackedStringArray()
static var _index := 0
static var _dir := ""
static var _timeout := 0.0
static var _active := false


## Adopts the current batch scenario, when the command line carries a group;
## answers whether it did. The first boot parses the flags; every reload after
## it takes the next mode off the static queue. Called from the driver's
## _init so Battle's own capture pinning (game speed, the hint set) reads the
## current scenario's demo — and the per-scenario deadline (risk R3) is armed
## here for the same reason: a group process is alive as long as *any*
## scenario progresses, so the budget has to live where the stuck scenario's
## name is known.
static func adopt(args: PackedStringArray, battle: Node) -> bool:
	var demos := CmdArgs.value(args, DEMOS_ARG)
	if demos == "":
		return false
	if not _active:
		_active = true
		_modes = demos.split(",")
		_index = 0
		_dir = CmdArgs.value(args, SHOTS_DIR_ARG)
		_timeout = float(CmdArgs.value(args, SCENARIO_TIMEOUT_ARG))
	if _timeout > 0.0:
		var timer := battle.get_tree().create_timer(_timeout)
		timer.timeout.connect(_deadline.bind(_index, demo(), battle.get_tree()))
	return true


## The demo the current batch scenario runs — its mode minus the label suffix.
static func demo() -> String:
	return _modes[_index].trim_suffix(FOG_SUFFIX)


## Where the current scenario's capture lands: the mode name is the filename,
## colons to dashes, exactly as the sweep spells it for a single scenario.
static func shot_path() -> String:
	return _dir.path_join(_modes[_index].replace(":", "-") + ".png")


## The one capture ending. Mid-batch saves the frame and reloads the scene, so
## the next scenario gets a fresh Battle in the same window; the last scenario
## of a batch — and every non-batch capture — saves and quits as always.
static func finish_capture(battle: Node, path: String) -> void:
	if not _active or _index >= _modes.size() - 1:
		await ScreenshotUtil.capture_and_quit(battle, path)
		return
	if not await ScreenshotUtil.save_frame(battle, path):
		battle.get_tree().quit(1)
		return
	_index += 1
	battle.get_tree().reload_current_scene()


## R3's deadline, fired by the tree: a batch scenario still on stage past its
## budget fails the group by name. The sweep then re-runs the group's
## scenarios one process each (R2), where the stuck one meets the shell's own
## per-scenario timeout and message.
static func _deadline(index: int, mode: String, tree: SceneTree) -> void:
	if not _active or _index != index:
		return
	push_error("smoke batch: scenario '%s' exceeded its %ss deadline" % [mode, _timeout])
	tree.quit(1)
