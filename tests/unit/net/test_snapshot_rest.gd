extends GutTest
## Client rest culling (net/Interpolator.gd + SnapshotSync.client_tick).
##
## A track is at rest once its newest sample is sleeping, the render clock is
## past that sample and its convergence offset has decayed. A resting track
## leaves Interpolator.active_ids(); a push_sample with an awake or moved sample
## brings it back. client_tick writes a resting body's transform once, on
## entering rest, and keeps the contributing glow following the sleeping flag.

const NET_ID: int = 7
const OTHER_ID: int = 8
const STEP: float = 1.0 / 60.0
const EPOCH_MS: int = 10000
const TICK_MS: int = 33
## Long enough for a 100 ms convergence offset to be gone.
const SETTLE_SECONDS: float = 3.0

var _config: NetConfig = null
var _interp: Interpolator = null
var _out: Interpolator.Pose = null


func before_each() -> void:
	_config = (preload("res://config/net/net_config.tres") as NetConfig).duplicate() as NetConfig
	_interp = Interpolator.new(_config)
	_out = Interpolator.Pose.new()


func _push(id: int, host_ms: int, position: Vector3, sleeping: bool) -> void:
	assert_true(_interp.push_sample(id, host_ms, position, Quaternion.IDENTITY, sleeping), "fixture: sample accepted")


## One client frame: advance the clock, then read every active pose the way
## client_tick does.
func _frame() -> void:
	_interp.advance(STEP)
	for id: int in _interp.active_ids():
		_interp.pose_into(id, _out)


func _frames(seconds: float) -> void:
	for _i: int in range(int(ceil(seconds / STEP))):
		_frame()


func _active(id: int = NET_ID) -> bool:
	return Array(_interp.active_ids()).has(id)


# --- Interpolator: entering and leaving rest ---------------------------------

func test_a_sleeping_track_leaves_active_ids_once_render_time_is_past_it() -> void:
	_push(NET_ID, EPOCH_MS, Vector3(1.0, 0.0, 0.0), true)
	assert_true(_active(), "a fresh track is active: render time is still behind its only sample")
	_frame()
	assert_true(_active(), "still behind the sample after one frame")
	_frames(SETTLE_SECONDS)
	assert_gt(_interp.render_time_ms(), float(EPOCH_MS), "fixture: render time passed the sample")
	assert_false(_active(), "past the sleeping sample with no offset: at rest")


func test_a_track_stays_active_until_render_time_reaches_its_sleeping_sample() -> void:
	_push(NET_ID, EPOCH_MS, Vector3.ZERO, false)
	_push(NET_ID, EPOCH_MS + TICK_MS, Vector3(1.0, 0.0, 0.0), true)
	_frame()
	while _interp.render_time_ms() < float(EPOCH_MS + TICK_MS):
		assert_true(_active(), "behind the newest sample at %.0f ms" % _interp.render_time_ms())
		_frame()
	_frames(SETTLE_SECONDS)
	assert_false(_active(), "once past it, and settled, it rests")


func test_an_awake_track_never_rests_however_late_render_time_runs() -> void:
	_push(NET_ID, EPOCH_MS, Vector3.ZERO, false)
	_push(NET_ID, EPOCH_MS + TICK_MS, Vector3(1.0, 0.0, 0.0), false)
	_frames(SETTLE_SECONDS)
	assert_true(_active(), "an awake newest sample keeps the track active (held extrapolation)")


func test_a_track_waits_for_its_convergence_offset_to_decay_before_resting() -> void:
	# Stall past the extrapolation cap so the pose is held, then end the stall
	# with a sleeping sample elsewhere: the gap becomes a decaying offset.
	_push(NET_ID, EPOCH_MS, Vector3.ZERO, false)
	_push(NET_ID, EPOCH_MS + TICK_MS, Vector3(1.0, 0.0, 0.0), false)
	_frames(0.4)
	var rest_ms: int = EPOCH_MS + 500
	var rest_position: Vector3 = Vector3(5.0, 0.0, 0.0)
	_push(NET_ID, rest_ms, rest_position, true)
	_interp.pose_into(NET_ID, _out) # leaving the hold seeds the offset
	while _interp.render_time_ms() < float(rest_ms):
		_frame()
	assert_true(_active(), "render time is past the sleeping sample but the offset has not decayed")
	_frames(SETTLE_SECONDS)
	assert_false(_active(), "after the offset decayed it rests")
	assert_true(_interp.pose_into(NET_ID, _out), "a resting body still has a pose")
	assert_almost_eq(_out.position, rest_position, Vector3.ONE * 1e-3, "and it is exactly the sleeping sample")


func test_an_awake_sample_brings_a_resting_track_back() -> void:
	_push(NET_ID, EPOCH_MS, Vector3.ZERO, true)
	_frames(SETTLE_SECONDS)
	assert_false(_active(), "fixture: at rest")
	_push(NET_ID, EPOCH_MS + 5000, Vector3(0.0, 1.0, 0.0), false)
	assert_true(_active(), "an awake sample makes it active again")


func test_a_moved_sleeping_sample_brings_a_resting_track_back() -> void:
	_push(NET_ID, EPOCH_MS, Vector3.ZERO, true)
	_frames(SETTLE_SECONDS)
	assert_false(_active(), "fixture: at rest")
	_push(NET_ID, EPOCH_MS + 5000, Vector3(2.0, 0.0, 0.0), true)
	assert_true(_active(), "a sleeping sample at a new pose makes it active again")


func test_a_track_that_woke_rests_again_after_a_new_sleeping_sample() -> void:
	_push(NET_ID, EPOCH_MS, Vector3.ZERO, true)
	_frames(SETTLE_SECONDS)
	_push(NET_ID, EPOCH_MS + 5000, Vector3(0.0, 1.0, 0.0), false)
	_push(NET_ID, EPOCH_MS + 5000 + TICK_MS, Vector3(0.0, 1.5, 0.0), true)
	assert_true(_active(), "fixture: woke")
	_frames(SETTLE_SECONDS * 2.0)
	assert_false(_active(), "and rests again")


func test_active_ids_lists_only_the_tracks_that_are_not_at_rest() -> void:
	_push(NET_ID, EPOCH_MS, Vector3.ZERO, true)
	_push(OTHER_ID, EPOCH_MS, Vector3(3.0, 0.0, 0.0), false)
	_frames(SETTLE_SECONDS)
	assert_eq(Array(_interp.active_ids()), [OTHER_ID], "only the awake body is active")


func test_a_forgotten_track_is_not_active() -> void:
	_push(NET_ID, EPOCH_MS, Vector3.ZERO, false)
	assert_true(_active(), "fixture")
	_interp.forget(NET_ID)
	assert_false(_active(), "forget drops it")


func test_clear_drops_every_active_track() -> void:
	_push(NET_ID, EPOCH_MS, Vector3.ZERO, false)
	_interp.clear()
	assert_eq(_interp.active_ids().size(), 0, "nothing is active after clear")


# --- Interpolator.pose_into --------------------------------------------------

func test_pose_into_is_false_for_an_untracked_body_and_leaves_out_alone() -> void:
	_out.position = Vector3(9.0, 9.0, 9.0)
	assert_false(_interp.pose_into(NET_ID, _out), "no samples, no pose")
	assert_eq(_out.position, Vector3(9.0, 9.0, 9.0), "the caller's Pose is untouched")


func test_pose_into_reports_the_newest_samples_sleeping_flag_and_pose() -> void:
	_push(NET_ID, EPOCH_MS, Vector3.ZERO, false)
	_push(NET_ID, EPOCH_MS + TICK_MS, Vector3(1.0, 0.0, 0.0), false)
	_push(NET_ID, EPOCH_MS + TICK_MS * 2, Vector3(2.0, 0.0, 0.0), true)
	assert_true(_interp.pose_into(NET_ID, _out), "tracked")
	assert_true(_out.sleeping, "the newest sample's flag, whatever the render clock")
	_frames(SETTLE_SECONDS)
	assert_true(_interp.pose_into(NET_ID, _out), "tracked after settling")
	assert_almost_eq(_out.position, Vector3(2.0, 0.0, 0.0), Vector3.ONE * 1e-3, "settled on the newest pose")
	assert_true(_out.rotation.is_equal_approx(Quaternion.IDENTITY), "rotation too")
	assert_true(_out.sleeping, "still asleep")


func test_pose_into_reuses_one_pose_for_different_bodies() -> void:
	_push(NET_ID, EPOCH_MS, Vector3(1.0, 0.0, 0.0), false)
	_push(OTHER_ID, EPOCH_MS, Vector3(0.0, 4.0, 0.0), true)
	assert_true(_interp.pose_into(NET_ID, _out))
	assert_almost_eq(_out.position, Vector3(1.0, 0.0, 0.0), Vector3.ONE * 1e-4, "first body")
	assert_false(_out.sleeping, "first body is awake")
	assert_true(_interp.pose_into(OTHER_ID, _out))
	assert_almost_eq(_out.position, Vector3(0.0, 4.0, 0.0), Vector3.ONE * 1e-4, "second body overwrites it")
	assert_true(_out.sleeping, "and its flag")


func test_a_forgotten_body_has_no_pose() -> void:
	_push(NET_ID, EPOCH_MS, Vector3.ZERO, false)
	_interp.forget(NET_ID)
	assert_false(_interp.pose_into(NET_ID, _out), "forgotten")


# --- SnapshotSync.client_tick over a fake registry ---------------------------

## The one method SnapshotSync asks its registry for.
class FakeRegistry:
	extends Node
	var blocks: Dictionary = {}

	func block_for_net_id(net_id: int) -> Block:
		return blocks.get(net_id) as Block


var _sync: Node = null
var _registry: FakeRegistry = null
var _map: MapDef = null
var _block: Block = null
var _sequence: int = 0


func _start_client() -> void:
	_map = MapDef.new()
	_map.id = &"test_snapshot_rest"
	_map.field_radius = 6.0
	_map.cell_size = 1.0
	_map.disk_height = 1.0
	_map.territory_res = 32
	_registry = FakeRegistry.new()
	add_child_autofree(_registry)
	_block = BlockFactory.build(
		load("res://config/blocks/cube.tres") as BlockShape,
		load("res://config/physics/physics_tuning.tres") as PhysicsTuning,
		0
	)
	_block.net_id = NET_ID
	add_child_autofree(_block)
	_registry.blocks[NET_ID] = _block
	_sync = (load("res://net/SnapshotSync.gd") as GDScript).new() as Node
	add_child_autofree(_sync)
	_sync.call("bind_session", FakeSessionPort.new(FakeNet.client(0)))
	_sync.call("begin_match", _registry, _map)
	_sequence = 0


func _packet(host_ms: int, position: Vector3, sleeping: bool) -> PackedByteArray:
	_sequence += 1
	var bounds: AABB = _config.position_bounds(_map)
	return SnapshotWire.encode_fragment(
		_sequence, 0, 1, host_ms, 0,
		[{"net_id": NET_ID, "position": position, "rotation": Quaternion.IDENTITY, "sleeping": sleeping}],
		Transform3D.IDENTITY, bounds
	)


func _ticks(count: int) -> void:
	for _i: int in range(count):
		_sync.call("client_tick", STEP)


## Enough client ticks for render time to pass a sample and any offset to decay.
func _settle_ticks() -> void:
	_ticks(int(SETTLE_SECONDS / STEP))


func _distance(a: Transform3D, b: Vector3) -> float:
	return a.origin.distance_to(b)


func test_the_body_is_posed_at_its_sleeping_sample() -> void:
	_start_client()
	var rest_at: Vector3 = Vector3(2.0, 0.5, -1.0)
	_sync.call("receive_packet", _packet(EPOCH_MS, rest_at, true))
	_settle_ticks()
	assert_lt(_distance(_block.global_transform, rest_at), 0.05, "the body sits at the sleeper's pose")


func test_a_resting_bodys_transform_is_written_once() -> void:
	_start_client()
	var rest_at: Vector3 = Vector3(2.0, 0.5, -1.0)
	var elsewhere: Vector3 = Vector3(-3.0, 0.5, 2.0)
	_sync.call("receive_packet", _packet(EPOCH_MS, rest_at, true))
	_settle_ticks()
	assert_lt(_distance(_block.global_transform, rest_at), 0.05, "fixture: at rest at the sample")

	_block.global_transform = Transform3D(Basis(), elsewhere)
	_ticks(30)
	assert_lt(
		_distance(_block.global_transform, elsewhere), 0.001,
		"client_tick no longer rewrites a resting body"
	)


func test_an_awake_body_is_rewritten_every_tick() -> void:
	_start_client()
	var at: Vector3 = Vector3(2.0, 0.5, -1.0)
	_sync.call("receive_packet", _packet(EPOCH_MS, at, false))
	_settle_ticks()
	_block.global_transform = Transform3D(Basis(), Vector3(-3.0, 0.5, 2.0))
	_ticks(1)
	assert_lt(_distance(_block.global_transform, at), 0.05, "an awake body is posed again next tick")


func test_a_new_awake_sample_moves_a_resting_body_again() -> void:
	_start_client()
	var rest_at: Vector3 = Vector3(2.0, 0.5, -1.0)
	var elsewhere: Vector3 = Vector3(-3.0, 0.5, 2.0)
	_sync.call("receive_packet", _packet(EPOCH_MS, rest_at, true))
	_settle_ticks()
	_block.global_transform = Transform3D(Basis(), elsewhere)
	_ticks(5)
	assert_lt(_distance(_block.global_transform, elsewhere), 0.001, "fixture: resting, not rewritten")

	var moved_to: Vector3 = Vector3(4.0, 0.5, 4.0)
	_sync.call("receive_packet", _packet(EPOCH_MS + 3000, moved_to, false))
	_settle_ticks()
	# The awake track holds up to the extrapolation cap past its newest sample.
	assert_lt(_distance(_block.global_transform, moved_to), 0.5, "the new awake sample wakes the body and poses it")


func test_a_sleeping_sample_at_a_new_pose_moves_a_resting_body_again() -> void:
	_start_client()
	_sync.call("receive_packet", _packet(EPOCH_MS, Vector3(2.0, 0.5, -1.0), true))
	_settle_ticks()
	var moved_to: Vector3 = Vector3(-4.0, 0.5, 1.0)
	_sync.call("receive_packet", _packet(EPOCH_MS + 3000, moved_to, true))
	_settle_ticks()
	assert_lt(_distance(_block.global_transform, moved_to), 0.05, "the moved sleeper is posed at its new rest")


func test_the_body_is_frozen_kinematic_when_it_rests() -> void:
	_start_client()
	_sync.call("receive_packet", _packet(EPOCH_MS, Vector3(1.0, 0.5, 0.0), true))
	_settle_ticks()
	assert_true(_block.freeze, "a client body is frozen")
	assert_eq(_block.freeze_mode, RigidBody3D.FREEZE_MODE_KINEMATIC, "kinematically")


func test_the_contributing_glow_follows_the_sleeping_flag() -> void:
	_start_client()
	_sync.call("receive_packet", _packet(EPOCH_MS, Vector3(1.0, 0.5, 0.0), false))
	_settle_ticks()
	assert_false(_block.is_contributing_visual(), "an awake body does not glow")

	_sync.call("receive_packet", _packet(EPOCH_MS + 3000, Vector3(1.0, 0.5, 0.0), true))
	_settle_ticks()
	assert_true(_block.is_contributing_visual(), "a body that came to rest glows")

	_sync.call("receive_packet", _packet(EPOCH_MS + 6000, Vector3(1.0, 1.5, 0.0), false))
	_settle_ticks()
	assert_false(_block.is_contributing_visual(), "waking it clears the glow again")


func test_the_glow_is_set_for_a_body_that_rests_on_its_first_sample() -> void:
	_start_client()
	_sync.call("receive_packet", _packet(EPOCH_MS, Vector3(1.0, 0.5, 0.0), true))
	_settle_ticks()
	assert_true(_block.is_contributing_visual(), "a sleeping first sample lights the glow")
