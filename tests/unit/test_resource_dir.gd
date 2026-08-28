extends GutTest
## The one directory scan every registry and the map catalog go through.
##
## What it owes its callers is the `.remap` rule an exported build needs, the
## suffix filter, and the directory's own order — a registry that came back
## sorted would be a different seeding order than the one every shipped frame
## was captured with.


func test_files_are_full_paths_of_the_asked_suffix() -> void:
	var paths := ResourceDir.files(UnitDB.UNIT_DIR, ".tres", "test")
	assert_gt(paths.size(), 0, "the shipped unit roster is not empty")
	for path in paths:
		assert_true(path.begins_with(UnitDB.UNIT_DIR + "/"), "full path: %s" % path)
		assert_true(path.ends_with(".tres"), "asked suffix: %s" % path)


func test_other_suffixes_are_skipped() -> void:
	assert_eq(ResourceDir.files(MapCatalog.MAPS_DIR, ".tres", "test"), [] as Array[String])
	assert_gt(ResourceDir.files(MapCatalog.MAPS_DIR, ".txt", "test").size(), 0)


## Read against the filesystem's own listing rather than against a sorted copy:
## a directory this machine happens to hand back in order would let a sorting
## helper pass a sorted-copy check.
func test_order_is_the_directorys_own() -> void:
	var dir := DirAccess.open(MapCatalog.MAPS_DIR)
	var listed: Array[String] = []
	for file in dir.get_files():
		var map_file := file.trim_suffix(".remap")
		if map_file.ends_with(".txt"):
			listed.append(MapCatalog.MAPS_DIR.path_join(map_file))
	assert_eq(ResourceDir.files(MapCatalog.MAPS_DIR, ".txt", "test"), listed)


func test_the_catalog_sorts_what_the_scan_hands_back() -> void:
	var sorted := ResourceDir.files(MapCatalog.MAPS_DIR, ".txt", "test")
	sorted.sort()
	assert_eq(MapCatalog.paths(), sorted)
