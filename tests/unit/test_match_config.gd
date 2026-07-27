extends GutTest
## A staged match request is handed over exactly once.
##
## This is the property COM-58 was closed on. The latched resume — a Continue
## press that found no save file on disk left the flag set for the rest of the
## process, so the next battle boot silently tried to resume again — was not
## patched; it was made unreachable, on the grounds that `take()` clearing leaves
## no staged state behind for a second boot to read. Take the clear away and the
## bug is reachable again, so it is asserted here rather than argued in a comment.
##
## MatchConfig is an autoload rather than a Node-free class, which is normally
## outside what tests/ targets. It earns the exception by being reachable without
## a scene: the singleton is up for the whole run, and these three tests are the
## whole of its behaviour.


func after_each() -> void:
	MatchConfig.take()  # never leave a request staged for the next test


func test_take_hands_over_the_staged_request() -> void:
	var request := MatchRequest.new()
	MatchConfig.stage(request)
	assert_same(MatchConfig.take(), request, "the battle scene plays what was staged")


func test_a_request_is_handed_over_only_once() -> void:
	MatchConfig.stage(MatchRequest.new())
	MatchConfig.take()
	assert_null(MatchConfig.take(), "nothing is left staged for the boot after")


## The COM-58 sequence itself: Continue stages a resume, the battle scene takes
## it and finds no save on disk, and the boot after that must play a fresh match.
func test_a_resume_cannot_outlive_the_boot_it_was_staged_for() -> void:
	var request := MatchRequest.new()
	request.resume = true
	MatchConfig.stage(request)
	MatchConfig.take()
	assert_null(MatchConfig.take(), "no resume left staged for the next battle boot")
