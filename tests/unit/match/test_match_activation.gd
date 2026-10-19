extends GutTest
## S2c: Match builds its controllers in late_activate(), not in _ready()
## when Boot defers activation; the MatchContext answers null-object defaults until then.

var _previous_context: MatchContext = null


func before_each() -> void:
	_previous_context = MatchContext.installed()


func after_each() -> void:
	MatchContext.install(_previous_context)


func _deferred_match() -> MatchAutoload:
	var node: MatchAutoload = MatchAutoload.new()
	node.net_tap = MatchNetTap.new()
	node.net_tap.defer_activation = true
	add_child_autofree(node)
	return node


func test_context_answers_defaults_while_inactive() -> void:
	var node: MatchAutoload = _deferred_match()
	var context: MatchContext = node.context()
	assert_eq(context.state(), MatchPhase.State.LOBBY)
	assert_eq(context.slot_count(), 0)
	assert_null(context.slot(0))
	assert_eq(context.slot_color(0, Color.RED), Color.RED)
	assert_eq(context.active_slot(), -1)
	assert_null(context.raster())
	assert_null(context.cell_grid())
	assert_eq(context.glue_drops_left(0), 0)
	assert_false(context.feed_timer_enabled())
	assert_eq(context.feed_time_left(0), 0.0)
	assert_false(context.has_weather())
	assert_false(context.grant_glue_drops(0, 1))
	assert_false(context.start_cat(0, Vector3.ZERO, null))


## MatchNet._process reads the authority's state, so a deferred
## (pre-Boot-prewarm) MatchNet must stay idle until its own late_activate().
func test_deferred_match_net_is_idle_until_activated() -> void:
	var match_node: MatchAutoload = _deferred_match()
	var net: Node = load("res://net/MatchNet.gd").new() as Node
	net.set("tap", MatchNetTap.new())
	(net.get("tap") as MatchNetTap).defer_activation = true
	add_child_autofree(net)
	net.call(&"set_providers", null, match_node)
	assert_false(net.call(&"is_late_active"))
	assert_false(net.is_processing())
	for _frame: int in 5:
		await get_tree().process_frame
	net.call(&"late_activate")
	assert_true(net.is_processing())
