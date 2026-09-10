extends GutTest
## The six marks neither pixel face draws, baked from pixel masks into a bitmap
## face. It is a pure static answer like `UiTheme.stat()` and `PathArrow.segments`
## and the whole of it is read without a scene: the masks are data, the baked face
## reports its own glyphs, and the load-bearing claim is the wiring — that every
## face the shell serves carries the marks behind it, which is what a browser,
## handing the engine no system font to fall through to, needs.


func test_every_mask_is_square_on_the_grid() -> void:
	for mark: String in UiMarks.MARKS:
		var rows: Array = UiMarks.MARKS[mark]
		assert_eq(rows.size(), UiMarks.GRID, "%s has the wrong row count" % mark)
		for row: String in rows:
			assert_eq(row.length(), UiMarks.GRID, "a %s row is the wrong width" % mark)
			# The air past a mark is this column, not a wider advance.
			assert_eq(row[UiMarks.GRID - 1], ".", "%s fills the column it sets in" % mark)


func test_the_baked_face_draws_every_mark() -> void:
	var face := UiMarks.font()
	for mark: String in UiMarks.MARKS:
		assert_true(face.has_char(mark.unicode_at(0)), "%s did not bake" % mark)
		assert_eq(
			face.get_string_size(mark, 0, -1, UiMarks.GRID).x,
			float(UiMarks.GRID),
			"%s sets to the wrong width" % mark
		)


## The six the shell actually prints. Named here rather than counted, so dropping
## one from the sheet fails instead of shrinking the promise — membership only,
## since the order they bake in is the sheet's business.
func test_the_sheet_covers_what_the_shell_prints() -> void:
	for mark in ["✓", "✗", "★", "☆", "→", "∞"]:
		assert_true(UiMarks.MARKS.has(mark), "%s left the sheet" % mark)
	assert_eq(UiMarks.MARKS.size(), 6)


## An open star is a filled one with a hollow in it, and the hollow has to be
## enclosed: opened at the bottom it runs into the gap between the star's feet and
## the mark reads as two blobs instead of a star, which a defence rating counts in
## beside the filled one. Flooding the clear pixels in from outside the mask is
## how a hole is told from a notch.
func test_the_open_star_holds_a_closed_hollow() -> void:
	var mask: Array = UiMarks.MARKS["☆"]
	var outside := _outside_of(mask)
	var hollow := 0
	for y in UiMarks.GRID:
		for x in UiMarks.GRID:
			if mask[y][x] != "#" and not outside.has(Vector2i(x, y)):
				hollow += 1
	assert_gt(hollow, 0, "the open star's hollow is open to the outside")


## Every clear pixel reachable from the mask's border without crossing a set one.
func _outside_of(mask: Array) -> Dictionary:
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = []
	for edge in UiMarks.GRID:
		queue.append(Vector2i(edge, 0))
		queue.append(Vector2i(edge, UiMarks.GRID - 1))
		queue.append(Vector2i(0, edge))
		queue.append(Vector2i(UiMarks.GRID - 1, edge))
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		if seen.has(cell):
			continue
		var inside := (
			cell.x >= 0 and cell.y >= 0 and cell.x < UiMarks.GRID and cell.y < UiMarks.GRID
		)
		if not inside or mask[cell.y][cell.x] == "#":
			continue
		seen[cell] = true
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			queue.append(cell + step)
	return seen


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
