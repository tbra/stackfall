extends GutTest
## docs/archive/M6_PLAN.md package B1: the territory-limit bypass MatchPlacement.gd's
## request_place()/request_throw() gain for `_match.config.sandbox` (spec
## 2.7 "Sandbox: no territory limits"), and game/main/Main.gd's Main-Menu-
## reachable start_sandbox_from_menu(), the CLI-only _start_sandbox_match()'s
## own twin.
##
## Part 1 (fixture mirrors tests/unit/match/test_placement_refusal.gd's own: tiny
## map, real Field/Match, no live peer) proves the MatchPlacement bypass
## itself: OUTSIDE_TERRITORY/CONTESTED are waived under config.sandbox, but
## OFF_DISK and HOLE are not -- and the identical point is still refused
## without config.sandbox, so the contrast is pinned in one file rather than
## trusted to test_placement_refusal.gd's separate fixture.
##
## Part 2 (fixture mirrors tests/unit/field/test_field_map_def.gd's own "drive
## Main directly" pattern) proves start_sandbox_from_menu() reaches a real
## PLAYING sandbox match with no Lobby/Net state touched.
##
## DECISION (tests/unit/main/test_sandbox_placement.gd): each test calls its own
## explicit `_setup_*()`/`_teardown_*()` pair rather than this script
## declaring GUT's `before_each()`/`after_each()` -- Part 1's fixture (a bare
## Field/BlockRegistry/Node3D trio) and Part 2's (a whole Main.tscn, which
## owns its own Field/BlockRegistry) cannot share one script-wide fixture
## without one leaving stray nodes/registrations for the other.

# --- Part 1: MatchPlacement's config.sandbox territory bypass ---------------

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func _setup_placement() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func _teardown_placement() -> void:
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config(sandbox: bool, hole_mode: MatchConfig.HoleMode = MatchConfig.HoleMode.OFF) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	# Script swap first: Object.set_script() resets script-level state to the
	# new script's declared defaults (test_match_flow.gd's own
	# _tiny_map_config() DECISION has the full story).
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 24680
	config.goal_flag_count = 0
	config.sandbox = sandbox
	config.hole_mode = hole_mode
	return config


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


func test_manual_placement_outside_territory_succeeds_in_sandbox() -> void:
	_setup_placement()
	Match.start_match(_config(true))
	_run_countdown()
	var slot_id: int = 0

	# Slot 1's home is outside slot 0's own territory (on-disk, non-hole,
	# non-goal-zone -- the exact case docs/archive/M6_PLAN.md package B1 calls out).
	var reason: StringName = Match.request_place(
		slot_id, _home_world_position(1), 0, Quaternion.IDENTITY, false
	)

	assert_eq(reason, PlacementRules.REASON_OK, "spec 1.2: sandbox has no territory limits.")
	assert_eq(_blocks_root.get_child_count(), 1)
	_teardown_placement()


func test_manual_placement_outside_territory_is_still_refused_without_sandbox() -> void:
	_setup_placement()
	Match.start_match(_config(false))
	_run_countdown()
	var slot_id: int = 0

	var reason: StringName = Match.request_place(
		slot_id, _home_world_position(1), 0, Quaternion.IDENTITY, false
	)

	assert_eq(
		reason, PlacementRules.REASON_OUTSIDE_TERRITORY,
		"fixture contrast: the identical point is refused outside sandbox."
	)
	assert_eq(_blocks_root.get_child_count(), 0)
	_teardown_placement()


# --- OFF_DISK and HOLE stay refused even under sandbox ----------------------

func test_hole_placement_is_still_refused_in_sandbox() -> void:
	_setup_placement()
	# HoleMode.TEMPORARY: validate_point()'s own doc comment -- is_hole() only
	# ever answers true under the legacy stamp fill (TEMPORARY/PERMANENT); the
	# v2 argmax fill (HoleMode.OFF) never sets it.
	Match.start_match(_config(true, MatchConfig.HoleMode.TEMPORARY))
	_run_countdown()
	var slot_id: int = 0
	# Off the +x/-x axis (2-player home flags sit at angle 0/180 --
	# PlayerSlot.home_position_for()'s own doc comment), so this point is on
	# no slot's own home flag -- punching a hole directly on one eliminates
	# it (test_match_territory_punch.gd's own "home-flag-elimination
	# trigger"), which would refuse the placement below with REASON_NO_BLOCK
	# before ever reaching the territory check this test means to pin. Also
	# outside the default single goal flag's own no-build zone at the map
	# centre (MatchConfig.GOAL_FLAG_MIN clamps goal_flag_count up to 1
	# regardless of this fixture's own _config(); TerritoryTuning.goal_zone_
	# radius is 4 m) -- validate_point() checks GOAL_ZONE before HOLE (this
	# file's own quote of its doc comment above), so this point must clear
	# the goal zone too, not just miss every home flag. Still well inside
	# this fixture's 20 m field_radius.
	var hole_point: Vector2 = Vector2(0.0, 10.0)
	Match.punch_special_hole(hole_point, 2.0, 2.0)
	var hole_cell: Vector2i = Match.cell_grid().world_to_cell(hole_point)
	assert_true(
		Match.raster().is_hole(hole_cell.x, hole_cell.y),
		"fixture: the punched cell must actually be a hole before this test means anything."
	)
	assert_true(Match.slot(slot_id).home_flag_alive, "fixture: the offset hole must not have eliminated slot 0's flag.")

	var reason: StringName = Match.request_place(
		slot_id, _field.to_global(Vector3(hole_point.x, 5.0, hole_point.y)), 0, Quaternion.IDENTITY, false
	)

	assert_eq(
		reason, PlacementRules.REASON_HOLE,
		"spec 1.2: 'no territory limits' is not 'place blocks through a hole'."
	)
	assert_eq(_blocks_root.get_child_count(), 0)
	_teardown_placement()


# --- Part 2: start_sandbox_from_menu() (game/main/Main.gd) -----------------------
