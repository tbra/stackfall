extends GutTest
## game/CameraRig.gd's own coverage (previously only exercised indirectly
## through test_playercontroller_mouse.gd's follow-block tests).
##
## Bontago-mv0.17 item 4 (owner feel report: "on match start the follow
## camera's yaw must look from the player's home flag toward the disk
## centre"): CameraRig.set_home_view() is what PlayerController.
## set_home_position() calls once a controller binds to a real slot
## (game/HotSeat.gd's bind_local_slot(), game/Sandbox.gd's own turn-changed
## handler) — see those files' own DECISION comments for who calls this and
## why.


func _make_rig() -> CameraRig:
	var rig: CameraRig = load("res://game/CameraRig.tscn").instantiate()
	add_child_autofree(rig)
	return rig


## Bontago-b7r (owner decision 2026-09-28, Bontago-aem): camera_snap_goal no
## longer shares gamepad B with rotate_snap at all (moved to X; see
## tools/bootstrap_project.gd) -- so a bare JOY_BUTTON_B press must never
## reach camera_snap_home/goal, regardless of block_held. The tap-to-TURN/
## hold-to-PEEK gesture that replaced this file's old instant _snap_to() test
## for camera_snap_home/goal now lives in tests/unit/test_camera_focus.gd,
## alongside the X-chord gating (Start+X, Back+X) that made camera_snap_goal's
## move onto X safe.
func test_b_never_reaches_camera_snap_home_or_goal_regardless_of_block_held() -> void:
	var rig: CameraRig = _make_rig()
	var yaw_before: float = rig.get_yaw()
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_B
	event.pressed = true

	rig.block_held = true
	rig._unhandled_input(event)
	assert_false(rig.is_peeking())
	assert_almost_eq(rig.get_yaw(), yaw_before, 0.0001)

	rig.block_held = false
	rig._unhandled_input(event)
	assert_false(rig.is_peeking())
	assert_almost_eq(rig.get_yaw(), yaw_before, 0.0001)


func test_rig_and_camera_have_physics_interpolation_off() -> void:
	# Bontago-1bt (owner log: "Interpolated Camera3D triggered from outside
	# physics process" x4 per 60s bot run): this rig writes both its own
	# global_position and its Camera3D child's transform every rendered
	# _process() frame (never _physics_process), the same pattern
	# the removed DiscMirror's own mirror camera already had fixed -- see
	# test_disc_mirror.gd's test_mirror_camera_has_physics_interpolation_off()
	# and this rig's own _ready() doc comment.
	var rig: CameraRig = _make_rig()

	assert_eq(rig.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_OFF)
	assert_eq(rig.get_camera().physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_OFF)


func test_set_home_view_points_the_rig_from_home_toward_the_center() -> void:
	var rig: CameraRig = _make_rig()

	var home: Vector3 = Vector3(0.0, 0.0, 20.0)
	rig.set_home_view(home)

	var expected_yaw: float = atan2(home.x, home.z)
	assert_almost_eq(rig.get_yaw(), expected_yaw, 0.001)
	assert_almost_eq(rig.get_target().x, home.x, 0.001)
	assert_almost_eq(rig.get_target().z, home.z, 0.001)


func test_set_home_view_camera_looks_toward_the_center_not_away_from_it() -> void:
	var rig: CameraRig = _make_rig()

	# A home flag out on the +X rim; the centre (the default look_at_position)
	# is the world origin.
	rig.set_home_view(Vector3(20.0, 0.0, 0.0))

	var camera: Camera3D = rig.get_camera()
	var facing: Vector3 = -camera.global_transform.basis.z  # Camera3D looks down its own -Z.
	assert_lt(facing.x, 0.0, "from a home flag on the +X rim, the camera should face back toward the centre (-X), not out toward the rim.")


func test_set_home_view_seeds_the_follow_position_so_there_is_no_snap_back() -> void:
	var rig: CameraRig = _make_rig()
	assert_true(rig.tuning.follow_block, "fixture: follow_block defaults to true.")

	var home: Vector3 = Vector3(-8.0, 0.0, 3.0)
	rig.set_home_view(home)
	# Bontago-mv0.17: set_home_view() also seeds _follow_position, so a single
	# _process() tick right after binding does not visibly pull the target
	# away from home_position before PlayerController's own
	# set_follow_position() call this same frame arrives.
	rig._process(1.0 / 60.0)

	assert_almost_eq(rig.get_target().x, home.x, 0.01)
	assert_almost_eq(rig.get_target().z, home.z, 0.01)


func test_set_home_view_with_a_home_position_already_at_the_center_keeps_the_previous_yaw() -> void:
	var rig: CameraRig = _make_rig()
	rig.set_home_view(Vector3(15.0, 0.0, 0.0))
	var yaw_before: float = rig.get_yaw()

	# A degenerate "home == centre" input must not divide by a zero-length
	# direction; the yaw should simply stay put.
	rig.set_home_view(Vector3.ZERO)

	assert_almost_eq(rig.get_yaw(), yaw_before, 0.001)


# --- Bontago-pt-4 (owner playtest: "Camera always jumps up after block drops
# or when clicking the drop button") -- begin_follow_transition() -----------


func test_begin_follow_transition_eases_a_jump_instead_of_hard_snapping() -> void:
	var rig: CameraRig = _make_rig()
	rig.tuning = rig.tuning.duplicate() as CameraTuning
	assert_almost_eq(rig.tuning.follow_lag_seconds, 0.0, 0.0001, "fixture: shipped default is a hard snap.")

	rig.set_home_view(Vector3(0.0, 0.0, 10.0))
	rig._process(1.0 / 60.0)
	var target_y_before: float = rig.get_target().y

	rig.begin_follow_transition()
	rig.set_follow_position(Vector3(0.0, 5.0, 10.0))
	rig._process(1.0 / 60.0)

	var one_frame_delta: float = rig.get_target().y - target_y_before
	assert_gt(one_frame_delta, 0.0, "the rig must still move toward the new height, just not all at once.")
	assert_lt(one_frame_delta, 2.5, "a single frame must ease into the jump, not cover the whole 5m in one step.")

	for _i: int in range(120):
		rig._process(1.0 / 60.0)
	assert_almost_eq(rig.get_target().y, 5.0, 0.01, "it must still fully converge, just not instantly.")


func test_begin_follow_transition_does_not_affect_ordinary_movement_once_converged() -> void:
	var rig: CameraRig = _make_rig()
	rig.tuning = rig.tuning.duplicate() as CameraTuning

	rig.begin_follow_transition()
	rig.set_follow_position(Vector3(1.0, 0.0, 0.0))
	for _i: int in range(120):
		rig._process(1.0 / 60.0)
	assert_almost_eq(rig.get_target().x, 1.0, 0.01, "fixture: the transition must have converged and cleared itself.")

	# A brand new, ordinary follow_position update (no begin_follow_transition()
	# call for it) must hard-snap exactly as before -- the eased state must not
	# leak into unrelated later frames.
	rig.set_follow_position(Vector3(9.0, 0.0, 0.0))
	rig._process(1.0 / 60.0)
	assert_almost_eq(rig.get_target().x, 9.0, 0.0001, "an ordinary update after convergence must still be a hard snap.")


# --- Bontago-mv0.20b: apply_follow_tuning() (F4 tuning panel live-apply) -----


func test_apply_follow_tuning_reapplies_distance_and_pitch_clamped() -> void:
	var rig: CameraRig = _make_rig()
	# A rig-local duplicate keeps this test from mutating the shared
	# config/camera_tuning.tres singleton every other test/scene reads.
	rig.tuning = rig.tuning.duplicate() as CameraTuning
	assert_true(rig.tuning.follow_block, "fixture: follow_block defaults to true.")

	rig.tuning.follow_distance = rig.tuning.zoom_max + 50.0  # out of range, must clamp.
	rig.tuning.follow_pitch_deg = -50.0

	rig.apply_follow_tuning()

	assert_almost_eq(rig.get_distance(), rig.tuning.zoom_max, 0.001, "clamped to zoom_max, same as _ready().")
	assert_almost_eq(rig.get_pitch(), deg_to_rad(-50.0), 0.001)


# --- Bontago-mv0.22: zoom_by_orbit_step (spec 2.5 "Camera orbit (hold + drag)
# ... mouse wheel zooms while held" [ORIGINAL, owner test 2026-09-22]) -------


func test_zoom_by_orbit_step_changes_distance_by_the_tuned_step_clamped() -> void:
	var rig: CameraRig = _make_rig()
	rig.tuning = rig.tuning.duplicate() as CameraTuning
	var start_distance: float = rig.get_distance()

	rig.zoom_by_orbit_step(-1.0)

	assert_almost_eq(
		rig.get_distance(), start_distance - rig.tuning.orbit_zoom_step, 0.001,
		"negative direction should zoom in by exactly orbit_zoom_step."
	)

	rig.tuning.orbit_zoom_step = rig.tuning.zoom_max * 2.0
	rig.zoom_by_orbit_step(1.0)

	assert_almost_eq(rig.get_distance(), rig.tuning.zoom_max, 0.001, "zoom_by_orbit_step must clamp to zoom_max.")


# --- Bontago-mv0.27 (owner: "is there a fish-eye effect? add a slider") -----


func test_fov_deg_default_is_a_sane_lens_and_a_fresh_rig_uses_it() -> void:
	var tuning: CameraTuning = CameraTuning.new()
	assert_gt(tuning.fov_deg, 0.0)
	assert_lt(tuning.fov_deg, 180.0)
	var rig: CameraRig = _make_rig()
	assert_almost_eq(rig.get_camera().fov, rig.tuning.fov_deg, 0.001, "the built camera takes its fov from the tuning")


func test_apply_follow_tuning_pushes_fov_deg_to_the_camera_live() -> void:
	var rig: CameraRig = _make_rig()
	rig.tuning = rig.tuning.duplicate() as CameraTuning

	rig.tuning.fov_deg = 95.0
	rig.apply_follow_tuning()

	assert_almost_eq(rig.get_camera().fov, 95.0, 0.001)


func test_apply_follow_tuning_pushes_fov_deg_even_when_not_following_the_block() -> void:
	var rig: CameraRig = _make_rig()
	rig.tuning = rig.tuning.duplicate() as CameraTuning
	rig.tuning.follow_block = false

	rig.tuning.fov_deg = 55.0
	rig.apply_follow_tuning()

	assert_almost_eq(rig.get_camera().fov, 55.0, 0.001, "fov isn't a follow-only concept; it must update even in free-orbit mode.")


# --- Bontago-mv0.26 (owner test 2026-09-22: "the ghost block is a bit
# jittery when I'm moving around and especially when scrolling") -- process-
# order regression: CameraRig used to _process() before PlayerController every
# frame (it is a static game/Main.tscn child, added before HotSeat, whose
# PlayerController is add_child()'d at runtime -- see this rig's own
# _PROCESS_PRIORITY_AFTER_GHOST doc comment for the full root-cause writeup),
# so _target always reflected last frame's ghost position. Mirrors that same
# tree shape (rig added first, controller/ghost added after) and lets the real
# SceneTree dispatch _process() itself -- process_priority, not call order in
# this test, is what must keep them in sync. -------------------------------

func _make_ghost_with_shape() -> GhostPreview:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	return ghost


func test_camera_target_matches_the_ghost_position_the_same_frame_it_moves() -> void:
	# Same order as game/Main.tscn/game/HotSeat.tscn: the rig exists first,
	# the controller (and its ghost) are added afterward.
	var rig: CameraRig = _make_rig()
	var ghost: GhostPreview = _make_ghost_with_shape()
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller.set_camera_rig(rig)
	# DECISION (tests/unit/test_camera_rig.gd): a rig-local tuning duplicate
	# with ghost_collision disabled -- this test is isolating the CameraRig/
	# PlayerController process-order question only. Bontago-mv0.23's swept
	# collision test (_clamp_cursor_collision()) queries the live
	# PhysicsDirectSpaceState3D every _process(), which only reflects whatever
	# the physics server has actually stepped so far; with no Field/physics
	# ticks driving this bare test tree, that lags render frames unevenly and
	# introduces its own frame-to-frame variance unrelated to the camera bug
	# under test here (see test_ghost_collision.gd for that feature's own
	# coverage).
	controller.ghost_tuning = controller.ghost_tuning.duplicate() as GhostTuning
	controller.ghost_tuning.ghost_collision_enabled = false

	# A newly add_child()'d node's first _process() call can land one
	# process_frame signal later than the frame it was actually added on
	# (Godot's own scheduling, nothing to do with this bug) -- let that
	# one-time startup transient pass before the constant-motion loop below,
	# so it measures steady-state behaviour, not this test fixture's own
	# warm-up frame.
	await get_tree().process_frame
	await get_tree().process_frame

	var previous_ghost_x: float = ghost.global_position.x
	var previous_displacement: float = 0.0
	for i: int in range(60):
		# A fixed per-iteration cursor step, independent of the real engine's
		# (possibly uneven, headless) frame delta -- isolates "does the camera
		# see the same frame's ghost position" from unrelated frame-timing
		# noise, and gives a displacement that can only be non-constant if
		# something in the ghost/camera pipeline itself introduces variance.
		controller._cursor += Vector3(0.1, 0.0, 0.0)
		await get_tree().process_frame

		var displacement: float = ghost.global_position.x - previous_ghost_x
		if i > 0:
			assert_almost_eq(
				displacement, previous_displacement, 0.0001,
				"frame %d: the ghost's per-frame displacement must stay constant under constant input." % i
			)
		previous_ghost_x = ghost.global_position.x
		previous_displacement = displacement

		assert_almost_eq(
			rig.get_target().x, ghost.global_position.x, 0.0001,
			"frame %d: the camera target must equal the ghost position from this same frame, not one frame stale." % i
		)


func test_apply_follow_tuning_is_a_noop_when_not_following_the_block() -> void:
	var rig: CameraRig = _make_rig()
	rig.tuning = rig.tuning.duplicate() as CameraTuning
	rig.tuning.follow_block = false
	var distance_before: float = rig.get_distance()
	var pitch_before: float = rig.get_pitch()

	rig.tuning.follow_distance = 5.0
	rig.tuning.follow_pitch_deg = -10.0
	rig.apply_follow_tuning()

	assert_almost_eq(
		rig.get_distance(), distance_before, 0.0001,
		"the free-orbit camera must not be reset by a follow-only tuning push."
	)
	assert_almost_eq(rig.get_pitch(), pitch_before, 0.0001)


# --- Bontago-mv0.29 (owner: "the mmb rotation issue persists, can the camera
# just be locked in place while mmb is pressed?" -- feedback/rotation-issue.png)
# -----------------------------------------------------------------------------


func _motion(relative: Vector2) -> InputEventMouseMotion:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.relative = relative
	return event


func test_process_freezes_target_yaw_pitch_and_distance_while_rotate_drag_is_held() -> void:
	var rig: CameraRig = _make_rig()
	rig.tuning = rig.tuning.duplicate() as CameraTuning
	rig.set_home_view(Vector3(5.0, 0.0, 10.0))
	rig._process(1.0 / 60.0)

	var target_before: Vector3 = rig.get_target()
	var yaw_before: float = rig.get_yaw()
	var pitch_before: float = rig.get_pitch()
	var distance_before: float = rig.get_distance()
	var transform_before: Transform3D = rig.get_camera().global_transform

	Input.action_press(&"rotate_drag")
	# A moving follow target -- the ghost's rotated centre sliding during the
	# drag, mv0.28's own regression -- must not move the camera while frozen,
	# and neither should the gamepad's always-on right-stick orbit strength
	# left at zero here (asserted separately by the RMB+MMB test below).
	for i: int in range(5):
		rig.set_follow_position(Vector3(5.0 + float(i), 1.0, 10.0 - float(i)))
		rig._process(1.0 / 60.0)
		assert_true(
			rig.get_target().is_equal_approx(target_before),
			"frame %d: target must not move while rotate_drag is held." % i
		)
	Input.action_release(&"rotate_drag")

	assert_almost_eq(rig.get_yaw(), yaw_before, 0.0001, "yaw must be untouched by the frozen frames.")
	assert_almost_eq(rig.get_pitch(), pitch_before, 0.0001, "pitch must be untouched by the frozen frames.")
	assert_almost_eq(rig.get_distance(), distance_before, 0.0001, "distance must be untouched by the frozen frames.")
	assert_true(
		rig.get_camera().global_transform.is_equal_approx(transform_before),
		"global_transform must be bit-for-bit unchanged for the whole drag."
	)

	# MMB release -> follows again (follow_lag_seconds == 0 here, an instant
	# snap to the latest set_follow_position(), same as any other frame).
	rig._process(1.0 / 60.0)
	assert_true(
		rig.get_target().is_equal_approx(Vector3(9.0, 1.0, 6.0)),
		"after release, the rig must resume following the latest follow position."
	)


func test_unhandled_input_ignores_camera_orbit_motion_while_rotate_drag_is_held() -> void:
	# DECISION (game/CameraRig.gd, _rotate_drag_frozen()): rotate_drag (MMB)
	# always wins over camera_orbit (RMB) when both are held at once.
	var rig: CameraRig = _make_rig()
	var yaw_before: float = rig.get_yaw()
	var pitch_before: float = rig.get_pitch()

	Input.action_press(&"rotate_drag")
	Input.action_press(&"camera_orbit")
	rig._unhandled_input(_motion(Vector2(120.0, 40.0)))
	Input.action_release(&"camera_orbit")
	Input.action_release(&"rotate_drag")

	assert_almost_eq(rig.get_yaw(), yaw_before, 0.0001, "rotate_drag must freeze yaw even with camera_orbit also held.")
	assert_almost_eq(rig.get_pitch(), pitch_before, 0.0001, "rotate_drag must freeze pitch even with camera_orbit also held.")


func test_zoom_by_orbit_step_is_a_noop_while_rotate_drag_is_held() -> void:
	var rig: CameraRig = _make_rig()
	var distance_before: float = rig.get_distance()

	Input.action_press(&"rotate_drag")
	rig.zoom_by_orbit_step(-1.0)
	Input.action_release(&"rotate_drag")

	assert_almost_eq(
		rig.get_distance(), distance_before, 0.0001,
		"PlayerController calls zoom_by_orbit_step() directly (bypassing this rig's own _unhandled_input), so it needs its own freeze guard."
	)


## Bontago-1pi.85.39: LT (camera_zoom_modifier) no longer throws, so holding it
## must not block the right-stick orbit (spec 2.5: LT + left stick zooms only).
func test_process_orbits_with_gamepad_right_stick_while_lt_zoom_modifier_is_held() -> void:
	var rig: CameraRig = _make_rig()
	var yaw_before: float = rig.get_yaw()

	Input.action_press(&"camera_zoom_modifier")
	Input.action_press(&"camera_look_right")
	rig._process(1.0 / 60.0)

	assert_ne(rig.get_yaw(), yaw_before, "LT held must not suppress the right-stick orbit.")

	Input.action_release(&"camera_zoom_modifier")
	Input.action_release(&"camera_look_right")
