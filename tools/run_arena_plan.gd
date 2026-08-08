extends SceneTree
## Prints the pool driver's arguments for one arena pool, and nothing else.
##
## The boards, the seeds and the anchor round-robin are `ArenaPools`', and the
## report reads finished matches back against that same split — so the command
## that plays a pool must not be a second spelling of it. This is how the one
## spelling reaches a shell:
##
##   Godot --headless --path . -s res://tools/run_arena_plan.gd -- --pool=training
##   --maps=… --pairings=… --seeds=12 --seed-offset=0 --days=100
##
## `make arena-anchors ARENA_POOL=training` is that line handed to `tools/balance_pool.py`
## and then to the report. The engine prints a banner of its own first, so a
## caller keeps the line that starts with `--`.


func _init() -> void:
	var pool := ArenaPools.TRAINING
	for arg in CmdArgs.user():
		if arg.begins_with("--pool="):
			pool = arg.get_slice("=", 1).strip_edges()
		else:
			push_error("arena-plan: unknown flag '%s'" % arg)
			quit(2)
			return
	if ArenaPools.boards(pool).is_empty():
		push_error("arena-plan: unknown pool '%s'. Known: %s" % [pool, ", ".join(ArenaPools.POOLS)])
		quit(2)
		return
	print(ArenaPools.pool_args(pool))
	quit(0)
