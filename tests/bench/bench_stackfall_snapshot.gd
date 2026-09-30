extends Node
## Measures snapshot encoding at a 300-body baseline and Stackfall's 12-body
## peak addition. Run alone, headless; this is a wire proxy, not a frame-rate claim.

const SYNC := preload("res://net/SnapshotSync.gd")
const BASE_BODIES: int = 300
const RAIN_BODIES: int = 12
const SAMPLES: int = 100


func _ready() -> void:
	var net_config: NetConfig = preload("res://config/net_config.tres")
	var bounds: AABB = AABB(Vector3(-70.0, -48.0, -70.0), Vector3(140.0, 168.0, 140.0))
	var bodies: Array = []
	for i: int in range(BASE_BODIES + RAIN_BODIES):
		bodies.append({
			"net_id": i + 1,
			"position": Vector3(float(i % 20) * 2.0, 5.0 + float(i / 20), float(i % 15) * 2.0),
			"rotation": Quaternion.IDENTITY,
			"sleeping": false,
		})
	_measure("baseline", bodies.slice(0, BASE_BODIES), bounds, net_config)
	_measure("stackfall_peak", bodies, bounds, net_config)
	get_tree().quit()


func _measure(label: String, bodies: Array, bounds: AABB, net_config: NetConfig) -> void:
	var packets: Array[PackedByteArray] = []
	var started: int = Time.get_ticks_usec()
	for sample: int in range(SAMPLES):
		packets = SYNC.build_snapshot(
			sample, sample * 33, SYNC.FLAG_DISK_STATE, bodies,
			Transform3D.IDENTITY, bounds, net_config
		)
	var avg_encode_ms: float = float(Time.get_ticks_usec() - started) / 1000.0 / float(SAMPLES)
	var bytes_total: int = 0
	var max_fragment: int = 0
	for packet: PackedByteArray in packets:
		bytes_total += packet.size()
		max_fragment = maxi(max_fragment, packet.size())
	print("BENCH_STACKFALL_SNAPSHOT label=%s bodies=%d fragments=%d bytes=%d max_fragment=%d avg_encode_ms=%.4f" % [label, bodies.size(), packets.size(), bytes_total, max_fragment, avg_encode_ms])
	if max_fragment > net_config.max_packet_bytes:
		get_tree().quit(1)
