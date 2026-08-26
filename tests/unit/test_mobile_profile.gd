extends GutTest
## Which builds are played with a finger. Pure over the arguments handed in, like
## CmdArgs and MatchRequest's flag grammar, so the gate the mobile chrome is built
## behind is checked without an exported package.


func test_a_desktop_build_with_no_flag_is_not_a_touch_build() -> void:
	assert_false(MobileProfile.touch(PackedStringArray(["--fog"]), false))


func test_the_engine_feature_tag_is_the_device_door() -> void:
	assert_true(MobileProfile.touch(PackedStringArray([]), true))


## The desktop door, so a touch frame can be photographed on this machine.
func test_the_flag_is_the_desktop_door() -> void:
	assert_true(MobileProfile.touch(PackedStringArray(["--mobile"]), false))


## A value, not a switch: `--mobile=1` is a spelling nobody documents, and it must
## not half-open the gate.
func test_only_the_bare_switch_opens_it() -> void:
	assert_false(MobileProfile.touch(PackedStringArray(["--mobile=1"]), false))
