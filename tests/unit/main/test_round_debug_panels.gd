extends GutTest
## RoundDebugPanels: the F2 pose, F3 net and F9 bot-cost panels of one match are built whether or not
## debug mode is on, wired from the properties set before add_child, and freed with the node.

var _camera: Camera3D = null
var _field: Field = null
var _context: MatchContext = null
var _config: DebugConfig = null
var _panels: RoundDebugPanels = null


func before_each() -> void:
	_camera = autofree(Camera3D.new()) as Camera3D
	_field = autofree(Field.new()) as Field
	_context = MatchContext.current()
	_config = DebugConfig.new()
	_panels = RoundDebugPanels.new()
	_panels.camera = _camera
	_panels.field = _field
	_panels.match_context = _context
	_panels.config = _config


func after_each() -> void:
	DebugMode.clear_override_for_test()


func _children_of(type: Variant) -> Array[Node]:
	var found: Array[Node] = []
	for node: Node in _panels.get_children():
		if is_instance_of(node, type):
			found.append(node)
	return found


func _check_builds_exactly_the_three(debug_on: bool) -> void:
	DebugMode.set_override_for_test(debug_on)
	add_child_autofree(_panels)
	assert_eq(_children_of(PoseOverlay).size(), 1, "F2")
	assert_eq(_children_of(NetDebugOverlay).size(), 1, "F3")
	assert_eq(_children_of(PerfBotCostOverlay).size(), 1, "F9")
	assert_eq(_panels.get_child_count(), 3, "nothing else")


func test_debug_on_builds_f2_f3_f9() -> void:
	_check_builds_exactly_the_three(true)


func test_debug_off_builds_f2_f3_f9_too() -> void:
	_check_builds_exactly_the_three(false)


func test_pose_overlay_is_wired() -> void:
	add_child_autofree(_panels)
	var found: Array[Node] = _children_of(PoseOverlay)
	if found.is_empty():
		fail_test("PoseOverlay not built")
		return
	var pose: PoseOverlay = found[0] as PoseOverlay
	assert_eq(pose.camera, _camera)
	assert_eq(pose.field, _field)
	assert_eq(pose.match_context, _context)
	assert_eq(pose.config, _config)


func test_bot_cost_overlay_is_wired() -> void:
	add_child_autofree(_panels)
	var found: Array[Node] = _children_of(PerfBotCostOverlay)
	if found.is_empty():
		fail_test("PerfBotCostOverlay not built")
		return
	var bot_cost: PerfBotCostOverlay = found[0] as PerfBotCostOverlay
	assert_eq(bot_cost.match_context, _context)
	assert_eq(bot_cost.config, _config)


func test_net_overlay_reads_live_net_stats_and_gets_the_config() -> void:
	add_child_autofree(_panels)
	var found: Array[Node] = _children_of(NetDebugOverlay)
	if found.is_empty():
		fail_test("NetDebugOverlay not built")
		return
	var net: NetDebugOverlay = found[0] as NetDebugOverlay
	assert_true(net.source is NetStatsLive, "F3 source is the live net stats")
	assert_eq(net.config, _config)


func test_freeing_the_node_frees_the_panels() -> void:
	add_child(_panels)
	var kids: Array[Node] = _panels.get_children()
	assert_eq(kids.size(), 3)
	_panels.free()
	for kid: Node in kids:
		assert_false(is_instance_valid(kid), "panel freed with RoundDebugPanels")
