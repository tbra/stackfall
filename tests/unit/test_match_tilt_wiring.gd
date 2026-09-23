extends GutTest
## autoload/match/MatchLifecycle.gd wiring MatchConfig.tilt_mode into the Field
## it was handed by register_world() (spec 2.6 tilt, 2.8 tilt_mode; docs/
## M4_PLAN.md P0b/P5 tilt notes; Bontago-1en.23).
##
## Before this package, nothing ever called Field.set_tilt_enabled(true) in a
## real match: Field shipped the controller off by default (game/Field.gd's
## own doc: "every scene and test that predates this package" stays
## untouched), and no autoload/match/*.gd file flipped it on. Anvil/Propeller/
## Earthquake's apply_tilt_impulse() calls were therefore silent no-ops the
## moment they ran inside an actual match, even under the default
## SPECIALS_ONLY tilt_mode.
##
## Same fast fixture as tests/unit/test_gift_claim.gd: a bare Field (not the
## whole Main scene/Net), directly through Match.register_world(), so this
## stays a quick unit test rather than needing test_match_lifecycle.gd's real
## ENet host session.

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef

const TICK: float = 1.0 / 60.0


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


func _config(tilt_mode: MatchConfig.TiltMode = MatchConfig.TiltMode.SPECIALS_ONLY) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 4242
	config.tilt_mode = tilt_mode
	return config


# --- register_world() + start_match() enables tilt --------------------------

func test_starting_a_specials_only_match_enables_tilt_on_the_registered_field() -> void:
	assert_false(_field.tilt_enabled(), "fixture: Field starts with tilt off")

	Match.start_match(_config(MatchConfig.TiltMode.SPECIALS_ONLY))

	assert_true(
		_field.tilt_enabled(),
		"start_match() with tilt_mode SPECIALS_ONLY must enable the field's tilt controller"
	)

	_field.apply_tilt_impulse(Vector2(1.0, 0.0), 0.5)
	_field._update_tilt(TICK)
	assert_ne(
		_field.tilt_vector(), Vector2.ZERO,
		"with tilt enabled, an Anvil/Propeller/Earthquake-style impulse must actually move the disk"
	)


func test_starting_a_physical_balance_match_also_enables_tilt() -> void:
	Match.start_match(_config(MatchConfig.TiltMode.PHYSICAL_BALANCE))

	assert_true(
		_field.tilt_enabled(),
		"tilt_mode PHYSICAL_BALANCE tilts too (config/MatchConfig.gd); only a future OFF value would not"
	)


# --- abort disables tilt and levels the disc ---------------------------------

func test_abort_disables_tilt_and_levels_the_disc() -> void:
	Match.start_match(_config())
	_field.apply_tilt_impulse(Vector2(1.0, 0.0), 0.5)
	_field._update_tilt(TICK)
	assert_ne(_field.tilt_vector(), Vector2.ZERO, "fixture: the disk is actually tilted before abort")

	Match.abort_match()

	assert_false(_field.tilt_enabled(), "abort_match() must disable the field's tilt controller")
	assert_eq(_field.tilt_vector(), Vector2.ZERO, "abort_match() must level the disc")


# --- a second match start re-enables tilt ------------------------------------

func test_a_second_match_start_re_enables_tilt() -> void:
	Match.start_match(_config())
	Match.abort_match()
	assert_false(_field.tilt_enabled(), "fixture: disabled after the first match's abort")

	Match.start_match(_config())

	assert_true(_field.tilt_enabled(), "a fresh start_match() must re-enable tilt for the new match")
