class_name ResourceDir
extends RefCounted
## One statement of "every file of this kind directly under this directory".
##
## The registries and the map catalog all scan a data directory the same way,
## and the one rule none of them may forget is that an exported build lists a
## packed file with a `.remap` suffix — so the suffix is trimmed here, once,
## rather than in every caller.

const REMAP_SUFFIX := ".remap"


## Full paths, in the directory's own order — never sorted, because a caller
## that wants a stable order says so itself and the registries are seeded in
## whatever order the filesystem hands over. `who` names the caller in the
## error a missing directory pushes.
static func files(dir_path: String, suffix: String, who: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("%s: cannot open %s" % [who, dir_path])
		return result
	for file in dir.get_files():
		var name := file.trim_suffix(REMAP_SUFFIX)
		if name.ends_with(suffix):
			result.append(dir_path.path_join(name))
	return result
