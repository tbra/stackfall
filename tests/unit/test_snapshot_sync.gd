extends GutTest
## net/SnapshotSync.gd's host -> client disk-state apply path (Bontago-1en.27,
## spec 3.4 "Disk state: tilt quaternion and position offset, sent every
## snapshot"). Before this fix, the client half of that sentence was never
## true: client_tick() decoded a snapshot's disk pose into disk_position()/
## disk_rotation() and stopped there -- nothing ever wrote it into a client's
## Field -- so the host's disc tilted under Anvil/Propeller/Earthquake while
## every client saw a level one.
##
## SnapshotSync has no class_name (it is an autoload), so these tests
## instantiate the script directly, the same way test_snapshot_wire.gd's own
## `_sync` does. No real peer or FakeNet is needed: build_snapshot() (host
## encode) and receive_packet() (client decode + apply) are already exactly
## the host -> wire -> client path a real RPC would carry, so feeding one
## instance's encoded bytes straight into a second instance's receive_packet()
## is a genuine two-peer round trip of the wire format itself.

const TICK: float = 1.0 / 60.0

## PhysicsCallDriver (tests/unit/support/PhysicsCallDriver.gd) gets a call
## into a genuine physics step. Needed both for tilting the host (Field's own
## _physics_process(), driven for real via wait_physics_frames() below,
## already does this) and for driving the client's SnapshotSync.client_tick():
## apply_replicated_pose() writes global_transform on an AnimatableBody3D with
## sync_to_physics = true (spec 3.5), which game/Field.gd's set_tilt_enabled()
## DECISION documents as only accepting writes made through an actual physics
## step -- calling client_tick() as a bare synchronous test call silently
## reverts the write, which would make this file's assertions compare two
## untilted (identity) transforms and pass for the wrong reason. Review NIT
## (Bontago-1en.27): this used to be a private inner class identical to
## tests/unit/test_field_tilt.gd's own.

var _config: NetConfig = preload("res://config/net_config.tres")
var _map: MapDef = null
var _host_field: Field = null
var _client_field: Field = null
var _client_sync: Node = null
var _client_registry: BlockRegistry = null
var _previous_net_mode: int = Net.Mode.OFFLINE
var _previous_joined_accepted: bool = false


func _small_map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_snapshot_sync_tilt"
	map_def.field_radius = 6.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	return map_def


func before_each() -> void:
	_map = _small_map()

	_host_field = Field.new()
	_host_field.map_def = _map
	add_child_autofree(_host_field)
	_host_field.set_tilt_enabled(true)

	_client_field = Field.new()
	_client_field.map_def = _map
	add_child_autofree(_client_field)
	# autoload/match/MatchLifecycle.gd's _apply_tilt_mode() runs on the host
	# and on a client alike (it cannot tell them apart) -- a client's own
	# Field spring is "enabled" too, which is exactly the state
	# apply_replicated_pose() has to suppress.
	_client_field.set_tilt_enabled(true)

	_client_registry = autofree(BlockRegistry.new())
	add_child_autofree(_client_registry)
	_client_sync = (load("res://net/SnapshotSync.gd") as GDScript).new() as Node
	add_child_autofree(_client_sync)
	_client_sync.call("set_disk", _client_field)
	_client_sync.call("begin_match", _client_registry, _map)

	# client_tick() no-ops unless Net.is_client() -- flip the real autoload's
	# mode directly (test_net_session.gd's own tests build a *separate* Net
	# instance for this; SnapshotSync.gd reads the live `Net` autoload by
	# name, so there is no injection seam here, and poking the live one is
	# the smaller change). _joined_accepted must go along with it: Net's own
	# _process() runs every frame regardless of how _mode got set, and its
	# Mode.CLIENT branch calls _fail_join() -- which flips _mode back to
	# OFFLINE -- the moment `now > _join_deadline`, which a bare _mode flip
	# with no real handshake leaves permanently true. Restored in after_each
	# so neither leaks into another test in the same run.
	_previous_net_mode = Net._mode
	_previous_joined_accepted = Net._joined_accepted
	Net._mode = Net.Mode.CLIENT
	Net._joined_accepted = true


func after_each() -> void:
	if _client_sync != null and is_instance_valid(_client_sync):
		_client_sync.call("end_match")
	Net._mode = _previous_net_mode
	Net._joined_accepted = _previous_joined_accepted
	_host_field = null
	_client_field = null
	_client_sync = null
	_client_registry = null


func _bounds() -> AABB:
	return _config.position_bounds(_map)


## One host -> client fragment carrying `disk_transform` and no bodies, the
## same shape host_tick() sends once FLAG_DISK_STATE is set (every snapshot).
func _snapshot_packet(sequence: int, host_time_ms: int, disk_transform: Transform3D) -> PackedByteArray:
	var encoder: Node = (load("res://net/SnapshotSync.gd") as GDScript).new() as Node
	var flag_disk: int = int(
		(load("res://net/SnapshotSync.gd") as GDScript).get_script_constant_map()["FLAG_DISK_STATE"]
	)
	var packets: Array = encoder.call(
		"build_snapshot", sequence, host_time_ms, flag_disk, [], disk_transform, _bounds(), _config
	) as Array
	encoder.free()
	return packets[0] as PackedByteArray


## Ticks the host's own real _physics_process() -- a genuine engine physics
## step, since _host_field is a live child of the test's tree -- so its
## spring-driven global_transform (not just its internal tilt_vector()) is
## trustworthy to read afterwards.
func _tilt_host(direction: Vector2, magnitude: float, ticks: int) -> void:
	_host_field.apply_tilt_impulse(direction, magnitude)
	await wait_physics_frames(ticks)


## One host -> client fragment carrying a single body record and no disk
## state -- the shape host_tick() sends for a settled/moving block (see
## SnapshotSync._select_bodies()/_encode_body()), used below to prove the
## client's own "contributing to territory influence" glow
## (Block.set_contributing_visual()) follows the wire's `sleeping` flag
## rather than this body's own (inert, frozen-kinematic) sleeping_state_changed
## (Bontago-xtq.27 fix round, review MAJOR).
func _body_snapshot_packet(
	sequence: int, host_time_ms: int, net_id: int, position: Vector3, rotation: Quaternion, sleeping: bool
) -> PackedByteArray:
	var encoder: Node = (load("res://net/SnapshotSync.gd") as GDScript).new() as Node
	var packets: Array = encoder.call(
		"build_snapshot", sequence, host_time_ms, 0,
		[{"net_id": net_id, "position": position, "rotation": rotation, "sleeping": sleeping}],
		Transform3D.IDENTITY, _bounds(), _config
	) as Array
	encoder.free()
	return packets[0] as PackedByteArray


## Feeds `packet` to the client SnapshotSync and runs exactly one client_tick()
## through a genuine physics step (see PhysicsCallDriver's own doc comment).
func _deliver_to_client(packet: PackedByteArray) -> void:
	var driver: PhysicsCallDriver = PhysicsCallDriver.new()
	driver.callable = func() -> void:
		_client_sync.call("receive_packet", packet)
		_client_sync.call("client_tick", TICK)
	add_child_autofree(driver)
	await wait_physics_frames(1)


# --- The apply path -----------------------------------------------------

func test_the_client_field_tilts_to_match_the_hosts_tilt_after_a_snapshot() -> void:
	await _tilt_host(Vector2(1.0, 0.0), 0.5, 30)
	assert_gt(_host_field.tilt_vector().length(), 0.0, "fixture: the host actually tilted")
	assert_gt(
		_host_field.global_transform.basis.get_rotation_quaternion().angle_to(Quaternion.IDENTITY),
		deg_to_rad(0.1),
		"fixture: the host's transform genuinely reflects the tilt, not just tilt_vector()"
	)
	assert_eq(_client_field.tilt_vector(), Vector2.ZERO, "fixture: the client starts level")

	var packet: PackedByteArray = _snapshot_packet(1, 1000, _host_field.global_transform)
	await _deliver_to_client(packet)

	assert_lt(
		_client_field.global_transform.basis.get_rotation_quaternion().angle_to(
			_host_field.global_transform.basis.get_rotation_quaternion()
		),
		deg_to_rad(0.1),
		"the client Field's rotation matches the host's after one snapshot"
	)
	assert_gt(
		_client_field.tilt_vector().length(), 0.0,
		"tilt_vector() on the client reflects the replicated tilt"
	)


func test_the_client_field_ignores_its_own_impulses_once_mirroring() -> void:
	await _tilt_host(Vector2(1.0, 0.0), 0.5, 30)
	var packet: PackedByteArray = _snapshot_packet(1, 1000, _host_field.global_transform)
	await _deliver_to_client(packet)
	var mirrored: Quaternion = _client_field.global_transform.basis.get_rotation_quaternion()

	# Nothing calls apply_tilt_impulse() on a client's own Field in real play
	# (specials simulate host-side only) -- but if something did, the mirror
	# must not drift on its own between snapshots. Real physics frames again:
	# it is _client_field's own _physics_process() (dispatched for real by
	# the engine here) that must skip _update_tilt() while mirrored.
	_client_field.apply_tilt_impulse(Vector2(0.0, 1.0), 5.0)
	await wait_physics_frames(10)

	assert_lt(
		_client_field.global_transform.basis.get_rotation_quaternion().angle_to(mirrored),
		deg_to_rad(0.001),
		"the client Field does not drift on its own once it is mirroring"
	)


func test_the_host_field_is_unaffected_by_the_client_apply_path() -> void:
	await _tilt_host(Vector2(1.0, 0.0), 0.5, 30)
	var before: Quaternion = _host_field.global_transform.basis.get_rotation_quaternion()

	# Snapshots only ever get applied to the client's own Field
	# (SnapshotSync.set_disk(_client_field) above); ticking the host's own
	# spring on afterwards must still behave exactly as it did before any of
	# this package existed.
	var packet: PackedByteArray = _snapshot_packet(1, 1000, _host_field.global_transform)
	await _deliver_to_client(packet)
	await wait_physics_frames(1)

	assert_lt(
		_host_field.global_transform.basis.get_rotation_quaternion().angle_to(before),
		deg_to_rad(5.0),
		"the host's own spring keeps ticking normally (a small further decay is fine, a jump is not)"
	)
	assert_false(_host_field._mirrored, "the host Field is never switched into mirror mode")


## M6 B5 (spec 2.1/2.7, Bontago-keo.11 ENet check): PHYSICAL_BALANCE feeds a
## continuous per-tick torque into the host's own tilt spring (Field.
## _physical_balance_torque_accel(), config/TiltTuning.gd's
## physical_balance_torque_gain DECISION) rather than a one-shot
## apply_tilt_impulse() -- so unlike every test above, the host's tilt never
## settles onto one fixed value between snapshots, it keeps easing toward its
## equilibrium lean the whole time. Replication itself is mode-agnostic
## (apply_replicated_pose()/SnapshotSync read only the host's transform, never
## tilt_mode), so this proves the client keeps tracking that moving target
## across two separate snapshots, not just a single frozen pose.
func test_the_client_field_mirrors_the_hosts_continuous_physical_balance_tilt() -> void:
	# Same host BlockRegistry wiring MatchLifecycle._apply_tilt_mode() performs
	# for TiltMode.PHYSICAL_BALANCE (tests/unit/test_field_tilt.gd's own
	# _make_registry() pattern) -- built here, not in before_each, so every
	# other test in this file keeps its SPECIALS_ONLY-shaped host untouched.
	var host_registry: BlockRegistry = BlockRegistry.new()
	add_child_autofree(host_registry)
	host_registry.configure(_host_field, _map)
	_host_field.set_registry(host_registry)
	_host_field.set_physical_balance_enabled(true)

	# A settled off-center block, same fixture as test_field_tilt.gd's
	# _settled_block_at(): frozen so it settles immediately, its own weight is
	# what PHYSICAL_BALANCE turns into the host's continuous torque.
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
	var block: Block = BlockFactory.build(shape, tuning, 0)
	_host_field.add_child(block)
	autofree(block)
	block.freeze = true
	block.global_position = Vector3(2.0, 0.5, 0.0)
	Events.block_placed.emit(block, shape.id)

	var settle_ticks: int = int(ceil(tuning.sleep_settle_time * Engine.physics_ticks_per_second)) + 5
	await wait_physics_frames(settle_ticks)

	# First snapshot, taken while the spring is still easing toward its
	# torque-driven equilibrium (config/TiltTuning.gd's DECISION: several
	# return_time_constant_s pass before it is truly steady). 20 ticks (not
	# just a handful) keeps host_tilt_1 comfortably above float noise given
	# this mode's tuned (small, single-block) torque_gain.
	await wait_physics_frames(20)
	var host_tilt_1: Vector2 = _host_field.tilt_vector()
	assert_gt(host_tilt_1.length(), 0.0, "fixture: PHYSICAL_BALANCE actually tilted the host")

	var packet_1: PackedByteArray = _snapshot_packet(1, 1000, _host_field.global_transform)
	await _deliver_to_client(packet_1)
	assert_almost_eq(
		_client_field.global_transform.basis.get_rotation_quaternion().angle_to(
			_host_field.global_transform.basis.get_rotation_quaternion()
		),
		0.0, 0.001,
		"the client mirrors the host's first PHYSICAL_BALANCE snapshot"
	)
	assert_gt(
		_client_field.tilt_vector().length(), 0.0,
		"the client's own tilt_vector() reflects a non-zero replicated PHYSICAL_BALANCE tilt"
	)

	# A second, later snapshot: PHYSICAL_BALANCE's continuous forcing means the
	# host's tilt has moved again by now, not held at host_tilt_1 forever --
	# and the client must follow it there too. 200 more ticks gives a clearly
	# distinct float, again well clear of noise at this mode's tuned gain.
	await wait_physics_frames(200)
	var host_tilt_2: Vector2 = _host_field.tilt_vector()
	assert_ne(
		host_tilt_2, host_tilt_1,
		"fixture: the host's PHYSICAL_BALANCE tilt keeps changing between snapshots (continuous, not one-shot)"
	)

	var packet_2: PackedByteArray = _snapshot_packet(2, 1500, _host_field.global_transform)
	await _deliver_to_client(packet_2)
	assert_almost_eq(
		_client_field.global_transform.basis.get_rotation_quaternion().angle_to(
			_host_field.global_transform.basis.get_rotation_quaternion()
		),
		0.0, 0.001,
		"the client mirrors the host's second, changed PHYSICAL_BALANCE snapshot"
	)


# --- Bontago-xtq.27 fix round (review MAJOR): a client's own "contributing" --
# --- glow must follow the wire, not this body's own (inert on a client) -----
# --- sleeping_state_changed ---------------------------------------------------

## Before this fix round, BlockFactory.build() wrote Block.set_contributing_
## visual() straight from this body's own `sleeping`/sleeping_state_changed --
## which only ever reflects reality on whichever peer runs physics for this
## body. A client's synced blocks are frozen kinematic (SnapshotSync.
## freeze_body(), spec 3.4) and never sleep for real, so a client never saw
## the settled glow at all. net/Interpolator.gd now threads the newest
## buffered sample's own `sleeping` flag through sample_at_render_time(), and
## client_tick() calls Block.set_contributing_visual() with it every tick,
## the same seam BlockFactory.build()'s own sleeping_state_changed connection
## writes through on the host.
func test_a_clients_settled_glow_follows_the_wires_sleeping_flag() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
	var block: Block = BlockFactory.build(shape, tuning, 0)
	add_child_autofree(block)
	Events.block_placed.emit(block, shape.id)
	assert_gt(block.net_id, 0, "fixture: the client registry allocated a net_id")
	assert_false(block.is_contributing_visual(), "fixture: a fresh block starts non-contributing")

	var packet_asleep: PackedByteArray = _body_snapshot_packet(
		1, 1000, block.net_id, Vector3.ZERO, Quaternion.IDENTITY, true
	)
	await _deliver_to_client(packet_asleep)
	assert_true(
		block.is_contributing_visual(),
		"a sleeping=true body record in the wire snapshot lights the client's glow, not just the host's own physics"
	)

	var packet_awake: PackedByteArray = _body_snapshot_packet(
		2, 1033, block.net_id, Vector3(0.1, 0.0, 0.0), Quaternion.IDENTITY, false
	)
	await _deliver_to_client(packet_awake)
	assert_false(
		block.is_contributing_visual(),
		"and a later sleeping=false sample turns it back off"
	)


# --- The 2-sample bracket: blend, ordering, extrapolation, decay -----------
#
# Bontago-1en.27 review SHOULD-FIX 2: every test above delivers exactly one
# snapshot, so the bracket itself -- lerp/slerp between two samples,
# rejecting a late/duplicate one, extrapolating past the newest for at most
# config.max_extrapolation_ms then holding, and converging rather than
# snapping once a hold/extrapolation ends -- had zero coverage. These reach
# into _client_sync's private bracket/convergence state through .get()/.call()
# (it has no class_name, so it is typed Node and has no static members to
# read directly) and net/Interpolator.gd's own render_time_ms through a
# plain property write on the real Interpolator instance interpolator()
# hands back (that one does have a class_name, so a cast makes it a normal
# typed write) -- the same white-box pattern test_field_tilt.gd already uses
# for _mirrored, applied here so render time can be pinned exactly rather
# than fought over with the adaptive clock-chase real client_tick() calls
# drive it with.

func _set_render_time_ms(ms: float) -> void:
	var interp: Interpolator = _client_sync.call("interpolator") as Interpolator
	interp._render_time_ms = ms


func _disk_pose() -> Dictionary:
	return _client_sync.call("_disk_pose_at_render_time") as Dictionary


func test_disk_pose_blends_between_two_bracketing_samples() -> void:
	var tilt_a: Basis = Basis(Vector3.RIGHT, deg_to_rad(2.0))
	var tilt_b: Basis = Basis(Vector3.RIGHT, deg_to_rad(8.0))
	_client_sync.call(
		"receive_packet", _snapshot_packet(1, 1000, Transform3D(tilt_a, Vector3.ZERO))
	)
	_client_sync.call(
		"receive_packet", _snapshot_packet(2, 1033, Transform3D(tilt_b, Vector3(1.0, 0.0, 0.0)))
	)

	_set_render_time_ms(1016.5) # strictly mid-bracket (1000 .. 1033)
	var mid: Dictionary = _disk_pose()
	assert_true(bool(mid["ok"]), "a two-sample bracket is drawable")
	var mid_x: float = (mid["position"] as Vector3).x
	assert_gt(mid_x, 0.001, "the blend is not equal to the older endpoint")
	assert_lt(mid_x, 0.999, "the blend is not equal to the newer endpoint")
	var mid_rotation: Quaternion = mid["rotation"] as Quaternion
	assert_gt(
		mid_rotation.angle_to(tilt_a.get_rotation_quaternion()), deg_to_rad(0.01),
		"the blended tilt is not equal to the older endpoint"
	)
	assert_gt(
		mid_rotation.angle_to(tilt_b.get_rotation_quaternion()), deg_to_rad(0.01),
		"the blended tilt is not equal to the newer endpoint"
	)

	_set_render_time_ms(1008.25) # quarter-way
	var quarter_x: float = (_disk_pose()["position"] as Vector3).x
	_set_render_time_ms(1024.75) # three-quarters
	var three_quarter_x: float = (_disk_pose()["position"] as Vector3).x
	assert_lt(quarter_x, mid_x, "the blend is monotone across the bracket")
	assert_lt(mid_x, three_quarter_x, "the blend is monotone across the bracket")


func test_disk_bracket_rejects_duplicate_and_out_of_order_packets() -> void:
	_client_sync.call(
		"receive_packet",
		_snapshot_packet(1, 1000, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(2.0)), Vector3.ZERO))
	)
	_client_sync.call(
		"receive_packet",
		_snapshot_packet(
			2, 1033, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(8.0)), Vector3(1.0, 0.0, 0.0))
		)
	)
	var next_time_before: int = int(_client_sync.get("_disk_next_time_ms"))
	var next_position_before: Vector3 = _client_sync.get("_disk_next_position") as Vector3
	var prev_time_before: int = int(_client_sync.get("_disk_prev_time_ms"))

	# A duplicate of the newest fragment's host_time_ms -- the same snapshot's
	# fragment 0 delivered twice, or a re-sent packet.
	_client_sync.call(
		"receive_packet",
		_snapshot_packet(
			3, 1033, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(80.0)), Vector3(9.0, 9.0, 9.0))
		)
	)
	assert_eq(
		int(_client_sync.get("_disk_next_time_ms")), next_time_before,
		"a duplicate host_time_ms leaves the bracket unchanged"
	)
	assert_eq(_client_sync.get("_disk_next_position") as Vector3, next_position_before)

	# An out-of-order fragment, older than the newest already buffered.
	_client_sync.call(
		"receive_packet",
		_snapshot_packet(
			4, 1010, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(80.0)), Vector3(9.0, 9.0, 9.0))
		)
	)
	assert_eq(
		int(_client_sync.get("_disk_next_time_ms")), next_time_before,
		"an out-of-order fragment leaves the bracket unchanged"
	)
	assert_eq(int(_client_sync.get("_disk_prev_time_ms")), prev_time_before)


func test_disk_pose_extrapolates_within_the_cap_then_clamps_beyond_it() -> void:
	_client_sync.call(
		"receive_packet", _snapshot_packet(1, 1000, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	)
	_client_sync.call(
		"receive_packet",
		_snapshot_packet(2, 1033, Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, 0.0)))
	)

	# 50 ms past the newest sample, inside max_extrapolation_ms (100 ms).
	_set_render_time_ms(1033.0 + 50.0)
	var extrapolated_x: float = (_disk_pose()["position"] as Vector3).x
	assert_gt(
		extrapolated_x, 1.0 + 0.01,
		"less than max_extrapolation_ms past the newest sample extrapolates onward"
	)

	_set_render_time_ms(1033.0 + 150.0) # past the cap
	var capped_x: float = (_disk_pose()["position"] as Vector3).x
	_set_render_time_ms(1033.0 + 500.0) # further still
	var held_x: float = (_disk_pose()["position"] as Vector3).x
	assert_almost_eq(
		capped_x, held_x, 1e-4,
		"once ahead_ms passes max_extrapolation_ms the pose holds instead of continuing"
	)


func test_disk_pose_does_not_fully_snap_after_a_capped_stall_and_converges() -> void:
	# The magnitude assertions below read off *rotation* (angle_to()), not
	# position: _bounds() (config.position_bounds(), read from the tiny test
	# map's field_radius) quantizes any XZ position outside a few metres of
	# the disk's centre to its edge, which would silently substitute a much
	# smaller "materially different" position than the literal passed to
	# _snapshot_packet() and make this test assert against a target the wire
	# never actually carried. Rotation has no such bound.
	var tilt_a: Quaternion = Basis(Vector3.RIGHT, deg_to_rad(2.0)).get_rotation_quaternion()
	var tilt_b: Quaternion = Basis(Vector3.RIGHT, deg_to_rad(8.0)).get_rotation_quaternion()
	_client_sync.call(
		"receive_packet", _snapshot_packet(1, 1000, Transform3D(Basis(tilt_a), Vector3.ZERO))
	)
	_client_sync.call(
		"receive_packet",
		_snapshot_packet(2, 1033, Transform3D(Basis(tilt_b), Vector3(0.5, 0.0, 0.0)))
	)

	# Hold well past max_extrapolation_ms, latching _disk_was_clamped -- the
	# "dropped fragment at high tilt" SHOULD-FIX 1 describes.
	_set_render_time_ms(1033.0 + _config.max_extrapolation_ms + 200.0)
	var held: Dictionary = _disk_pose()
	assert_true(bool(held["ok"]))
	assert_true(bool(_client_sync.get("_disk_was_clamped")), "fixture: the hold is latched clamped")
	var held_rotation: Quaternion = held["rotation"] as Quaternion

	# The stall ends with a materially different sample: a big jump in tilt,
	# what the host kept simulating through the stall actually produced.
	var target_tilt: Quaternion = Basis(Vector3.RIGHT, deg_to_rad(80.0)).get_rotation_quaternion()
	_client_sync.call(
		"receive_packet",
		_snapshot_packet(3, 3000, Transform3D(Basis(target_tilt), Vector3(1.0, 0.0, 0.0)))
	)
	var raw_jump: float = held_rotation.angle_to(target_tilt)
	assert_gt(
		raw_jump, deg_to_rad(20.0), "fixture: the new sample's tilt really is far from the held pose"
	)

	# Land exactly on the new sample (ahead_ms == 0, not clamped): the
	# production client_tick() -> _disk_pose_at_render_time() transition path,
	# not the private method called standalone.
	_set_render_time_ms(3000.0)
	_client_sync.call("client_tick", TICK)
	var applied_rotation: Quaternion = _client_sync.get("_disk_last_rotation") as Quaternion
	assert_lt(
		applied_rotation.angle_to(held_rotation), deg_to_rad(0.5),
		"the tick right after the stall ends is continuous with the held tilt, not a jump to the target"
	)
	assert_gt(
		applied_rotation.angle_to(target_tilt), raw_jump * 0.9,
		"and is still far from the new target the instant the offset is seeded"
	)

	# The offset then decays every tick (client_tick() calls
	# _decay_disk_error() unconditionally). Render time is pinned here rather
	# than driven through more client_tick() calls -- the interpolator's own
	# adaptive clock-chase (already covered by test_interpolator.gd) would
	# otherwise also move the render clock and confound "did the offset decay"
	# with "did the render clock also drift", which is a separate question
	# from the one this test asks. Direct decay calls are still the production
	# method, exercised once already above through client_tick() itself.
	for _tick: int in range(40):
		_client_sync.call("_decay_disk_error", TICK * 1000.0)
	var converged_rotation: Quaternion = _disk_pose()["rotation"] as Quaternion
	assert_lt(
		converged_rotation.angle_to(target_tilt), raw_jump * 0.25,
		"the pose converges toward the new target tilt within a bounded number of ticks"
	)
	assert_gt(
		converged_rotation.angle_to(held_rotation), raw_jump * 0.5,
		"and has genuinely moved away from the stall's held tilt, not stuck there"
	)
