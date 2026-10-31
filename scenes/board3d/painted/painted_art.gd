class_name PaintedArt
extends RefCounted
## Whether the 3D board wears the Blender-built painted miniatures: the default,
## with `--art=code` to see the code models they replaced. A headless run draws
## nothing and keeps the code models, which are what its geometry suites measure.

const CODE_ART := "code"

static var _on := -1


static func on() -> bool:
	if _on < 0:
		var code := CmdArgs.value(CmdArgs.user(), "--art") == CODE_ART
		_on = 0 if code or DisplayServer.get_name() == "headless" else 1
	return _on == 1


## For a suite that checks one art or the other, whatever the default is.
static func force(enabled: bool) -> void:
	_on = 1 if enabled else 0
