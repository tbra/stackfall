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

	var request_place_calls: Array[Dictionary] = []
	var request_throw_calls: Array[Dictionary] = []

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

	func request_place(
		slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion, auto_drop: bool, feed_seq_arg: int = -1
	) -> StringName:
		request_place_calls.append({
			"slot_id": slot_id, "origin": origin, "orientation_index": orientation_index,
			"free_quat": free_quat, "auto_drop": auto_drop, "feed_seq": feed_seq_arg,
		})
		return PlacementRules.REASON_OK

	func request_throw(
		slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion, velocity: Vector3, feed_seq_arg: int = -1
	) -> StringName:
		request_throw_calls.append({
			"slot_id": slot_id, "origin": origin, "orientation_index": orientation_index,
			"free_quat": free_quat, "velocity": velocity, "feed_seq": feed_seq_arg,
		})
		return PlacementRules.REASON_OK


class BotControllerFakeNet:
	var is_host_value: bool = true

	func is_host() -> bool:
		return is_host_value


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
