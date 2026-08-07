extends SceneTree
## Plays every campaign mission AI-vs-AI and reports whether it resolves, and
## whether the MISSION's own objective is ever reachable in practice.
const DAYS := 25


func _init() -> void:
	var tdb := TerrainDB.load_default()
	var udb := UnitDB.load_default()
	var chart: DamageChart = load("res://data/damage_chart.tres")
	var db := CampaignDB.load_default()
	var stalls := 0
	var inert := 0
	var unmet := 0
	var played := 0
	for campaign in db.all():
		var bad: Array[String] = []
		for m: MissionDefinition in campaign.missions:
			var map := MapData.load_from_file(m.map_path, tdb)
			var seats: Array[int] = m.seats.duplicate()
			var st := GameState.create(map, udb, chart, {}, seats)
			if st == null:
				continue
			st.rng.seed = 7
			var before := st.property_owners.duplicate()
			var ai := AIController.new(udb)
			var cap := maxi(400, map.width * map.height * 4)
			var n := 0
			var runtime := MissionRuntime.new(m)
			var decided := false
			while st.winner == 0 and st.day <= DAYS and n < cap:
				var c := ai.plan_next_command(st)
				if c.validate(st) != "":
					break
				c.apply(st)
				n += 1
				if not decided and runtime.evaluate(st).is_over():
					decided = true
			played += 1
			if n >= cap:
				stalls += 1
				bad.append("%s STALL" % m.id)
			elif st.winner == 0 and before == st.property_owners:
				inert += 1
				bad.append("%s INERT" % m.id)
			elif not decided:
				unmet += 1
				bad.append("%s never-decided" % m.id)
		print("%-20s %s" % [campaign.id, "ok" if bad.is_empty() else ", ".join(bad)])
	print("")
	print("played=%d  stalls=%d  inert=%d  never-decided=%d" % [played, stalls, inert, unmet])
	quit()
