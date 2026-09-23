extends GutTest
## MatchTerritory.punch_special_hole() / Match.punch_special_hole() (M4
## P5-HOLE, Bontago-1en.20): a special effect's own local hole, independent of
## territory contest (spec 2.6). TerritoryRaster.force_hole_cell()'s own timer
## math (opens immediately, closes via the existing hole_close_delay decay,
## never under PERMANENT) is tested directly in test_territory_raster.gd; this
## file is the host-level contract punch_special_hole() adds on top: HoleMode
## gating, the radius-to-cells conversion, the single hole_cells_changed
## emit, and the home-flag-elimination trigger (Bontago-3td, owner question 2
## -- shipped as the default per docs/M4_SPECIALS_PACKAGES.md's "Orchestrator
## decisions (2026-09-23, binding)", item 2).
##
## New file rather than appended to test_match_flow.gd (already ~990 lines
## covering the whole state machine) or test_territory_raster.gd (the raster-
## level force_hole_cell() tests already added there) -- see the dispatch
## brief's file-ownership note.
##
## Fixture mirrors test_match_flow.gd's own before_each/_tiny_map_config
## exactly (TinyMapMatchConfig, see that file's own DECISION for why a 20 m
## map replaces Field.gd's default round_medium.tres for these tests).

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


func _tiny_map_config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	return config


func _hotseat_config(hole_mode: MatchConfig.HoleMode) -> MatchConfig:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = 2
	config.hot_seat = true
	config.block_timer = 6.0
	config.rng_seed = 12345
	config.hole_mode = hole_mode
	return config


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


# --- HoleMode gating (owner decision Bontago-z4h) ---------------------------

func test_punch_special_hole_is_a_noop_under_hole_mode_off() -> void:
	Match.start_match(_hotseat_config(MatchConfig.HoleMode.OFF))
	_run_countdown()
	watch_signals(Events)

	var home0: Vector2 = Match.slot(0).home_position
	Match.punch_special_hole(home0, 2.0, 2.0)

	var cell: Vector2i = Match.cell_grid().world_to_cell(home0)
	assert_false(Match.raster().is_hole(cell.x, cell.y), "OFF must never open a hole.")
	assert_signal_not_emitted(Events, "hole_cells_changed")
	assert_true(Match.slot(0).home_flag_alive, "OFF must not eliminate anyone either.")


# --- Radius and the change-set (TEMPORARY) ----------------------------------

func test_punch_special_hole_opens_the_expected_cells_under_temporary() -> void:
	Match.start_match(_hotseat_config(MatchConfig.HoleMode.TEMPORARY))
	_run_countdown()

	var home0: Vector2 = Match.slot(0).home_position
	var radius: float = 2.0
	Match.punch_special_hole(home0, radius, 2.0)

	var center_cell: Vector2i = Match.cell_grid().world_to_cell(home0)
	assert_true(Match.raster().is_hole(center_cell.x, center_cell.y), "The punched centre is a hole.")

	## The disk's own centre: on this map's layout (home_flag_radius_fraction
	## 0.85 of a 20 m field) that is 17 m from home0, far outside radius_m.
	var far_cell: Vector2i = Match.cell_grid().world_to_cell(Vector2.ZERO)
	assert_false(Match.raster().is_hole(far_cell.x, far_cell.y), "Outside radius_m stays untouched.")


func test_punch_special_hole_emits_hole_cells_changed_exactly_once() -> void:
	Match.start_match(_hotseat_config(MatchConfig.HoleMode.TEMPORARY))
	_run_countdown()
	watch_signals(Events)

	var home0: Vector2 = Match.slot(0).home_position
	Match.punch_special_hole(home0, 2.0, 2.0)

	assert_signal_emit_count(Events, "hole_cells_changed", 1,
		"One punch covering several cells is one change-set, not one signal per cell.")


# --- Home-flag elimination (Bontago-3td, orchestrator decision 2) -----------

func test_punch_special_hole_eliminates_a_home_flag_sitting_in_the_punched_disk() -> void:
	Match.start_match(_hotseat_config(MatchConfig.HoleMode.TEMPORARY))
	_run_countdown()
	watch_signals(Events)

	var home0: Vector2 = Match.slot(0).home_position
	Match.punch_special_hole(home0, 2.0, 2.0)

	assert_false(Match.slot(0).home_flag_alive)
	assert_signal_emitted_with_parameters(Events, "player_eliminated", [0, 0])


# --- Match-state guard (SHOULD-FIX, review 2026-09-23) ----------------------
#
# _finish_match() only sets State.END (autoload/match/MatchLifecycle.gd);
# nothing tears the raster down or stops a SpecialEffect's physics_tick(), so
# a Jumping Bean still hopping after a natural win could otherwise still
# punch a hole under a still-alive slot's home flag on the winning team and
# eliminate it after the match is already decided. Mirrors
# MatchPlacement.spawn_special_projectile()'s own State.PLAYING guard.
func test_punch_special_hole_is_a_noop_after_the_match_has_ended() -> void:
	Match.start_match(_hotseat_config(MatchConfig.HoleMode.TEMPORARY))
	_run_countdown()
	assert_true(Match.slot(1).home_flag_alive, "Setup: slot 1 is still alive.")

	Match._finish_match(0)
	assert_eq(Match.state(), Match.State.END, "Setup: the match already has a winner.")
	watch_signals(Events)

	var home1: Vector2 = Match.slot(1).home_position
	Match.punch_special_hole(home1, 2.0, 2.0)

	var cell: Vector2i = Match.cell_grid().world_to_cell(home1)
	assert_false(Match.raster().is_hole(cell.x, cell.y),
		"A punch after State.END must not open a hole at all.")
	assert_true(Match.slot(1).home_flag_alive,
		"A slot still alive when the match ended must not be eliminated afterwards.")
	assert_signal_not_emitted(Events, "player_eliminated")
