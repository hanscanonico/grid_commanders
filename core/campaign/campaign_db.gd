class_name CampaignDB
extends RefCounted
## Registry of the shipped campaigns, indexed by id. Mirrors CommanderDB and
## UnitDB: adding a campaign is dropping a directory under `data/campaigns/`,
## and nothing here lists them by hand.
##
## A campaign is a directory rather than a file because its missions are files
## too; `campaign.tres` is the one the loader looks for, and everything beside
## it is that campaign's own.

const CAMPAIGN_DIR := "res://data/campaigns"
const CAMPAIGN_FILE := "campaign.tres"

var _by_id: Dictionary[StringName, CampaignDefinition] = {}
var _order: Array[StringName] = []


static func load_default() -> CampaignDB:
	var db := CampaignDB.new()
	var dir := DirAccess.open(CAMPAIGN_DIR)
	if dir == null:
		push_error("CampaignDB: cannot open %s" % CAMPAIGN_DIR)
		return db
	var names := dir.get_directories()
	names.sort()
	for name in names:
		var path := CAMPAIGN_DIR.path_join(name).path_join(CAMPAIGN_FILE)
		if not ResourceLoader.exists(path):
			continue
		var campaign: CampaignDefinition = load(path)
		if campaign != null:
			db.register(campaign)
	return db


func register(campaign: CampaignDefinition) -> void:
	var error := campaign.definition_error()
	if error != "":
		push_error("CampaignDB: %s" % error)
		return
	if _by_id.has(campaign.id):
		push_error("CampaignDB: duplicate campaign id '%s'" % campaign.id)
		return
	_by_id[campaign.id] = campaign
	_order.append(campaign.id)


## Null when unknown — a campaign, unlike a commander, has no sensible fallback:
## there is nothing to play instead.
func by_id(campaign_id: StringName) -> CampaignDefinition:
	return _by_id.get(campaign_id)


func has(campaign_id: StringName) -> bool:
	return _by_id.has(campaign_id)


## Every campaign, in directory order, which is alphabetical by id.
func all() -> Array[CampaignDefinition]:
	var result: Array[CampaignDefinition] = []
	for campaign_id in _order:
		result.append(_by_id[campaign_id])
	return result


func size() -> int:
	return _order.size()
