extends GutTest
## Bontago-1pi.11.29: a catch-up window of several solve steps with one change
## emits territory_updated once and solves once; weather changes never dirty the
## territory solve.

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef
var _emits: int = 0


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
	Match.abort_match()
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = true
	config.hole_mode = MatchConfig.HoleMode.OFF
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	Match._territory._solve_accum = 0.0
	Match._territory.mark_dirty()
	Match._territory._tick_territory(1.0)
	Match._territory._solve_accum = 0.0
	_emits = 0
	Events.territory_updated.connect(_on_updated)


func after_each() -> void:
	if Events.territory_updated.is_connected(_on_updated):
		Events.territory_updated.disconnect(_on_updated)
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _on_updated(_raster: TerritoryRaster, _groups: TerritoryGroups) -> void:
	_emits += 1


func test_multi_step_catch_up_emits_once() -> void:
	var step: float = 1.0 / Match._territory_tuning.solve_hz
	var solves: int = Match._territory.solve_step_count()
	Match._territory.mark_dirty()
	Match._territory._tick_territory(step * 3.5)
	assert_eq(Match._territory.solve_step_count() - solves, 1, "one solve for one change")
	assert_eq(_emits, 1, "one territory_updated for one change")


func test_weather_visual_changes_do_not_dirty_the_solve() -> void:
	var step: float = 1.0 / Match._territory_tuning.solve_hz
	var solves: int = Match._territory.solve_step_count()
	var overlay: TerritoryOverlay = _field.overlay()
	if overlay != null:
		overlay.set_wet(1.0, 0.2, 0.5)
		overlay.set_wet(0.0, 0.2, 0.5)
	Match._territory._tick_territory(step * 2.5)
	assert_eq(Match._territory.solve_step_count(), solves, "wet sheen leaves the solve clean")
	assert_eq(_emits, 0, "no territory_updated for presentation-only changes")
