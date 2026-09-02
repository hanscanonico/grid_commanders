extends GutTest
## What the hub's route map plots. `plot` and `standing` are static and take the
## war and its progress, so the shape is read without building the control — and
## every state on it is `CampaignState`'s own answer, never a rule of the map's.

const HELD := &"greenwater_held"


func _campaign() -> CampaignDefinition:
	var missions: Array[MissionDefinition] = []
	for id: StringName in [&"one", &"two", &"three", &"four"]:
		missions.append(CampaignFixture.mission(id))
	var campaign := CampaignFixture.campaign(&"probe", missions)
	campaign.block_titles = ["Alone", "Together"]
	campaign.block_lengths = [2, 2]
	return campaign


func _gate(flag: StringName) -> FlagCondition:
	var condition := FlagCondition.new()
	condition.flag = flag
	condition.at_least = 1
	return condition


func _state_of(nodes: Array[CampaignRouteMap.RouteNode], id: StringName) -> int:
	for node in nodes:
		if node.id == id:
			return node.state
	return -1


func test_a_fresh_war_opens_on_its_first_node_and_locks_the_rest() -> void:
	var campaign := _campaign()
	var nodes := CampaignRouteMap.plot(campaign, CampaignState.begin(campaign))
	assert_eq(nodes.size(), 4, "a node per mission, in list order")
	assert_eq(_state_of(nodes, &"one"), CampaignRouteMap.NodeState.OPEN)
	assert_eq(_state_of(nodes, &"two"), CampaignRouteMap.NodeState.LOCKED)
	assert_eq(nodes[2].block, 1, "the third mission is the second act's first")


func test_a_cleared_node_carries_its_stars_and_the_next_opens() -> void:
	var campaign := _campaign()
	var state := CampaignState.begin(campaign)
	state.complete(campaign, &"one", 2, 5)
	var nodes := CampaignRouteMap.plot(campaign, state)
	assert_eq(_state_of(nodes, &"one"), CampaignRouteMap.NodeState.CLEARED)
	assert_eq(nodes[0].stars, 2, "the record's stars, not the mission's ceiling")
	assert_eq(_state_of(nodes, &"two"), CampaignRouteMap.NodeState.OPEN)


func test_a_gated_mission_is_a_branch_and_a_road_not_taken_reads_as_one() -> void:
	var campaign := _campaign()
	campaign.missions[1].unlock_requires = _gate(HELD)
	var state := CampaignState.begin(campaign)
	state.complete(campaign, &"one", 1, 3)
	var nodes := CampaignRouteMap.plot(campaign, state)
	assert_true(nodes[1].branch, "it opens on a condition, so it hangs off the line")
	assert_false(nodes[0].branch)
	assert_eq(_state_of(nodes, &"two"), CampaignRouteMap.NodeState.NOT_TAKEN)
	assert_eq(_state_of(nodes, &"three"), CampaignRouteMap.NodeState.OPEN)
	assert_eq(_state_of(nodes, &"four"), CampaignRouteMap.NodeState.LOCKED)


## The denominator is what the war still offers, never the authored list — a
## road not taken is not a mission left to clear.
func test_the_standing_counts_cleared_of_offered() -> void:
	var campaign := _campaign()
	campaign.missions[1].unlock_requires = _gate(HELD)
	var state := CampaignState.begin(campaign)
	assert_eq(CampaignRouteMap.standing(campaign, state), "0 / 4 · 0 ★")
	state.complete(campaign, &"one", 3, 4)
	assert_eq(
		CampaignRouteMap.standing(campaign, state),
		"1 / 3 · 3 ★",
		"the route walked past mission two, so the war is three long now"
	)
