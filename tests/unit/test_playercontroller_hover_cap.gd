extends GutTest
## Bontago-mv0.34 (owner playtest 2026-09-23: "there's a max height above which
## I can't scroll up or place blocks, there shouldn't be"). Before this fix,
## GhostTuning.hover_manual_max was 30 m, so no amount of wheeling could raise
## the held block past 30 m above the disk, and any placement request built
## from that ceiling could never carry a higher pose either.
##
## Three things this package's fix has to get right, each its own test:
## 1. The wheel must actually be able to raise the ghost past the old 30 m
##    cap (game/PlayerController.gd's _step_hover(), clamped by
##    GhostTuning.hover_manual_max).
## 2. A placement request at that height must be accepted by the host's own
##    rules (autoload/match/MatchPlacement.gd request_place()) -- not just
##    reachable on screen.
## 3. That height must still round-trip over the wire (core/net/Quantize.gd,
##    NetConfig.pos_min_y/pos_max_y) within the same tolerance every other
##    position already carries -- this package's own audit found the wire
##    band (-48..72 m) already brackets a 60 m manual cap plus
##    PhysicsTuning.hover_height (60.3 m total), so Quantize/NetConfig needed
##    no change; this test is the regression pin proving that.

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef

## The exact height the owner's playtest report named as unreachable under
## the old 30 m cap.
const TARGET_HEIGHT_M: float = 40.0
## Same tolerance test_quantize.gd's own position round-trip assertions use
## (docs/M3a_PLAN.md P2: "a position anywhere in the map-M AABB round-trips
## within 2.1 mm") -- not re-derived here, just reused for this one directed
## regression pin (this package does not own core/net/Quantize.gd or its own
## test file, since the wire range did not need to grow; see this file's own
## header DECISION).
const POSITION_TOLERANCE_M: float = 0.0021


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
	# Bontago-integ (2026-09-23 combined-run regression): before_each()'s own
	# _field is autofree()'d at the end of this test, but Match._field is a
	# plain autoload var nothing else resets (same DECISION as
	# test_jumping_bean_effect.gd:251) -- left alone, the next script in a
	# combined run that reads Match.field() without registering its own world
	# (e.g. test_throw_arc_preview.gd's PlayerController fixtures) gets a
	# freed Field and Godot's own argument type-check throws "previously
	# freed" before the callee even runs. Clear it here, not just abort the
	# match, so this script's own throwaway Field never outlives it.
	Match._field = null


func _config(player_count: int = 2) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 24680
	return config


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _wheel_up() -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP
	event.pressed = true
	return event


func _make_controller() -> PlayerController:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	return controller


# --- 1. The wheel must reach past the old 30 m cap -------------------------

func test_wheel_raises_the_ghost_past_the_old_30m_cap() -> void:
	var controller: PlayerController = _make_controller()
	assert_gt(
		controller.ghost_tuning.hover_manual_max, 30.0,
		"fixture: this package's fix must raise the configured cap itself."
	)

	var notches: int = int(ceil(TARGET_HEIGHT_M / controller.ghost_tuning.hover_wheel_step)) + 1
	for _i: int in range(notches):
		controller._unhandled_input(_wheel_up())

	assert_gte(
		controller._ghost.manual_hover_offset, TARGET_HEIGHT_M,
		"wheeling up enough notches must be able to clear 40 m -- the exact height the owner reported as stuck at 30."
	)
	assert_lte(
		controller._ghost.manual_hover_offset, controller.ghost_tuning.hover_manual_max,
		"the wheel must still respect whatever the (now higher) cap is."
	)


# --- 2. request_place at 40 m is accepted by the host's own rules -----------

func test_request_place_at_40m_is_accepted() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	var controller: PlayerController = _make_controller()
	controller.set_acting_slot(slot_id)
	controller._ghost.set_shape(Match.held_shape(slot_id))

	var home: Vector2 = Match.slot(slot_id).home_position
	var origin: Vector3 = _field.to_global(Vector3(home.x, TARGET_HEIGHT_M, home.y))

	var rejected: Array = []
	Events.placement_rejected.connect(func(rejected_slot: int, reason: StringName) -> void:
		rejected.append(reason)
	)

	var reason: StringName = Match.request_place(
		slot_id, origin, controller._ghost.orientation_index, controller._ghost.free_quaternion, false
	)

	assert_eq(reason, PlacementRules.REASON_OK, "a 40 m pose over the player's own home territory must be accepted.")
	assert_eq(_blocks_root.get_child_count(), 1, "the accepted request must actually have spawned a block.")
	assert_true(rejected.is_empty(), "no placement_rejected should fire for an accepted request.")


# --- 3. A 40 m pose still round-trips over the wire -------------------------

func test_40m_pose_round_trips_over_the_wire_within_tolerance() -> void:
	var net_config: NetConfig = load("res://config/net_config.tres")
	var map_def: MapDef = load("res://config/maps/round_medium.tres")
	var bounds: AABB = net_config.position_bounds(map_def)

	assert_lte(
		TARGET_HEIGHT_M, net_config.pos_max_y,
		"fixture/DECISION: this package's audit found NetConfig.pos_max_y (72 m) already brackets a 40 m pose " +
		"(and this package's new 60 m manual cap plus hover_height, 60.3 m total) with no change needed."
	)

	var world: Vector3 = Vector3(3.0, TARGET_HEIGHT_M, -4.0)
	var data: PackedByteArray = PackedByteArray()
	data.resize(Quantize.POSITION_BYTES)
	Quantize.pack_position(data, 0, world, bounds)
	var round_tripped: Vector3 = Quantize.unpack_position(data, 0, bounds)

	assert_almost_eq(
		round_tripped.y, TARGET_HEIGHT_M, POSITION_TOLERANCE_M,
		"a 40 m pose must still round-trip within the same tolerance every other position on the wire gets."
	)
