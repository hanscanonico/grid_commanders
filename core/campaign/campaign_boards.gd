class_name CampaignBoards
extends RefCounted
## Which campaign boards are the same ground, and which of those shares are
## meant.
##
## `MapCatalog.paths()` scans only the top level of `maps/`, so the 108 boards
## under `maps/campaign/` were only ever seen one mission at a time and a board
## copied into a second mission had no symptom. This class reads them as a set.
## A board is identified by its **terrain alone**: two missions that differ only
## in armies or ownership are still fighting over the same ground, which is the
## thing a player notices.
##
## Node-free like the rest of core/, asked by `tools/check_campaigns.gd` and by
## `tests/unit/test_campaign_maps.gd`.

const CAMPAIGN_DIR := "res://maps/campaign"

## The shares that may stand, one group per entry, by board filename without the
## suffix. fw07/fw08 are the same battlefield twice on purpose — the second
## mission is the counter-attack over the first one's ground. The rest are
## unpaid authoring debt, listed so a *new* share cannot slip in beside them.
##
## A group is checked in both directions: a board that has since been given
## ground of its own has to leave the list. An entry kept past its share would
## quietly re-license a copy between boards somebody had already separated, and
## the README points a reader here for what still shares.
const SHARED_BOARDS: Array[Array] = [
	["fw01_dry_taps", "fw02_last_granary"],
	["fw07_pipeline_east", "fw08_pipeline_west", "hc03_the_garrison", "hc13_the_capital_road"],
	["hc01_border_skirmish", "hc02_river_line"],
	["hc05_the_ultimatum", "hc15_the_regents_gate"],
	["hc06_the_crack", "hc17_the_high_seat"],
	[
		"hc07_uneasy_alliance",
		"hc08_shared_supply",
		"hc09_the_crossroads",
		"hc10_broken_column",
		"hc11_two_fronts",
		"hc12_the_bargain_kept",
		"hc14_last_garrison",
		"hc16_siege_lines",
	],
	["lf18_the_keep_at_draeg_hold", "qw18_the_man_himself"],
	["qw07_the_cache_at_millhollow", "qw10_the_relay_tower"],
	["qw08_the_waystation", "qw12_the_network_node"],
	["tc10_the_squeeze", "tc14_draegs_line"],
]


## Every board under `maps/campaign/`, alphabetically by campaign then filename —
## a stable order that does not depend on the filesystem's.
static func paths() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(CAMPAIGN_DIR)
	if dir == null:
		push_error("CampaignBoards: cannot open %s" % CAMPAIGN_DIR)
		return result
	var campaigns := dir.get_directories()
	campaigns.sort()
	for campaign in campaigns:
		var boards := ResourceDir.files(CAMPAIGN_DIR.path_join(campaign), ".txt", "CampaignBoards")
		boards.sort()
		result.append_array(boards)
	return result


## What a board's ground hashes to. Terrain only: ownership and armies are the
## mission's, the ground is the board's.
static func terrain_digest(map: MapData) -> String:
	var rows := PackedStringArray()
	for y in map.height:
		var ids := PackedStringArray()
		for x in map.width:
			ids.append(str(map.terrain_at(Vector2i(x, y)).id))
		rows.append("|".join(ids))
	return "\n".join(rows).sha256_text()


## The board names sharing each digest, keyed by digest — groups of one included,
## so a caller can count what it read. A board that will not parse is skipped:
## `check_campaigns` already fails on it by name, and reporting it twice sends
## the author looking for a second problem.
static func groups(db: TerrainDB) -> Dictionary[String, PackedStringArray]:
	var by_digest: Dictionary[String, PackedStringArray] = {}
	for path in paths():
		var map := MapData.load_from_file(path, db)
		if map == null:
			continue
		var digest := terrain_digest(map)
		var names: PackedStringArray = by_digest.get(digest, PackedStringArray())
		names.append(path.get_file().trim_suffix(".txt"))
		by_digest[digest] = names
	return by_digest


## Every undeclared share and every declared group that has stopped being one,
## a line each, or "" when the boards and `SHARED_BOARDS` agree.
static func shared_board_error(db: TerrainDB) -> String:
	var lines := PackedStringArray()
	var by_digest := groups(db)
	for names in by_digest.values():
		if names.size() < 2 or _is_declared(names):
			continue
		lines.append("boards share terrain and are not in SHARED_BOARDS: %s" % ", ".join(names))
	lines.append_array(stale_group_errors(by_digest))
	lines.sort()
	return "\n".join(lines)


## The groups that have outlived their share, one line each naming the boards
## that no longer stand on anyone's ground but their own, so the list is pruned
## by the same run that separates them. Takes `groups()`'s reading rather than
## the disk, so a test can hand it a board set that does not exist yet.
static func stale_group_errors(
	by_digest: Dictionary[String, PackedStringArray]
) -> PackedStringArray:
	var digests: Dictionary[String, String] = {}
	for digest in by_digest:
		for name in by_digest[digest]:
			digests[name] = digest
	var lines := PackedStringArray()
	for group in SHARED_BOARDS:
		var gone := PackedStringArray()
		for name in group:
			if not _shares_within(name, group, digests):
				gone.append(name)
		if not gone.is_empty():
			lines.append(
				"SHARED_BOARDS lists boards that no longer share terrain: %s" % ", ".join(gone)
			)
	return lines


## Whether some other board in the same group stands on this one's ground. A
## board that no campaign holds any more answers no: a name nobody can look up
## is as stale as a share that was fixed.
static func _shares_within(name: String, group: Array, digests: Dictionary[String, String]) -> bool:
	var digest: String = digests.get(name, "")
	if digest == "":
		return false
	for other in group:
		if other != name and digests.get(other, "") == digest:
			return true
	return false


static func _is_declared(names: PackedStringArray) -> bool:
	for group in SHARED_BOARDS:
		var declared := true
		for name in names:
			if not group.has(name):
				declared = false
				break
		if declared:
			return true
	return false
