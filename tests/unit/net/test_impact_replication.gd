extends GutTest
## Block impacts are detected only by host physics (game/blocks/Block.gd). ImpactReplicator batches
## them on the host (collect/flush) and queues a received batch on a client (receive/drain), where
## MatchNet re-emits Events.block_impacted / block_impacted_at, so Sfx/camera/rumble/dust need no
## network awareness; a client's frozen kinematic replicas never detect impacts of their own.

## A view time far past any playback delay: everything queued is due.
const VIEW_LATE_MS: float = 1.0e9

var _config: NetConfig = NetConfig.new()
var _speeds: Array[float] = []
var _at: Array[Array] = []
var _speed_listener: Callable
var _at_listener: Callable


func before_each() -> void:
	_config = NetConfig.new()
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


func _replicator() -> ImpactReplicator:
	return ImpactReplicator.new(_config, TokenBucket.new())


func _batch(events: Array[Dictionary]) -> PackedByteArray:
	return ImpactWire.encode(events)


func _event(speed: float, position: Vector3, age_ms: int = 0) -> Dictionary:
	return {
		ImpactWire.KEY_SPEED: speed, ImpactWire.KEY_POSITION: position, ImpactWire.KEY_AGE_MS: age_ms
	}


## The speed and position of one drained row, whatever order and extra fields the row has.
func _row_speed(row: Array) -> float:
	for value: Variant in row:
		if value is float:
			return value as float
	return -1.0


func _row_position(row: Array) -> Vector3:
	for value: Variant in row:
		if value is Vector3:
			return value as Vector3
	return Vector3(INF, INF, INF)


func _decode(packet: PackedByteArray) -> Array[Dictionary]:
	return ImpactWire.decode(packet, _config.impact_speed_max, _config.pos_min_y, _config.pos_max_y)


# --- Round trip ---------------------------------------------------------------

func test_host_impact_reaches_a_client_as_a_row() -> void:
	var host: ImpactReplicator = _replicator()
	var position: Vector3 = Vector3(1.234, 2.5, -3.456)
	host.collect(6.5, position, 1000)
	var packet: PackedByteArray = host.flush(1000)
	assert_eq(packet.size(), ImpactWire.HEADER_BYTES + ImpactWire.EVENT_BYTES, "one event on the wire")

	var client: ImpactReplicator = _replicator()
	assert_true(client.receive(packet, 2000))
	var rows: Array[Array] = client.drain(VIEW_LATE_MS)
	assert_eq(rows.size(), 1, "one impact to play")
	if rows.size() == 1:
		assert_almost_eq(_row_speed(rows[0]), 6.5, ImpactWire.SPEED_QUANTUM)
		var got: Vector3 = _row_position(rows[0])
		assert_almost_eq(got.x, position.x, ImpactWire.POSITION_QUANTUM_M)
		assert_almost_eq(got.y, position.y, ImpactWire.POSITION_QUANTUM_M)
		assert_almost_eq(got.z, position.z, ImpactWire.POSITION_QUANTUM_M)
	assert_eq(client.drain(VIEW_LATE_MS).size(), 0, "a drained impact is not played twice")


func test_nothing_collected_means_nothing_to_send() -> void:
	var host: ImpactReplicator = _replicator()
	assert_eq(host.flush(1000).size(), 0)
	host.collect(5.0, Vector3(1.0, 1.0, 1.0), 1000)
	assert_gt(host.flush(1000).size(), 0)
	assert_eq(host.flush(1100).size(), 0, "a flushed batch is not sent again")


func test_an_impact_plays_when_the_view_reaches_the_moment_it_happened() -> void:
	var host: ImpactReplicator = _replicator()
	host.collect(5.0, Vector3(1.0, 1.0, 1.0), 1000)
	var client: ImpactReplicator = _replicator()
	# Detected 100 ms before the send, received at 2000: it happened at 1900 on the client clock.
	assert_true(client.receive(host.flush(1100), 2000))
	assert_eq(client.drain(1899.0).size(), 0, "the view has not reached it yet")
	assert_eq(client.drain(1900.0).size(), 1, "and it is still queued when the view arrives")
	assert_eq(client.drain(VIEW_LATE_MS).size(), 0)


# --- Coalescing and caps ----------------------------------------------------

func test_same_cell_impacts_coalesce_to_the_strongest() -> void:
	var host: ImpactReplicator = _replicator()
	var base: Vector3 = Vector3(2.1, 3.1, 4.1)
	for i: int in range(50):
		host.collect(1.0 + float(i % 17), base + Vector3(0.001 * float(i), 0.0, 0.0), 0)
	var events: Array[Dictionary] = _decode(host.flush(10))
	assert_eq(events.size(), 1, "one cell -> one event")
	if events.size() == 1:
		assert_almost_eq(float(events[0][ImpactWire.KEY_SPEED]), 17.0, ImpactWire.SPEED_QUANTUM)


func test_sustained_flood_holds_the_per_second_cap() -> void:
	var host: ImpactReplicator = _replicator()
	var interval_ms: int = int(1000.0 / _config.impact_batch_hz)
	var per_window: Array[int] = [0, 0, 0]
	var total: int = 0
	var now_ms: int = 0
	while now_ms < 3000:
		for i: int in range(200):
			host.collect(
				2.0 + float(i) * 0.05, Vector3(float(i % 20) * 2.0, 1.0, floorf(float(i) / 20.0) * 2.0), now_ms
			)
		var events: Array[Dictionary] = _decode(host.flush(now_ms))
		assert_true(events.size() <= _config.impact_max_per_batch, "batch at %d ms within cap" % now_ms)
		per_window[int(float(now_ms) / 1000.0)] += events.size()
		total += events.size()
		now_ms += interval_ms
	for second: int in range(3):
		assert_true(per_window[second] <= _config.impact_max_per_second + _config.impact_max_per_batch,
			"second %d sent %d" % [second, per_window[second]])
	assert_true(total <= _config.impact_max_per_second * 3 + _config.impact_max_per_batch, "3 s total %d" % total)
	assert_true(total >= _config.impact_max_per_second * 2, "the flood is throttled, not silenced (%d)" % total)


# --- Client validation --------------------------------------------------------

func test_malformed_batches_are_refused() -> void:
	var client: ImpactReplicator = _replicator()
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
	var too_low: PackedByteArray = _batch([_event(3.0, Vector3(0.0, _config.pos_min_y - 5.0, 0.0))])
	var oversized: PackedByteArray = PackedByteArray()
	oversized.resize(ImpactWire.MAX_PACKET_BYTES + ImpactWire.EVENT_BYTES)
	var packets: Array[PackedByteArray] = [
		PackedByteArray(), bad_version, bad_count, zero_count, truncated, zero_speed, too_fast, too_low,
		oversized,
	]
	for packet: PackedByteArray in packets:
		assert_false(client.receive(packet, 100), "refused: %d bytes" % packet.size())
	assert_eq(client.drain(VIEW_LATE_MS).size(), 0, "nothing from a malformed batch plays")
	assert_true(client.receive(good, 100), "the well-formed control is accepted")
	assert_eq(client.drain(VIEW_LATE_MS).size(), 1, "and plays")


## One bad event inside a well-formed batch is skipped on its own; its neighbours still play.
func test_one_bad_event_does_not_silence_the_rest_of_the_batch() -> void:
	var client: ImpactReplicator = _replicator()
	var high: float = _config.pos_max_y + 20.0
	var low: float = _config.pos_min_y - 20.0
	assert_true(client.receive(_batch([
		_event(3.0, Vector3(0.0, 1.0, 0.0)),
		_event(4.0, Vector3(0.0, high, 0.0)),
		_event(5.0, Vector3(2.0, 1.0, 0.0)),
		_event(6.0, Vector3(0.0, low, 0.0)),
		_event(7.0, Vector3(4.0, 1.0, 0.0)),
	]), 100))
	var speeds: Array[float] = []
	for row: Array in client.drain(VIEW_LATE_MS):
		speeds.append(_row_speed(row))
	assert_eq(speeds.size(), 3, "the three in-range events play (got %s)" % [speeds])
	if speeds.size() == 3:
		assert_almost_eq(speeds[0], 3.0, ImpactWire.SPEED_QUANTUM)
		assert_almost_eq(speeds[1], 5.0, ImpactWire.SPEED_QUANTUM)
		assert_almost_eq(speeds[2], 7.0, ImpactWire.SPEED_QUANTUM)
	# A bad speed is per-event too.
	var bad_speed: PackedByteArray = _batch([_event(3.0, Vector3.ZERO), _event(3.0, Vector3(1.0, 1.0, 1.0))])
	bad_speed.encode_u16(ImpactWire.HEADER_BYTES + 6, 0)
	client.receive(bad_speed, 100)
	assert_eq(client.drain(VIEW_LATE_MS).size(), 1, "only the zero-speed event is skipped")


# --- Client caps and rate window ----------------------------------------------

func _full_batch(seed_x: float) -> PackedByteArray:
	var events: Array[Dictionary] = []
	for i: int in range(_config.impact_max_per_batch):
		events.append(_event(3.0, Vector3(seed_x + float(i), 1.0, 0.0)))
	return _batch(events)


func test_a_flooding_host_cannot_make_a_client_play_more_than_the_per_second_cap() -> void:
	var client: ImpactReplicator = _replicator()
	var played: int = 0
	for i: int in range(60):
		client.receive(_full_batch(float(i) * 20.0), 1000 + i)
		played += client.drain(VIEW_LATE_MS).size()
	assert_true(played <= _config.impact_client_max_per_second, "played %d inside one second" % played)
	assert_true(played >= _config.impact_max_per_batch, "a full batch always plays")


func test_the_client_rate_window_reopens_after_a_second() -> void:
	var client: ImpactReplicator = _replicator()
	for i: int in range(60):
		client.receive(_full_batch(float(i) * 20.0), 1000)
	client.drain(VIEW_LATE_MS)
	client.receive(_full_batch(0.0), 1500)
	assert_eq(client.drain(VIEW_LATE_MS).size(), 0, "still inside the window of the flood")
	client.receive(_full_batch(0.0), 2500)
	assert_eq(client.drain(VIEW_LATE_MS).size(), _config.impact_max_per_batch, "a later second plays again")


## A batch longer than the per-batch cap is refused or trimmed, never played in full.
func test_a_batch_over_the_per_batch_cap_does_not_play_in_full() -> void:
	var client: ImpactReplicator = _replicator()
	var events: Array[Dictionary] = []
	for i: int in range(_config.impact_max_per_batch + 20):
		events.append(_event(3.0, Vector3(float(i) * 2.0, 1.0, 0.0)))
	client.receive(_batch(events), 100)
	assert_true(client.drain(VIEW_LATE_MS).size() <= _config.impact_max_per_batch)


# --- No client-side detection -------------------------------------------------

## The probe: a frozen kinematic replica moved by transform writes (the
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
