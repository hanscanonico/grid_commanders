class_name MapCatalog
extends RefCounted
## The shipped map roster: which files under maps/ are maps, what they are
## called, and the order the menu offers them in.
##
## Adding a map is still dropping a .txt in maps/ — nothing here lists them by
## hand. The point of the class is that the menu, the map lint and the per-map
## AI soak all discover the roster through one function instead of three
## DirAccess loops that can drift apart.
##
## Node-free like the rest of core/, so tests read exactly what the menu reads.

const MAPS_DIR := "res://maps"
## The teaching board pinned to item zero in `ordered()`. The menu reads this
## same key for its TUTORIAL badge and MissionStrip asks `teaches()` about it, so
## which board leads, which board says so, and which board hints cannot drift
## apart (COM-122).
const TUTORIAL_MAP_PATH := "res://maps/boot_camp.txt"
## Boards that exist to be tested on rather than played: the fixture boards —
## most measured on for balance, a couple built for a specific test instead
## (the replay analyser's, the smoke sweep's). Deliberately a subdirectory,
## because `paths()` below scans only the top level — so a fixture is
## reachable by name from the offline tools and the battle scene, and still
## absent from the menu and the per-map AI soak. It is *not* absent from the
## map lint: the balance verdicts are measured on these boards, so an
## unplayable one is worse here than on the shelf (COM-106). See
## `fixture_paths()`.
const FIXTURES_DIR := "res://maps/fixtures"
## Where a board the player drew themselves is kept. Outside `res://` because
## nothing in an exported game may be written to, and deliberately outside
## `paths()`: the shipped roster is a fixed list the README counts and the
## per-map AI soak plays, and a board that arrived on this machine an hour ago
## belongs to neither. `UserMaps` owns writing here; this class only finds and
## names what is already there.
const USER_DIR := "user://maps"


## Every shipped map, alphabetically by filename — a stable order that does not
## depend on the filesystem's. `ordered()` is what the menu shows.
static func paths() -> Array[String]:
	return _txt_paths(MAPS_DIR)


## Every fixture board, alphabetically — the same discovery `paths()` does, one
## directory down. One function rather than a DirAccess loop per caller, for the
## reason the class exists: the name resolver and the map lint have to be reading
## the same set of files.
static func fixture_paths() -> Array[String]:
	return _txt_paths(FIXTURES_DIR)


## Every board the player has drawn, alphabetically — the same discovery
## `paths()` does, in the writable directory. Empty, and silently so, when
## nothing has ever been saved there: a fresh install has no such directory and
## that is the ordinary case rather than a failure.
static func user_paths() -> Array[String]:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(USER_DIR)):
		return []
	return _txt_paths(USER_DIR)


## Every `.txt` board directly under `dir`, alphabetically by filename — a stable
## order that does not depend on the filesystem's. Shared by `paths()` and
## `fixture_paths()`, which differ only in which directory they scan.
static func _txt_paths(dir_path: String) -> Array[String]:
	var result := ResourceDir.files(dir_path, ".txt", "MapCatalog")
	result.sort()
	return result


## The roster parsed with the tutorial board first, then smallest board first.
## Item zero is the menu's default, so first contact should open on the board
## written to teach the game rather than merely the shortest duel. The rest keep
## the established data-derived order; ties break on filename.
## Maps that fail to parse are dropped with a pushed error rather than taking
## the menu down with them.
static func ordered(db: TerrainDB) -> Array[MapData]:
	var maps: Array[MapData] = []
	for path in paths():
		var map := MapData.load_from_file(path, db)
		if map != null:
			maps.append(map)
	maps.sort_custom(_tutorial_then_smaller)
	return maps


## Whether a board is one the first-match teaching strip runs on. The one answer
## to that question: every other board is an ordinary match and shows no hints,
## so a player who came back for a second game is not taught again (COM-122).
static func teaches(map_path: String) -> bool:
	return map_path == TUTORIAL_MAP_PATH


## The dropdown label for a map path: "first_steps.txt" -> "First Steps".
static func display_name(path: String) -> String:
	return path.get_file().trim_suffix(".txt").capitalize()


## A bare board name — what a `--map=` flag carries — to the file it names, or ""
## when nothing answers to it. Shipped maps win over fixtures, and both win over
## the player's own boards, which is the right way round: the roster is the game,
## the fixtures are instruments, and a board saved on this machine may not quietly
## stand in for either. `UserMaps` refuses a name already taken here, so the
## precedence is a backstop rather than the rule.
##
## The single answer to "which board is `ironworks`?", so the offline balance
## tools and the battle scene resolve a spec identically — a watched match has to
## be played on the same board its headless row was, and two resolvers would
## eventually disagree about that.
##
## `fixtures_dir` defaults to `FIXTURES_DIR` for every real caller; it exists so
## a test can point the fixture half of the lookup at a scratch directory
## instead of writing into the versioned `maps/fixtures/` (COM-212).
static func resolve(name: String, fixtures_dir: String = FIXTURES_DIR) -> String:
	var bare := name.strip_edges().trim_suffix(".txt")
	if bare == "":
		return ""
	for dir in [MAPS_DIR, fixtures_dir, USER_DIR]:
		var path: String = dir.path_join("%s.txt" % bare)
		if ResourceLoader.exists(path) or FileAccess.file_exists(path):
			return path
	return ""


## Every name that ships, shipped roster first then fixtures — what a tool prints
## when a `--map=` flag names something that does not exist. The player's own
## boards resolve but are deliberately not listed: this is the list a bug report
## quotes, and it has to read the same on every machine.
static func resolvable_names() -> Array[String]:
	var names: Array[String] = []
	for path in paths() + fixture_paths():
		names.append(path.get_file().trim_suffix(".txt"))
	return names


static func _tutorial_then_smaller(a: MapData, b: MapData) -> bool:
	var a_teaches := teaches(a.source_path)
	var b_teaches := teaches(b.source_path)
	if a_teaches != b_teaches:
		return a_teaches
	var area_a := a.width * a.height
	var area_b := b.width * b.height
	if area_a != area_b:
		return area_a < area_b
	return a.source_path < b.source_path
