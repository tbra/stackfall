extends GutTest
## Regression coverage for Bontago-pt-4 ("Camera always jumps
## up after block drops or when clicking the drop button").
##
## ROOT CAUSE (full writeup on game/player/PlayerController.gd's
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
## the existing fix) but Y from _last_hit_point.y (the cursor's own surface
## hit) plus the current hover height (tuning.hover_height +
## _ghost.manual_hover_offset) -- shape-independent by construction.
## begin_follow_transition() is now only called for the one case that *is* a
## genuine, deliberate hover change: _apply_spawn_clearance()'s own raise when
## the next piece would otherwise spawn inside the block just placed.
##
## Fixture mirrors tests/unit/player/test_playercontroller_spawn_clearance.gd's own
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
	# Bontago-integ (combined-run regression, same DECISION as
	# test_playercontroller_spawn_clearance.gd's own after_each()): clears the
	# throwaway Field this file registered so a later script's Match.field()
	# read never sees a freed node.
	MatchTestReset.clear_world()


func _config(player_count: int = 2) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
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
	# spawn clearance is off by default now; these tests cover
	# the feature itself, so enable it on a private copy of the tuning.
	controller.ghost_tuning = controller.ghost_tuning.duplicate() as GhostTuning
	controller.ghost_tuning.spawn_clearance_enabled = true
	add_child_autofree(controller)
	controller._ghost = ghost
	var rig: CameraRig = autofree(load("res://game/player/CameraRig.tscn").instantiate())
	add_child_autofree(rig)
	# A rig-local tuning duplicate keeps this test from mutating the shared
	# config/player/camera_tuning.tres singleton every other test/scene reads (same
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

	# round 2: the camera is tied to the held block, so it
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

