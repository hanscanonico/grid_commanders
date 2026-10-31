class_name PaintedArt
extends RefCounted
## Whether the 3D board wears the Blender-built painted miniatures. Off until the
## whole set is approved, so the live game never shows a mix; `--art=painted`
## turns it on for one run, and so does `?art=painted` on the web build, so it can
## be tried on a real phone.

static var _on := -1


static func on() -> bool:
	if _on < 0:
		var asked := CmdArgs.value(CmdArgs.user(), "--art") == "painted"
		_on = 1 if asked or _web_asks() else 0
	return _on == 1


static func _web_asks() -> bool:
	if not OS.has_feature("web"):
		return false
	var query: Variant = JavaScriptBridge.eval("window.location.search")
	return query is String and (query as String).contains("art=painted")


## For a suite that holds the painted set to the code models' contract.
static func force(enabled: bool) -> void:
	_on = 1 if enabled else 0
