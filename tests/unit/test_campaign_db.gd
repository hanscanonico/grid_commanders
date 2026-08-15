extends GutTest
## Which war the picker leads with. The roster is still discovered rather than
## listed (`load_default` scans the directory), so what is pinned here is the one
## thing a scan cannot say: the flagship goes first and everything else keeps the
## alphabetical order it loaded in.


func _campaign(id: StringName) -> CampaignDefinition:
	var mission := MissionDefinition.new()
	mission.id = &"one"
	mission.title = "One"
	mission.map_path = "res://maps/first_steps.txt"
	var campaign := CampaignDefinition.new()
	campaign.id = id
	campaign.title = String(id)
	campaign.missions.append(mission)
	return campaign


func _ids(db: CampaignDB) -> Array[StringName]:
	var ids: Array[StringName] = []
	for campaign in db.all():
		ids.append(campaign.id)
	return ids


func test_the_shipped_roster_leads_with_the_flagship() -> void:
	var ids := _ids(CampaignDB.load_default())
	assert_false(ids.is_empty(), "the shipped campaigns load")
	assert_eq(ids[0], CampaignDB.FLAGSHIP_ID, "the flagship is item zero")


func test_the_wars_after_the_flagship_stay_alphabetical() -> void:
	# Compared as Strings on purpose: StringNames sort by interned pointer, which
	# is not the alphabetical order the directory scan produced.
	var rest: Array[String] = []
	for campaign_id in _ids(CampaignDB.load_default()).slice(1):
		rest.append(String(campaign_id))
	var sorted := rest.duplicate()
	sorted.sort()
	assert_eq(rest, sorted, "only the flagship's place moved")


func test_a_roster_without_the_flagship_keeps_the_order_it_loaded() -> void:
	var db := CampaignDB.new()
	for id: StringName in [&"alpha", &"beta"]:
		db.register(_campaign(id))
	db.pin_flagship()
	assert_eq(_ids(db), [&"alpha", &"beta"] as Array[StringName], "a missing pin moves nothing")


func test_the_badge_and_the_order_read_the_same_key() -> void:
	assert_true(CampaignDB.leads(CampaignDB.FLAGSHIP_ID), "the flagship leads")
	assert_false(CampaignDB.leads(&"six_marshals"), "and nothing else does")
	# The row the picker prints, not just the key behind it: the war that leads
	# the list has to be the war that says to start there.
	assert_string_contains(
		CampaignPickerPanel.row_text(_campaign(CampaignDB.FLAGSHIP_ID), null), "START HERE"
	)
	assert_false(
		CampaignPickerPanel.row_text(_campaign(&"six_marshals"), null).contains("START HERE"),
		"and no other war wears the badge"
	)
