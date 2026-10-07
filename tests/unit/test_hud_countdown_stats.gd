extends GutTest
## Bontago-1pi.99: the top-left player stats box must list every player from
## the first COUNTDOWN frame, whether the HUD existed before the state change
## (host/client mirror signal path) or is built after it (world build awaits
## frames, so the LOADING/COUNTDOWN emits can precede HUD._ready()).

const HUD_SCENE: PackedScene = preload("res://ui/HUD.tscn")
const PLAYER_COUNT: int = 3

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func after_each() -> void:
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = PLAYER_COUNT
	config.hot_seat = false
	config.rng_seed = 99
	config.countdown_seconds = MatchConfig.COUNTDOWN_SECONDS_DEFAULT
	return config


func _make_hud() -> HUD:
	var hud: HUD = autofree(HUD_SCENE.instantiate()) as HUD
	add_child_autofree(hud)
	return hud


func _assert_rows_populated(hud: HUD) -> void:
	assert_eq(hud._share_rows.size(), PLAYER_COUNT, "one stats row per player")
	for i: int in range(hud._share_name_labels.size()):
		assert_false((hud._share_name_labels[i] as Label).text.is_empty(), "row %d has a name" % i)
		assert_false((hud._share_labels[i] as Label).text.is_empty(), "row %d has a value" % i)
	assert_true(hud._shares_box.is_visible_in_tree(), "stats box is visible")


func test_host_hud_built_before_countdown_has_rows_in_countdown() -> void:
	var hud: HUD = _make_hud()
	Match.start_match(_config())
	assert_eq(Match.state(), Match.State.COUNTDOWN)
	_assert_rows_populated(hud)


func test_host_hud_built_after_countdown_began_has_rows() -> void:
	Match.start_match(_config())
	assert_eq(Match.state(), Match.State.COUNTDOWN)
	var hud: HUD = _make_hud()
	_assert_rows_populated(hud)


func test_client_mirror_hud_has_rows_in_countdown() -> void:
	# A client builds its match locally from the lobby config, then mirrors the
	# host's replicated state changes; its HUD can be built at either point.
	Match.start_match(_config())
	Match.apply_replicated_state_change(Match.State.LOADING)
	var hud: HUD = _make_hud()
	Match.apply_replicated_state_change(Match.State.COUNTDOWN)
	Match.apply_replicated_countdown(3)
	assert_eq(Match.state(), Match.State.COUNTDOWN)
	_assert_rows_populated(hud)
	var late_hud: HUD = _make_hud()
	_assert_rows_populated(late_hud)
