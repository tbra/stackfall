extends GutTest
## game/player/PlayerController.gd's post-placement ghost-spawn displacement
## (requirement "when you place a block and the
## next block loads it gets displaced so it doesn't spawn directly within the
## placed block"). Before this fix, the ghost issued right after a placement
## sat exactly where the old one was released -- overlapping it.
##
## Fixture mirrors tests/unit/match/test_placement_refusal.gd's own (tiny map, real
## Field/Match, no live peer) so request_place() resolves host-inline and
## every Events signal PlayerController reacts to fires synchronously, the
## same as single-PC play.

## Per-drop frame cap for the tower to settle, and how long the dropped block
## must have rested (asleep) before the ratchet is measured.
const SETTLE_MAX_FRAMES: int = 150
const SETTLE_REST_FRAMES: int = 30

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef

## Mirrors GhostPreview's own _CORNER_SIGNS (private there) -- duplicated
## rather than reached into, the same call this file's own fixtures make for
## every other package-local geometry helper in this project.
const _CORNER_SIGNS: Array[Vector3] = [
	Vector3(-1.0, -1.0, -1.0), Vector3(1.0, -1.0, -1.0), Vector3(-1.0, 1.0, -1.0), Vector3(1.0, 1.0, -1.0),
	Vector3(-1.0, -1.0, 1.0), Vector3(1.0, -1.0, 1.0), Vector3(-1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0),
]


func before_each() -> void:
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


func after_each() -> void:
	Match.abort_match()
	Match.set_process(true)
	# Combined-run regression: before_each()'s own
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
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	# Script swap first: Object.set_script() resets script-level state to the
	# new script's declared defaults (test_match_flow.gd's own
	# _tiny_map_config() DECISION has the full story).
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.block_timer = 6.0
	config.rng_seed = 24680
	return config


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


## Advances the host's own feed tick past a full block_timer interval
## (autoload/match/MatchFeed.gd's concurrent-ticks _tick_feed()) so a slot that
## released early this same interval (_release_locked) crosses the boundary
## and may release again -- spec 1.4's "[ORIGINAL target]" cadence, which two
## back-to-back manual placements in one test would otherwise trip on their
## own (a second _place_ghost_block() call inside the same interval is
## correctly refused with REASON_NO_BLOCK, exactly as real play would refuse
## it -- this is not a bug this package's fix needs to work around, just a
## fixture concern for exercising a *second* placement at all).
func _advance_past_one_release_interval() -> void:
	var ticks: int = int(ceil((Match.config.block_timer + 0.1) * Engine.physics_ticks_per_second))
	for _i: int in range(ticks):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


func _make_controller() -> PlayerController:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	var controller: PlayerController = autofree(PlayerController.new())
	# spawn clearance is off by default now; these tests cover
	# the feature itself, so enable it on a private copy of the tuning.
	controller.ghost_tuning = controller.ghost_tuning.duplicate() as GhostTuning
	controller.ghost_tuning.spawn_clearance_enabled = true
	add_child_autofree(controller)
	controller._ghost = ghost
	return controller


## game/player/PlayerController.gd's own _process() -- not
## _on_feed_block_issued() anymore -- is what actually calls
## _apply_spawn_clearance() (see that function's own header DECISION): a
## physics query run in the same call that spawned a body cannot see that
## body yet, so the check has to wait for at least one physics step. Every
## test below that exercises the overlap path drives that same sequence by
## hand: wait a physics frame (so the space's broadphase has actually
## registered whatever was just placed), refresh the ghost's transform for
## its current cursor/shape (_process()'s own next step), then call
## _apply_spawn_clearance() directly -- exactly what _process() does, minus
## the unrelated gamepad/tint/publish steps this package doesn't touch.
func _resolve_pending_spawn_clearance(controller: PlayerController) -> void:
	await wait_physics_frames(1)
	controller._update_ghost_transform()
	controller._apply_spawn_clearance()


## The world-space AABB `shape` occupies at `transform`, built exactly the way
## game/blocks/BlockFactory.gd and game/player/GhostPreview.gd both do (same cube_size/
## cube_margin, same BlockShape.bottom_center() pivot) so this matches what
## the real spawned Block's own collision boxes -- and the ghost's own
## collision_box_local_centers()/collision_half_size() -- actually occupy.
func _shape_world_aabb(shape: BlockShape, transform: Transform3D) -> AABB:
	var tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
	var half_size: float = (tuning.cube_size - tuning.cube_margin) * 0.5
	var pivot: Vector3 = shape.bottom_center()
	var result: AABB = AABB()
	var first: bool = true
	for cell: Vector3i in shape.cells:
		var local_center: Vector3 = (Vector3(cell) - pivot) * tuning.cube_size
		for corner_sign: Vector3 in _CORNER_SIGNS:
			var world_point: Vector3 = transform * (local_center + corner_sign * half_size)
			if first:
				result = AABB(world_point, Vector3.ZERO)
				first = false
			else:
				result = result.expand(world_point)
	return result


# --- round 2: minimal raise, camera follows, no compounding ---

## Ten drops onto the same spot of a growing tower: the ghost stays about one
## hover above the tower top instead of ratcheting upward (the 69 m report).
func test_ten_drops_on_a_growing_tower_do_not_ratchet() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	var controller: PlayerController = _make_controller()
	controller.set_acting_slot(slot_id)
	var cursor: Vector3 = _home_world_position(slot_id)
	controller._cursor = cursor
	controller._ghost.set_shape(Match.held_shape(slot_id))
	controller._update_ghost_transform()
	var phys: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
	var placed_shapes: Array[BlockShape] = []
	for i: int in range(10):
		_advance_past_one_release_interval()
		placed_shapes.append(controller._ghost.get_shape())
		controller._cursor = cursor
		controller._update_ghost_transform()
		controller._place_ghost_block()
		await _resolve_pending_spawn_clearance(controller)
		assert_false(controller._ghost_overlaps_a_placed_block(), "drop %d: fresh spawn must be clear." % i)
		var rested_frames: int = 0
		for _t: int in range(SETTLE_MAX_FRAMES):
			await wait_physics_frames(1)
			rested_frames = rested_frames + 1 if (_blocks_root.get_child(i) as Block).sleeping else 0
			if rested_frames >= SETTLE_REST_FRAMES:
				break
			controller._update_ghost_transform()
			controller._decay_clearance_raise(1.0 / 60.0)
		var top_y: float = 0.0
		for index: int in range(mini(_blocks_root.get_child_count(), placed_shapes.size())):
			var body: Node3D = _blocks_root.get_child(index) as Node3D
			if body != null:
				top_y = maxf(top_y, _shape_world_aabb(placed_shapes[index], body.global_transform).end.y)
		var bottom_y: float = controller._ghost.global_position.y
		# DECISION: the bound allows one tallest shape (3 cells) of slack for
		# tumbling blocks that settle unevenly; a ratchet would blow far past it.
		assert_lt(
			bottom_y, top_y + phys.hover_height + 3.5,
			"drop %d: ghost bottom %.2f must stay near the tower top %.2f (no ratchet)." % [i, bottom_y, top_y]
		)


# --- The first piece of a match must never be pre-displaced -----------------

func _placed_controller() -> PlayerController:
	Match.start_match(_config())
	_run_countdown()
	var controller: PlayerController = _make_controller()
	controller.set_acting_slot(0)
	controller._ghost.set_shape(Match.held_shape(0))
	controller._cursor = _home_world_position(0)
	controller._update_ghost_transform()
	controller._place_ghost_block()
	await wait_physics_frames(1)
	controller._update_ghost_transform()
	return controller


func test_settle_wait_times_out_on_a_block_that_never_settles() -> void:
	var controller: PlayerController = await _placed_controller()
	var timeout: float = controller.ghost_tuning.spawn_clearance_settle_timeout_s
	var block: Block = _blocks_root.get_child(0) as Block
	assert_false(block.sleeping, "fixture: the dropped block is still awake")
	controller._apply_spawn_clearance(timeout * 0.25, true)
	assert_true(controller._pending_spawn_active, "still waiting before the timeout")
	assert_eq(controller._ghost.manual_hover_offset, 0.0, "and nothing is raised meanwhile")
	controller._apply_spawn_clearance(timeout, true)
	assert_false(controller._pending_spawn_active, "the wait ends at the timeout")
	assert_gt(controller._ghost.manual_hover_offset, 0.0, "and the ghost is raised clear of the block inside it")

