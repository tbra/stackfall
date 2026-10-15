extends GutTest
## Bontago-1pi.55: block impacts are detected only by host physics
## (game/blocks/Block.gd) and replicated to clients by net/MatchNet.gd through
## core/net/ImpactWire.gd. A client re-emits Events.block_impacted /
## block_impacted_at, so Sfx/camera/rumble/dust need no network awareness; a
## client's frozen kinematic replicas never detect impacts of their own.

const MatchNetScript := preload("res://net/MatchNet.gd")

var _nodes: Array[MatchNetScript] = []
var _speeds: Array[float] = []
var _at: Array[Array] = []
var _speed_listener: Callable
var _at_listener: Callable


func before_each() -> void:
	_speeds = []
	_at = []
	_speed_listener = func(speed: float) -> void:
		_speeds.append(speed)
	_at_listener = func(speed: float, position: Vector3) -> void:
		_at.append([speed, position])
	Events.block_impacted.connect(_speed_listener)
	Events.block_impacted_at.connect(_at_listener)


func after_each() -> void:
	Events.block_impacted.disconnect(_speed_listener)
	Events.block_impacted_at.disconnect(_at_listener)
	for node: MatchNetScript in _nodes:
		if is_instance_valid(node):
			node.set_providers(null, null)
	_nodes.clear()
	Match.set_replicator(null)


func _make_net(fake: FakeNet) -> MatchNetScript:
	var node: MatchNetScript = MatchNetScript.new()
	node.set_process(false)
	# A private copy: the shipped net_config.tres is a shared preload, and some
	# tests below edit caps.
	node.config = node.config.duplicate() as NetConfig
	add_child_autofree(node)
	node.set_providers(fake, null)
	_nodes.append(node)
	return node


func _host() -> MatchNetScript:
	var node: MatchNetScript = _make_net(FakeNet.host({1: 0, 2: 1}, [0]))
	node.capture_impacts = true
	return node


func _client() -> MatchNetScript:
	var node: MatchNetScript = _make_net(FakeNet.client(1))
	node.impact_delay_override_ms = 0.0
	return node


func _batch(events: Array[Dictionary]) -> PackedByteArray:
	return ImpactWire.encode(events)


func _event(speed: float, position: Vector3, age_ms: int = 0) -> Dictionary:
	return {
		ImpactWire.KEY_SPEED: speed, ImpactWire.KEY_POSITION: position, ImpactWire.KEY_AGE_MS: age_ms
	}


func _decode(net: MatchNetScript, packet: PackedByteArray) -> Array[Dictionary]:
	return ImpactWire.decode(packet, net.config.impact_speed_max, net.config.pos_min_y, net.config.pos_max_y)


# --- Round trip ---------------------------------------------------------------

func test_host_impact_reaches_client_as_the_same_signals() -> void:
	var host: MatchNetScript = _host()
	var position: Vector3 = Vector3(1.234, 2.5, -3.456)
	Events.block_impacted_at.emit(6.5, position)
	var packet: PackedByteArray = host.flush_impacts(1000)
	assert_eq(packet.size(), ImpactWire.HEADER_BYTES + ImpactWire.EVENT_BYTES, "one event on the wire")
	host.capture_impacts = false
	_speeds.clear()
	_at.clear()

	var client: MatchNetScript = _client()
	client.receive_impacts(packet, 2000)
	assert_eq(_speeds.size(), 1, "client emits block_impacted once")
	assert_eq(_at.size(), 1, "client emits block_impacted_at once")
	assert_almost_eq(_speeds[0], 6.5, ImpactWire.SPEED_QUANTUM)
	assert_almost_eq(float(_at[0][0]), 6.5, ImpactWire.SPEED_QUANTUM)
	var got: Vector3 = _at[0][1] as Vector3
	assert_almost_eq(got.x, position.x, ImpactWire.POSITION_QUANTUM_M)
	assert_almost_eq(got.y, position.y, ImpactWire.POSITION_QUANTUM_M)
	assert_almost_eq(got.z, position.z, ImpactWire.POSITION_QUANTUM_M)
	assert_eq(client.impacts_emitted, 1)


# --- Coalescing and caps ----------------------------------------------------

func test_same_cell_impacts_coalesce_to_the_strongest() -> void:
	var host: MatchNetScript = _host()
	var base: Vector3 = Vector3(2.1, 3.1, 4.1)
	for i: int in range(50):
		host.collect_impact(1.0 + float(i % 17), base + Vector3(0.001 * float(i), 0.0, 0.0), 0)
	var events: Array[Dictionary] = _decode(host, host.flush_impacts(10))
	assert_eq(events.size(), 1, "one cell -> one event")
	assert_almost_eq(float(events[0][ImpactWire.KEY_SPEED]), 17.0, ImpactWire.SPEED_QUANTUM)


func test_sustained_flood_holds_the_per_second_cap() -> void:
	var host: MatchNetScript = _host()
	var cfg: NetConfig = host.config
	var interval_ms: int = int(1000.0 / cfg.impact_batch_hz)
	var per_window: Array[int] = [0, 0, 0]
	var total: int = 0
	var now_ms: int = 0
	while now_ms < 3000:
		for i: int in range(200):
			host.collect_impact(2.0 + float(i) * 0.05, Vector3(float(i % 20) * 2.0, 1.0, floorf(float(i) / 20.0) * 2.0), now_ms)
		var events: Array[Dictionary] = _decode(host, host.flush_impacts(now_ms))
		assert_true(events.size() <= cfg.impact_max_per_batch, "batch at %d ms within cap" % now_ms)
		per_window[int(float(now_ms) / 1000.0)] += events.size()
		total += events.size()
		now_ms += interval_ms
	for second: int in range(3):
		assert_true(per_window[second] <= cfg.impact_max_per_second + cfg.impact_max_per_batch,
			"second %d sent %d" % [second, per_window[second]])
	assert_true(total <= cfg.impact_max_per_second * 3 + cfg.impact_max_per_batch, "3 s total %d" % total)
	assert_true(total >= cfg.impact_max_per_second * 2, "the flood is throttled, not silenced (%d)" % total)


# --- Client validation --------------------------------------------------------

func test_malformed_batches_are_ignored() -> void:
	var client: MatchNetScript = _client()
	var good: PackedByteArray = _batch([_event(3.0, Vector3(0.0, 1.0, 0.0))])
	var bad_version: PackedByteArray = good.duplicate()
	bad_version[0] = ImpactWire.VERSION + 1
	var bad_count: PackedByteArray = good.duplicate()
	bad_count[1] = 2
	var zero_count: PackedByteArray = PackedByteArray([ImpactWire.VERSION, 0])
	var truncated: PackedByteArray = good.slice(0, good.size() - 1)
	var zero_speed: PackedByteArray = good.duplicate()
	zero_speed.encode_u16(ImpactWire.HEADER_BYTES + 6, 0)
	var too_fast: PackedByteArray = good.duplicate()
	too_fast.encode_u16(ImpactWire.HEADER_BYTES + 6, ImpactWire.SPEED_RAW_MAX)
	var too_low: PackedByteArray = _batch([_event(3.0, Vector3(0.0, client.config.pos_min_y - 5.0, 0.0))])
	var oversized: PackedByteArray = PackedByteArray()
	oversized.resize(ImpactWire.MAX_PACKET_BYTES + ImpactWire.EVENT_BYTES)
	var packets: Array[PackedByteArray] = [
		PackedByteArray(), bad_version, bad_count, zero_count, truncated, zero_speed, too_fast, too_low,
		oversized,
	]
	for packet: PackedByteArray in packets:
		client.receive_impacts(packet, 100)
	assert_eq(_speeds.size(), 0, "nothing from a malformed batch plays")
	assert_eq(client.impact_batches_rejected, packets.size())
	client.receive_impacts(good, 100)
	assert_eq(_speeds.size(), 1, "the well-formed control still plays")


## Bontago-1pi.55 review fix: one bad event inside a well-formed batch is
## skipped on its own; its neighbours still play.
func test_one_bad_event_does_not_silence_the_rest_of_the_batch() -> void:
	var client: MatchNetScript = _client()
	var high: float = client.config.pos_max_y + 20.0
	var low: float = client.config.pos_min_y - 20.0
	client.receive_impacts(_batch([
		_event(3.0, Vector3(0.0, 1.0, 0.0)),
		_event(4.0, Vector3(0.0, high, 0.0)),
		_event(5.0, Vector3(2.0, 1.0, 0.0)),
		_event(6.0, Vector3(0.0, low, 0.0)),
		_event(7.0, Vector3(4.0, 1.0, 0.0)),
	]), 100)
	assert_eq(_speeds.size(), 3, "the three in-range events play (got %s)" % [_speeds])
	assert_almost_eq(_speeds[0], 3.0, ImpactWire.SPEED_QUANTUM)
	assert_almost_eq(_speeds[1], 5.0, ImpactWire.SPEED_QUANTUM)
	assert_almost_eq(_speeds[2], 7.0, ImpactWire.SPEED_QUANTUM)
	assert_eq(client.impact_batches_rejected, 0, "the batch itself was fine")
	assert_eq(client.impact_events_dropped, 2, "the two out-of-volume events are counted")
	# A bad speed is per-event too.
	_speeds.clear()
	var bad_speed: PackedByteArray = _batch([_event(3.0, Vector3.ZERO), _event(3.0, Vector3(1.0, 1.0, 1.0))])
	bad_speed.encode_u16(ImpactWire.HEADER_BYTES + 6, 0)
	client.receive_impacts(bad_speed, 100)
	assert_eq(_speeds.size(), 1, "only the zero-speed event is skipped")


# --- Client caps and MTU bound ------------------------------------------------

# --- No client-side detection -------------------------------------------------

## The 1pi.52 probe: a frozen kinematic replica moved by transform writes (the
## spawn teleport, then interpolated motion, then a stop) reported ~588 m/s and
## ~12 m/s "impacts". It must report none.
func test_client_kinematic_replica_emits_no_impact() -> void:
	var block: Block = Block.new()
	block.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	block.freeze = true
	add_child_autofree(block)
	block.global_position = Vector3(0.0, 9.8, 0.0)
	await wait_physics_frames(2)
	for i: int in range(12):
		block.global_position = Vector3(0.0, 9.8 - 0.2 * float(i), 0.0)
		await wait_physics_frames(1)
	block.global_position = Vector3(40.0, 1.0, 0.0)
	await wait_physics_frames(6)
	assert_eq(_speeds.size(), 0, "a frozen replica never detects an impact (got %s)" % [_speeds])
	assert_eq(_at.size(), 0)


## Positive controls for the frozen early-return in Block._physics_process: the
## suppression is keyed on `freeze`, not on being a Block, so a dynamic
## (host-simulated) block that really lands still emits its impact.
func _floor_and_block(frozen: bool) -> Block:
	var floor_body: StaticBody3D = StaticBody3D.new()
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	var floor_box: BoxShape3D = BoxShape3D.new()
	floor_box.size = Vector3(20.0, 1.0, 20.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	add_child_autofree(floor_body)
	floor_body.global_position = Vector3(0.0, -0.5, 0.0)
	var block: Block = Block.new()
	var block_shape: CollisionShape3D = CollisionShape3D.new()
	var block_box: BoxShape3D = BoxShape3D.new()
	block_box.size = Vector3.ONE
	block_shape.shape = block_box
	block.add_child(block_shape)
	if frozen:
		block.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		block.freeze = true
	add_child_autofree(block)
	block.global_position = Vector3(0.0, 4.0, 0.0)
	return block


func _wait_for_impact(max_frames: int) -> void:
	for _i: int in range(max_frames):
		if not _speeds.is_empty():
			return
		await wait_physics_frames(1)


func test_block_released_from_a_freeze_detects_impacts_again() -> void:
	var block: Block = _floor_and_block(true)
	await wait_physics_frames(20)
	assert_eq(_speeds.size(), 0, "a frozen block hovering at 4 m detects nothing")
	block.freeze = false
	await _wait_for_impact(150)
	await wait_physics_frames(20)
	assert_eq(_speeds.size(), 1, "released, it falls and its landing is heard (got %s)" % [_speeds])
