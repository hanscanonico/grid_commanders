class_name SeaBeat
extends Node
## Puts the open-water sheet on the board's beat: on every BoardBeat.SEA_MS tick
## it re-points the sea TileSet source's texture at the other frame. Frame B is
## the same three phases in the same order, so the source id, the cut,
## `sheet_cells`, `atlas_coords` and `variant` are all untouched and the swell
## costs one pointer.
##
## The whole board rides it for free: the backdrop and the property ground share
## `terrain_layer.tile_set`, so the out-of-bounds ring swells with the water it
## continues, by construction rather than by a second code path.
##
## A Node because a beat needs a frame to arrive on and BattleView is RefCounted;
## it owns nothing but the pointer it was handed, in the dumb-drawer idiom
## CapturePips and MuzzleFlash are in. BattleView, the one owner of the TileSet
## and its sources, is what hands the source over — nothing here looks one up.

var _source: TileSetAtlasSource
var _frame: int = 0


## Hangs a beat on `parent` for `source`, opening on whatever frame the rest of
## the board is on — a board loaded mid-beat would otherwise show frame A and
## snap a tick later.
static func attach(parent: Node, source: TileSetAtlasSource) -> void:
	var beat := SeaBeat.new()
	beat._source = source
	beat._frame = BoardBeat.frame(BoardBeat.SEA_MS)
	beat._point_at(beat._frame)
	parent.add_child(beat)


func _process(_delta: float) -> void:
	var frame := BoardBeat.frame(BoardBeat.SEA_MS)
	if frame == _frame:
		return
	_frame = frame
	_point_at(frame)


func _point_at(frame: int) -> void:
	_source.texture = load(TerrainAutotiles.sheet_path(TerrainAutotiles.Family.SEA, frame))
