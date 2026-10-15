extends GutTest
## game/bots/BotController.gd's cadence/gating state machine: the reaction-delay countdown, the
## release-lock/held-shape gates, the host gate, and the per-bot seeded jitter that staggers
## multiple bots' first think across different physics frames.
##
## Local fakes rather than tests/support/FakeMatch.gd -- that shared
## double only ever answered game/player/PlayerController.gd's/ui/HUD.gd's narrower
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

	## Bontago-1t5.2: Match.gift_states()'s shape (id/phase/position).
	var gift_states_value: Array[Dictionary] = []

	func gift_states() -> Array[Dictionary]:
		return gift_states_value

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

	## Bontago-1pi.175: the slot's remaining block-timer seconds (large = never the limit).
	var feed_time_left_value: float = 99.0

	func feed_time_left(_slot_id: int) -> float:
		return feed_time_left_value

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

	## Bontago-1t5.3: optional mode goal provider (a Callable slot -> BotModeGoal).
	var mode_goal_calls: Array[int] = []
	var mode_goal_factory: Callable = Callable()

	func bot_mode_goal(slot_id: int) -> BotModeGoal:
		mode_goal_calls.append(slot_id)
		if mode_goal_factory.is_valid():
			return mode_goal_factory.call(slot_id) as BotModeGoal
		return null

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


## Forces the aim-noise offset (_aim_noise_offset()) to a fixed value so a test can prove
## _send_best_placement() samples support height at the *noisy* point, without depending on the
## seeded RNG's draw order.
class BotControllerForcedNoise:
	extends BotController
	var forced_noise: Vector2 = Vector2.ZERO

	func _aim_noise_offset() -> Vector2:
		return forced_noise


## Bontago-d5c.10 (item C): writes a known, fixed rotation onto a Field's own
## transform from inside a physics tick, then goes idle -- the memory'd
## convention for a Field write (game/field/Field.gd's own DECISION on
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
	config.disc_size_step = 1
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
	# V2 only generates sites inside its own territory: stamp the seat's home circle.
	var territory: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
	fake.raster_value = TerritoryRaster.new(CellGrid.new(20.0, 1.0), territory)
	fake.cell_grid_value = fake.raster_value.grid()
	var home: Array[InfluenceCircle] = [InfluenceCircle.for_home(Vector2(1.0, 0.0), slot_id, slot_id, territory)]
	fake.raster_value.update(home, TerritorySolver.new(territory).solve(home), 0.1, false, false)
	return fake


func _make_controller(field: Field, match_ref: BotControllerFakeMatch, net_ref: BotControllerFakeNet) -> BotController:
	var controller: BotController = BotController.new()
	add_child_autofree(controller)
	# Bontago-1pi.175: these tests assert the decision pipeline, not the release hold.
	controller.tuning = _tuning_with_release_delay(0.0, 0.0)
	controller.set_match_provider(match_ref)
	controller.set_net_provider(net_ref)
	return controller


## Ticks `frames` physics frames of 1/60s each.
func _tick(controller: BotController, frames: int) -> void:
	for _i: int in range(frames):
		controller._physics_process(1.0 / 60.0)


## Ticks until the bot has sent its first request (place or throw); returns the frames used. A
## ceiling of 200 frames is far above reaction delay (<= 0.6 s) + think deadline + acting.
func _tick_until_request(controller: BotController, match_ref: BotControllerFakeMatch) -> int:
	var frames: int = 0
	while match_ref.request_place_calls.is_empty() and match_ref.request_throw_calls.is_empty() and frames < 200:
		controller._physics_process(1.0 / 60.0)
		frames += 1
	return frames


func test_sends_exactly_one_request_place_after_the_reaction_delay() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)

	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	Events.feed_block_issued.emit(0, &"cube", &"")

	var frames: int = _tick_until_request(controller, match_ref)

	# The reaction delay (0.2 s = 12 frames) plus the think deadline (14 ticks) must have passed.
	assert_gt(frames, 12 + 14 - 1, "no request before the reaction delay and the think deadline")
	assert_eq(match_ref.request_place_calls.size(), 1, "exactly one placement request after one full think-cycle")
	assert_eq(int(match_ref.request_place_calls[0]["slot_id"]), 0)


func test_bot_still_places_in_sudden_death() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	match_ref.state_value = MatchAutoload.State.SUDDEN_DEATH
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)
	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	Events.feed_block_issued.emit(0, &"cube", &"")
	_tick_until_request(controller, match_ref)
	assert_eq(match_ref.request_place_calls.size(), 1, "spec 2.8: bots keep playing in sudden death")


func test_sends_nothing_while_release_locked() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	match_ref.release_locked[0] = true
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)

	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	Events.feed_block_issued.emit(0, &"cube", &"")
	_tick(controller, 120)

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
	_tick(controller, 120)

	assert_eq(match_ref.request_place_calls.size(), 0, "nothing to place with no held shape")


func test_non_host_is_a_no_op_every_frame() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	net_ref.is_host_value = false
	var controller: BotController = _make_controller(field, match_ref, net_ref)

	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	Events.feed_block_issued.emit(0, &"cube", &"")
	_tick(controller, 120)

	assert_eq(match_ref.request_place_calls.size(), 0, "a non-host controller never sends anything")


## docs/archive/M5_PLAN.md P1: "two BotControllers with different think_phase_jitter_s
## draws never fire their first think-tick on the identical physics frame --
## deterministic with a fixed seed." Each controller has its own FakeMatch
## (matching its own slot_id's seeded stride) so their countdowns run
## independently; the frame each first leaves IDLE (drawn once at setup(),
## seeded off the shared config.rng_seed + a per-slot stride) is asserted to
## differ.
func test_two_bots_with_different_jitter_draws_never_start_thinking_on_the_same_frame() -> void:
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


## Review fix regression: best.support_height was sampled at the pre-noise origin -- the aim-noise
## offset can legitimately move the request onto a different collider's surface. Two platforms sit
## under two known disk-local points: a low one under the candidate origin (0, 0), top at world Y 1.0,
## and a taller one under the forced noisy point (3, 0), top at world Y 2.5. The request must quote
## Y 2.5 (a fresh raycast at the actual noisy point), not the pre-noise Y 1.0.
func test_send_best_placement_resamples_support_height_at_the_noisy_origin() -> void:
	var field: Field = _make_field()
	_make_platform(field, Vector3(0.0, 0.5, 0.0), 1.0)
	_make_platform(field, Vector3(3.0, 2.0, 0.0), 1.0)
	# A freshly added StaticBody3D's collision shape is only committed to the physics server on the
	# next real physics frame; without this both raycasts miss.
	await wait_physics_frames(2)
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotControllerForcedNoise = BotControllerForcedNoise.new()
	add_child_autofree(controller)
	controller.tuning = _tuning_with_release_delay(0.0, 0.0)
	controller.set_match_provider(match_ref)
	controller.set_net_provider(net_ref)
	controller.forced_noise = Vector2(3.0, 0.0)
	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	controller._candidates = [_candidate_at(Vector2.ZERO)]

	controller._send_best_placement(Vector2.ZERO)

	assert_eq(match_ref.request_place_calls.size(), 1, "one placement request")
	var world_origin: Vector3 = match_ref.request_place_calls[0]["origin"] as Vector3
	assert_almost_eq(world_origin.x, 3.0, 0.05, "fixture: the noisy point's own x")
	assert_almost_eq(world_origin.z, 0.0, 0.05, "fixture: the noisy point's own z")
	assert_almost_eq(
		world_origin.y, 2.5, 0.05,
		"must sample support height under the noisy point (2.5), not the stale pre-noise sample (1.0)"
	)


## Bontago-d5c.2 (review fix regression, MINOR): with no backoff, a rejected
## request_place() leaves _countdown at 0.0 and _tick_idle() re-enters
## thinking the very next frame, so an always-rejecting FakeMatch would
## retry roughly once per full think+ACTING cycle (~15 frames) forever. tuning.rejection_backoff_s (0.5 s = 30 frames) must hold
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


# --- Bontago-d5c.11 items 2/3: skip triggered specials, sort output ---------

## Bontago-d5c.11 item 2 (review fix): a spent special's SpecialBehavior node
## lingers in game/gifts/specials/SpecialBehavior.GROUP until its Block is actually
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

## A placed special's planned `place_target` (BotSpecialAction.has_place_target) sends the think's
## candidate nearest to it, not the think's own pick: with two candidates and a target at the far
## one, the request lands within aim noise of the far candidate.
func test_send_best_placement_honours_a_held_specials_place_target() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	match_ref.held_specials[0] = &"rocket"
	var controller: BotController = _make_controller(field, match_ref, BotControllerFakeNet.new())
	controller.setup(0, MatchConfig.AiDifficulty.HARD, field, null)
	var near_candidate: BotCandidate = _candidate_at(Vector2(0.0, 0.0))
	var far_candidate: BotCandidate = _candidate_at(Vector2(6.0, 2.0))
	controller._candidates = [near_candidate, far_candidate]

	controller._send_best_placement(Vector2(5.5, 2.0))

	assert_eq(match_ref.request_place_calls.size(), 1)
	var requested_origin: Vector3 = match_ref.request_place_calls[0]["origin"] as Vector3
	var requested_xz: Vector2 = Vector2(requested_origin.x, requested_origin.z)
	assert_true(
		requested_xz.distance_to(far_candidate.origin) <= controller._profile.aim_noise_m + 0.01,
		"the request must land within aim-noise of the target-nearest candidate (got %s)" % requested_xz
	)


# --- Bontago-d5c.10 (item C): _send_throw's world-space velocity ------------

## Field tilted 15 degrees about its local X axis (a known, fixed rotation -- not the spring-integrated
## tilt path, which never lands on an exact angle): a Bomb throw's own `throw_velocity` (disk-local
## axes, BotSpecialPlanner._ballistic_velocity()) must reach Match.request_throw() rotated through
## Field.global_transform.basis, not verbatim -- a level Field made the two spaces coincide and hid
## the pre-fix bug.
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
	var controller: BotController = _make_controller(field, match_ref, BotControllerFakeNet.new())
	controller.setup(0, MatchConfig.AiDifficulty.HARD, field, null)
	var action: BotSpecialPlanner.BotSpecialAction = BotSpecialPlanner.BotSpecialAction.new()
	action.should_throw = true
	action.throw_origin = Vector2(1.0, 0.0)
	action.throw_velocity = Vector3(0.6, 0.5, 0.6)

	controller._send_throw(action)

	assert_eq(match_ref.request_place_calls.size(), 0)
	assert_eq(match_ref.request_throw_calls.size(), 1, "exactly one throw request")

	# Bontago-1pi.85.29: the bot sends the unit aim; the host owns the speed.
	# Bontago-1pi.85.39: flat camera-style forward; the host (GiftAim.throw_velocity) adds the loft once.
	var tilted: Vector3 = tilt_basis * action.throw_velocity
	var expected_world_velocity: Vector3 = Vector3(tilted.x, 0.0, tilted.z).normalized()
	var actual_velocity: Vector3 = match_ref.request_throw_calls[0]["velocity"] as Vector3
	assert_almost_eq(actual_velocity.x, expected_world_velocity.x, 0.01, "world-space x")
	assert_almost_eq(actual_velocity.y, expected_world_velocity.y, 0.01, "world-space y")
	assert_almost_eq(actual_velocity.z, expected_world_velocity.z, 0.01, "world-space z")
	assert_almost_eq(
		actual_velocity.length(), 1.0, 0.01,
		"the bot sends a unit aim direction (the host never reads a client speed)"
	)
	var special_tuning: SpecialTuning = SpecialTuning.new()
	assert_eq(
		GiftAim.throw_velocity(actual_velocity, special_tuning),
		GiftAim.throw_velocity(expected_world_velocity, special_tuning),
		"host velocity equals GiftAim.throw_velocity of the flat forward"
	)
	assert_almost_eq(actual_velocity.y, 0.0, 0.0001, "no loft in the sent aim (host adds it; no double loft)")
	assert_true(
		actual_velocity.distance_to(action.throw_velocity.normalized()) > 0.05,
		"fixture: the tilt must actually change the vector -- otherwise this test cannot tell the fix from the bug"
	)


# --- Bontago-d5c.10 (item F): active specials ---

## Bontago-d5c.10 (item F): every SpecialBehavior.GROUP node's parent's
## global_position, converted to disk-local through Field.disk_local_from_world().
func test_active_special_positions_converts_ticking_specials_to_disk_local() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)
	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)

	# "A Block-like Node3D" (docs/archive/M5_PLAN.md's own item F brief) -- a plain
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


## Bontago-6fc.2: Reach the Sky / Elimination spawn no goal flag, so bots have
## no goal to target; classic still has its goal.
func test_bots_have_no_goal_targets_without_goal_flags() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	var controller: BotController = _make_controller(field, match_ref, BotControllerFakeNet.new())
	match_ref.config.game_mode = MatchConfig.GameMode.REACH_THE_SKY
	assert_true(controller._goal_positions().is_empty())
	match_ref.config.game_mode = MatchConfig.GameMode.ELIMINATION
	assert_true(controller._goal_positions().is_empty())
	match_ref.config.game_mode = MatchConfig.GameMode.CLASSIC
	assert_eq(controller._goal_positions().size(), 1)


## Bontago-1t5.3 review fix: the match's bot_mode_goal(slot) is asked for once
## per placement for the bot's own slot (not per candidate).
func test_send_best_placement_asks_the_match_for_the_mode_goal_once() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	var goal: BotModeGoal = BotModeGoal.new()
	goal.mode = MatchConfig.GameMode.ELIMINATION
	match_ref.mode_goal_factory = func(_slot: int) -> BotModeGoal: return goal
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)
	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	Events.feed_block_issued.emit(0, &"cube", &"")
	_tick_until_request(controller, match_ref)
	assert_eq(match_ref.request_place_calls.size(), 1)
	assert_eq(match_ref.mode_goal_calls, [0] as Array[int])


func test_send_best_placement_tolerates_a_null_mode_goal() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)
	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	Events.feed_block_issued.emit(0, &"cube", &"")
	_tick_until_request(controller, match_ref)
	assert_eq(match_ref.request_place_calls.size(), 1)
	assert_eq(match_ref.mode_goal_calls.size(), 1)


# --- Bontago-1t5.2: claim landed gifts, use held gifts promptly -------------

func _candidate_at(origin: Vector2) -> BotCandidate:
	var candidate: BotCandidate = BotCandidate.new()
	candidate.origin = origin
	return candidate


func test_held_special_is_spent_after_the_short_gift_use_delay() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	match_ref.held_specials[0] = &"anvil"
	var controller: BotController = _make_controller(field, match_ref, BotControllerFakeNet.new())
	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	Events.feed_block_issued.emit(0, &"cube", &"")
	# gift_use_delay_s 0.25 s = 15 frames + the 14-tick think deadline + 1 acting.
	var frames: int = _tick_until_request(controller, match_ref)
	assert_lte(frames, 30, "a held special is placed after the short use delay, not the full reaction delay")
	assert_eq(match_ref.request_place_calls.size(), 1)


## Bontago-1t5.19 review Low1: V2 bots ticked manually (several _physics_process calls in one
## engine frame) must neither inherit the static frame budget nor starve one another.
func test_two_bots_ticked_in_one_engine_frame_both_progress() -> void:
	var field_a: Field = _make_field()
	var field_b: Field = _make_field()
	var match_a: BotControllerFakeMatch = _make_ready_match(0)
	var match_b: BotControllerFakeMatch = _make_ready_match(1)
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var bot_a: BotController = _make_controller(field_a, match_a, net_ref)
	var bot_b: BotController = _make_controller(field_b, match_b, net_ref)
	# A stale, exhausted counter from an earlier run must not leak in (setup() resets it).
	BotController._think_frame = Engine.get_physics_frames()
	BotController._think_frame_used_us = 1000000
	bot_a.setup(0, MatchConfig.AiDifficulty.NORMAL, field_a, null)
	bot_b.setup(1, MatchConfig.AiDifficulty.NORMAL, field_b, null)
	for bot: BotController in [bot_a, bot_b]:
		bot._profile = bot._profile.duplicate() as BotDifficultyProfile
		bot._profile.think_budget_us = 1
		bot._profile.think_frame_cap_us = 1
	Events.feed_block_issued.emit(0, &"cube", &"")
	Events.feed_block_issued.emit(1, &"cube", &"")
	var progressed_a: bool = false
	var progressed_b: bool = false
	for _i: int in range(400):
		bot_a._physics_process(1.0 / 60.0)
		bot_b._physics_process(1.0 / 60.0)
		progressed_a = progressed_a or (bot_a._think != null and bot_a._think.candidates().size() > 0)
		progressed_b = progressed_b or (bot_b._think != null and bot_b._think.candidates().size() > 0)
		if progressed_a and progressed_b:
			break
	assert_true(progressed_a, "bot A thinks despite the exhausted shared cap")
	assert_true(progressed_b, "bot B is not starved by bot A")


## Bontago-1t5.37: a bot on a fixture that has territory (sites are generated inside it).
func _make_v2_bot(difficulty: MatchConfig.AiDifficulty) -> BotController:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	var bot: BotController = _make_controller(field, match_ref, BotControllerFakeNet.new())
	bot.setup(0, difficulty, field, null)
	return bot


## Ticks a bot out of IDLE (its countdown cleared) and returns how many further ticks it spends
## in `state` before leaving it (the decision latency the E6 bench measures).
func _ticks_in_state(bot: BotController, state: BotController.State) -> int:
	bot._countdown = 0.0
	bot._physics_process(1.0 / 60.0)
	assert_eq(bot._state, state, "precondition: the begin tick entered the state")
	var ticks: int = 0
	while bot._state == state and ticks < 100:
		bot._physics_process(1.0 / 60.0)
		ticks += 1
	return ticks


## Bontago-1t5.37: the decision deadline is Hard's window for every tier (Bontago-1t5.57), measured
## off the shipped profile: ceil(110 / 8) = 14 ticks.
func test_think_deadline_is_hards_generation_window_for_every_tier() -> void:
	var tuning: BotTuning = load("res://config/bots/bot_tuning.tres")
	var hard_ticks: int = tuning.hard.generation_ticks(tuning.max_generation_frames)
	assert_eq(hard_ticks, 14, "ceil(110 / 8)")
	for difficulty: MatchConfig.AiDifficulty in [
		MatchConfig.AiDifficulty.EASY, MatchConfig.AiDifficulty.NORMAL, MatchConfig.AiDifficulty.HARD
	]:
		assert_eq(_make_v2_bot(difficulty).think_deadline_ticks(), hard_ticks, "difficulty %d" % difficulty)


## Bontago-1t5.37: with no per-tick budget and an exhausted shared cap, the think still ends on
## its deadline tick (the deadline share always runs, the last tick completes it).
func test_v2_think_is_decided_by_its_deadline_tick() -> void:
	var bot: BotController = _make_v2_bot(MatchConfig.AiDifficulty.EASY)
	bot._profile = bot._profile.duplicate() as BotDifficultyProfile
	bot._profile.think_budget_us = 0
	bot._profile.think_frame_cap_us = 0
	var deadline: int = bot.think_deadline_ticks()
	var ticks: int = _ticks_in_state(bot, BotController.State.THINKING)
	assert_lte(ticks, deadline, "decided by the deadline tick")
	assert_eq(bot._state, BotController.State.ACTING)
	assert_true(bot._think.is_done())
	assert_eq(bot._think.decision().kind, BotThink.DecisionKind.PLACE)


# --- Bontago-1pi.175: staggered release ---

func _tuning_with_release_delay(lo: float, hi: float) -> BotTuning:
	var t: BotTuning = (load("res://config/bots/bot_tuning.tres") as BotTuning).duplicate() as BotTuning
	t.release_delay_min_s = lo
	t.release_delay_max_s = hi
	return t


## Frames from a freshly set-up bot until its request_place() is sent.
func _frames_until_release(slot_id: int, seed_value: int, lo: float, hi: float, time_left: float = -1.0) -> int:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(slot_id)
	match_ref.config.rng_seed = seed_value
	if time_left >= 0.0:
		match_ref.feed_time_left_value = time_left
	var net_ref: BotControllerFakeNet = BotControllerFakeNet.new()
	var controller: BotController = _make_controller(field, match_ref, net_ref)
	controller.tuning = _tuning_with_release_delay(lo, hi)
	controller.setup(slot_id, MatchConfig.AiDifficulty.NORMAL, field, null)
	# An unlimited think budget finishes the think on its first tick, so the frame count is
	# deterministic (a time-sliced think can end a tick earlier or later with measured cost).
	controller._profile = controller._profile.duplicate() as BotDifficultyProfile
	controller._profile.think_budget_us = 1000000000
	controller._profile.think_frame_cap_us = 1000000000
	var frames: int = 0
	while match_ref.request_place_calls.is_empty() and frames < 2000:
		controller._physics_process(1.0 / 60.0)
		frames += 1
	return frames


func test_release_delay_spreads_bots_and_is_seed_deterministic() -> void:
	var first: Array[int] = []
	for slot: int in range(4):
		first.append(_frames_until_release(slot, 42, 0.0, 1.5))
	var distinct: Dictionary = {}
	for f: int in first:
		distinct[f] = true
	assert_gt(distinct.size(), 1, "bots release on different ticks: %s" % str(first))
	var second: Array[int] = []
	for slot: int in range(4):
		second.append(_frames_until_release(slot, 42, 0.0, 1.5))
	assert_eq(second, first, "same match seed, same release ticks")
	var none: int = _frames_until_release(0, 42, 0.0, 0.0)
	assert_gt(_frames_until_release(0, 42, 1.0, 1.0), none + 50, "a fixed 1 s hold adds about 60 ticks")


func test_release_hold_is_cut_before_the_block_timer_expires() -> void:
	var held: int = _frames_until_release(0, 42, 3.0, 3.0, 1.0)
	var free: int = _frames_until_release(0, 42, 0.0, 0.0, 1.0)
	# Only (time_left - margin) = 0.5 s may be spent holding, never the full 3 s.
	assert_lt(held - free, 40, "hold capped by the timer")


# --- Bontago-1t5.46: BotController._apply_weather (host live weather -> view) ---

class BotControllerFakeBreeze:
	var gust_list: Array[Dictionary] = []

	func gusts() -> Array[Dictionary]:
		return gust_list


class BotControllerFakeWeather:
	var id: StringName = &""
	var intensity: float = 0.0
	var seed_number: int = 4242
	var event_number: int = 1
	var breeze_ref: BotControllerFakeBreeze = BotControllerFakeBreeze.new()

	func active_id() -> StringName:
		return id

	func active_intensity() -> float:
		return intensity

	func seed_value() -> int:
		return seed_number

	func event_index() -> int:
		return event_number

	func breeze() -> BotControllerFakeBreeze:
		return breeze_ref


class BotControllerWeatherMatch:
	extends BotControllerFakeMatch
	var weather_ref: BotControllerFakeWeather = BotControllerFakeWeather.new()

	func weather() -> BotControllerFakeWeather:
		return weather_ref


func _weather_view(match_ref: Variant, field: Field) -> BotWorldView:
	var bot: BotController = _make_controller(field, match_ref, BotControllerFakeNet.new())
	bot.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	var view: BotWorldView = BotWorldView.new()
	bot._apply_weather(view, match_ref)
	return view


func test_apply_weather_calm_leaves_view_untouched() -> void:
	var match_ref: BotControllerWeatherMatch = BotControllerWeatherMatch.new()
	var view: BotWorldView = _weather_view(match_ref, _make_field())
	assert_eq(view.weather_id, &"")
	assert_eq(view.weather_intensity, 0.0)
	assert_null(view.wind_tuning)
	assert_eq(view.wind_dir, Vector2.ZERO)
	assert_null(view.breeze_tuning)
	assert_true(view.gust_power_values.is_empty())


func test_apply_weather_without_weather_accessor_is_a_noop() -> void:
	var view: BotWorldView = _weather_view(_make_ready_match(0), _make_field())
	assert_null(view.wind_tuning)
	assert_null(view.breeze_tuning)


func test_apply_weather_storm_copies_intensity_and_heading() -> void:
	var match_ref: BotControllerWeatherMatch = BotControllerWeatherMatch.new()
	match_ref.weather_ref.id = WeatherIds.STORM
	match_ref.weather_ref.intensity = 0.6
	var view: BotWorldView = _weather_view(match_ref, _make_field())
	assert_eq(view.weather_id, WeatherIds.STORM)
	assert_almost_eq(view.weather_intensity, 0.6, 0.0001)
	assert_eq(view.wind_tuning, BotController.STORM_TUNING)
	var angle: float = WindField.base_angle(WindField.event_seed(4242, 1))
	assert_almost_eq(view.wind_dir.x, cos(angle), 0.0001, "an untransformed field keeps the world heading")
	assert_almost_eq(view.wind_dir.y, sin(angle), 0.0001)


func test_apply_weather_rain_has_no_wind() -> void:
	var match_ref: BotControllerWeatherMatch = BotControllerWeatherMatch.new()
	match_ref.weather_ref.id = &"rain"
	match_ref.weather_ref.intensity = 1.0
	var view: BotWorldView = _weather_view(match_ref, _make_field())
	assert_eq(view.weather_intensity, 1.0)
	assert_null(view.wind_tuning)
	assert_eq(view.wind_dir, Vector2.ZERO)


func test_apply_weather_copies_live_gusts_into_disk_local_space() -> void:
	var match_ref: BotControllerWeatherMatch = BotControllerWeatherMatch.new()
	match_ref.weather_ref.breeze_ref.gust_list.append({
		"id": 1, "x": 2.0, "y": 5.0, "z": -3.0, "a": 0.0, "r": 4.0, "d": 2.0, "s": 0.8, "age": 0.0,
	})
	match_ref.weather_ref.breeze_ref.gust_list.append({
		"id": 2, "x": 0.0, "y": 5.0, "z": 0.0, "a": 0.0, "r": 4.0, "d": 2.0, "s": 1.0, "age": 2.5,
	})
	var field: Field = _make_field()
	var view: BotWorldView = _weather_view(match_ref, field)
	assert_eq(view.gust_power_values.size(), 1, "the expired gust is dropped")
	assert_eq(view.breeze_tuning, BotController.BREEZE_TUNING)
	assert_eq(view.gust_center[0], field.to_local(Vector3(2.0, 5.0, -3.0)))
	assert_almost_eq(view.gust_power_values[0], 0.8, 0.0001)
	assert_almost_eq(view.gust_radius[0], 4.0, 0.0001)
	assert_almost_eq(view.gust_heading[0].x, 1.0, 0.0001)
	assert_almost_eq(view.gust_heading[0].y, 0.0, 0.0001)
	var tall: BotCandidate = BotCandidate.new()
	tall.origin = Vector2(2.0, -3.0)
	tall.top_height = 9.0
	assert_gt(BotEvaluator.breeze_tip(tall, view), 0.0, "the controller data drives the evaluator")


func test_apply_weather_skips_malformed_gusts() -> void:
	var match_ref: BotControllerWeatherMatch = BotControllerWeatherMatch.new()
	match_ref.weather_ref.breeze_ref.gust_list.append({"id": 1, "x": 0.0})
	var view: BotWorldView = _weather_view(match_ref, _make_field())
	assert_true(view.gust_power_values.is_empty())
	assert_null(view.breeze_tuning)


func test_world_view_gifts_include_airborne_gifts_within_horizon() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	var controller: BotController = _make_controller(field, match_ref, BotControllerFakeNet.new())
	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	var landing: Vector3 = Vector3(2.0, 0.3, 0.0)
	match_ref.gift_states_value = [
		{"id": 1, "phase": MatchGifts.LANDED, "position": Vector2(5.0, 0.0)},
		{"id": 2, "phase": MatchGifts.FALLING, "position": Vector2(2.0, 0.0), "origin": landing + Vector3.UP * 4.0, "landing": landing, "elapsed": 0.0},
		{"id": 3, "phase": MatchGifts.FALLING, "position": Vector2(9.0, 9.0), "origin": landing + Vector3.UP * 500.0, "landing": landing, "elapsed": 0.0},
	]
	var positions: PackedVector2Array = controller._landed_gift_positions(match_ref)
	assert_eq(positions, PackedVector2Array([Vector2(5.0, 0.0), Vector2(2.0, 0.0)]), "landed + near-landing airborne; the far one is beyond the horizon")


# --- Bontago-1t5.47: _apply_incoming_specials scene path ---------------------

## Builds an enemy (slot 1, team 1) Block carrying a SpecialBehavior at `at` with `velocity`.
func _make_thrown_block(at: Vector3, velocity: Vector3) -> Block:
	var block: Block = Block.new()
	block.owner_slot = 1
	block.freeze = false
	add_child_autofree(block)
	block.global_position = at
	block.linear_velocity = velocity
	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	behavior.add_to_group(SpecialBehavior.GROUP)
	return block


func _incoming_controller(field: Field) -> BotController:
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	match_ref.team_by_slot[1] = 1
	var controller: BotController = _make_controller(field, match_ref, BotControllerFakeNet.new())
	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	controller.set_meta(&"fake_match", match_ref)
	return controller


func test_apply_incoming_specials_adds_airborne_enemy_throw() -> void:
	var field: Field = _make_field()
	var controller: BotController = _incoming_controller(field)
	_make_thrown_block(Vector3(0.0, 10.0, 0.0), Vector3(4.0, 3.0, 0.0))
	var view: BotWorldView = BotWorldView.new()
	view.team_id = 0
	controller._apply_incoming_specials(view, controller.get_meta(&"fake_match"))
	assert_eq(view.incoming_points.size(), 1, "an airborne enemy special is incoming")
	assert_true(view.incoming_points[0].x > 0.0, "predicted impact lies downrange of the throw")


func test_apply_incoming_specials_skips_sliding_and_own_team() -> void:
	var field: Field = _make_field()
	var controller: BotController = _incoming_controller(field)
	_make_thrown_block(Vector3(0.0, 1.0, 0.0), Vector3(5.0, 0.0, 0.0))
	var own: Block = _make_thrown_block(Vector3(0.0, 10.0, 0.0), Vector3(0.0, -5.0, 0.0))
	own.owner_slot = 0
	var view: BotWorldView = BotWorldView.new()
	view.team_id = 0
	controller._apply_incoming_specials(view, controller.get_meta(&"fake_match"))
	assert_eq(view.incoming_points.size(), 0, "a sliding enemy special and an own-team throw are ignored")
