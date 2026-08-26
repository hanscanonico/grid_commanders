class_name MobileProfile
extends RefCounted
## Whether this build is being played with a finger — the one answer, resolved
## once per boot (mobile plan D5).
##
## Two doors and they mean the same thing: the engine's own `mobile` feature tag,
## which an exported Android or iOS package carries, and the presentation-only
## `--mobile` flag, which exists so a touch frame can be photographed on a desktop
## machine. The flag reaches no MatchRequest field, no save and no replay: a match
## played with it resolves identically, because everything downstream of this
## answer is chrome.
##
## Here rather than on UiTheme because a platform is not a metric — UiTheme owns
## the sizes a touch build reads and UiKit the widgets built from them, and both
## ask this. Nothing under core/ or ai/ may ask it at all (D1).

## The desktop door onto the touch profile. Presentation-only, like `--speed=`.
const FLAG := "--mobile"

## -1 until the first ask; 0/1 after. Resolved once because the two reads behind
## it are a process fact that cannot change while the game runs.
static var _active := -1


## True when the game is being played on a touchscreen build, or posed as one.
static func active() -> bool:
	if _active < 0:
		_active = 1 if touch(CmdArgs.user(), OS.has_feature("mobile")) else 0
	return _active == 1


## Pins the answer for this process. The driven gate (tests/unit/test_touch_press.gd)
## has to build mobile chrome inside an ordinary headless run, where neither door
## is open; `unpin` puts the question back.
static func pin(active: bool) -> void:
	_active = 1 if active else 0


static func unpin() -> void:
	_active = -1


## The same answer over arguments handed in, so the rule is checkable without a
## process to launch — CmdArgs' own idiom, and the reason that class takes its
## args rather than reading them.
static func touch(args: PackedStringArray, feature: bool) -> bool:
	return feature or CmdArgs.flag(args, FLAG)
