extends Control
## Dev-only component gallery: renders a CommanderCard for every record the
## CommanderDB holds — the neutral commander plus all twenty-two generals — so the
## G1 card foundation can be eyeballed and, more importantly, so building all
## twenty-three at once proves no id is missing its art or its copy. If any card
## failed to construct, the scene would crash before it could be captured, which
## is what turns the screenshot into a real gate.
##
## Boot with:  Godot --path . scenes/menu/commander_gallery.tscn -- --screenshot=/abs.png
## (see `make gallery-screenshot`).

const _COLUMNS := 4


func _ready() -> void:
	# Dev-only page, out of the smoke sweep (tools/smoke_scenarios.sh never boots
	# this scene), so it wears the shell every other full-screen page wears —
	# opaque veil, page margin, page title — and is free to move a pixel doing it.
	UiKit.page_veil(self, 1.0)
	var rows := UiKit.page_body(self, 6)

	var title := UiKit.page_title("COMMANDER CARD GALLERY")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rows.add_child(title)

	var grid := GridContainer.new()
	grid.columns = _COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	rows.add_child(grid)

	var db := CommanderDB.load_default()
	for commander in db.all():
		var card := CommanderCard.new()
		grid.add_child(card)
		card.bind(commander)

	var shot_path := ScreenshotUtil.requested()
	if shot_path != "":
		ScreenshotUtil.capture_and_quit(self, shot_path)
