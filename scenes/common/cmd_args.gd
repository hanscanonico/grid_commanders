class_name CmdArgs
extends RefCounted
## The command line, read once and parsed in one place.
##
## Six scenes each scanned `OS.get_cmdline_user_args()` with their own inline
## loop, which is how `--map=` came to be last-wins and `--screenshot=` was
## first-wins without anyone deciding either. The flags themselves are unchanged
## — this owns only *how* one is found, so a spelling means the same thing to
## every scene that reads it.
##
## `user()` is deliberately the only line in the repository outside the offline
## tools that touches `OS`: everything else takes the args as an argument, which
## is what makes the parsing testable without a process to launch.


## The flags after `--`, as Godot hands them over. Held apart from the parsers
## below so a caller can pass its own list in a test.
static func user() -> PackedStringArray:
	return OS.get_cmdline_user_args()


## The value of `--name=<value>`, or `bare` when the flag appears with no `=`
## (the `--co-select` shape), or `""` when it is absent entirely.
##
## Last spelling wins, which is what five of the six original loops did by
## assigning into a variable as they went.
static func value(args: PackedStringArray, name: String, bare: String = "") -> String:
	var found := ""
	for arg in args:
		if arg == name:
			found = bare
		elif arg.begins_with(name + "="):
			found = arg.get_slice("=", 1)
	return found


## Whether a valueless switch such as `--fog` or `--hotseat` was passed.
static func flag(args: PackedStringArray, name: String) -> bool:
	return name in args


## Whether the flag was passed at all, in either shape. Distinct from a non-empty
## `value` because an explicitly empty one means something: `--co=` clears the
## commanders the menu picked, and `--seed=` pins seed 0.
static func has(args: PackedStringArray, name: String) -> bool:
	for arg in args:
		if arg == name or arg.begins_with(name + "="):
			return true
	return false
