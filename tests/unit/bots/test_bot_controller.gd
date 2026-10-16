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
	## item F: Match.circle_render_arrays()'s own shape
	## (parallel xs/zs/teams, disk-local) -- empty by default, so every
	## existing fixture that never sets this still gets the pre-existing
	## home-flags-only behaviour of _enemy_circle_centers().
	var circle_arrays_value: Dictionary = {
		"xs": PackedFloat32Array(),
		"zs": PackedFloat32Array(),
		"radii": PackedFloat32Array(),
		"teams": PackedInt32Array(),
	}

	## Match.gift_states()'s shape (id/phase/position).
	var gift_states_value: Array[Dictionary] = []

	func gift_states() -> Array[Dictionary]:
		return gift_states_value

	## Match.gift_slot_head()/request_use_gift_slot(): the QoL gift slot a bot
	## spends from. A spend empties the slot, like the real one.
	var gift_slot_heads: Dictionary = {}
	var use_gift_slot_calls: Array[int] = []

	func gift_slot_head(slot_id: int) -> StringName:
		return gift_slot_heads.get(slot_id, &"") as StringName

	func request_use_gift_slot(slot_id: int) -> bool:
		use_gift_slot_calls.append(slot_id)
		gift_slot_heads.erase(slot_id)
		return true

	var request_place_calls: Array[Dictionary] = []
	var request_throw_calls: Array[Dictionary] = []
	## review fix regression: lets a test make every
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

	## the slot's remaining block-timer seconds (large = never the limit).
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

	## optional mode goal provider (a Callable slot -> BotModeGoal).
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


## item C: writes a known, fixed rotation onto a Field's own
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
	# these tests assert the decision pipeline, not the release hold.
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
	assert_eq(match_ref.request_place_calls.size(), 1, "spec 1.9: bots keep playing in sudden death")


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


## Design rule: "two BotControllers with different think_phase_jitter_s
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


## review fix regression, MINOR: with no backoff, a rejected
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


# --- claim landed gifts, use held gifts promptly -------------

## Only a landed gift, or a falling one that lands within
## BotEvalTuning.air_gift_horizon_s, reaches the think's world view.
func test_landed_and_imminent_gifts_reach_the_think_world_view() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	var landed_at: Vector2 = Vector2(3.0, 4.0)
	var landing_soon_at: Vector2 = Vector2(-5.0, 2.0)
	var landing_late_at: Vector2 = Vector2(6.0, -6.0)
	var states: Array[Dictionary] = [
		{"id": 1, "phase": MatchGifts.LANDED, "position": landed_at},
		{
			"id": 2, "phase": MatchGifts.FALLING, "position": landing_soon_at,
			"origin": Vector3(-5.0, 10.0, 2.0), "landing": Vector3(-5.0, 0.0, 2.0), "elapsed": 100.0,
		},
		{
			"id": 3, "phase": MatchGifts.FALLING, "position": landing_late_at,
			"origin": Vector3(6.0, 500.0, -6.0), "landing": Vector3(6.0, 0.0, -6.0), "elapsed": 0.0,
		},
	]
	match_ref.gift_states_value = states
	var controller: BotController = _make_controller(field, match_ref, BotControllerFakeNet.new())
	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	Events.feed_block_issued.emit(0, &"cube", &"")

	_tick_until_request(controller, match_ref)

	var gifts: PackedVector2Array = controller._special_view.gifts
	assert_eq(gifts.size(), 2, "the landed gift and the one about to land, not the one minutes from landing")
	assert_true(gifts.has(landed_at), "a landed gift is a target")
	assert_true(gifts.has(landing_soon_at), "a gift landing within the horizon is a target")
	assert_false(gifts.has(landing_late_at), "a gift still far from landing is not")


## A freshly fed gift piece is spent after gift_use_delay_s, not the full
## reaction delay.
func test_a_held_special_shortens_the_reaction_delay_to_gift_use_delay_s() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	var controller: BotController = _make_controller(field, match_ref, BotControllerFakeNet.new())
	controller.tuning.gift_use_delay_s = 0.05
	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)

	Events.feed_block_issued.emit(0, &"cube", &"")
	assert_gt(controller._countdown, controller.tuning.gift_use_delay_s, "fixture: an ordinary piece waits the full reaction delay")

	match_ref.held_specials[0] = &"anvil"
	Events.feed_block_issued.emit(0, &"cube", &"")
	assert_almost_eq(controller._countdown, controller.tuning.gift_use_delay_s, 0.0001, "a held gift waits only gift_use_delay_s")


## A gift sitting in the gift slot is spent through request_use_gift_slot once
## the reaction delay has run, instead of thinking about an ordinary placement.
func test_a_slotted_gift_is_spent_through_request_use_gift_slot_not_placed() -> void:
	var field: Field = _make_field()
	var match_ref: BotControllerFakeMatch = _make_ready_match(0)
	match_ref.gift_slot_heads[0] = &"anvil"
	var controller: BotController = _make_controller(field, match_ref, BotControllerFakeNet.new())
	controller.setup(0, MatchConfig.AiDifficulty.NORMAL, field, null)
	Events.feed_block_issued.emit(0, &"cube", &"")

	_tick(controller, 5)
	assert_eq(match_ref.use_gift_slot_calls.size(), 0, "not before the reaction delay has run")

	var frames: int = 5
	while match_ref.use_gift_slot_calls.is_empty() and frames < 200:
		controller._physics_process(1.0 / 60.0)
		frames += 1

	assert_eq(match_ref.use_gift_slot_calls, [0], "the bot spends its slotted gift exactly once, for its own slot")
	assert_eq(match_ref.request_place_calls.size(), 0, "and places nothing in the frame it spent it")


# --- staggered release ---


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


# --- BotController._apply_weather (host live weather -> view) ---

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


# --- _apply_incoming_specials scene path ---------------------
