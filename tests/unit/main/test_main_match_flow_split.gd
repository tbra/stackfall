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


func _config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	var tiny: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	tiny.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = tiny
	(config as TinyMapMatchConfig).set_tiny_map(tiny)
	config.player_count = 2
	config.rng_seed = 777
	return config


## Behaviour behind the old "the forwarder loaded the flow, bound to this Main" check: the first
## match state change reaches the match flow, which builds the world as children of this Main.
func test_the_first_match_start_reaches_the_flow_and_builds_the_world_under_this_main() -> void:
	assert_false(MainNodes.world_is_built(_main), "no world before the first match state change")
	Match.start_match(_config())
	assert_true(MainNodes.world_is_built(_main), "the state change reached the flow, which built the world")
	assert_not_null(MainNodes.local_player(_main), "the world's LocalPlayer hangs under this Main")


func test_end_match_world_without_a_world_is_idempotent_through_the_forwarder() -> void:
	watch_signals(Events)
	Events.match_state_changed.emit(Match.State.LOADING, Match.State.LOBBY)
	Events.match_state_changed.emit(Match.State.LOADING, Match.State.LOBBY)
	assert_false(MainNodes.world_is_built(_main))
	assert_signal_emit_count(Events, "match_scope_reset", 2, "every return to LOBBY resets the scope, world or not")
