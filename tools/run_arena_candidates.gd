extends SceneTree
## Writes candidate profiles: a base vector plus the dials one wave moved, saved
## as `.tres` under `reports/` and playable by `run_ai_arena.gd` unchanged.
##
## A candidate is an `AIProfile` and nothing else (plan D3), so this is the whole
## of what "propose a vector" means — no arena-only field, no fork of the planner.
## Which dials may be written and what values they may take is `ArenaBlocks`', not
## this script's: it applies and refuses, it does not decide.
##
## Usage (headless; the search driver runs this itself):
##   Godot --headless --path . -s res://tools/run_arena_candidates.gd -- [flags]
##     --spec=<file.json>   what to write
##
## The spec, whose paths are the search's own naming and are project-relative:
##
##   {"base": "data/ai/default.tres", "candidates": [
##     {"path": "reports/ai_arena/search/x/candidates/c0a1b2c3.tres",
##      "overrides": {"kill_bonus": 2.0, "counter_weight": 0.4}}]}
##
## **A file that already exists is left alone.** The driver names a candidate for
## a digest of the vector it carries, so a path that is on disk holds the profile
## this spec asks for — and every shard the pool has already played against it is
## keyed to that same path. Rewriting it would buy nothing and risk a run whose
## records were played against a file that has since moved.

var _spec_path := ""


func _init() -> void:
	if not _parse_args():
		quit(2)
		return
	var spec := _spec()
	if spec.is_empty():
		quit(2)
		return
	var base := _base(String(spec.get("base", "")))
	if base == null:
		quit(2)
		return
	var written := 0
	var kept := 0
	for entry: Variant in spec["candidates"]:
		if not (entry is Dictionary):
			_refuse("a candidate is an object with 'path' and 'overrides'")
			return
		var candidate: Dictionary = entry
		var state := _write(base, candidate)
		if state < 0:
			return
		written += state
		kept += 1 - state
	print("arena-candidates: wrote %d profile(s), %d already on disk" % [written, kept])
	quit(0)


func _parse_args() -> bool:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spec="):
			_spec_path = arg.get_slice("=", 1).strip_edges()
		else:
			push_error("arena-candidates: unknown flag '%s'" % arg)
			return false
	if _spec_path == "":
		push_error("arena-candidates: --spec=<file.json> names what to write")
		return false
	return true


func _spec() -> Dictionary:
	var path := ArenaRequest.project_path(_spec_path)
	if path == "" or not FileAccess.file_exists(path):
		push_error("arena-candidates: cannot read the spec '%s'" % _spec_path)
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		push_error("arena-candidates: '%s' is not a JSON object" % _spec_path)
		return {}
	var spec: Dictionary = json.data
	if not (spec.get("candidates") is Array):
		push_error("arena-candidates: 'candidates' is a list of {path, overrides}")
		return {}
	return spec


## The profile every candidate is a step away from. Loaded once: a candidate is
## the base vector with a handful of dials moved, so everything the search is not
## looking at stays exactly what shipped (plan R5).
func _base(path: String) -> AIProfile:
	var res_path := ArenaRequest.project_path(path)
	if res_path == "" or not ResourceLoader.exists(res_path):
		push_error("arena-candidates: no base profile at '%s'" % path)
		return null
	var loaded: Resource = load(res_path)
	if not (loaded is AIProfile):
		push_error("arena-candidates: '%s' is not an AIProfile" % path)
		return null
	var base: AIProfile = loaded
	return base


## 1 when the profile was written, 0 when it was already there, -1 when the
## request was refused and the run is over.
func _write(base: AIProfile, candidate: Dictionary) -> int:
	var out_path := String(candidate.get("path", ""))
	var overrides: Variant = candidate.get("overrides", {})
	if not (overrides is Dictionary):
		_refuse("'%s': overrides are a dial-to-number object" % out_path)
		return -1
	if BalanceReportWriter.resolve_out(out_path.get_base_dir()) == "":
		_refuse(
			(
				"'%s' is outside %s/, where a searched profile lives"
				% [out_path, BalanceReportWriter.REPORTS_ROOT]
			)
		)
		return -1
	var res_path := ArenaRequest.project_path(out_path)
	if FileAccess.file_exists(res_path):
		return 0
	var profile: AIProfile = base.duplicate(true)
	var problem := ArenaBlocks.apply(profile, overrides)
	if problem != "":
		_refuse("'%s': %s" % [out_path, problem])
		return -1
	if BalanceReportWriter.prepare_dir(out_path.get_base_dir()) == "":
		_refuse("cannot make a directory for '%s'" % out_path)
		return -1
	var status := ResourceSaver.save(profile, res_path)
	if status != OK:
		_refuse("cannot write '%s' (error %d)" % [out_path, status])
		return -1
	return 1


func _refuse(reason: String) -> void:
	push_error("arena-candidates: %s" % reason)
	quit(2)
