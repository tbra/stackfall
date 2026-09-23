extends GutTest
## game/PlayerController.gd's post-placement ghost-spawn displacement
## (Bontago-mv0.30, owner test 2026-09-23: "when you place a block and the
## next block loads it gets displaced so it doesn't spawn directly within the
## placed block"). Before this fix, the ghost issued right after a placement
## sat exactly where the old one was released -- overlapping it.
##
## Fixture mirrors tests/unit/test_placement_refusal.gd's own (tiny map, real
## Field/Match, no live peer) so request_place() resolves host-inline and
## every Events signal PlayerController reacts to fires synchronously, the
## same as single-PC play.

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
	# Script swap first: Object.set_script() resets script-level state to the
	# new script's declared defaults (test_match_flow.gd's own
	# _tiny_map_config() DECISION has the full story).
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


## Advances the host's own feed tick past a full block_timer interval
## (autoload/match/MatchFeed.gd's non-hot-seat _tick_feed()) so a slot that
## released early this same interval (_release_locked) crosses the boundary
## and may release again -- spec 2.4's "[ORIGINAL target]" cadence, which two
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
	add_child_autofree(controller)
	controller._ghost = ghost
	return controller


## Bontago-mv0.33: game/PlayerController.gd's own _process() -- not
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
## game/BlockFactory.gd/game/GhostPreview.gd both do (same cube_size/
## cube_margin, same BlockShape.bottom_center() pivot) so this matches what
## the real spawned Block's own collision boxes -- and the ghost's own
## collision_box_local_centers()/collision_half_size() -- actually occupy.
func _shape_world_aabb(shape: BlockShape, transform: Transform3D) -> AABB:
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
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


# --- The bug: the next ghost must not spawn inside the block just placed ---

func test_next_ghost_does_not_overlap_the_block_just_placed() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	var controller: PlayerController = _make_controller()
	controller.set_acting_slot(slot_id)

	var placed_shape: BlockShape = Match.held_shape(slot_id)
	controller._ghost.set_shape(placed_shape)
	controller._cursor = _home_world_position(slot_id)
	controller._update_ghost_transform()

	controller._place_ghost_block()

	assert_eq(_blocks_root.get_child_count(), 1, "fixture: the click must have actually spawned a block.")
	var placed_block: Node3D = _blocks_root.get_child(0) as Node3D
	var placed_aabb: AABB = _shape_world_aabb(placed_shape, placed_block.global_transform)

	await _resolve_pending_spawn_clearance(controller)
	var ghost_shape: BlockShape = controller._ghost.get_shape()
	assert_ne(ghost_shape, null, "fixture: the next piece must have been issued.")
	var ghost_transform: Transform3D = Transform3D(controller._ghost.basis, controller._ghost.global_position)
	var ghost_aabb: AABB = _shape_world_aabb(ghost_shape, ghost_transform)

	assert_false(
		placed_aabb.intersects(ghost_aabb),
		"the next ghost (%s) must not spawn overlapping the block just placed (%s)." % [ghost_aabb, placed_aabb]
	)
	assert_gt(
		controller._ghost.manual_hover_offset, 0.0,
		"the fix should have raised the new ghost's hover height above the placed block it actually overlaps."
	)


# --- The first piece of a match must never be pre-displaced -----------------

func test_first_piece_of_the_match_is_not_displaced() -> void:
	var controller: PlayerController = _make_controller()
	controller.set_acting_slot(0)

	Match.start_match(_config())
	_run_countdown()

	assert_ne(controller._ghost.get_shape(), null, "fixture: the match's first feed must have armed the ghost.")
	assert_almost_eq(
		controller._ghost.manual_hover_offset, 0.0, 0.0001,
		"the very first piece of a match must never be pre-displaced -- nothing was ever placed yet."
	)


# --- The displacement must not accumulate across unrelated feeds -----------

## Regression pin for the exact failure mode that would cause runaway
## accumulation: if _pending_spawn_active were never cleared (or cleared too
## late) after _apply_spawn_clearance() consumes it, every later
## feed_block_issued for the same slot -- not just the one right after a real
## placement -- would re-seed (and, with a naive `+=` implementation, keep
## growing) the hover offset from the same stale top-height reading.
func test_displacement_does_not_reapply_or_accumulate_on_an_unrelated_later_feed() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	var controller: PlayerController = _make_controller()
	controller.set_acting_slot(slot_id)
	controller._ghost.set_shape(Match.held_shape(slot_id))
	controller._cursor = _home_world_position(slot_id)
	controller._update_ghost_transform()

	controller._place_ghost_block()
	await _resolve_pending_spawn_clearance(controller)

	var offset_after_placement: float = controller._ghost.manual_hover_offset
	assert_gt(offset_after_placement, 0.0, "fixture: the placement should have displaced the next ghost.")
	assert_false(
		controller._pending_spawn_active,
		"the pending-spawn flag must be consumed the moment _apply_spawn_clearance() uses it."
	)

	# An unrelated later feed for the same slot -- not preceded by a new
	# _request_place() call -- must be a pure no-op for the hover offset.
	Events.feed_block_issued.emit(slot_id, Match.held_shape(slot_id).id, &"")
	controller._update_ghost_transform()

	assert_almost_eq(
		controller._ghost.manual_hover_offset, offset_after_placement, 0.0001,
		"a feed not preceded by a new placement must never re-apply or grow the seeded hover offset."
	)


# --- Bontago-mv0.33: unobstructed must mean untouched, not "reset toward
# zero" -- the pre-mv0.33 fix (mv0.30) recomputed manual_hover_offset from
# the just-placed block's own top on *every* feed, unconditionally, even when
# the new ghost's cursor was nowhere near that block. The owner's playtest
# report ("should only happen when the block would spawn inside another
# block, not all the time") is exactly this: an unobstructed next spot must
# leave whatever manual_hover_offset the ghost already carried completely
# alone, not quietly recompute it toward some other value. -----------------

func test_offset_is_left_untouched_when_the_new_ghost_does_not_overlap_anything() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	var controller: PlayerController = _make_controller()
	controller.set_acting_slot(slot_id)
	controller._ghost.set_shape(Match.held_shape(slot_id))
	controller._cursor = _home_world_position(slot_id)
	controller._update_ghost_transform()

	# One real placement, so a real placed block exists on the disk and
	# _pending_spawn_top_y below reflects a real, freshly-captured value --
	# not a hand-picked number this test invented.
	controller._place_ghost_block()
	await _resolve_pending_spawn_clearance(controller)
	assert_gt(
		controller._ghost.manual_hover_offset, 0.0,
		"fixture: the piece fed right where the first block landed should have been displaced (this is the overlap case, covered by its own test above)."
	)

	# An arbitrary value distinct from both 0.0 and whatever the overlap case
	# above just computed, so this test can tell "untouched" apart from either
	# "reset to 0" (the old, wrong behaviour the owner reported) or
	# "recomputed to the same thing the overlap case gets" by coincidence.
	const ARBITRARY_OFFSET: float = 7.25
	controller._ghost.manual_hover_offset = ARBITRARY_OFFSET

	# Move to a spot with nothing anywhere near it -- still inside slot 0's own
	# home circle (home_radius = 6.0m, config/territory_tuning.tres) so a real
	# placement there would stay valid, and far enough from the one existing
	# block (well under 1m across) that a cube-sized ghost cannot reach it.
	var away: Vector2 = Match.slot(slot_id).home_position + Vector2(4.0, 0.0)
	controller._cursor = _field.to_global(Vector3(away.x, 5.0, away.y))
	controller._update_ghost_transform()

	# Simulate the bookkeeping a second real _request_place() call would have
	# set for the *next* piece, without actually performing one: a genuine
	# second click at `away` would itself place a new block exactly there,
	# which would immediately re-create the overlap case for the *third*
	# piece (this project's own ghost always spawns centered on whatever
	# cursor placed the previous piece) -- that would test the overlap path a
	# second time, not the no-overlap path this test is about. Driving
	# _apply_spawn_clearance()'s own preconditions directly isolates its
	# overlap decision from that mechanics.
	controller._pending_spawn_active = true
	controller._pending_spawn_top_y = controller._ghost.projection_span_y().x
	await _resolve_pending_spawn_clearance(controller)

	assert_almost_eq(
		controller._ghost.manual_hover_offset, ARBITRARY_OFFSET, 0.0001,
		"a ghost that would not overlap anything at its baseline hover height must be left exactly where it was -- not reset, not recomputed."
	)
