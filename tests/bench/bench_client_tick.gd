extends Node
## Cost of a late-game field where every body is asleep: 1,500 frozen bodies,
## the client's render clock past the newest sample, and a host with one peer
## and nothing moving.
##
## Run headless (not a GUT test):
##   godot --headless --path . res://tests/bench/bench_client_tick.tscn
## Prints one machine-readable row and quits 0:
##   BENCH_CLIENT_TICK bodies=1500 client_ms_per_tick=<ms> host_ms_per_snapshot=<ms>
##
## It drives only SnapshotSync's public begin_match / receive_packet /
## client_tick / host_tick, so it runs unchanged on a base without the rest
## culling and on a candidate with it; the two rows compare directly (the
## acceptance is a ratio, because absolute milliseconds depend on the machine).
## The host half needs a peer list and a send seam, which the two overrides in
## HostSync provide; they replace the transport only.

const BODY_COUNT: int = 1500
const GRID_COLUMNS: int = 39
## Share of the field's width the bodies are spread over.
const FIELD_FILL: float = 0.8
const EPOCH_MS: int = 10000
const PEER_ID: int = 2
const STEP: float = 1.0 / 60.0
## Ticks (or snapshots) per timed sample, and samples; the median is reported.
const TICKS_PER_SAMPLE: int = 100
const SNAPSHOTS_PER_SAMPLE: int = 60
const SAMPLES: int = 5
## Client ticks that carry the render clock past the newest sample and let any
## convergence offset decay before timing starts.
const WARMUP_TICKS: int = 180
## Cap on host ticks spent waiting for one snapshot interval to elapse.
const MAX_TICKS_PER_SNAPSHOT: int = 4

var _config: NetConfig = preload("res://config/net/net_config.tres")
var _map: MapDef = preload("res://config/match/maps/round.tres")


## The one method SnapshotSync asks its registry for.
class FakeRegistry:
	extends Node
	var blocks: Dictionary = {}

	func block_for_net_id(net_id: int) -> BlockBody:
		return blocks.get(net_id) as BlockBody


## The host half with the transport replaced: a fixed peer list and a counter
## of what would have been sent.
class HostSync:
	extends "res://net/SnapshotSync.gd"
	var sent_fragments: int = 0

	func _remote_peers() -> PackedInt32Array:
		return PackedInt32Array([2])

	func _send_packet(_packet: PackedByteArray) -> void:
		sent_fragments += 1


func _ready() -> void:
	print(
		"BENCH_CLIENT_TICK start bodies=%d samples=%d ticks_per_sample=%d snapshots_per_sample=%d" % [
			BODY_COUNT, SAMPLES, TICKS_PER_SAMPLE, SNAPSHOTS_PER_SAMPLE
		]
	)
	var client_ms: float = _client_ms_per_tick()
	var host_ms: float = _host_ms_per_snapshot()
	print("BENCH_CLIENT_TICK bodies=%d client_ms_per_tick=%.4f host_ms_per_snapshot=%.4f" % [
		BODY_COUNT, client_ms, host_ms
	])
	get_tree().quit(0)


func _positions() -> Array[Vector3]:
	var bounds: AABB = _config.position_bounds(_map)
	var spacing: float = bounds.size.x * FIELD_FILL / float(GRID_COLUMNS)
	var origin: Vector3 = bounds.get_center() - Vector3(spacing * float(GRID_COLUMNS) * 0.5, 0.0, spacing * float(GRID_COLUMNS) * 0.5)
	var result: Array[Vector3] = []
	for index: int in range(BODY_COUNT):
		result.append(origin + Vector3(
			float(index % GRID_COLUMNS) * spacing, 0.5, float(index / GRID_COLUMNS) * spacing
		))
	return result


func _bodies(parent: Node, positions: Array[Vector3], sleeping: bool) -> Array[BlockBody]:
	var bodies: Array[BlockBody] = []
	for index: int in range(BODY_COUNT):
		var body: BlockBody = BlockBody.new()
		body.net_id = index + 1
		parent.add_child(body)
		body.global_position = positions[index]
		body.sleeping = sleeping
		bodies.append(body)
	return bodies


func _median(values: Array[float]) -> float:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _client_ms_per_tick() -> float:
	var root: Node3D = Node3D.new()
	add_child(root)
	var positions: Array[Vector3] = _positions()
	var registry: FakeRegistry = FakeRegistry.new()
	add_child(registry)
	for body: BlockBody in _bodies(root, positions, true):
		registry.blocks[body.net_id] = body

	var sync: Node = (load("res://net/SnapshotSync.gd") as GDScript).new() as Node
	add_child(sync)
	sync.call("bind_session", FakeSessionPort.new(FakeNet.client(0)))
	sync.call("begin_match", registry, _map)

	var records: Array = []
	for index: int in range(BODY_COUNT):
		records.append({
			"net_id": index + 1, "position": positions[index],
			"rotation": Quaternion.IDENTITY, "sleeping": true,
		})
	var packets: Array[PackedByteArray] = SnapshotWire.build_snapshot(
		1, EPOCH_MS, SnapshotWire.FLAG_DISK_STATE, records, Transform3D.IDENTITY,
		_config.position_bounds(_map), _config
	)
	for packet: PackedByteArray in packets:
		sync.call("receive_packet", packet)
	for _i: int in range(WARMUP_TICKS):
		sync.call("client_tick", STEP)

	var samples: Array[float] = []
	for _sample: int in range(SAMPLES):
		var start: int = Time.get_ticks_usec()
		for _i: int in range(TICKS_PER_SAMPLE):
			sync.call("client_tick", STEP)
		samples.append(float(Time.get_ticks_usec() - start) / 1000.0 / float(TICKS_PER_SAMPLE))
	sync.call("end_match")
	sync.queue_free()
	registry.queue_free()
	root.queue_free()
	return _median(samples)


func _host_ms_per_snapshot() -> float:
	var root: Node3D = Node3D.new()
	add_child(root)
	var registry: FakeRegistry = FakeRegistry.new()
	add_child(registry)
	var sync: HostSync = HostSync.new()
	add_child(sync)
	sync.bind_session(FakeSessionPort.new(FakeNet.host()))
	sync.begin_match(registry, _map)
	var disk: Node3D = Node3D.new()
	add_child(disk)
	sync.set_disk(disk)
	for body: BlockBody in _bodies(root, _positions(), true):
		Events.block_replicated.emit(body, body.net_id)

	# The first snapshot to a new peer carries every body; it is not what is timed.
	_next_snapshot(sync)
	for _i: int in range(MAX_TICKS_PER_SNAPSHOT * 4):
		_next_snapshot(sync)

	var samples: Array[float] = []
	for _sample: int in range(SAMPLES):
		var start: int = Time.get_ticks_usec()
		for _i: int in range(SNAPSHOTS_PER_SAMPLE):
			_next_snapshot(sync)
		samples.append(float(Time.get_ticks_usec() - start) / 1000.0 / float(SNAPSHOTS_PER_SAMPLE))
	sync.end_match()
	sync.queue_free()
	registry.queue_free()
	root.queue_free()
	disk.queue_free()
	return _median(samples)


## Ticks the host until one snapshot has gone out.
func _next_snapshot(sync: HostSync) -> void:
	var before: int = sync.sent_fragments
	for _i: int in range(MAX_TICKS_PER_SNAPSHOT):
		sync.host_tick(STEP)
		if sync.sent_fragments != before:
			return
