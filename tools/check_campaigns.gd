extends SceneTree
## Loads every shipped campaign and holds it to the bar a playable mission has
## to clear: the board parses, the seating is one the board deals, every
## objective names ground that exists, every fact its content reads is one the war
## writes, every mission it lists can be opened by some route through it, and the
## whole thing can be launched.
##
## Authoring guard rather than a unit test — it walks real content, so it is a
## `tools/` script the content author runs. `make campaigns` is the entry point.
##
## Exits non-zero on the first campaign that could not be played, naming the
## mission and the reason, so a bad `.tres` is loud at the door.

var _errors: Array[String] = []
var _missions := 0


func _init() -> void:
	var terrain_db := TerrainDB.load_default()
	var unit_db := UnitDB.load_default()
	var chart: DamageChart = load("res://data/damage_chart.tres")
	var commander_db := CommanderDB.load_default()
	var difficulty_db := DifficultyDB.load_default()
	var db := CampaignDB.load_default()
	if db.size() == 0:
		_fail("no campaigns found under data/campaigns/")
	for campaign in db.all():
		_check_campaign(campaign, terrain_db, unit_db, chart, commander_db, difficulty_db)
	print("")
	if _errors.is_empty():
		print("check_campaigns: %d campaigns, %d missions, all playable" % [db.size(), _missions])
		quit(0)
		return
	for error in _errors:
		printerr("  %s" % error)
	printerr("check_campaigns: %d problem(s)" % _errors.size())
	quit(1)


func _fail(message: String) -> void:
	_errors.append(message)


func _check_campaign(
	campaign: CampaignDefinition,
	terrain_db: TerrainDB,
	unit_db: UnitDB,
	chart: DamageChart,
	commander_db: CommanderDB,
	difficulty_db: DifficultyDB
) -> void:
	var structural := campaign.definition_error()
	if structural != "":
		_fail(structural)
		return
	# The one check that needs the whole war at once: a flag a mission reads and no
	# mission of it writes is a variant line nobody ever hears.
	var ledger := campaign.ledger_error()
	if ledger != "":
		_fail(ledger)
	# The other check that needs the whole war at once: a mission that carries an
	# army in behind one that carries none out opens with nothing having arrived.
	var chain := campaign.carry_error()
	if chain != "":
		_fail(chain)
	# The third: a mission whose condition no earlier mission can satisfy is one
	# the route walks past every time, on every route (campaign-depth D7).
	var route := campaign.route_error()
	if route != "":
		_fail(route)
	for page: CampaignInterlude in campaign.interludes:
		var interlude := page.definition_error(commander_db)
		if interlude != "":
			_fail("%s: %s" % [campaign.id, interlude])
	print("%s — %s (%d missions)" % [campaign.id, campaign.title, campaign.mission_count()])
	for mission: MissionDefinition in campaign.missions:
		_missions += 1
		_check_mission(campaign, mission, terrain_db, unit_db, chart, commander_db, difficulty_db)


func _check_mission(
	campaign: CampaignDefinition,
	mission: MissionDefinition,
	terrain_db: TerrainDB,
	unit_db: UnitDB,
	chart: DamageChart,
	commander_db: CommanderDB,
	difficulty_db: DifficultyDB
) -> void:
	var where := "%s/%s" % [campaign.id, mission.id]
	if not FileAccess.file_exists(mission.map_path):
		_fail("%s: no such board '%s'" % [where, mission.map_path])
		return
	var map := MapData.parse(FileAccess.get_file_as_string(mission.map_path), terrain_db)
	if map == null:
		_fail("%s: board '%s' does not parse" % [where, mission.map_path])
		return
	var error := mission.definition_error(map, unit_db)
	if error != "":
		_fail("%s: %s" % [where, error])
		return
	var tier := mission.difficulty_error(difficulty_db)
	if tier != "":
		_fail("%s: %s" % [where, tier])
	var story := mission.story_error(commander_db)
	if story != "":
		_fail("%s: %s" % [where, story])
	for team: int in mission.commanders:
		var commander_id: StringName = mission.commanders[team]
		if not commander_db.has(commander_id):
			_fail(
				(
					"%s: seat %d is cast as '%s', who is not on the roster"
					% [where, team, commander_id]
				)
			)
	# The launch has to actually build, which is the only check that proves the
	# seating, the grouping and the board agree with one another.
	var seats: Array[int] = mission.seats.duplicate()
	var state := GameState.create(map, unit_db, chart, {}, seats)
	if state == null:
		# `create` has already pushed the specific reason — a unit standing on
		# ground its movement class cannot enter is the usual one, and naming the
		# seating here instead sent an author looking at the wrong line.
		_fail("%s: the board would not build (see the GameState error above)" % where)
		return
	if not mission.briefing.is_empty() and mission.victory.is_empty():
		_fail("%s: has a briefing but nothing to say when it is won" % where)
	_check_events(where, mission, state)


## Every scripted effect against the board the mission actually opens on. The
## mission's own `definition_error` has already held them to the *map*; this is
## the one question it cannot ask, because a map deals every seat it names while
## a mission may have closed some of them — reinforcements for a seat nobody is
## playing parse perfectly and land nowhere.
func _check_events(where: String, mission: MissionDefinition, state: GameState) -> void:
	for event: MissionEvent in mission.events:
		for effect: MissionEffect in event.effects:
			var error := effect.board_error(state, mission.player_team)
			if error != "":
				_fail("%s: event '%s': %s" % [where, event.id, error])
