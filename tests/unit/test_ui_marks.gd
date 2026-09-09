extends GutTest
## What the web build printed instead of a tick: a white box reading "2713", the
## hex Godot draws for a glyph no font in the chain has. Neither pixel face draws
## ✓ ✗ ★ ☆ → ∞, and the fallback that hid it on the desktop is the machine's own
## system font — which a browser does not hand the engine at all.
##
## `UiMarks` is a bitmap face baked from pixel masks, so it is a pure static
## answer like `UiTheme.stat()` and `PathArrow.segments` and the whole of it is
## read without a scene: the masks are data, the baked face reports its own
## glyphs, and the load-bearing claim is the wiring — that every face the shell
## serves carries the marks behind it, on every platform.


func test_every_mask_is_square_on_the_grid() -> void:
	for mark: String in UiMarks.MARKS:
		var rows: Array = UiMarks.MARKS[mark]
		assert_eq(rows.size(), UiMarks.GRID, "%s has the wrong row count" % mark)
		for row: String in rows:
			assert_eq(row.length(), UiMarks.GRID, "a %s row is the wrong width" % mark)


func test_the_baked_face_draws_every_mark() -> void:
	var face := UiMarks.font()
	for mark: String in UiMarks.MARKS:
		assert_true(face.has_char(mark.unicode_at(0)), "%s did not bake" % mark)
		assert_eq(
			face.get_string_size(mark, 0, -1, UiMarks.GRID).x,
			float(UiMarks.ADVANCE),
			"%s sets to the wrong width" % mark
		)


## The six the shell actually prints. Named here rather than counted, so dropping
## one from the sheet fails instead of shrinking the promise.
func test_the_sheet_covers_what_the_shell_prints() -> void:
	assert_eq(UiMarks.MARKS.keys(), ["✓", "✗", "★", "☆", "→", "∞"])


## The wiring, and the reason the file exists: a face served by `UiTheme` reaches
## the marks whether or not the machine owns a system font.
func test_every_served_face_carries_the_marks() -> void:
	var marks: RID = UiMarks.font().get_rids()[0]
	for face: Font in [
		UiTheme.stat(), UiTheme.stat(true), UiTheme.display(), UiTheme.display(true)
	]:
		assert_true(face.get_rids().has(marks), "a served face has no marks behind it")
		assert_true(face.has_char("✓".unicode_at(0)))
		assert_true(face.has_char("★".unicode_at(0)))
