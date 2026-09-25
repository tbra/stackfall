extends GutTest
## Bontago-keo.2 (docs/M6_PLAN.md package A0): Field must bake the *match's*
## real MapDef, not whatever its own @export default happens to be.
## `game/Field.gd`'s `_build_cells()` (now `_rebuild_cells()`) used to run
## only once, from `_ready()`, against Field's own `@export var map_def`
## (`round_medium.tres`); `game/Main.gd` never told it about the match's real
## `config.map_def()` at any of its three `place_flags()`/`set_overlay_
## source()` call sites. This drives the real Main scene directly, the same
## fixture shape as `tests/unit/test_headless_bot_match.gd`'s own
## `before_each` ("the real Main scene, a tiny map override so
## round_medium.tres's own collision build doesn't pay its ~6300-cell cost
## per test"), deliberately giving Field's own default map a *different*
## radius/cell_size than the match's map so a rebuild that never ran would
## be caught, not silently matched by coincidence.

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")

## game/Main.gd has no class_name (a scene root) -- see test_headless_bot_
## match.gd's matching comment -- so the instance is held untyped.
var _main: Variant = null
var _field_default_map: MapDef
var _match_map: MapDef

static var _next_port: int = 48700


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	assert_true(Net.is_offline(), "fixture: the real Net must start offline")

	_main = MAIN_SCENE.instantiate()

	# Field's own @export default, deliberately a different size and cell
	# resolution than the match's own map below -- a test that passed before
	# Bontago-keo.2's fix (Field baking this one forever, regardless of the
	# match's real config) would fail every assertion here.
	_field_default_map = MapDef.new()
	_field_default_map.id = &"field_default"
	_field_default_map.field_radius = 20.0
	_field_default_map.cell_size = 2.0
	(_main.get_node("Field") as Field).map_def = _field_default_map

	# The match's real map: only reachable through MatchConfig.map_def() --
	# exactly the seam keo.2's bug skipped.
	_match_map = MapDef.new()
	_match_map.id = &"match_real"
	_match_map.field_radius = 12.0
	_match_map.cell_size = 1.0

	var tiny_match_config: MatchConfig = (
		load("res://config/match_defaults.tres") as MatchConfig
	).duplicate(true)
	tiny_match_config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(tiny_match_config as TinyMapMatchConfig).set_tiny_map(_match_map)
	tiny_match_config.rng_seed = 90210
	_main.match_config = tiny_match_config

	add_child_autofree(_main)
	assert_not_null(_main._main_menu, "fixture: Main boots to the main menu with no command-line flags")


func after_each() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame


func _take_port() -> int:
	var port: int = _next_port
	_next_port += 1
	return port


func _field() -> Field:
	return _main.get_node("Field") as Field


## Value equality, not object identity: Match.start_match() always runs on
## `match_config.duplicate(true)` (autoload/match/MatchLifecycle.gd:90), and
## Resource.duplicate(true) deep-duplicates TinyMapMatchConfig's own
## `@export var tiny_map` right along with it, so the MapDef
## `Match.config.map_def()` (and therefore rebuild_for_map()) actually
## receives is a distinct object from `_match_map` with the same field
## values -- exactly the "deep duplicate" TinyMapMatchConfig's own doc
## comment already documents.
func _assert_field_matches_the_match_map() -> void:
	var baked: MapDef = _field().map_definition()
	assert_eq(baked.id, _match_map.id, "Field must bake the match's real MapDef, not its own default")
	assert_almost_eq(baked.field_radius, _match_map.field_radius, 0.001)
	assert_almost_eq(baked.cell_size, _match_map.cell_size, 0.001)
	assert_almost_eq(_field().grid().field_radius, _match_map.field_radius, 0.001)
	assert_almost_eq(_field().grid().cell_size, _match_map.cell_size, 0.001)


# --- Call site 1: _start_hot_seat_match() ------------------------------------

func test_hot_seat_rebuilds_field_for_the_match_map() -> void:
	assert_eq(
		_field().map_definition(), _field_default_map,
		"fixture: Field starts on its own default map, not the match's"
	)

	_main._start_hot_seat_match()

	_assert_field_matches_the_match_map()


# --- Call site 2: _start_sandbox_match_with_args() ---------------------------

func test_sandbox_rebuilds_field_for_the_match_map() -> void:
	_main._start_sandbox_match_with_args(PackedStringArray(["--players=2"]))

	_assert_field_matches_the_match_map()


# --- Call site 3: _build_match_world() (the real networked/lobby path,
# reached here through --headless-host --bots=, same seam test_headless_bot_
# match.gd's own fixture uses) ------------------------------------------------

func test_networked_match_world_rebuilds_field_for_the_match_map() -> void:
	assert_eq(Net.host_game(_take_port(), "Hostie"), OK)
	assert_true(_main._net_is_hosting())

	_main._start_headless_bot_match_with_args(PackedStringArray(["--bots=2"]))
	await get_tree().process_frame
	await get_tree().process_frame

	_assert_field_matches_the_match_map()
