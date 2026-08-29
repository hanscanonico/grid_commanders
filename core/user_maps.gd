class_name UserMaps
extends RefCounted
## Storage for the boards the player draws: reads, writes, renames and deletes
## files under `MapCatalog.USER_DIR`, and nothing else.
##
## Everything about *what* a board contains belongs to `MapData` and
## `MapDocument`, and whether it plays belongs to `MapValidator` — the same split
## SaveGame keeps from SaveCodec, so a full disk and an unplayable board are
## separate failures with separate messages. What this file owns is the one thing
## neither of them can: which file a name means, and which names are a name at
## all.
##
## A board is saved as the plain `maps/*.txt` text every shipped board is, so a
## user map is loaded, resolved, thumbnailed and played by exactly the code that
## loads a shipped one. There is no user-map format.
##
## Node-free like the rest of `core/`.

const EXTENSION := ".txt"
## What a name may be made of. A board's name is also its filename, and the same
## text goes into a `--map=` flag, so the set is the one every filesystem and
## every shell agree about rather than whatever the text field accepted.
const NAME_CHARACTERS := "abcdefghijklmnopqrstuvwxyz0123456789_-"
## How long a name may be — twice the longest board that ships
## (`coal_and_crown`, at 14), which is room for a title and none for a paragraph.
const MAX_NAME_LENGTH := 28


## The file `name` is kept in, whether or not anything is there yet.
static func path_for(name: String) -> String:
	return MapCatalog.USER_DIR.path_join(slug(name) + EXTENSION)


## What the player typed, as a filename: lower case, runs of anything else
## collapsed to one underscore, and trimmed. Every name goes through here before
## it reaches the disk, so a board saved as "Iron Gulf!" and one saved as
## "iron  gulf" are the same board rather than two files one screen shows twice.
static func slug(name: String) -> String:
	var out := ""
	for character in name.to_lower():
		if NAME_CHARACTERS.contains(character):
			out += character
		elif not out.ends_with("_"):
			out += "_"
	return out.lstrip("_").rstrip("_")


## Why `name` cannot be used, in the author's words, or "" when it can. A name
## that collides with a shipped board or a fixture is refused here rather than
## shadowed at resolution: `--map=ironworks` has to mean the same board on every
## machine, and a picker showing two rows called Ironworks is nobody's idea of a
## roster.
static func name_error(name: String) -> String:
	var bare := slug(name)
	if bare.is_empty():
		return "Give the map a name."
	if bare.length() > MAX_NAME_LENGTH:
		return "That name is too long — %d letters at most." % MAX_NAME_LENGTH
	if MapCatalog.resolvable_names().has(bare):
		return "A map that ships with the game is already called '%s'." % bare
	return ""


## Whether the player already has a board under this name.
static func exists(name: String) -> bool:
	var bare := slug(name)
	return not bare.is_empty() and FileAccess.file_exists(path_for(bare))


## Writes `text` as the board called `name`, replacing one already there.
## Returns "" on success, else why not — a refused name and a disk that will not
## take the file are both the author's business, so neither is only a log line.
static func save(name: String, text: String) -> String:
	var error := name_error(name)
	if error != "":
		return error
	if not _ensure_dir():
		return "The folder your maps are kept in cannot be opened."
	var handle := FileAccess.open(path_for(name), FileAccess.WRITE)
	if handle == null:
		return "'%s' could not be written (error %d)." % [slug(name), FileAccess.get_open_error()]
	handle.store_string(text)
	handle.close()
	return ""


## The names the player has saved, alphabetically — what a picker lists.
static func list() -> Array[String]:
	var names: Array[String] = []
	for path in MapCatalog.user_paths():
		names.append(path.get_file().trim_suffix(EXTENSION))
	return names


## One saved board, parsed. Null (with a pushed error, MapData's) when the file
## is missing or is not a board.
static func load_map(name: String, db: TerrainDB) -> MapData:
	return MapData.load_from_file(path_for(name), db)


## Forgets a board. Returns "" on success, else why not. A name that was never
## there is a failure and says so: the caller asked for it to be gone by that
## name, and silence would tell them a board they can still see was removed.
static func delete(name: String) -> String:
	if not exists(name):
		return "There is no map called '%s'." % slug(name)
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(path_for(name))) != OK:
		return "'%s' could not be deleted." % slug(name)
	return ""


## Moves a board to a new name, refusing to write over one that is already
## there — renaming onto an existing board is how an author loses the one they
## were not looking at. Returns "" on success, else why not.
static func rename(from: String, to: String) -> String:
	if not exists(from):
		return "There is no map called '%s'." % slug(from)
	var error := name_error(to)
	if error != "":
		return error
	if slug(to) == slug(from):
		return ""
	if exists(to):
		return "You already have a map called '%s'." % slug(to)
	var dir := DirAccess.open(MapCatalog.USER_DIR)
	if dir == null or dir.rename(path_for(from), path_for(to)) != OK:
		return "'%s' could not be renamed." % slug(from)
	return ""


static func _ensure_dir() -> bool:
	var absolute := ProjectSettings.globalize_path(MapCatalog.USER_DIR)
	if DirAccess.dir_exists_absolute(absolute):
		return true
	var made := DirAccess.make_dir_recursive_absolute(absolute)
	if made != OK:
		push_error("UserMaps: cannot make %s (error %d)" % [MapCatalog.USER_DIR, made])
		return false
	return true
