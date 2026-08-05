## D3's property-parity check (asymmetric-board plan), shared because it has two
## callers: test_maps.gd's whole-board sweep and test_map_grouping.gd's counter
## tests, and test_maps.gd already sits at the gdlintrc max-public-methods
## ceiling — the same reason test_sides_flag.gd split from test_match_request.gd.
## No claim lives here beyond `MapData.grouping`'s own; every assertion belongs
## to the two suites that drive this.
##
## Preloaded by its path rather than registered as a class_name: it is test
## scaffolding, and the global class list is the shipped game's.

## What "level" means for a board's property, split by whether it declares
## `# grouping`. Untagged, every seat has to match every other kind for kind —
## the check this lint has always run, and every shipped board's verdict is
## exactly that check, because none of them carries the tag. A board that does
## declare one is checked side by side instead: within a side, seats still
## have to match kind for kind; across sides, no side's total owned-property
## count — a plain sum, not counted by kind, because a lint cannot judge
## 30-against-36 but can cap a side from out-owning everyone else combined —
## may exceed the sum of all the others'.
##
## Two ways the tag itself is the defect rather than the board, and both fail
## here instead of skipping the lint (D3's rejected opt-out, R5's guard): a
## grouping that reads as a free-for-all claims nothing, and a grouping whose
## seats were already going to pass the untagged check bought nothing.
static func error(map: MapData) -> String:
	var by_team := _owned_properties_by_team(map)
	var seat_error := _seat_error(map, by_team)
	if map.grouping.is_empty():
		return seat_error
	var grouped := MatchRequest.parse_sides_flag(map.grouping)
	if grouped.is_empty():
		return (
			"%s: `# grouping %s` reads as a free-for-all — state a real grouping or delete the tag"
			% [_name(map), map.grouping]
		)
	if seat_error == "":
		return (
			"%s: every seat already opens identical kind for kind — `# grouping %s` is unearned"
			% [_name(map), map.grouping]
		)
	return _side_error(map, by_team, grouped)


static func _name(map: MapData) -> String:
	return map.source_path.get_file()


## What each seat opens holding, `team -> {terrain id -> count}`, with an entry
## for every seat the board deals — an army that starts on nothing still has to
## be compared against the one that started on something.
static func _owned_properties_by_team(map: MapData) -> Dictionary:
	var by_team := {}
	for team in map.teams():
		by_team[team] = {}
	for cell in map.property_cells():
		var team := map.owner_at(cell)
		if team == MapData.NEUTRAL:
			continue
		var counts: Dictionary = by_team[team]
		var id := map.terrain_at(cell).id
		counts[id] = int(counts.get(id, 0)) + 1
	return by_team


## The untagged check: every seat matches every other, kind for kind. Counted
## by kind because a base is not a city: equal totals with one seat holding the
## only airfield is the same defect wearing a fair number.
static func _seat_error(map: MapData, by_team: Dictionary) -> String:
	var lead: Dictionary = by_team[map.teams()[0]]
	var kinds := {}
	for team: int in by_team:
		for id: StringName in by_team[team]:
			kinds[id] = true
	for id: StringName in kinds:
		for team in map.teams():
			var counts: Dictionary = by_team[team]
			if int(counts.get(id, 0)) != int(lead.get(id, 0)):
				return (
					(
						"%s: team %d opens on %d %s to team %d's %d — a seat with more "
						% [
							_name(map),
							team,
							int(counts.get(id, 0)),
							id,
							map.teams()[0],
							int(lead.get(id, 0))
						]
					)
					+ "income or more production is an edge no playtest attributes right"
				)
	return ""


## D3's two side-scoped checks, run once a grouping has already cleared R5's
## guard. Grouped by the board's own seat order, so the first seat named on
## each side is always its comparison lead and a failure is deterministic
## without a sort. A seat the grouping never names stands alone (the same
## reading `GameState.allied` gives it), keyed off its own team id and offset
## negative so it can never collide with a real, zero-based side id.
static func _side_error(map: MapData, by_team: Dictionary, grouped: Dictionary) -> String:
	var sides: Dictionary = {}  # side id -> Array[int], the seats standing on it
	for team in map.teams():
		var side: int = int(grouped.get(team, -team))
		if not sides.has(side):
			sides[side] = []
		sides[side].append(team)
	for side: int in sides:
		var seats: Array = sides[side]
		var lead_team: int = seats[0]
		var lead: Dictionary = by_team[lead_team]
		var kinds := {}
		for team: int in seats:
			for id: StringName in by_team[team]:
				kinds[id] = true
		for id: StringName in kinds:
			for team: int in seats:
				var counts: Dictionary = by_team[team]
				if int(counts.get(id, 0)) != int(lead.get(id, 0)):
					return (
						(
							"%s: seat %d opens on %d %s to its ally seat %d's %d — allied seats "
							% [
								_name(map),
								team,
								int(counts.get(id, 0)),
								id,
								lead_team,
								int(lead.get(id, 0)),
							]
						)
						+ "have to match kind for kind"
					)
	var totals: Dictionary = {}  # side id -> total owned property cells, any kind
	var grand_total := 0
	for side: int in sides:
		var total := 0
		for team: int in sides[side]:
			var counts: Dictionary = by_team[team]
			for id: StringName in counts:
				total += int(counts[id])
		totals[side] = total
		grand_total += total
	for side: int in totals:
		var mine: int = totals[side]
		var rest: int = grand_total - mine
		if mine > rest:
			return (
				(
					"%s: seats %s open on %d properties combined to the rest of the board's "
					% [_name(map), _seat_list(sides[side]), mine]
				)
				+ "%d — a side can't out-own everyone else" % rest
			)
	return ""


## Seats joined the way the tag itself writes them, for a failure message that
## names the side rather than a synthetic index.
static func _seat_list(seats: Array) -> String:
	var parts: Array[String] = []
	for team: int in seats:
		parts.append(str(team))
	return "+".join(parts)
