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


func test_order_is_the_directory_s_own() -> void:
	var scanned := ResourceDir.files(MapCatalog.MAPS_DIR, ".txt", "test")
	var sorted := scanned.duplicate()
	sorted.sort()
	assert_eq(MapCatalog.paths(), sorted, "the catalog sorts what the scan hands back")
