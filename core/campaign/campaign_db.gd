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
## The war pinned to item zero in `load_default()`. The picker reads this same key
## for its START HERE badge, so which campaign leads and which one says so cannot
## drift apart — `MapCatalog.TUTORIAL_MAP_PATH`'s shape, for its reason. A pin
## rather than an assumption: a build this campaign is missing from loads the rest
## alphabetically instead of refusing.
const FLAGSHIP_ID := &"the_furnace_winter"

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
	db.pin_flagship()
	return db


## Moves the flagship to the head of the order, leaving the rest as they loaded.
## Its own call site is `load_default`; it is public so a hand-built roster can be
## ordered the way the shipped one is.
func pin_flagship() -> void:
	var at := _order.find(FLAGSHIP_ID)
	if at <= 0:
		return
	_order.remove_at(at)
	_order.insert(0, FLAGSHIP_ID)


## Whether a campaign is the one the picker leads with and badges START HERE. The
## one answer to that question, so the order and the badge read the same key.
static func leads(campaign_id: StringName) -> bool:
	return campaign_id == FLAGSHIP_ID


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


## Every campaign, the flagship first and the rest in directory order, which is
## alphabetical by id.
func all() -> Array[CampaignDefinition]:
	var result: Array[CampaignDefinition] = []
	for campaign_id in _order:
		result.append(_by_id[campaign_id])
	return result


func size() -> int:
	return _order.size()
