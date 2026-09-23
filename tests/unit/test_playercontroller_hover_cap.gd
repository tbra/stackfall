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
##
## Bontago-mv0.35 (owner regression report, 2026-09-23, "REGRESSION/UNFIXED --
## there is still a maximum height the block cannot be raised or placed
## above", reproduced hovering a domino above a placed tower): mv0.34's fix
## above raised the configured *ceiling* (GhostTuning.hover_manual_max), but
## never exercised the hover-raise path against an actual placed block. The
## real remaining bug was in game/PlayerController.gd's ghost-vs-placed-block
## collision sweep (Bontago-mv0.23) -- _cast_one_box(): the ghost's own
## baseline hover height (_update_ghost_transform(), mv0.17 item 5)
## deliberately ignores whatever tower sits under the cursor, so a ghost
## routinely starts a frame already embedded in a placed block; raising past
## it is the only way out, by design. cast_motion() called from an
## already-overlapping shape reported that motion as unsafe even when it was
## carrying the box further along its own way out, so raising above a tower
## taller than one wheel notch got stuck partway up forever, nowhere near
## hover_manual_max. Fixed by exempting a box that already overlaps a placed
## block at its own current position from that one query's block entirely
## (see _cast_one_box()'s own DECISION). test_towers_below_the_ghost_do_not_
## trap_the_hover_raise() below is this bug's regression pin: before the fix
## it failed by freezing partway up a 4-cube tower; after the fix it clears
## the tower and reaches hover_manual_max.

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
	MatchTestReset.clear_world()


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


# --- 4. A tower under the ghost must never trap the hover-raise -------------

## Reproduces the owner's exact report: a real, physics-settled 4-cube tower
## (~3.4 m tall -- taller than one GhostTuning.hover_wheel_step notch, 0.4 m)
## directly under the cursor, then a domino wheeled straight up from its own
## baseline (which starts embedded in the tower's bottom cube -- mv0.17 item
## 5's own baseline ignores the tower). Before this package's fix this froze
## partway up (observed: manual_hover_offset stuck at ~0.6 m, never reaching
## even the tower's own ~3.4 m top); after the fix it clears the tower
## entirely and reaches GhostTuning.hover_manual_max.
func test_towers_below_the_ghost_do_not_trap_the_hover_raise() -> void:
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
	var ghost_tuning: GhostTuning = GhostTuning.new()

	var blocks: Array[Block] = []
	for i: int in range(4):
		var block: Block = BlockFactory.build(load("res://config/blocks/cube.tres"), tuning)
		_field.get_parent().add_child(block)
		autofree(block)
		block.global_position = Vector3(0.0, 0.3 + float(i) * (tuning.cube_size + 0.05) + 5.0, 0.0)
		blocks.append(block)
		await wait_physics_frames(90)
	var tower_top: float = 0.0
	for block: Block in blocks:
		block.sleeping = true
		tower_top = maxf(tower_top, block.global_position.y + tuning.cube_size * 0.5)
	assert_gt(
		tower_top, ghost_tuning.hover_wheel_step,
		"fixture: the settled tower must be taller than a single wheel notch, or this test can't tell the bug apart from a normal short block."
	)

	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/domino.tres"))
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller.ghost_tuning = ghost_tuning
	controller._cursor = Vector3.ZERO
	controller._clamp_cursor_collision()
	controller._update_ghost_transform()
	assert_lt(
		controller._ghost.global_position.y, tower_top,
		"fixture: the ghost's own baseline height must start below the tower's top (ignoring the tower under it, mv0.17 item 5) for this to reproduce the bug."
	)

	var notches: int = int(ceil(ghost_tuning.hover_manual_max / ghost_tuning.hover_wheel_step)) + 5
	for _i: int in range(notches):
		var wheel: InputEventMouseButton = InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		controller._unhandled_input(wheel)
		controller._clamp_cursor_collision()
		controller._update_ghost_transform()

	assert_almost_eq(
		controller._ghost.manual_hover_offset, ghost_tuning.hover_manual_max, 0.01,
		"wheeling up enough notches must reach the real ceiling, not freeze partway up the tower underneath."
	)
	assert_gt(
		controller._ghost.global_position.y, tower_top,
		"the ghost must actually clear the tower's own top, not stay embedded somewhere inside it."
	)

	for block: Block in blocks:
		assert_true(block.sleeping, "a placed block must never wake just because the ghost swept through the space it used to ignore.")
