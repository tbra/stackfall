extends Node
## Host -> client rigid body state (spec 2.6 "Snapshots"), at
## NetConfig.snapshot_hz (30 Hz), as unreliable RPCs carrying a packed
## PackedByteArray on NetConfig.snapshot_channel.
##
## Registered as the `SnapshotSync` autoload, so the RPC's node path is
## /root/SnapshotSync on every instance and no scene structure has to match.
## **No `class_name`** — it would collide with the singleton name.
##
## An unreliable RPC on its own channel is how spec 2.6's "custom packets on
## their own channel ... tag each with a sequence number" is met while staying
## inside MultiplayerAPI (CLAUDE.md: gameplay code must never assume a
## transport). Steam's peer carries it unchanged.
##
## **Wire layout** lives in core/net/SnapshotWire.gd (version, header, flags,
## fragmentation); callers name SnapshotWire directly.
##
## **Client side** it owns net/Interpolator.gd: buffer, render 100 ms behind
## with a jitter-adaptive delay, extrapolate at most 100 ms, and write every
## synced body's transform in `_physics_process` — never `_process`, or the
## writes fight Godot's own physics interpolation (project.godot has
## physics_interpolation on).

## The channel, read from core/net/SnapshotWire.gd (the layout and the
## PACKET_VERSION rule are documented there). @rpc needs it as a compile-time
## constant on this script.
const SNAPSHOT_CHANNEL: int = SnapshotWire.SNAPSHOT_CHANNEL

@export var config: NetConfig = preload("res://config/net/net_config.tres")

# --- Shared state -----------------------------------------------------------

# DECISION: held as Node so this file names no game/ class; block_for_net_id is called dynamically.
var _registry: Node = null
var _bounds: AABB = AABB()
var _running: bool = false
## The session seam: bind_session() (or the bind_net() shim) sets it; see _session().
var _session_port: SessionPort = null
const NET_NODE_NAME: NodePath = ^"Net"
## The SessionPort methods this node calls (and NetFanout through it).
const SESSION_METHODS: PackedStringArray = ["is_host", "is_client", "is_offline", "report_stats"]

# --- Host state -------------------------------------------------------------

## instance id (int) -> Block, every body this instance has seen spawn.
##
## DECISION (net/SnapshotSync.gd): BlockRegistry exposes block_for_net_id() but
## no "every live body" accessor, and that registry file is not owned by this code path. Mirroring the set from Events.block_placed /
## Events.block_removed — the same bus BlockRegistry itself listens on — costs
## one Dictionary and keeps the package boundary intact. net_id is read at
## snapshot time, not at signal time, so the two handlers' order does not
## matter.
var _bodies: Dictionary = {}

## The resend decision for sleeping bodies: what each body looked like the last
## time it went out, and whether the disc moved. Rebuilt per match with the live config.
var _selector: SnapshotSelector = SnapshotSelector.new()

var _send_accumulator: float = 0.0
var _sequence: int = 0
var _host_clock_ms: float = 0.0

## The host's snapshot clock is the shared presentation time base. Clients use
## the same interpolated host timestamp as the disc, including join-in-progress.
func sky_cycle_seconds() -> float:
	if not _running:
		return 0.0
	var session: SessionPort = _session()
	if session.is_client():
		return maxf(_interpolator.render_time_ms(), 0.0) / 1000.0
	return _host_clock_ms / 1000.0
var _last_snapshot_bytes: int = 0
var _keyframe_cursor: int = 0
var _known_peer_count: int = 0
## Peer ids seen last tick (sorted); a new id forces a full snapshot even
## when another peer left in the same tick.
var _known_peers: PackedInt32Array = PackedInt32Array()
var _disk: Node3D = null

# --- Client state -----------------------------------------------------------

var _interpolator: Interpolator = null
var _pose: Interpolator.Pose = Interpolator.Pose.new()
var _last_noted_sequence: int = -1
var _stats_accumulator: float = 0.0

## Client-side disk pose smoothing (bracket, extrapolation, convergence); built
## per match so it always reads the live config.
var _disk_smoother: DiskPoseSmoother = null

## Seconds since begin_match(): the one time base the NetSim queue and the
## Interpolator's jitter estimate share. It has to be read at *arrival*, not
## accumulated from _physics_process's delta, or every packet in a tick would
## be stamped with the same time and the jitter estimate would measure the
## 60 Hz tick grid instead of the link.
var _clock_base_usec: int = 0

## This instance's own delay/drop queue for inbound snapshots.
##
## core/net/NetSim.gd: "the simulation lives one level up, in the two places
## that own their own traffic: net/SnapshotSync.gd runs every inbound snapshot
## packet through a NetSim ...; autoload/Net.gd runs outbound intents and
## cursors through one". Two places, two queues — draining Net's would take
## its outbound intents off it and hand them here as if they were packets.
## Settings are shared, the queue is not; see set_simulation().
var _sim: NetSim = null


# --- Lifecycle --------------------------------------------------------------

## Called by Match when a match starts, on both host and client. `registry` is
## the BlockRegistry that resolves net_id -> Block; `map_def` fixes the
## quantization bounds, so both ends must be handed the same one.
func begin_match(registry: Node, map_def: MapDef) -> void:
	end_match()
	_registry = registry
	_bounds = config.position_bounds(map_def)
	_selector = SnapshotSelector.new(config)
	_running = true
	_sequence = 0
	_host_clock_ms = 0.0
	_send_accumulator = 0.0
	_clock_base_usec = Time.get_ticks_usec()
	_stats_accumulator = 0.0
	_last_noted_sequence = -1
	_last_snapshot_bytes = 0
	_keyframe_cursor = 0
	_known_peer_count = 0
	_disk_smoother = DiskPoseSmoother.new(config)

	_interpolator = Interpolator.new(config)
	_interpolator.set_known_id_filter(_is_spawned)
	_sim = NetSim.new(config.sim_lag_ms, config.sim_jitter_ms, config.sim_loss)

	if not Events.block_placed.is_connected(_on_block_placed):
		Events.block_placed.connect(_on_block_placed)
	if not Events.block_removed.is_connected(_on_block_removed):
		Events.block_removed.connect(_on_block_removed)
	if not Events.block_replicated.is_connected(_on_block_replicated):
		Events.block_replicated.connect(_on_block_replicated)


## Stops sending and drops every buffer. Called when a match ends or the
## session closes.
func end_match() -> void:
	if Events.block_placed.is_connected(_on_block_placed):
		Events.block_placed.disconnect(_on_block_placed)
	if Events.block_removed.is_connected(_on_block_removed):
		Events.block_removed.disconnect(_on_block_removed)
	if Events.block_replicated.is_connected(_on_block_replicated):
		Events.block_replicated.disconnect(_on_block_replicated)
	_running = false
	_registry = null
	_bodies.clear()
	_selector.reset()
	if _disk_smoother != null:
		_disk_smoother.reset()
	_disk_smoother = null
	if _interpolator != null:
		_interpolator.clear()
	_interpolator = null
	if _sim != null:
		_sim.reset()
	_sim = null


func is_running() -> bool:
	return _running


## Host only: makes the next snapshot carry every body, the
## same thing a newly connected peer id triggers in host_tick(). net/MatchNet.gd
## calls it once a mid-match joiner acknowledges its world replay: the joiner
## connected (and was "new" here) before it had a world to apply snapshots to.
func request_full_snapshot() -> void:
	_selector.reset()


## The disk, so its tilt can ride every snapshot (spec 2.6 "Disk state"). Main
## hands it over when it builds the world, on the host (host_tick() reads its
## real global_transform via _disk_transform()) and on a client (client_tick()
## drives it via apply_replicated_pose()) alike.
func set_disk(disk: Node3D) -> void:
	_disk = disk


# --- Host side --------------------------------------------------------------

## Builds and sends this tick's snapshot, if 1/config.snapshot_hz has elapsed.
## Host only; a no-op on a client and offline. Selects bodies that are awake
## (`RigidBody3D.sleeping` is false), that moved past
## config.resend_position_epsilon / resend_angle_epsilon since they were last
## sent, or that are in this tick's slice of the keyframe rotation.
##
## **Awake here means the physics engine's sleep state, not the settled rule**
## (PhysicsTuning.sleep_* and BlockRegistry.is_settled). Those thresholds are
## deliberately looser and feed territory influence; confusing the two makes
## towers stutter or influence flicker.
func host_tick(delta: float) -> void:
	var session: SessionPort = _session()
	if not _running or session.is_client():
		return
	# DECISION: the snapshot clock also ticks in offline play;
	# only packet selection and sending require a network host.
	_host_clock_ms += delta * 1000.0
	if not session.is_host() or session.is_offline():
		return
	var peers: PackedInt32Array = _remote_peers()
	var peer_count: int = peers.size()
	if peer_count == 0:
		# Nobody to send to: skip selection, quantization and packing. Forget
		# what was "sent" so the first snapshot after a peer connects (join,
		# mid-match join, reconnect) carries every body, not just movers.
		_known_peer_count = 0
		_known_peers = PackedInt32Array()
		_selector.reset()
		_last_snapshot_bytes = 0
		_send_accumulator = 0.0
		return
	var has_new_peer: bool = false
	for peer_id: int in peers:
		if _known_peers.bsearch(peer_id) >= _known_peers.size() or _known_peers[_known_peers.bsearch(peer_id)] != peer_id:
			has_new_peer = true
			break
	if has_new_peer:
		_selector.reset()
		_send_accumulator = 1.0 / maxf(config.snapshot_hz, 1.0)
	_known_peer_count = peer_count
	_known_peers = peers
	_send_accumulator += delta
	var interval: float = 1.0 / maxf(config.snapshot_hz, 1.0)
	if _send_accumulator < interval:
		return
	# One snapshot per tick even after a long frame: catching up by sending two
	# at once would only make the client's jitter estimate worse.
	_send_accumulator = fmod(_send_accumulator, interval)

	var selection: Dictionary = _select_bodies()
	var bodies: Array = selection["bodies"] as Array
	var flags: int = SnapshotWire.FLAG_DISK_STATE
	if bool(selection["keyframe"]):
		flags |= SnapshotWire.FLAG_KEYFRAME

	_sequence = (_sequence + 1) % SnapshotWire.SEQUENCE_MODULUS
	var packets: Array[PackedByteArray] = SnapshotWire.build_snapshot(
		_sequence, int(_host_clock_ms), flags, bodies, _disk_transform(), _bounds, config
	)
	_last_snapshot_bytes = 0
	for packet: PackedByteArray in packets:
		_last_snapshot_bytes += packet.size()
	_remember_sent(bodies)

	for packet: PackedByteArray in packets:
		_send_packet(packet)

	session.report_stats(&"snapshot", {
		"snapshot_last_bytes": _last_snapshot_bytes,
		"snapshot_bodies": bodies.size(),
		"snapshot_fragments": packets.size(),
		"snapshot_sequence": _sequence,
	})


## Sleepers per snapshot needed to refresh `sleeping_count` of them once per
## config.keyframe_interval. Static so the benchmark and the tests can ask
## without a live match.
static func keyframe_slice_for(sleeping_count: int, net_config: NetConfig) -> int:
	if sleeping_count <= 0:
		return 0
	var ticks: float = maxf(net_config.keyframe_interval, 0.001) * maxf(net_config.snapshot_hz, 1.0)
	return maxi(1, int(ceil(float(sleeping_count) / maxf(ticks, 1.0))))


# --- Client side ------------------------------------------------------------

## Advances every synced body to the current render time. **Call from
## _physics_process only.** Client only.
func client_tick(delta: float) -> void:
	var session: SessionPort = _session()
	if not _running or not session.is_client() or _interpolator == null:
		return

	if _sim != null and not _sim.is_idle():
		for payload: Variant in _sim.drain(now()):
			_apply_packet(payload as PackedByteArray)

	_interpolator.advance(delta)
	if _disk_smoother != null:
		_disk_smoother.decay(delta * 1000.0)

	for net_id: int in _interpolator.active_ids():
		var block: BlockBody = _registry.call("block_for_net_id", net_id) as BlockBody if _registry != null else null
		if block == null or not is_instance_valid(block):
			continue
		freeze_body(block)
		if not _interpolator.pose_into(net_id, _pose):
			continue
		# Writing global_transform here and nowhere else is the whole trick:
		# physics_interpolation smooths this 30 Hz stream up to the display rate
		# by itself, and a write from _process would fight it. A body that comes
		# to rest drops out of active_ids() after this tick's write.
		block.global_transform = Transform3D(Basis(_pose.rotation), _pose.position)
		# The "contributing to territory influence" glow
		# (Block.set_contributing_visual()) is driven from here too: this body is
		# frozen kinematic (freeze_body() above) and never sleeps for real on a
		# client, so BlockFactory.build()'s sleeping_state_changed hook never
		# fires. The newest buffered sample's sleeping flag is applied every tick;
		# Block's own change-guard keeps identical values cheap.
		block.set_contributing_visual(_pose.sleeping)

	# the disk rides every snapshot the same way a body does
	# (spec 2.6 "Disk state ... sent every snapshot"), so it gets the same
	# render-time interpolation treatment here, on a client only -- a host
	# drives its own Field straight off Field's own tilt spring, never off
	# this. `_disk` is a plain Node3D so set_disk() stays decoupled from any
	# one node type; the cast is guarded because a headless test that never
	# calls set_disk() with a real Field (test_snapshot_wire.gd's pure wire
	# tests) must not have client_tick() throw.
	var field: FieldBody = _disk as FieldBody
	if field != null:
		var disk_pose: Dictionary = _disk_smoother.pose_at(_interpolator.render_time_ms())
		if bool(disk_pose["ok"]):
			field.apply_replicated_pose(
				disk_pose["position"] as Vector3, disk_pose["rotation"] as Quaternion
			)

	_stats_accumulator += delta
	var stats_interval: float = 1.0 / maxf(config.stats_hz, 0.1)
	if _stats_accumulator >= stats_interval:
		_stats_accumulator = 0.0
		session.report_stats(&"snapshot", {
			"snapshot_last_bytes": _last_snapshot_bytes,
			"interp_delay_ms": interpolation_delay_ms(),
			"loss_pct": measured_loss() * 100.0,
			"dropped_unknown": _interpolator.dropped_unknown_count(),
		})


## The adaptive interpolation delay in force right now, in milliseconds —
## config.base_interp_delay_ms plus jitter_multiplier x measured jitter,
## clamped. The debug overlay shows this.
func interpolation_delay_ms() -> float:
	return _interpolator.delay_ms() if _interpolator != null else config.base_interp_delay_ms


## Snapshots the client noticed were missing, as a fraction of those expected,
## measured from gaps in the sequence numbers. The overlay's "packet loss".
func measured_loss() -> float:
	return _interpolator.loss_fraction() if _interpolator != null else 0.0


## Puts one body into the state a client keeps every synced body in: kinematic
## freeze, so Jolt never integrates it and only the interpolator's writes move
## it (spec 2.6: "Clients set every synced RigidBody3D to freeze = true").
static func freeze_body(body: RigidBody3D) -> void:
	if body.freeze and body.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC:
		return
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.freeze = true
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO


# --- RPC --------------------------------------------------------------------

## Host -> clients. Unreliable on config.snapshot_channel; the sequence number
## in the payload is what makes late and duplicate delivery detectable.
@rpc("authority", "call_remote", "unreliable", SNAPSHOT_CHANNEL)
func net_snapshot(packet: PackedByteArray) -> void:
	receive_packet(packet)


## The RPC's body, reachable without a peer so a test can drive the whole
## client path. Unreliable traffic is droppable, which is what makes
## --sim-loss simulate a lossy link rather than break reliability.
func receive_packet(packet: PackedByteArray) -> void:
	if not _running or _interpolator == null:
		return
	# Droppable, because a snapshot is unreliable traffic: dropping it is the
	# whole point of --sim-loss, and doing it here rather than under ENet is
	# what keeps reliable RPCs reliable (core/net/NetSim.gd).
	if _sim != null and not _sim.is_idle():
		_sim.submit(packet, now(), true)
		return
	_apply_packet(packet)


## Seconds since begin_match(), on the client's arrival clock.
func now() -> float:
	return float(Time.get_ticks_usec() - _clock_base_usec) / 1000000.0


## Re-tunes the inbound-snapshot simulator, in the same units as
## Net.set_simulation(): `lag_ms` is one-way and `loss` is a fraction. Net
## should forward to this whenever its own simulator is retuned, so the debug
## overlay's sliders and --sim-lag / --sim-loss reach both directions.
func set_simulation(lag_ms: float, jitter_ms: float, loss: float) -> void:
	if _sim != null:
		_sim.configure(lag_ms, jitter_ms, loss)


# --- Internals --------------------------------------------------------------

func _apply_packet(packet: PackedByteArray) -> void:
	var fragment: Dictionary = SnapshotWire.decode_fragment(packet, _bounds)
	if fragment.is_empty():
		return

	var sequence: int = int(fragment["sequence"])
	var host_time_ms: int = int(fragment["host_time_ms"])
	# One note per snapshot, not per fragment (Interpolator.note_snapshot).
	if sequence != _last_noted_sequence:
		_last_noted_sequence = sequence
		_interpolator.note_snapshot(sequence, host_time_ms, now())

	if (int(fragment["flags"]) & SnapshotWire.FLAG_DISK_STATE) != 0:
		var disk_transform: Transform3D = fragment["disk_transform"] as Transform3D
		_disk_smoother.push_sample(
			host_time_ms, disk_transform.origin, disk_transform.basis.get_rotation_quaternion()
		)

	for entry: Variant in fragment["bodies"] as Array:
		var body: Dictionary = entry as Dictionary
		_interpolator.push_sample(
			int(body["net_id"]),
			host_time_ms,
			body["position"] as Vector3,
			body["rotation"] as Quaternion,
			bool(body["sleeping"])
		)


## The predicate Interpolator asks before buffering a sample: a net_id whose
## reliable spawn RPC has not landed yet is unknown, and its sample is dropped
## and counted (the spawn/snapshot race).
func _is_spawned(net_id: int) -> bool:
	if _registry == null:
		return true
	return _registry.call("block_for_net_id", net_id) != null


## The session every send and mode check goes through. Net binds itself in its
## _ready (bind_net, until the global wiring replaces it); an unbound instance (a
## test, or a call before Net._ready) falls back to the real Net autoload by path
## so no file edge to autoload/Net.gd exists.
func _session() -> SessionPort:
	if _session_port != null:
		return _session_port
	# Through the SceneTree root so an instance not (yet) in the tree resolves too.
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var net: Node = tree.root.get_node_or_null(NET_NODE_NAME) if tree != null else null
	if net == null:
		return null
	var port: SessionPort = SessionPort.new(net, SESSION_METHODS)
	if not port.is_valid():
		return null
	_session_port = port
	return port


## Binds the typed session. An invalid port (a session missing a method this node
## calls) is refused with an error and leaves the current binding alone.
func bind_session(port: SessionPort) -> bool:
	if port == null or not port.is_valid():
		push_error("SnapshotSync.bind_session: the session port is missing or invalid")
		return false
	_session_port = port
	return true


## Shim until the global wiring replaces Net's call (the one in Net._ready):
## wraps the session node in a SessionPort over just the methods used here.
func bind_net(net: Node) -> void:
	bind_session(SessionPort.new(net, SESSION_METHODS))


## The one network send (a seam so tests can count sends without a peer).
func _send_packet(packet: PackedByteArray) -> void:
	NetFanout.broadcast(self, _session(), &"net_snapshot", [packet])


## Sorted remote peer ids (empty without a multiplayer peer).
func _remote_peers() -> PackedInt32Array:
	if not multiplayer.has_multiplayer_peer():
		return PackedInt32Array()
	# a peer being kicked is not a snapshot target (and with only
	# such peers left there is nothing to select, quantize or send).
	var peers: PackedInt32Array = PackedInt32Array(NetFanout.targets(multiplayer, _session()))
	peers.sort()
	return peers


## {"bodies": Array, "keyframe": bool} for this tick.
func _select_bodies() -> Dictionary:
	var awake_or_moved: Array = []
	var sleepers: Array[BlockBody] = []
	var saw_freed: bool = false
	_selector.begin_tick(_disk_transform())

	# This loop visits every body every snapshot, so an unchanged sleeper costs
	# only its sleep flag and one needs_check: its pose is read (and its carrier
	# re-posed) only when it is awake, drift-tested or recorded.
	for held: Variant in _bodies.values():
		if not is_instance_valid(held):
			saw_freed = true
			continue
		var block: BlockBody = held as BlockBody
		var net_id: int = block.net_id
		if net_id <= 0:
			continue
		var sleeping: bool = block.net_sleeping()
		# SHORTCUT: a sleeping body that moved with no disc change and no sleep flip (a teleport or anchored-group pose edit that leaves it asleep) is resent only by its keyframe slice, upgrade when a playtest or the session-close soak shows a stale sleeper
		if sleeping and not _selector.needs_check(net_id, sleeping):
			sleepers.append(block)
			continue
		_refresh_carrier_pose(block)
		if not sleeping or _selector.moved_since_sent(
			net_id, block.global_position, block.global_basis.get_rotation_quaternion()
		):
			awake_or_moved.append(_record(block))
		else:
			sleepers.append(block)
	if saw_freed:
		_drop_freed_bodies()

	var slice: int = mini(keyframe_slice_for(sleepers.size(), config), sleepers.size())
	var keyframe: bool = slice > 0
	for step: int in range(slice):
		var block: BlockBody = sleepers[(_keyframe_cursor + step) % sleepers.size()]
		_refresh_carrier_pose(block)
		awake_or_moved.append(_record(block))
	if not sleepers.is_empty():
		_keyframe_cursor = (_keyframe_cursor + slice) % sleepers.size()

	return {"bodies": awake_or_moved, "keyframe": keyframe}


## An anchored group's followers must be posed from the disc of THIS tick before
## their pose is read (the carrier's own tick runs after this node). The carrier
## re-poses at most once per physics frame however many followers ask.
func _refresh_carrier_pose(block: BlockBody) -> void:
	var carrier: RigidBody3D = block.fused_carrier()
	if carrier != null and carrier.has_method(&"refresh_anchor_pose"):
		carrier.call(&"refresh_anchor_pose")


func _drop_freed_bodies() -> void:
	for key: Variant in _bodies.keys():
		if not is_instance_valid(_bodies[key]):
			_bodies.erase(key)


func _record(block: BlockBody) -> Dictionary:
	return {
		"net_id": block.net_id,
		"position": block.global_position,
		"rotation": block.global_basis.get_rotation_quaternion(),
		"sleeping": block.net_sleeping(),
	}


func _remember_sent(bodies: Array) -> void:
	for entry: Variant in bodies:
		var body: Dictionary = entry as Dictionary
		_selector.remember_sent(
			int(body["net_id"]),
			body["position"] as Vector3,
			body["rotation"] as Quaternion,
			bool(body["sleeping"])
		)


func _disk_transform() -> Transform3D:
	if _disk != null and is_instance_valid(_disk):
		return _disk.global_transform
	return Transform3D.IDENTITY


func _on_block_placed(block: RigidBody3D, _shape_id: StringName) -> void:
	_track(block)


func _on_block_replicated(block: RigidBody3D, _net_id: int) -> void:
	_track(block)
	var session: SessionPort = _session()
	if session.is_client():
		freeze_body(block)


func _track(block: RigidBody3D) -> void:
	var typed: BlockBody = block as BlockBody
	if typed == null:
		return
	_bodies[typed.get_instance_id()] = typed


func _on_block_removed(block: RigidBody3D, _reason: String) -> void:
	_bodies.erase(block.get_instance_id())
	var typed: BlockBody = block as BlockBody
	if typed == null:
		return
	_selector.forget(typed.net_id)
	if _interpolator != null:
		_interpolator.forget(typed.net_id)
