extends GutTest
## MF3: game/main/Main.gd no longer names the match-world classes; the match flow
## lives in game/main/MainMatchFlow.gd and is loaded before the first LOBBY -> LOADING reaction.

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
var _main: Variant = null


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_main = MAIN_SCENE.instantiate()
	add_child_autofree(_main)


func after_each() -> void:
	Match.abort_match()
	Match.set_process(true)


func test_state_change_forwarder_loads_the_flow_before_the_first_reaction() -> void:
	assert_null(_main._match_flow, "no flow before the first match state change")
	_main._on_match_state_changed(Match.State.LOBBY, Match.State.LOBBY)
	assert_not_null(_main._match_flow, "the forwarder ensured the flow")
	assert_true(_main._match_flow is MainMatchFlow)
	assert_eq(_main._match_flow.main, _main, "bound to this Main")


func test_end_match_world_without_a_world_is_idempotent_through_the_forwarder() -> void:
	_main._end_match_world()
	_main._end_match_world()
	assert_false(_main._world_built)
