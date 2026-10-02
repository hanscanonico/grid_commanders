class_name SaveBoard
extends RefCounted
## Which board a save resumes on.
##
## A shipped board is stored by path and reloaded on the way back in, so a save
## stays small and follows that board's edits. A board the player drew is not the
## game's to keep still: Match Setup renames and deletes it and the editor saves
## over it, and a save that named it by path alone stopped opening the moment any
## of the three happened (playtest ED-02). So a save on one of those carries the
## board's own text beside its path, and resumes on the board it was played on
## whatever became of the file. The path stays, and still names the match.
##
## Not a version bump: the key is optional at every version. A save without it is a
## shipped board's or one written before boards were carried, and reads as it always
## did; an older build reading a save with it ignores the key and reads the path.
##
## Node-free like the rest of `core/`.

const KEY := "map_text"


## Adds the board to a save's envelope when it is one the player drew.
static func carry(envelope: Dictionary, map: MapData, map_path: String) -> void:
	if UserMaps.owns(map_path) and map != null and not map.source_text.is_empty():
		envelope[KEY] = map.source_text


## "" when the carried board, if any, is text, else why the save is refused.
## Structure only, like the rest of `SaveCodec.validate`: whether the text parses
## into a board is `load_map`'s question.
static func error(data: Dictionary) -> String:
	if data.has(KEY) and not (data[KEY] is String and not String(data[KEY]).is_empty()):
		return "'%s' is malformed" % KEY
	return ""


## The board a save resumes on: the one it carries, else the file its path names.
## Null (with a pushed error) when neither gives a board.
static func load_map(data: Dictionary, terrain_db: TerrainDB) -> MapData:
	var map_path := String(data["map_path"])
	if not data.has(KEY):
		return MapData.load_from_file(map_path, terrain_db)
	var map := MapData.parse(String(data[KEY]), terrain_db)
	if map != null:
		map.source_path = map_path
	return map


## Whether a save names a board it does not carry and that is no longer on disk —
## a save no Continue could open, said before it is offered rather than after.
static func gone(data: Dictionary) -> bool:
	return not data.has(KEY) and not FileAccess.file_exists(String(data["map_path"]))
