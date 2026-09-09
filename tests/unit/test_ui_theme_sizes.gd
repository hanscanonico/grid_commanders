extends GutTest
## What the size ladder must never do again: the shell served body copy at 8 and
## a page title at 15 with the banner at 24, so a rules paragraph sat a threefold
## jump under the words above it and nothing stood between them (COM-271). Body
## and tip read at 10 now — the button size, already proven crisp — and the
## subtitle token fills the step between a button and a page title.
##
## A size is a number anybody can type, so the ladder is checked rather than
## stated: `UiTheme`'s constants are pure statics, like the face `display()`
## returns, so the whole rhythm is read without building a Control.

## Every size token the shell has, smallest first. A new token belongs in this
## list — `test_the_ladder_names_every_size_token` fails until it is here, which
## is what keeps the ladder the one place the rhythm is decided.
const LADDER: Array[String] = [
	"SIZE_MARK",
	"SIZE_SEGMENT",
	"SIZE_STAT",
	"SIZE_TITLE",
	"SIZE_BODY",
	"SIZE_TIP",
	"SIZE_BUTTON",
	"SIZE_SUBTITLE",
	"SIZE_PAGE_TITLE",
	"SIZE_BANNER",
	"SIZE_WORDMARK",
]

## The two tokens drawn under the pixel face's design size, and why each is
## allowed to be: SIZE_MARK is the one or two digits a board badge carries over a
## tile, and SIZE_SEGMENT is a single word set in the display face, which has no
## grid to fall off. Everything a player *reads* — copy, tips, buttons, headings
## — stays on the grid or above it.
const UNDER_THE_GRID: Array[String] = ["SIZE_MARK", "SIZE_SEGMENT"]


## The constants as data rather than as eleven named reads: a token nobody names
## is exactly the drift this suite is here to catch. `UiTheme` is static-only, so
## the map comes off a throwaway instance's script rather than a path literal,
## which would be a second statement of where the shell lives.
func _constants() -> Dictionary:
	var script := UiTheme.new().get_script() as GDScript
	return script.get_script_constant_map()


func _size(token: String) -> int:
	var sizes := _constants()
	assert_true(sizes.has(token), "UiTheme has no %s" % token)
	return sizes.get(token, 0)


func _size_tokens() -> Array[String]:
	var found: Array[String] = []
	for key: String in _constants().keys():
		if key.begins_with("SIZE_"):
			found.append(key)
	found.sort()
	return found


func test_the_ladder_names_every_size_token() -> void:
	var named := LADDER.duplicate()
	named.sort()
	assert_eq(named, _size_tokens())


func test_the_ladder_never_steps_down() -> void:
	for i in range(1, LADDER.size()):
		assert_gte(
			_size(LADDER[i]),
			_size(LADDER[i - 1]),
			"%s is smaller than %s" % [LADDER[i], LADDER[i - 1]]
		)


## Body and tip are the same voice at two reading distances — a rules paragraph
## and the sentence a tooltip holds — so a change to one that skipped the other
## would print the same copy at two sizes on the same screen.
func test_body_and_tip_are_one_size() -> void:
	assert_eq(_size("SIZE_TIP"), _size("SIZE_BODY"))


## And that one size is the button's, which every menu page has been printing
## legibly since the shell was drawn — the reason the raise stops there rather
## than at the next rung up.
func test_copy_reads_at_the_size_a_button_does() -> void:
	assert_eq(_size("SIZE_BODY"), _size("SIZE_BUTTON"))


func test_copy_is_never_set_under_the_pixel_grid() -> void:
	var under: Array[String] = []
	for token in LADDER:
		if _size(token) < UiTheme.STAT_DESIGN_PX:
			under.append(token)
	assert_eq(under, UNDER_THE_GRID)


## The step this ticket exists to add: something between the button and the page
## title, so the jump from copy to a title is two steps rather than one.
func test_the_subtitle_stands_between_the_button_and_the_page_title() -> void:
	assert_gt(_size("SIZE_SUBTITLE"), _size("SIZE_BUTTON"))
	assert_lt(_size("SIZE_SUBTITLE"), _size("SIZE_PAGE_TITLE"))


## The stat face is a pixel face with a grid, and the shell serves it at that
## grid and nowhere else — the whole of COM-254's "FUNDS 4200" printed as
## "FUHDG 42DD". Raising the body size must not have raised it with them.
func test_the_stat_face_keeps_its_design_size() -> void:
	assert_eq(UiTheme.SIZE_STAT, UiTheme.STAT_DESIGN_PX)
