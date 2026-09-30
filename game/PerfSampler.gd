class_name PerfSampler
extends Node
## Bontago-470.8: gathers one metrics snapshot every DebugConfig.stats_window_s
## and keeps a rolling history for the overlay graph. Both ui/PerfOverlay.gd and
## game/PerfLogger.gd read `latest`/`history_*` and never sample on their own, so
## PerfProbe.drain() has a single consumer.
##
## Consistency: everything in a snapshot is measured over the same window from
## per-frame / per-tick samples taken here (fps = frames / window seconds, frame
## ms = mean real frame time, physics = mean and worst per-tick time from
## Performance.TIME_PHYSICS_PROCESS read once per tick, process likewise per
## frame). Godot's own FPS monitor (a separate 1 s average) is not used.
##
## Local only: nothing here is networked and nothing writes game state.

signal sampled(metrics: Dictionary)

var config: DebugConfig = null
## The newest snapshot (see collect() for the keys). Empty before the first.
var latest: Dictionary = {}
var history_frame_ms: PackedFloat32Array = PackedFloat32Array()
var history_physics_ms: PackedFloat32Array = PackedFloat32Array()
var history_blocks: PackedFloat32Array = PackedFloat32Array()

var _window_s: float = 0.0
var _frames: int = 0
var _frame_sum_ms: float = 0.0
var _frame_max_ms: float = 0.0
var _ticks: int = 0
var _physics_sum_ms: float = 0.0
var _physics_max_ms: float = 0.0

var _bucket_s: float = 0.0
var _bucket_frame_max_ms: float = 0.0
var _bucket_physics_max_ms: float = 0.0
var _last_blocks: int = 0
var _session_start_msec: int = 0


func _ready() -> void:
	if config == null:
		config = DebugConfig.new()
	_session_start_msec = Time.get_ticks_msec()
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	# Real (unscaled) delta so sandbox slow motion does not flatter the numbers.
	var real: float = delta / maxf(Engine.time_scale, 0.0001)
	record_frame(real)
	if _window_s >= config.stats_window_s:
		sample_now()


func _physics_process(_delta: float) -> void:
	record_physics_tick(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)


## One rendered frame's real duration in seconds. (Godot's TIME_PROCESS monitor
## is deliberately unused: it read ~130 ms next to 13 ms frames, so it is not
## trustworthy here.)
## Also the test seam (stub values in, exact numbers out).
func record_frame(real_delta_s: float) -> void:
	var frame_ms: float = real_delta_s * 1000.0
	_frames += 1
	_window_s += real_delta_s
	_frame_sum_ms += frame_ms
	_frame_max_ms = maxf(_frame_max_ms, frame_ms)
	_bucket_s += real_delta_s
	_bucket_frame_max_ms = maxf(_bucket_frame_max_ms, frame_ms)
	if _bucket_s >= config.graph_interval_s:
		_push_history(_bucket_frame_max_ms, _bucket_physics_max_ms, float(_last_blocks))
		_bucket_s = 0.0
		_bucket_frame_max_ms = 0.0
		_bucket_physics_max_ms = 0.0


## One physics tick's cost in ms.
func record_physics_tick(physics_ms: float) -> void:
	_ticks += 1
	_physics_sum_ms += physics_ms
	_physics_max_ms = maxf(_physics_max_ms, physics_ms)
	_bucket_physics_max_ms = maxf(_bucket_physics_max_ms, physics_ms)


## Closes the current window into `latest` (also the test seam).
func sample_now() -> Dictionary:
	var frames: int = maxi(_frames, 1)
	var ticks: int = maxi(_ticks, 1)
	var stats: Dictionary = {
		"window_s": _window_s,
		"fps": float(_frames) / maxf(_window_s, 0.0001),
		"frame_ms": _frame_sum_ms / float(frames),
		"frame_ms_max": _frame_max_ms,
		"physics_ms": _physics_sum_ms / float(ticks),
		"physics_ms_max": _physics_max_ms,
	}
	var window: float = _window_s
	_window_s = 0.0
	_frames = 0
	_frame_sum_ms = 0.0
	_frame_max_ms = 0.0
	_ticks = 0
	_physics_sum_ms = 0.0
	_physics_max_ms = 0.0
	latest = collect(stats, window)
	latest["time_s"] = float(Time.get_ticks_msec() - _session_start_msec) / 1000.0
	_last_blocks = int(latest["blocks_total"])
	sampled.emit(latest)
	return latest


func _push_history(frame_ms: float, physics_ms: float, blocks: float) -> void:
	var capacity: int = maxi(int(ceilf(config.graph_window_s / config.graph_interval_s)), 2)
	history_frame_ms.append(frame_ms)
	history_physics_ms.append(physics_ms)
	history_blocks.append(blocks)
	while history_frame_ms.size() > capacity:
		history_frame_ms.remove_at(0)
		history_physics_ms.remove_at(0)
		history_blocks.remove_at(0)


## One flat snapshot Dictionary. Render/physics monitors read 0 in headless.
func collect(stats: Dictionary, interval_s: float) -> Dictionary:
	var m: Dictionary = stats.duplicate()
	m["draw_calls"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	m["objects_in_frame"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	m["primitives"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	m["vram_mb"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	m["static_mem_mb"] = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	m["object_count"] = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	m["node_count"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	m["orphan_nodes"] = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	# DECISION: Jolt does not feed Godot's PHYSICS_3D_ACTIVE_OBJECTS/PAIRS/ISLAND
	# monitors (they read 0 with 48 awake blocks), so "active bodies" is the
	# awake block count below instead of a dead monitor.

	var counts: Dictionary = _block_counts()
	m["blocks_total"] = int(counts["total"])
	m["blocks_awake"] = int(counts["awake"])
	m["blocks_sleeping"] = int(counts["sleeping"])

	m["match_state"] = _state_name()
	m["players"] = Match.slot_count()
	var weather: MatchWeather = Match.weather()
	m["weather_id"] = String(weather.active_id()) if weather != null else ""
	m["weather_intensity"] = weather.active_intensity() if weather != null else 0.0

	var net: Dictionary = Net.stats()
	m["net_mode"] = int(net.get("mode", 0))
	m["net_peers"] = int(net.get("peers", 0))
	m["net_ping_ms"] = float(net.get("ping_ms", 0.0))
	m["net_snapshot_bps"] = float(net.get("snapshot_bps", 0.0))

	# Probe windows are per drain (interval_s of wall time); report the average
	# per rendered frame's worth of physics ticks plus the worst single call.
	var probes: Dictionary = PerfProbe.drain()
	for key: StringName in [&"territory", &"weather", &"gifts", &"registry", &"block_effects", &"snapshot"]:
		var entry: Dictionary = probes.get(key, {})
		var calls: int = int(entry.get("calls", 0))
		var total_ms: float = float(entry.get("usec", 0)) / 1000.0
		# Mean ms per call and worst call; "per second" load is total/interval.
		m["%s_ms" % key] = total_ms / float(maxi(calls, 1))
		m["%s_peak_ms" % key] = float(entry.get("peak_usec", 0)) / 1000.0
		m["%s_load_pct" % key] = total_ms / maxf(interval_s * 1000.0, 0.001) * 100.0
	return m


func _block_counts() -> Dictionary:
	var counts: Dictionary = {"total": 0, "awake": 0, "sleeping": 0}
	var registry: BlockRegistry = Match.registry()
	if registry == null:
		return counts
	for block: Block in registry.all_blocks():
		counts["total"] = int(counts["total"]) + 1
		if block.sleeping or block.freeze:
			counts["sleeping"] = int(counts["sleeping"]) + 1
		else:
			counts["awake"] = int(counts["awake"]) + 1
	return counts


func _state_name() -> String:
	var key: Variant = Match.State.find_key(Match.state())
	return str(key) if key != null else "UNKNOWN"
