extends GutTest
## The one command-line parser, which six scenes now share.
##
## Worth its own suite because the three lookups are not interchangeable and the
## call sites pick between them deliberately: `value` treats an absent flag and an
## empty one alike, `has` tells them apart, and `flag` matches only the bare
## switch. `--co=` clearing the menu's commanders while omitting `--co` leaves
## them alone is exactly that distinction, and it is the kind of thing a rewrite
## silently loses.


func _args(list: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for item: String in list:
		out.append(item)
	return out


func test_value_reads_what_follows_the_equals() -> void:
	assert_eq(CmdArgs.value(_args(["--map=dustbowl"]), "--map"), "dustbowl")


func test_value_is_empty_when_the_flag_is_absent() -> void:
	assert_eq(CmdArgs.value(_args(["--fog"]), "--map"), "")


## Five of the six loops this replaced assigned into a variable as they walked,
## so the last spelling won. Kept, so a repeated flag means what it always did.
func test_the_last_spelling_wins() -> void:
	assert_eq(CmdArgs.value(_args(["--map=a", "--map=b"]), "--map"), "b")


## `--co-select` is valid bare and with a value; bare means the Red slot.
func test_a_bare_flag_takes_the_fallback() -> void:
	assert_eq(CmdArgs.value(_args(["--co-select"]), "--co-select", "red"), "red")
	assert_eq(CmdArgs.value(_args(["--co-select=blue"]), "--co-select", "red"), "blue")


func test_a_prefix_is_not_a_match() -> void:
	# `--co` must not answer for `--co-select`, which sits right beside it on the
	# same command lines the capture flows use.
	assert_eq(CmdArgs.value(_args(["--co-select=blue"]), "--co"), "")
	assert_false(CmdArgs.has(_args(["--co-select=blue"]), "--co"))


func test_has_separates_an_empty_flag_from_a_missing_one() -> void:
	assert_true(CmdArgs.has(_args(["--co="]), "--co"), "passed, with nothing after it")
	assert_false(CmdArgs.has(_args(["--fog"]), "--co"), "not passed at all")
	assert_eq(CmdArgs.value(_args(["--co="]), "--co"), "", "both look empty to value()")


func test_flag_matches_only_the_bare_switch() -> void:
	assert_true(CmdArgs.flag(_args(["--hotseat"]), "--hotseat"))
	assert_false(CmdArgs.flag(_args(["--hotseat=yes"]), "--hotseat"))
