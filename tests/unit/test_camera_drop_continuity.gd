extends GutTest
## Regression coverage for Bontago-pt-4 (owner playtest: "Camera always jumps
## up after block drops or when clicking the drop button").
##
## ROOT CAUSE (full writeup on game/PlayerController.gd's
## _camera_follow_anchor()): the camera used to follow GhostPreview.
## rotated_center_world(), whose Y is global_position.y plus roughly half the
## *held shape's* own height (config/blocks/*.tres shapes range from 1 cell
## tall, e.g. cube/domino, to 3, e.g. pillar) -- so swapping shapes moved the
## followed height in a single frame even when the hover/contact height never
## changed at all (no overlap, no spawn clearance, the same cursor spot).
## Easing that jump (CameraRig.begin_follow_transition(), this bead's first
## pass) still visibly moved the camera; the actual fix is for the followed
## anchor to stop depending on the held shape's geometry in the first place.
## _camera_follow_anchor() now supplies X/Z from rotated_center_world() (so
## orbiting/pitching the block still doesn't swing the camera horizontally --
## mv0.28's own fix) but Y from _last_hit_point.y (the cursor's own surface
## hit) plus the current hover height (tuning.hover_height +
## _ghost.manual_hover_offset) -- shape-independent by construction.
## begin_follow_transition() is now only called for the one case that *is* a
## genuine, deliberate hover change: _apply_spawn_clearance()'s own raise when
## the next piece would otherwise spawn inside the block just placed.
##
## Fixture mirrors tests/unit/test_playercontroller_spawn_clearance.gd's own
## (tiny map, real Field/Match, no live peer, request_place() resolves
## host-inline) for the spawn-clearance case; the shape-swap tests below need
## neither Match nor Field (_update_ghost_transform()'s own "no physics body
## under the cursor" plane fallback handles the raycast).

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
	# Bontago-integ (2026-09-23 combined-run regression, same DECISION as
	# test_playercontroller_spawn_clearance.gd's own after_each()): clears the
	# throwaway Field this file registered so a later script's Match.field()
	# read never sees a freed node.
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


func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


func _make_controller_with_rig() -> Dictionary:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	var controller: PlayerController = autofree(PlayerController.new())
	# Bontago-1pi.4: spawn clearance is off by default now; these tests cover
	# the feature itself, so enable it on a private copy of the tuning.
	controller.ghost_tuning = controller.ghost_tuning.duplicate() as GhostTuning
	controller.ghost_tuning.spawn_clearance_enabled = true
	add_child_autofree(controller)
	controller._ghost = ghost
	var rig: CameraRig = autofree(load("res://game/CameraRig.tscn").instantiate())
	add_child_autofree(rig)
	# A rig-local tuning duplicate keeps this test from mutating the shared
	# config/camera_tuning.tres singleton every other test/scene reads (same
	# DECISION every other CameraRig test in this project makes).
	rig.tuning = rig.tuning.duplicate() as CameraTuning
	controller.set_camera_rig(rig)
	return {"controller": controller, "rig": rig}


## Same manual sequence test_playercontroller_spawn_clearance.gd's own
## _resolve_pending_spawn_clearance() uses (see that file's header comment for
## why this can't just be a plain _process()/await process_frame loop: a
## physics query run in the same call that spawned a body cannot see that
## body yet), plus this file's own camera bookkeeping.
func _place_and_resolve_clearance(controller: PlayerController, slot_id: int) -> void:
	var placed_shape: BlockShape = Match.held_shape(slot_id)
	controller._ghost.set_shape(placed_shape)
	controller._cursor = _home_world_position(slot_id)
	controller._update_ghost_transform()

	controller._place_ghost_block()
	assert_eq(_blocks_root.get_child_count(), 1, "fixture: the click must have actually spawned a block.")

	await wait_physics_frames(1)
	controller._update_ghost_transform()


func test_camera_target_y_stays_continuous_across_a_drop_that_needs_spawn_clearance() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	var built: Dictionary = _make_controller_with_rig()
	var controller: PlayerController = built["controller"]
	var rig: CameraRig = built["rig"]
	controller.set_acting_slot(slot_id)

	await _place_and_resolve_clearance(controller, slot_id)

	# Establish the camera's baseline (pre-raise) followed position and let it
	# settle there -- exactly what PlayerController._process()'s own
	# _camera_rig.set_follow_position() call and CameraRig's own _process()
	# do every ordinary frame, before this frame's _apply_spawn_clearance().
	rig.set_follow_position(controller._camera_follow_anchor())
	rig._process(1.0 / 60.0)
	var target_y_before_clearance: float = rig.get_target().y
	var pitch_before: float = rig.get_pitch()

	controller._apply_spawn_clearance()
	assert_gt(
		controller._ghost.manual_hover_offset, 0.0,
		"fixture: the piece fed right where the first block landed must need spawn clearance."
	)

	# What production does the rest of this same frame: publish the (now
	# raised) follow anchor, then let the rig react to it.
	rig.set_follow_position(controller._camera_follow_anchor())
	rig._process(1.0 / 60.0)

	# Bontago-1pi.14 round 2: the camera is tied to the held block, so it
	# eases up to the raised ghost (no permanent offset, no drift).
	var expected_y: float = controller._camera_follow_anchor().y
	assert_gt(expected_y, target_y_before_clearance + 0.01, "fixture: the followed anchor must include the raise.")
	for _i: int in range(240):
		rig.set_follow_position(controller._camera_follow_anchor())
		rig._process(1.0 / 60.0)
	assert_almost_eq(rig.get_target().y, expected_y, 0.01, "the camera must settle exactly on the raised ghost.")
	assert_almost_eq(
		rig.get_pitch(), pitch_before, 0.0001,
		"nothing in this drop should touch the camera's pitch."
	)


## Repeated drops onto clear ground (cursor moved off the falling block each
## time): no raise, so ghost height and camera follow height never change.
func test_clear_spawns_never_move_ghost_or_camera_height() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	var built: Dictionary = _make_controller_with_rig()
	var controller: PlayerController = built["controller"]
	controller.set_acting_slot(slot_id)
	var home: Vector3 = _home_world_position(slot_id)
	controller._ghost.set_shape(Match.held_shape(slot_id))
	controller._cursor = home
	controller._update_ghost_transform()
	var ghost_y: float = controller._ghost.global_position.y
	var anchor_y: float = controller._camera_follow_anchor().y
	for i: int in range(3):
		var interval: int = int(ceil((Match.config.block_timer + 0.1) * Engine.physics_ticks_per_second))
		for _t: int in range(interval):
			Match._process(1.0 / Engine.physics_ticks_per_second)
		controller._cursor = home + Vector3(float(i % 2) * 2.0, 0.0, 0.0)
		controller._update_ghost_transform()
		controller._place_ghost_block()
		controller._cursor = home + Vector3(float((i + 1) % 2) * 2.0, 0.0, 2.5)
		await wait_physics_frames(1)
		controller._update_ghost_transform()
		controller._apply_spawn_clearance()
		assert_almost_eq(controller._ghost.global_position.y, ghost_y, 0.001, "clear spawn %d must not raise the ghost." % i)
		assert_almost_eq(controller._camera_follow_anchor().y, anchor_y, 0.001, "clear spawn %d must not move the camera." % i)
		assert_almost_eq(controller._clearance_raise, 0.0, 0.0001, "clear spawn %d must not record a raise." % i)


func test_camera_hard_snaps_as_before_when_no_drop_transition_was_begun() -> void:
	# Guards the other half of the fix: ordinary continuous ghost movement
	# (never followed by begin_follow_transition()) must still track
	# instantly under the shipped follow_lag_seconds == 0 default -- this
	# change must not have quietly added lag to every frame.
	var built: Dictionary = _make_controller_with_rig()
	var rig: CameraRig = built["rig"]
	assert_almost_eq(rig.tuning.follow_lag_seconds, 0.0, 0.0001, "fixture: shipped default is a hard snap.")

	rig.set_follow_position(Vector3(0.0, 3.0, 0.0))
	rig._process(1.0 / 60.0)

	assert_almost_eq(
		rig.get_target().y, 3.0, 0.0001,
		"without begin_follow_transition(), a new follow position must still snap in a single frame."
	)


# --- Coordinator follow-up (owner: "the camera ALWAYS jumps up ... not only
# when stacking"; second follow-up: easing the jump still read as a jump) --
# the general case, no overlap or spawn clearance involved: swapping between
# shapes of very different heights (cube, 1 cell, vs. pillar, 3 cells) must
# now give (near) *zero* camera movement, since _camera_follow_anchor()'s Y no
# longer depends on the held shape's own geometry at all -- true of a
# bare-disc drop, a drop via the place action, an expiry auto-drop, or any
# other ordinary next-piece feed, all of which funnel through
# _on_turn_changed()/_on_feed_block_issued()'s own _ghost.set_shape() call.
# -----------------------------------------------------------------------------

## How close counts as "didn't move" for these assertions -- generous relative
## to the ~1 m cube-vs-pillar geometry difference these tests exercise (see
## config/blocks/cube.tres and pillar.tres), tight relative to anything a
## player could perceive as camera motion.
const _NO_MOVEMENT_TOLERANCE_M: float = 0.01


func test_camera_does_not_move_across_an_ordinary_shape_swap_with_no_overlap_or_spawn_clearance() -> void:
	var built: Dictionary = _make_controller_with_rig()
	var controller: PlayerController = built["controller"]
	var rig: CameraRig = built["rig"]
	controller.set_acting_slot(0)

	controller._ghost.set_shape(load("res://config/blocks/cube.tres"))
	controller._cursor = Vector3(0.0, 5.0, 0.0)
	controller._update_ghost_transform()
	rig.set_follow_position(controller._camera_follow_anchor())
	rig._process(1.0 / 60.0)
	var target_before: Vector3 = rig.get_target()
	var pitch_before: float = rig.get_pitch()

	# The exact handler a real host-inline feed (bare-disc drop, drop-action
	# click, or expiry auto-drop -- all resolve through Match.request_place()
	# inline, which fires Events.feed_block_issued synchronously) calls; no
	# Match/Field needed since this only exercises the set_shape() site and
	# _update_ghost_transform()'s own graceful "no physics body under the
	# cursor" plane fallback.
	controller._on_feed_block_issued(0, &"pillar", &"")
	controller._update_ghost_transform()

	# Fixture sanity: the shape swap alone must be a real, sizeable geometric
	# jump for GhostPreview's own rotated_center_world() (the old, wrong
	# follow target), or this test couldn't tell "the fix works" apart from
	# "the fixture never actually swapped shapes".
	var old_target_would_have_jumped_by: float = (
		controller._ghost.rotated_center_world().y - controller._ghost.global_position.y
	)
	assert_gt(
		absf(old_target_would_have_jumped_by), 0.0001,
		"fixture: swapping from a 1-cell shape (cube) to a 3-cell one (pillar) must actually change rotated_center_offset()."
	)

	rig.set_follow_position(controller._camera_follow_anchor())
	rig._process(1.0 / 60.0)

	assert_almost_eq(
		rig.get_target().y, target_before.y, _NO_MOVEMENT_TOLERANCE_M,
		"an ordinary shape swap -- no overlap, no spawn clearance, no hover change -- must not move the camera's followed height at all."
	)
	assert_almost_eq(
		rig.get_pitch(), pitch_before, 0.0001,
		"a shape swap alone must not touch the camera's pitch either."
	)


func test_hot_seat_turn_changed_also_does_not_move_the_camera_on_a_shape_swap() -> void:
	# game/HotSeat.gd's own turn-alternation path (Events.turn_changed, not
	# Events.feed_block_issued) is the other real call site that swaps the
	# ghost's shape -- covers the plain offline/hot-seat "next piece" case as
	# well as the networked one above.
	var built: Dictionary = _make_controller_with_rig()
	var controller: PlayerController = built["controller"]
	var rig: CameraRig = built["rig"]
	controller.set_acting_slot(0)

	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.slots_by_id = {0: PlayerSlot.new()}
	fake_match.held_shapes = {0: load("res://config/blocks/cube.tres")}
	controller._match = fake_match

	controller._ghost.set_shape(load("res://config/blocks/cube.tres"))
	controller._cursor = Vector3(0.0, 5.0, 0.0)
	controller._update_ghost_transform()
	rig.set_follow_position(controller._camera_follow_anchor())
	rig._process(1.0 / 60.0)
	var target_before: Vector3 = rig.get_target()

	fake_match.held_shapes = {0: load("res://config/blocks/pillar.tres")}
	controller._on_turn_changed(0)
	controller._update_ghost_transform()

	rig.set_follow_position(controller._camera_follow_anchor())
	rig._process(1.0 / 60.0)

	assert_almost_eq(
		rig.get_target().y, target_before.y, _NO_MOVEMENT_TOLERANCE_M,
		"Events.turn_changed's own shape swap must not move the camera either."
	)
