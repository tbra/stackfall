extends GutTest
## game/BotController.gd's cadence/gating state machine (docs/M5_PLAN.md P1):
## the reaction-delay countdown, the release-lock/held-shape gates, the host
## gate, and the per-bot seeded jitter that staggers multiple bots' first
## think-tick across different physics frames.
##
## Local fakes rather than tests/unit/support/FakeMatch.gd -- that shared
## double only ever answered game/PlayerController.gd's/ui/HUD.gd's narrower
## contract (no raster()/cell_grid()/team_of()/slot_count()), and this
## package does not own it. Mirrors its own established shape (a Variant
## seam, a call-log array) instead of extending someone else's file.

const CUBE_SHAPE: BlockShape = preload("res://config/blocks/cube.tres")
const PILLAR_SHAPE: BlockShape = preload("res://config/blocks/pillar.tres")

## Small enough that a bare Field (no colliders at all) still answers
## get_world_3d()/map_def-driven raycasts without a real match world --
## test_playercontroller_mouse.gd's own _make_field_for_controller() pattern.
class BotControllerFakeMatch:
	var config: MatchConfig = null
	var state_value: int = MatchAutoload.State.PLAYING
	var slots_by_id: Dictionary = {}
	var held_shapes: Dictionary = {}
	var held_specials: Dictionary = {}
	var release_locked: Dictionary = {}
	var feed_seqs: Dictionary = {}
	var team_by_slot: Dictionary = {}
	var slot_count_value: int = 1
	var raster_value: TerritoryRaster = null
	var cell_grid_value: CellGrid = null
	## Bontago-d5c.10 (item F): Match.circle_render_arrays()'s own shape
	## (parallel xs/zs/teams, disk-local) -- empty by default, so every
	## existing fixture that never sets this still gets the pre-existing
	## home-flags-only behaviour of _enemy_circle_centers().
	var circle_arrays_value: Dictionary = {
		"xs": PackedFloat32Array(),
		"zs": PackedFloat32Array(),
		"radii": PackedFloat32Array(),
		"teams": PackedInt32Array(),
	}

	var request_place_calls: Array[Dictionary] = []
	var request_throw_calls: Array[Dictionary] = []
	## Bontago-d5c.2 (review fix regression): lets a test make every
	## request_place()/request_throw() come back rejected, the same shape a
	## real MatchPlacement/ThrowRules refusal returns (any StringName other
	## than PlacementRules.REASON_OK).
	var next_request_reason: StringName = PlacementRules.REASON_OK

	func state() -> int:
		return state_value

	func slot(slot_id: int) -> PlayerSlot:
		return slots_by_id.get(slot_id) as PlayerSlot

	func held_shape(slot_id: int) -> BlockShape:
		return held_shapes.get(slot_id) as BlockShape

	func held_special(slot_id: int) -> StringName:
		return held_specials.get(slot_id, &"") as StringName

	func is_release_locked(slot_id: int) -> bool:
		return bool(release_locked.get(slot_id, false))

	func feed_seq(slot_id: int) -> int:
		return int(feed_seqs.get(slot_id, 0))

	func team_of(slot_id: int) -> int:
		return int(team_by_slot.get(slot_id, slot_id))

	func slot_count() -> int:
		return slot_count_value

	func raster() -> TerritoryRaster:
		return raster_value

	func cell_grid() -> CellGrid:
		return cell_grid_value

	func circle_render_arrays() -> Dictionary:
		return circle_arrays_value

	func request_place(
		slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion, auto_drop: bool, feed_seq_arg: int = -1
	) -> StringName:
		request_place_calls.append({
			"slot_id": slot_id, "origin": origin, "orientation_index": orientation_index,
			"free_quat": free_quat, "auto_drop": auto_drop, "feed_seq": feed_seq_arg,
		})
		return next_request_reason

	func request_throw(
		slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion, velocity: Vector3, feed_seq_arg: int = -1
	) -> StringName:
		request_throw_calls.append({
			"slot_id": slot_id, "origin": origin, "orientation_index": orientation_index,
			"free_quat": free_quat, "velocity": velocity, "feed_seq": feed_seq_arg,
		})
		return next_request_reason


class BotControllerFakeNet:
	var is_host_value: bool = true

	func is_host() -> bool:
		return is_host_value


## Bontago-d5c.2 (review fix regression, MAJOR): forces both the pre-noise
## candidate origin (_sample_territory_point()) and the aim-noise offset
## (_aim_noise_offset()) to fixed values so a test can prove
## _send_best_placement() samples support height at the *noisy* point, not
## the pre-noise one, without depending on the seeded RNG's own draw order
## (GDScript inner classes may extend a global class_name; both overridden
## methods are ordinary, non-virtual functions on BotController).
class BotControllerForcedNoise:
	extends BotController
	var forced_origin: Vector2 = Vector2.ZERO
	var forced_noise: Vector2 = Vector2.ZERO

	func _sample_territory_point(_team_id: int) -> Vector2:
		return forced_origin

	func _aim_noise_offset() -> Vector2:
		return forced_noise


## Bontago-d5c.11 item 1 regression: canned raycast results keyed by the
## disk-local point _raycast_support_height() would be asked for, so a test
## can force one footprint corner to be a genuine miss (a hole) while a
## sibling corner reports the identical fallback height as a real hit,
## without needing a physics world or Field-level hole punching -- the
## brief's own fallback ("If a real physics raycast is impractical in the
## unit test, test the counting logic through the dictionary contract").
class BotControllerForcedRaycasts:
	extends BotController
	var canned: Dictionary = {}

	func _raycast_support_height(local_xz: Vector2) -> Dictionary:
		return canned.get(local_xz, {"height": 0.0, "collider": null, "hit": false})


## Bontago-d5c.10 (item C): writes a known, fixed rotation onto a Field's own
## transform from inside a physics tick, then goes idle -- the memory'd
## convention for a Field write (game/Field.gd's own DECISION on
## sync_to_physics/AnimatableBody3D: a plain node keeps sync_to_physics false,
## per `set_tilt_enabled()`'s own comment, so a direct write outside physics
## already sticks here too, but writing it inside _physics_process and
## awaiting a frame is the same safe pattern every other Field-transform test
## in this codebase uses, and keeps this test valid even if Field's own
## defaults ever change). One-shot: the rotation is applied exactly once.
class BotControllerFieldTiltWriter:
	extends Node
	var field: Field = null
	var basis_to_apply: Basis = Basis.IDENTITY
	var applied: bool = false

	func _physics_process(_delta: float) -> void:
		if applied or field == null:
			return
		field.transform = Transform3D(basis_to_apply, field.transform.origin)
		applied = true


func _small_map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_bot_disk"
	map_def.field_radius = 10.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 16
	return map_def


func _make_field() -> Field:
	var field: Field = Field.new()
	field.map_def = _small_map()
	add_child_autofree(field)
	return field


## A static box collider under `field`'s own physics world, top surface at
## `at.y + size * 0.5` (world Y, since a fresh Field's own transform is
## identity -- Field.to_local()/world_from_disk_local() are then a straight
## pass-through) -- test_field_raycast.gd's own _make_cube() pattern, a
## StaticBody3D instead of a RigidBody3D so no settle time is needed before
## the raycast is stable.
func _make_platform(field: Field, at: Vector3, size: float) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3.ONE * size
	collision.shape = box
	body.add_child(collision)
	field.get_parent().add_child(body)
	autofree(body)
	body.global_position = at
	return body


func _make_config() -> MatchConfig:
	var config: MatchConfig = MatchConfig.new()
	config.rng_seed = 777
	config.goal_flag_count = 1
	config.map_size = MapDef.MapSize.SMALL
	return config


## Fully wired fake: slot 0 holds a cube, unlocked, no special, own team --
## everything a think-cycle needs to complete and fire exactly one
## request_place().
func _make_ready_match(slot_id: int) -> BotControllerFakeMatch:
	var fake: BotControllerFakeMatch = BotControllerFakeMatch.new()
	fake.config = _make_config()
	fake.slot_count_value = 2
	var slot: PlayerSlot = PlayerSlot.new(slot_id, slot_id, "Bot %d" % slot_id, Color.WHITE, Vector2(1.0, 0.0))
	fake.slots_by_id[slot_id] = slot
	fake.team_by_slot[slot_id] = slot_id
	fake.held_shapes[slot_id] = CUBE_SHAPE
	fake.release_locked[slot_id] = false
	return fake


func _make_controller(field: Field, match_ref: BotControllerFakeMatch, net_ref: BotControllerFakeNet) -> BotController:
	var controller: BotController = BotController.new()
	add_child_autofree(controller)
	controller.set_match_provider(match_ref)
	controller.set_net_provider(net_ref)
	return controller


## Ticks `frames` physics frames of 1/60s each.
func _tick(controller: BotController, frames: int) -> void:
	for _i: int in range(frames):
		controller._physics_process(1.0 / 60.0)


func test_sends_exactly_one_request_place_after_the_reaction_delay() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)

	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	Events.feed_block_issued.emit(0, &"cube", &"")

	# Worst case per BotDifficultyProfile.normal's own tunables (reaction_delay_s
	# 0.6 + up to think_phase_jitter_s 0.4 = 1.0s = 60 frames) plus
	# ceil(candidate_count 70 / candidates_per_frame 8) = 9 GENERATING frames
	# plus 1 ACTING frame = 70 frames worst case; 72 leaves a two-frame margin
	# that still lands well short of a second full cycle (which needs >= 10
	# more).
	_tick(controller, 72)

	assert_eq(match_ref.request_place_calls.size(), 1, "exactly one placement request after one full think-cycle")
	assert_eq(int(match_ref.request_place_calls[0]["slot_id"]), 0)


func test_sends_nothing_while_release_locked() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	match_ref.release_locked[0] = true
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)

	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	Events.feed_block_issued.emit(0, &"cube", &"")
	_tick(controller, 72)

	assert_eq(match_ref.request_place_calls.size(), 0, "a release-locked slot never sends a placement request")
	assert_eq(match_ref.request_throw_calls.size(), 0)


func test_sends_nothing_with_no_held_shape() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	match_ref.held_shapes.erase(0)
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)

	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	Events.feed_block_issued.emit(0, &"cube", &"")
	_tick(controller, 72)

	assert_eq(match_ref.request_place_calls.size(), 0, "nothing to place with no held shape")


func test_non_host_is_a_no_op_every_frame() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	net_ref.is_host_value = false
	var controller: BotController = _make_controller(field, match_ref, net_ref)

	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	Events.feed_block_issued.emit(0, &"cube", &"")
	_tick(controller, 72)

	assert_eq(match_ref.request_place_calls.size(), 0, "a non-host controller never sends anything")


## docs/M5_PLAN.md P1: "two BotControllers with different think_phase_jitter_s
## draws never fire their first think-tick on the identical physics frame --
## deterministic with a fixed seed." Each controller has its own FakeMatch
## (matching its own slot_id's seeded stride) so their countdowns run
## independently; the frame each first leaves IDLE (drawn once at setup(),
## seeded off the shared config.rng_seed + a per-slot stride) is asserted to
## differ.
func test_two_bots_with_different_jitter_draws_never_start_generating_on_the_same_frame() -> void:
	var field_a: Field = _make_field()
	var field_b: Field = _make_field()
	var match_a: BotControllerFakeMatch = _make_ready_match(0)
	var match_b: BotControllerFakeMatch = _make_ready_match(1)
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var bot_a: BotController = _make_controller(field_a, match_a, net_ref)
	var bot_b: BotController = _make_controller(field_b, match_b, net_ref)

	bot_a.setup(0, MatchConfig.AiDifficulty.NORMAL, field_a, null)
	bot_b.setup(1, MatchConfig.AiDifficulty.NORMAL, field_b, null)
	Events.feed_block_issued.emit(0, &"cube", &"")
	Events.feed_block_issued.emit(1, &"cube", &"")

	var frame_a: int = -1
	var frame_b: int = -1
	for frame: int in range(120):
		bot_a._physics_process(1.0 / 60.0)
		bot_b._physics_process(1.0 / 60.0)
		if frame_a < 0 and bot_a._state != BotController.State.IDLE:
			frame_a = frame
		if frame_b < 0 and bot_b._state != BotController.State.IDLE:
			frame_b = frame
		if frame_a >= 0 and frame_b >= 0:
			break

	assert_true(frame_a >= 0, "fixture: bot A eventually starts thinking")
	assert_true(frame_b >= 0, "fixture: bot B eventually starts thinking")
	assert_ne(frame_a, frame_b, "different per-slot jitter draws land on different frames")


## Bontago-d5c.2 (review fix regression, MAJOR): best.support_height was
## sampled at the pre-noise origin -- the aim-noise offset can legitimately
## move the request onto a different collider's surface. Two platforms sit
## under two known disk-local points: a low one under the forced pre-noise
## origin (0, 0), top at world Y 1.0, and a taller one under the forced
## noisy point (3, 0), top at world Y 2.5. If the bug were still present the
## request would quote Y 1.0 (the pre-noise sample); the fix must quote Y 2.5
## (a fresh raycast at the actual noisy point).
func test_send_best_placement_resamples_support_height_at_the_noisy_origin() -> void:
	var field: Field = _make_field()
	_make_platform(field, Vector3(0.0, 0.5, 0.0), 1.0)
	_make_platform(field, Vector3(3.0, 2.0, 0.0), 1.0)
	# test_field_raycast.gd's own precedent: a freshly added StaticBody3D's
	# collision shape is only committed to the physics server on the next
	# real physics frame, and _tick()'s manual _physics_process() calls below
	# never step the engine itself -- without this, both raycasts miss.
	await wait_physics_frames(2)
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotControllerForcedNoise = BotControllerForcedNoise.new()
	add_child_autofree(controller)
	controller.set_match_provider(match_ref)
	controller.set_net_provider(net_ref)
	controller.forced_origin = Vector2(0.0, 0.0)
	controller.forced_noise = Vector2(3.0, 0.0)

	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	Events.feed_block_issued.emit(0, &"cube", &"")
	_tick(controller, 72)

	assert_eq(match_ref.request_place_calls.size(), 1, "one placement request after the think-cycle")
	var world_origin: Vector3 = match_ref.request_place_calls[0]["origin"] as Vector3
	assert_almost_eq(world_origin.x, 3.0, 0.05, "fixture: the noisy point's own x")
	assert_almost_eq(world_origin.z, 0.0, 0.05, "fixture: the noisy point's own z")
	assert_almost_eq(
		world_origin.y, 2.5, 0.05,
		"must sample support height under the noisy point (2.5), not the stale pre-noise sample (1.0)"
	)


## Bontago-d5c.2 (review fix regression, MINOR): with no backoff, a rejected
## request_place() leaves _countdown at 0.0 and _tick_idle() re-enters
## GENERATING the very next frame, so an always-rejecting FakeMatch would
## retry roughly once per full GENERATING+ACTING cycle (~10 frames for
## NORMAL) forever. tuning.rejection_backoff_s (0.5 s = 30 frames) must hold
## the bot in IDLE after each rejection, bounding the call count over `seconds`
## of simulated time to `ceil(seconds / rejection_backoff_s) + 1` (+1 for the
## first think-cycle's own reaction delay, which isn't backoff-gated).
func test_rejected_request_backs_off_before_retrying() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	match_ref.next_request_reason = PlacementRules.REASON_CONTESTED
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)

	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	Events.feed_block_issued.emit(0, &"cube", &"")

	var seconds: float = 5.0
	_tick(controller, int(seconds * 60.0))

	var max_calls: int = int(ceil(seconds / controller.tuning.rejection_backoff_s)) + 1
	assert_true(
		match_ref.request_place_calls.size() <= max_calls,
		"a rejected placement must back off for tuning.rejection_backoff_s before retrying (got %d calls, expected <= %d)"
			% [match_ref.request_place_calls.size(), max_calls]
	)


## Bontago-d5c.12 diagnostic accessor (tests/bench/bench_bot_vs_passive.gd's
## own bot-timeline report reads this): every non-OK reason
## _apply_rejection_backoff() ever saw must be tallied, and REASON_OK itself
## (a successful send, or nothing sent at all) must never be counted.
func test_rejection_counts_tallies_non_ok_reasons_only() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	match_ref.next_request_reason = PlacementRules.REASON_CONTESTED
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)

	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	Events.feed_block_issued.emit(0, &"cube", &"")
	assert_eq(controller.rejection_counts(), {}, "no rejection has happened yet")

	_tick(controller, int(5.0 * 60.0))

	var counts: Dictionary = controller.rejection_counts()
	assert_true(
		int(counts.get(PlacementRules.REASON_CONTESTED, 0)) >= 1,
		"a rejected send must be tallied under its own reason"
	)
	assert_false(
		counts.has(PlacementRules.REASON_OK), "REASON_OK must never be tallied"
	)

	match_ref.next_request_reason = PlacementRules.REASON_OK
	_tick(controller, int(5.0 * 60.0))
	assert_false(
		controller.rejection_counts().has(PlacementRules.REASON_OK),
		"a later successful send must still never add a REASON_OK entry"
	)


func test_rejection_counts_returns_a_copy_not_the_live_dictionary() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)

	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	var counts: Dictionary = controller.rejection_counts()
	counts[PlacementRules.REASON_CONTESTED] = 999
	assert_eq(
		controller.rejection_counts().get(PlacementRules.REASON_CONTESTED, 0), 0,
		"mutating a returned snapshot must not affect this bot's own counters"
	)


# --- Bontago-d5c.8 (M5 P3b-ii item E): BotCandidate.shape_height producer ----

func test_generate_one_candidate_sets_shape_height_for_cube_and_pillar() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)
	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)

	controller._generate_one_candidate(0, CUBE_SHAPE, 0)
	assert_almost_eq(
		controller._candidates[-1].shape_height, 1.0, 0.001,
		"a cube is one cube unit tall in any orientation, including identity (index 0)"
	)

	controller._generate_one_candidate(0, PILLAR_SHAPE, 0)
	assert_almost_eq(
		controller._candidates[-1].shape_height, 3.0, 0.001,
		"a pillar standing at the identity orientation (index 0) is three cube units tall"
	)

	var flat_orientation: int = BotPlacementScorer.flattest_orientations(PILLAR_SHAPE, 1)[0]
	controller._generate_one_candidate(0, PILLAR_SHAPE, flat_orientation)
	assert_almost_eq(
		controller._candidates[-1].shape_height, 1.0, 0.001,
		"the pillar's own flattest orientation lies it down to one cube unit tall"
	)


# --- Bontago-d5c.8 (M5 P3b-ii item B): BotCandidate.corner_support_hits ------

## Two footprint cells side by side (disk-local (0, 0) and (1, 0)); a platform
## sits only under (0, 0), with its top surface at the same height the origin
## raycast (also at (0, 0), forced) reports as `support_height`. Of the two
## corner rays `_fire_stability_raycasts()` fires (profile.normal.
## stability_raycast_count is 4, capped by the 2-cell footprint), exactly one
## (the one over the platform) must land within tuning.
## stability_contact_tolerance_m of support_height; the other (over open air,
## the disk-surface fallback height 0.0) must not.
func test_fire_stability_raycasts_counts_only_corners_within_tolerance() -> void:
	var field: Field = _make_field()
	_make_platform(field, Vector3(0.0, 0.5, 0.0), 1.0)
	# test_field_raycast.gd's own precedent: a freshly added StaticBody3D's
	# collision shape only commits to the physics server on the next real
	# physics frame -- without this, the raycast at (0, 0) would miss too.
	await wait_physics_frames(2)
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	match_ref.cell_grid_value = CellGrid.new(field.map_def.field_radius, field.map_def.cell_size)
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotControllerForcedNoise = BotControllerForcedNoise.new()
	add_child_autofree(controller)
	controller.set_match_provider(match_ref)
	controller.set_net_provider(net_ref)
	controller.forced_origin = Vector2(0.0, 0.0)
	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)

	var two_wide_shape: BlockShape = BlockShape.new()
	two_wide_shape.cells = [Vector3i(0, 0, 0), Vector3i(1, 0, 0)]
	controller._generate_one_candidate(0, two_wide_shape, 0)

	assert_eq(controller._candidates.size(), 1, "fixture: exactly one candidate generated")
	var candidate: BotCandidate = controller._candidates[0]
	assert_eq(candidate.footprint_cells.size(), 2, "fixture: the two-wide shape covers exactly two footprint cells")
	assert_almost_eq(candidate.support_height, 1.0, 0.05, "fixture: the origin raycast hits the platform's own top surface")
	assert_eq(
		candidate.corner_support_hits, 1,
		"only the corner over the platform (half the 2-ray footprint) counts as in contact"
	)


## Bontago-d5c.11 item 1 (review fix, MAJOR regression): before the fix, a
## genuine miss (nothing directly below a footprint corner -- a hole) and a
## real hit both reported the same shape (no explicit flag, `"height": 0.0`
## as the safe fallback), so whenever a candidate's own `support_height`
## happened to be 0.0 too, a hole corner counted as flush contact. Both
## corners here canned-report the identical fallback height (0.0); only
## `corner_b`'s dictionary carries `"hit": true`. If the old counting logic
## regressed back in, this would report 2 (both "match" 0.0), not 1.
func test_fire_stability_raycasts_excludes_a_hole_corner_even_at_a_matching_fallback_height() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	match_ref.cell_grid_value = CellGrid.new(field.map_def.field_radius, field.map_def.cell_size)
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotControllerForcedRaycasts = BotControllerForcedRaycasts.new()
	add_child_autofree(controller)
	controller.set_match_provider(match_ref)
	controller.set_net_provider(net_ref)
	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)

	var grid: CellGrid = match_ref.cell_grid_value
	var two_wide_shape: BlockShape = BlockShape.new()
	two_wide_shape.cells = [Vector3i(0, 0, 0), Vector3i(1, 0, 0)]
	var basis: Basis = BlockOrientations.get_basis(0)
	var footprint: PackedInt32Array = PlacementRules.footprint_cells(
		two_wide_shape.cells, basis, Vector2.ZERO, field.tuning.cube_size, grid
	)
	assert_eq(footprint.size(), 2, "fixture: the two-wide shape covers exactly two footprint cells")
	var corner_a: Vector2 = grid.index_center(footprint[0])
	var corner_b: Vector2 = grid.index_center(footprint[1])

	controller.canned[corner_a] = {"height": 0.0, "collider": null, "hit": false}
	controller.canned[corner_b] = {"height": 0.0, "collider": null, "hit": true}

	var candidate: BotCandidate = BotCandidate.new()
	candidate.origin = Vector2.ZERO
	candidate.support_height = 0.0
	controller._fire_stability_raycasts(candidate, footprint, grid)

	assert_eq(
		candidate.corner_support_hits, 1,
		"the hole corner (hit: false) must never count as support, even though its fallback height matches support_height"
	)


# --- Bontago-d5c.11 items 2/3: skip triggered specials, sort output ---------

## Bontago-d5c.11 item 2 (review fix): a spent special's SpecialBehavior node
## lingers in game/specials/SpecialBehavior.GROUP until its Block is actually
## freed (is_triggered() flips true on trigger() but nothing removes the node
## from the group before then) -- _active_special_positions() must skip it.
func test_active_special_positions_skips_already_triggered_specials() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)
	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)

	var live_block: Node3D = Node3D.new()
	add_child_autofree(live_block)
	live_block.global_position = Vector3(4.0, 1.0, -2.0)
	var live_behavior: SpecialBehavior = SpecialBehavior.new()
	live_block.add_child(live_behavior)
	autofree(live_behavior)
	live_behavior.add_to_group(SpecialBehavior.GROUP)

	var spent_block: Node3D = Node3D.new()
	add_child_autofree(spent_block)
	spent_block.global_position = Vector3(1.0, 1.0, 1.0)
	var spent_behavior: SpecialBehavior = SpecialBehavior.new()
	spent_block.add_child(spent_behavior)
	autofree(spent_behavior)
	spent_behavior._has_triggered = true
	spent_behavior.add_to_group(SpecialBehavior.GROUP)

	var positions: PackedVector2Array = controller._active_special_positions()

	assert_eq(positions.size(), 1, "only the still-live special counts")
	assert_almost_eq(positions[0].x, 4.0, 0.001, "the live special's own disk-local x")
	assert_almost_eq(positions[0].y, -2.0, 0.001, "the live special's own disk-local y")


## Bontago-d5c.11 item 3 (review fix): get_nodes_in_group() iteration order is
## not a stable contract, so the result must be sorted (Vector2's own `<`:
## x, then y) regardless of the order the two behaviors were added in.
func test_active_special_positions_sorts_by_x_then_y() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)
	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)

	# Added in reverse spatial order: the higher-x one first.
	var block_high_x: Node3D = Node3D.new()
	add_child_autofree(block_high_x)
	block_high_x.global_position = Vector3(9.0, 1.0, 0.0)
	var behavior_high_x: SpecialBehavior = SpecialBehavior.new()
	block_high_x.add_child(behavior_high_x)
	autofree(behavior_high_x)
	behavior_high_x.add_to_group(SpecialBehavior.GROUP)

	var block_low_x: Node3D = Node3D.new()
	add_child_autofree(block_low_x)
	block_low_x.global_position = Vector3(2.0, 1.0, 0.0)
	var behavior_low_x: SpecialBehavior = SpecialBehavior.new()
	block_low_x.add_child(behavior_low_x)
	autofree(behavior_low_x)
	behavior_low_x.add_to_group(SpecialBehavior.GROUP)

	var positions: PackedVector2Array = controller._active_special_positions()

	assert_eq(positions.size(), 2, "fixture: both live specials found")
	assert_true(
		positions[0].x <= positions[1].x,
		"positions must come out sorted ascending by x regardless of group insertion order"
	)
	assert_almost_eq(positions[0].x, 2.0, 0.001, "the lower-x special sorts first")
	assert_almost_eq(positions[1].x, 9.0, 0.001, "the higher-x special sorts second")


# --- Bontago-d5c.8 (M5 P3b-ii item A): a placed special's own place_target --

## HARD (uses_offensive_specials = true) with a held Rocket: core/ai/
## BotSpecialPlanner.gd's own _plan_rocket() sets has_place_target and aims it
## at the bot's own already-generated candidate nearest the densest enemy
## cluster -- here, the sole enemy's home flag, placed far from this bot's own
## home so BotPlacementScorer.pick_best()'s risk term would instead steer
## toward a candidate far from it. _tick_acting() must send whichever
## candidate is nearest that place_target, not pick_best()'s own choice.
func test_send_best_placement_honours_a_held_specials_place_target() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	match_ref.held_specials[0] = &"rocket"
	match_ref.slot_count_value = 2
	match_ref.team_by_slot[1] = 1
	match_ref.slots_by_id[1] = PlayerSlot.new(1, 1, "Enemy", Color.RED, Vector2(8.0, 0.0))
	# A real CellGrid/TerritoryRaster, solved once with a single team-0 circle
	# covering the whole disk (test_placement_rules.gd's own "past the rim"
	# fixture pattern: a circle of radius >= 2x field_radius centred on the
	# origin) -- an unsolved TerritoryRaster's own reset() leaves every cell at
	# team -1 (unowned), which would make _sample_territory_point() exhaust
	# every attempt and fall back to the same home position for every
	# candidate; this instead lets it actually spread candidates across the
	# whole disk, same as a real match.
	var territory_tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
	match_ref.cell_grid_value = CellGrid.new(field.map_def.field_radius, field.map_def.cell_size)
	match_ref.raster_value = TerritoryRaster.new(match_ref.cell_grid_value, territory_tuning)
	var solver: TerritorySolver = TerritorySolver.new(territory_tuning)
	var whole_disk_circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2.ZERO, field.map_def.field_radius * 2.0, 0, 0, true, -1)
	]
	match_ref.raster_value.update(whole_disk_circles, solver.solve(whole_disk_circles), 0.1, false, false)
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)

	controller.setup(0, MatchConfig.AiDifficulty.HARD, field, null)
	Events.feed_block_issued.emit(0, &"cube", &"")

	# Worst case per BotDifficultyProfile.hard's own tunables (reaction_delay_s
	# 0.2 + up to think_phase_jitter_s 0.4 = 0.6s = 36 frames) plus
	# ceil(candidate_count 110 / candidates_per_frame 8) = 14 GENERATING frames
	# plus 1 ACTING frame = 51 frames worst case; a manual loop (rather than a
	# fixed frame count) stops the instant the one request lands, since
	# ticking even one frame past ACTING would re-enter GENERATING and clear
	# _candidates before this test can inspect them.
	var frame: int = 0
	while match_ref.request_place_calls.is_empty() and match_ref.request_throw_calls.is_empty() and frame < 120:
		controller._physics_process(1.0 / 60.0)
		frame += 1

	assert_eq(match_ref.request_throw_calls.size(), 0, "fixture: Rocket is a placed special, never thrown")
	assert_eq(match_ref.request_place_calls.size(), 1, "exactly one placement request after one full think-cycle")

	var expected_action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"rocket",
		controller._home_position(),
		controller._territory_sample_points(),
		controller._enemy_circle_centers(),
		PackedVector2Array(),
		MatchConfig.AiDifficulty.HARD,
		controller.tuning
	)
	assert_true(expected_action.has_place_target, "fixture: Rocket on HARD (offensive) always sets a place_target here")
	assert_false(expected_action.should_throw, "fixture: Rocket never throws")

	var expected_candidate: BotCandidate = null
	var expected_dist_sq: float = INF
	for candidate: BotCandidate in controller._candidates:
		var dist_sq: float = candidate.origin.distance_squared_to(expected_action.place_target)
		if expected_candidate == null or dist_sq < expected_dist_sq:
			expected_candidate = candidate
			expected_dist_sq = dist_sq

	var requested_origin: Vector3 = match_ref.request_place_calls[0]["origin"] as Vector3
	var requested_xz: Vector2 = Vector2(requested_origin.x, requested_origin.z)
	var max_aim_noise: float = controller._profile.aim_noise_m
	assert_true(
		requested_xz.distance_to(expected_candidate.origin) <= max_aim_noise + 0.01,
		"the request must land within aim-noise of the target-nearest candidate (got %s, expected near %s)"
			% [requested_xz, expected_candidate.origin]
	)

	# Confirm this really is a different candidate than pick_best() would have
	# chosen on its own, so the test cannot pass merely because the two
	# coincide.
	var pick_best_candidate: BotCandidate = BotPlacementScorer.pick_best(
		controller._candidates, match_ref.raster(), match_ref.cell_grid(), 0,
		controller._goal_positions(), controller._enemy_circle_centers(), PackedVector2Array(),
		controller.tuning, controller._field_radius()
	)
	assert_ne(
		pick_best_candidate.origin, expected_candidate.origin,
		"fixture: the enemy placement must make pick_best() diverge from the Rocket's own place_target"
	)


# --- Bontago-d5c.10 (item C): _send_throw's world-space velocity ------------

## Field tilted 15 degrees about its local X axis (a known, fixed rotation --
## not the spring-integrated tilt path, which never lands on an exact angle):
## a HARD (offensive) Bomb throw's own `throw_velocity` (core/ai/
## BotSpecialPlanner.gd's `_ballistic_velocity()`, disk-local axes) must reach
## Match.request_throw() rotated through Field.global_transform.basis, not
## verbatim -- the regression this test guards is exactly the pre-fix
## behaviour, where a level Field made the two spaces coincide and hid the
## bug.
func test_send_throw_rotates_the_planners_velocity_through_the_field_basis() -> void:
	var field: Field = _make_field()
	var tilt_basis: Basis = Basis(Vector3.RIGHT, deg_to_rad(15.0))
	var writer: BotControllerFieldTiltWriter = BotControllerFieldTiltWriter.new()
	writer.field = field
	writer.basis_to_apply = tilt_basis
	add_child_autofree(writer)
	await wait_physics_frames(1)
	assert_true(field.global_transform.basis.is_equal_approx(tilt_basis), "fixture: the tilt write landed")

	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	match_ref.held_specials[0] = &"bomb"
	match_ref.slot_count_value = 2
	match_ref.team_by_slot[1] = 1
	match_ref.slots_by_id[1] = PlayerSlot.new(1, 1, "Enemy", Color.RED, Vector2(8.0, 0.0))
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)

	controller.setup(0, MatchConfig.AiDifficulty.HARD, field, null)
	Events.feed_block_issued.emit(0, &"cube", &"")

	# Manual loop, same pattern as the Rocket test above: stop the instant the
	# throw lands, before a further tick can clear _candidates/re-enter
	# GENERATING.
	var frame: int = 0
	while match_ref.request_throw_calls.is_empty() and match_ref.request_place_calls.is_empty() and frame < 120:
		controller._physics_process(1.0 / 60.0)
		frame += 1

	assert_eq(match_ref.request_place_calls.size(), 0, "fixture: HARD offensive Bomb always throws, never places")
	assert_eq(match_ref.request_throw_calls.size(), 1, "exactly one throw request after one full think-cycle")

	# Recompute the planner's own decision the same way _tick_acting() did --
	# a pure function of state _tick_acting() left untouched (_candidates is
	# only cleared on the next GENERATING/feed_block_issued, neither of which
	# has run since the throw landed).
	var expected_action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.plan(
		&"bomb",
		controller._home_position(),
		controller._territory_sample_points(),
		controller._enemy_circle_centers(),
		controller._active_special_positions(),
		MatchConfig.AiDifficulty.HARD,
		controller.tuning
	)
	assert_true(expected_action.should_throw, "fixture: an offensive Bomb with a live enemy target always throws")

	var expected_world_velocity: Vector3 = tilt_basis * expected_action.throw_velocity
	var actual_velocity: Vector3 = match_ref.request_throw_calls[0]["velocity"] as Vector3
	assert_almost_eq(actual_velocity.x, expected_world_velocity.x, 0.01, "world-space x")
	assert_almost_eq(actual_velocity.y, expected_world_velocity.y, 0.01, "world-space y")
	assert_almost_eq(actual_velocity.z, expected_world_velocity.z, 0.01, "world-space z")
	assert_almost_eq(
		actual_velocity.length(), expected_action.throw_velocity.length(), 0.01,
		"a pure rotation preserves the planner's own throw speed"
	)
	assert_true(
		actual_velocity.distance_to(expected_action.throw_velocity) > 0.05,
		"fixture: the tilt must actually change the vector -- otherwise this test cannot tell the fix from the bug"
	)


# --- Bontago-d5c.11 item 5: territory sampling excludes goal zones ----------

## _sample_territory_point() must never accept a point PlacementRules.
## validate_point() would itself refuse: this team owns the whole disk (same
## whole-disk-circle fixture as the Rocket test above), but a goal zone is
## stamped well away from the bot's own home flag (so the fallback home
## position, which the function returns only when every attempt fails, can
## never itself land in the zone and mask a real bug) and large enough that a
## pre-fix `team_at()`-only check would land inside it constantly over many
## samples.
func test_sample_territory_point_never_lands_in_a_goal_zone() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	var territory_tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
	match_ref.cell_grid_value = CellGrid.new(field.map_def.field_radius, field.map_def.cell_size)
	match_ref.raster_value = TerritoryRaster.new(match_ref.cell_grid_value, territory_tuning)
	var solver: TerritorySolver = TerritorySolver.new(territory_tuning)
	var whole_disk_circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2.ZERO, field.map_def.field_radius * 2.0, 0, 0, true, -1)
	]
	match_ref.raster_value.update(whole_disk_circles, solver.solve(whole_disk_circles), 0.1, false, false)
	# Slot 0's own home is (1, 0) (_make_ready_match()); the goal zone sits at
	# (5, 0) with a 2.5 m radius, so home is well outside it and every sampled
	# point that lands inside the zone is a genuine regression, not the
	# fallback.
	match_ref.raster_value.set_goal_zones(PackedVector2Array([Vector2(5.0, 0.0)]), 2.5)
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)
	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)

	for _i: int in range(200):
		var point: Vector2 = controller._sample_territory_point(0)
		var cell: Vector2i = match_ref.cell_grid_value.world_to_cell(point)
		assert_false(
			match_ref.raster_value.is_goal_zone(cell.x, cell.y),
			"sampled territory point %s must never fall inside a goal flag's no-build zone" % point
		)


# --- Bontago-d5c.10 (item F): real enemy circle centers + active specials ---

## Bontago-d5c.10 (item F): _enemy_circle_centers() must include both a living
## enemy's home flag AND the disk-local centers of that team's own live
## (Match.circle_render_arrays()) influence circles -- and never an ally's
## own circle (team 0, this bot's own team).
func test_enemy_circle_centers_includes_home_flags_and_live_enemy_circles() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	match_ref.slot_count_value = 2
	match_ref.team_by_slot[1] = 1
	match_ref.slots_by_id[1] = PlayerSlot.new(1, 1, "Enemy", Color.RED, Vector2(8.0, 0.0))
	match_ref.circle_arrays_value = {
		"xs": PackedFloat32Array([5.0, -3.0]),
		"zs": PackedFloat32Array([2.0, 1.0]),
		"radii": PackedFloat32Array([4.0, 6.0]),
		"teams": PackedInt32Array([1, 0]),
	}
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)
	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)

	var centers: PackedVector2Array = controller._enemy_circle_centers()

	assert_true(centers.has(Vector2(8.0, 0.0)), "enemy slot 1's own home flag")
	assert_true(centers.has(Vector2(5.0, 2.0)), "enemy team 1's own live circle center")
	assert_false(centers.has(Vector2(-3.0, 1.0)), "this bot's own team (0) must never count as an enemy circle")


## Bontago-d5c.10 (item F): every SpecialBehavior.GROUP node's parent's
## global_position, converted to disk-local through Field.disk_local_from_world().
func test_active_special_positions_converts_ticking_specials_to_disk_local() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)
	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)

	# "A Block-like Node3D" (docs/M5_PLAN.md's own item F brief) -- a plain
	# Node3D stands in for a real, physics-backed Block, since only its
	# global_position and its being the behaviour's parent matter here.
	var block_like: Node3D = Node3D.new()
	add_child_autofree(block_like)
	block_like.global_position = Vector3(4.0, 1.0, -2.0)
	var behavior: SpecialBehavior = SpecialBehavior.new()
	block_like.add_child(behavior)
	autofree(behavior)
	behavior.add_to_group(SpecialBehavior.GROUP)

	var positions: PackedVector2Array = controller._active_special_positions()

	assert_eq(positions.size(), 1, "exactly the one ticking special found in the group")
	assert_almost_eq(positions[0].x, 4.0, 0.001, "disk-local x off a level, origin-centered Field")
	assert_almost_eq(positions[0].y, -2.0, 0.001, "disk-local y (Field's local z) off a level, origin-centered Field")
