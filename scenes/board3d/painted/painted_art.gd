class_name PaintedArt
extends RefCounted
## Whether the 3D board wears the Blender-built painted miniatures. Off until the
## whole set is in, so the live game never shows a mix; `--art=painted` turns it
## on for one run.

static var _on := -1


static func on() -> bool:
	if _on < 0:
		_on = 1 if CmdArgs.value(CmdArgs.user(), "--art") == "painted" else 0
	return _on == 1


## For a suite that holds the painted set to the code models' contract.
static func force(enabled: bool) -> void:
	_on = 1 if enabled else 0
