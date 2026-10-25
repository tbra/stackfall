extends Node3D
## Host tick cost at 400-1500 settled bodies: a standalone Field + BlockRegistry +
## StableBlockManager + BlockEffectsManager + BlockStepBatch + a transport-free host
## SnapshotSync with one fake peer, no Match. One Godot process per body count (the
## Block / BlockStepBatch / StableBlockManager statics survive a scene reload):
##   godot --headless --fixed-fps 60 --path . res://tests/bench/bench_host_tick.tscn -- --bodies=400 --layout=slab
## Args: --bodies=<int> --layout=slab|columns [--rng-seed=<int>] [--smoke]
## --smoke shortens every phase and slice (about 120 ticks per phase), marks each line
## smoke=1 and prints no number anyone may quote.
##
## Schedule (ticks, full run): PRELUDE 1800, FROZEN 600, CHURN 1200 (8 cubes/s dropped on
## the pile from here to the end), ABLATE and REMAINDER in 120-tick slices (below).
## ABLATE slice 0 is all-ON, then for each subsystem X in (stable, registry, effects,
## batch): 5 x (X OFF, all ON). Every OFF slice has an all-ON slice on both sides at the
## same body state; delta_X = median over the 5 OFF slices of (mean of the two ON
## neighbours - the OFF slice). REMAINDER: ON, ALL-OFF, ON, ALL-OFF, ON; remainder_ms is
## the mean ALL-OFF slice (Jolt step + state sync + bench overhead).
##
## Per-tick time is the wall delta between consecutive _physics_process calls of this
## node, which under --fixed-fps is the whole frame. Headless timing on one machine is
## only a proxy for in-game frame time (see bench_rain.gd): only an idle PC gives
## numbers worth quoting.

const BODIES_ARG: String = "--bodies="
const LAYOUT_ARG: String = "--layout="
const SEED_ARG: String = "--rng-seed="
const SMOKE_ARG: String = "--smoke"
const LAYOUT_SLAB: String = "slab"
const LAYOUT_COLUMNS: String = "columns"
const DEFAULT_BODIES: int = 400
const DEFAULT_SEED: int = 20261023
const CUBE_PATH: String = "res://config/blocks/cube.tres"
const OWNER_SLOT_COUNT: int = 8

## Slab: cubes per row; the pile is one contiguous contact island.
const SLAB_WIDTH: int = 20
## Columns: cubes per tower and tower spacing (m).
const COLUMN_HEIGHT: int = 10
const COLUMN_SPACING_M: float = 1.5

const PRELUDE_TICKS: int = 1800
const FROZEN_TICKS: int = 600
const CHURN_TICKS: int = 1200
const SMOKE_PHASE_TICKS: int = 120
const SLICE_TICKS: int = 120
## Smoke slice: one StableBlockManager scan interval (30 ticks).
const SMOKE_SLICE_TICKS: int = 30
const PAIRS_PER_SUBSYSTEM: int = 5
const REMAINDER_SLICES: int = 5

const CHURN_DROPS_PER_SECOND: int = 8
const DROP_CLEARANCE_M: float = 3.0
const DROP_FOOTPRINT_FILL: float = 0.8

const HIST_BIN_MS: float = 0.05
const HIST_BINS: int = 2000
const BUDGET_MS: float = 1000.0 / 60.0
const SCAN_RESIDUES: int = 30
const SNAPSHOT_PARITIES: int = 2
const POSE_HASH_BODIES: int = 50
const POSE_ROUND_STEP: float = 0.0001
const USEC_PER_MS: float = 1000.0
const SUBSYSTEM_NAMES: Array[String] = ["stable", "registry", "effects", "batch"]
## Plan value of an all-ON slice and of an all-OFF slice (otherwise the subsystem index that is OFF).
const PLAN_ALL_ON: int = -1
const PLAN_ALL_OFF: int = 4

const PHASE_PRELUDE: String = "prelude"
const PHASE_FROZEN: String = "frozen"
const PHASE_CHURN: String = "churn"
const PHASE_ABLATE: String = "ablate"
const PHASE_REMAINDER: String = "remainder"


## Tick-time statistics of one phase.
class PhaseStats:
	extends RefCounted
	var name: String = ""
	var ticks: int = 0
	var sum_ms: float = 0.0
	var max_ms: float = 0.0
	var over_budget: int = 0
	var hist: PackedInt32Array = PackedInt32Array()
	var residue_sum: PackedFloat64Array = PackedFloat64Array()
	var residue_n: PackedInt32Array = PackedInt32Array()
	var parity_sum: PackedFloat64Array = PackedFloat64Array()
	var parity_n: PackedInt32Array = PackedInt32Array()
	var awake_sum: float = 0.0

	func _init(phase_name: String) -> void:
		name = phase_name
		hist.resize(HIST_BINS)
		residue_sum.resize(SCAN_RESIDUES)
		residue_n.resize(SCAN_RESIDUES)
		parity_sum.resize(SNAPSHOT_PARITIES)
		parity_n.resize(SNAPSHOT_PARITIES)

	func add(tick_index: int, ms: float, awake: int) -> void:
		ticks += 1
		sum_ms += ms
		max_ms = maxf(max_ms, ms)
		if ms > BUDGET_MS:
			over_budget += 1
		hist[mini(int(ms / HIST_BIN_MS), HIST_BINS - 1)] += 1
		residue_sum[tick_index % SCAN_RESIDUES] += ms
		residue_n[tick_index % SCAN_RESIDUES] += 1
		parity_sum[tick_index % SNAPSHOT_PARITIES] += ms
		parity_n[tick_index % SNAPSHOT_PARITIES] += 1
		awake_sum += float(awake)

	func mean_ms() -> float:
		return sum_ms / float(maxi(ticks, 1))

	## Upper edge (ms) of the histogram bin holding quantile `q`.
	func percentile_ms(q: float) -> float:
		var target: int = int(ceil(q * float(ticks)))
		var seen: int = 0
		for bin: int in range(HIST_BINS):
			seen += hist[bin]
			if seen >= target:
				return float(bin + 1) * HIST_BIN_MS
		return max_ms

	## Index of the residue (or parity) bin with the highest mean tick time.
	static func top_bin(sums: PackedFloat64Array, counts: PackedInt32Array) -> int:
		var best: int = 0
		var best_mean: float = -1.0
		for i: int in range(sums.size()):
			var mean: float = sums[i] / float(maxi(counts[i], 1))
			if mean > best_mean:
				best_mean = mean
				best = i
		return best

	## {"top": mean of the top bin, "rest": mean of every other bin, "index": top bin}.
	static func split(sums: PackedFloat64Array, counts: PackedInt32Array) -> Dictionary:
		var top: int = top_bin(sums, counts)
		var rest_sum: float = 0.0
		var rest_n: int = 0
		for i: int in range(sums.size()):
			if i != top:
				rest_sum += sums[i]
				rest_n += counts[i]
		return {
			"top": sums[top] / float(maxi(counts[top], 1)),
			"rest": rest_sum / float(maxi(rest_n, 1)),
			"index": top,
		}


## Host SnapshotSync with the transport replaced (as bench_client_tick.gd's HostSync;
## duplicated because a bench cannot import another bench's private helpers) and the
## host_tick wrapped in a PerfProbe key.
class HostSync:
	extends "res://net/SnapshotSync.gd"
	const FAKE_PEER_ID: int = 2
	var sent_fragments: int = 0

	func _remote_peers() -> PackedInt32Array:
		return PackedInt32Array([FAKE_PEER_ID])

	func _send_packet(_packet: PackedByteArray) -> void:
		sent_fragments += 1

	func host_tick(delta: float) -> void:
		var started: int = PerfProbe.start()
		super.host_tick(delta)
		PerfProbe.stop(&"snapshot", started)


var _tuning: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
var _bodies_wanted: int = DEFAULT_BODIES
var _layout: String = LAYOUT_SLAB
var _rng_seed: int = DEFAULT_SEED
var _smoke: bool = false

var _field: Field = null
var _registry: BlockRegistry = null
var _manager: StableBlockManager = null
var _effects: BlockEffectsManager = null
var _sync: HostSync = null
var _blocks_root: Node3D = null
var _blocks: Array[Block] = []
var _shape: BlockShape = null
var _drop_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _pile_top_y: float = 0.0
var _footprint_half_m: float = 0.0

var _phase_names: Array[String] = []
var _phase_ticks: Array[int] = []
var _phase_index: int = -1
var _phase_start_tick: int = 0
var _total_ticks: int = 0
var _tick: int = 0
var _last_usec: int = 0
var _stats: PhaseStats = null
var _plan: Array[int] = []
var _slice_ticks: int = SLICE_TICKS
var _slice_index: int = -1
var _slice_sum_ms: PackedFloat64Array = PackedFloat64Array()
var _slice_n: PackedInt32Array = PackedInt32Array()
var _slice_max_vy: PackedFloat64Array = PackedFloat64Array()
var _churn_ticks: int = 0
var _churn_dropped: int = 0
var _kill_plane_falls: int = 0
var _batch_callable: Callable = Callable()
var _batch_connected: bool = true
var _finished: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(BODIES_ARG):
			_bodies_wanted = arg.substr(BODIES_ARG.length()).to_int()
		elif arg.begins_with(LAYOUT_ARG):
			_layout = arg.substr(LAYOUT_ARG.length())
		elif arg.begins_with(SEED_ARG):
			_rng_seed = arg.substr(SEED_ARG.length()).to_int()
		elif arg == SMOKE_ARG:
			_smoke = true
	if _layout != LAYOUT_SLAB and _layout != LAYOUT_COLUMNS:
		push_error("bench_host_tick: --layout must be slab or columns, got %s" % _layout)
		get_tree().quit(1)
		set_physics_process(false)
		return
	seed(_rng_seed)
	_drop_rng.seed = _rng_seed
	_shape = load(CUBE_PATH) as BlockShape
	_build_world()
	_build_pile()
	_build_schedule()
	Events.block_removed.connect(_on_block_removed)
	PerfProbe.enabled = true
	print("BENCH_HOST_TICK start bodies=%d layout=%s seed=%d smoke=%d ticks=%d" % [
		_blocks.size(), _layout, _rng_seed, int(_smoke), _total_ticks,
	])


## Production wiring (as bench_p4_parity.gd) plus the effects manager and a host
## SnapshotSync with one fake peer.
func _build_world() -> void:
	var map: MapDef = MapDef.base()
	_field = Field.new()
	_field.map_def = map
	add_child(_field)
	_blocks_root = Node3D.new()
	add_child(_blocks_root)
	_registry = BlockRegistry.new()
	add_child(_registry)
	_registry.set_host_authority(true)
	_registry.configure(_field, map)
	_registry.reset()
	_field.set_registry(_registry)
	_manager = StableBlockManager.new()
	add_child(_manager)
	_manager.setup(_registry)
	_effects = BlockEffectsManager.new()
	add_child(_effects)
	_sync = HostSync.new()
	add_child(_sync)
	_sync.bind_session(FakeSessionPort.new(FakeNet.host()))
	_sync.begin_match(_registry, map)
	_sync.set_disk(_field)


## Places every cube at rest, in the first tick, on exact edge spacing.
func _build_pile() -> void:
	var edge: float = _tuning.cube_size - _tuning.cube_margin
	var base_y: float = _field.surface_y() - _tuning.cube_margin * 0.5
	var levels: int = 0
	if _layout == LAYOUT_SLAB:
		var per_layer: int = SLAB_WIDTH * SLAB_WIDTH
		levels = int(ceil(float(_bodies_wanted) / float(per_layer)))
		var width: int = mini(SLAB_WIDTH, _bodies_wanted)
		var rows: int = int(ceil(float(mini(per_layer, _bodies_wanted)) / float(width)))
		_footprint_half_m = float(maxi(width, rows)) * edge * 0.5
		for i: int in range(_bodies_wanted):
			var column: int = (i % per_layer) % width
			var row: int = (i % per_layer) / width
			var level: int = i / per_layer
			var x: float = (float(column) - float(width - 1) * 0.5) * edge
			var z: float = (float(row) - float(rows - 1) * 0.5) * edge
			_place(i, Vector3(x, base_y + edge * float(level), z))
	else:
		var towers: int = int(ceil(float(_bodies_wanted) / float(COLUMN_HEIGHT)))
		var across: int = int(ceil(sqrt(float(towers))))
		levels = mini(COLUMN_HEIGHT, _bodies_wanted)
		_footprint_half_m = float(across) * COLUMN_SPACING_M * 0.5
		for i: int in range(_bodies_wanted):
			var tower: int = i / COLUMN_HEIGHT
			var level: int = i % COLUMN_HEIGHT
			var x: float = (float(tower % across) - float(across - 1) * 0.5) * COLUMN_SPACING_M
			var z: float = (float(tower / across) - float(across - 1) * 0.5) * COLUMN_SPACING_M
			_place(i, Vector3(x, base_y + edge * float(level), z))
	_pile_top_y = base_y + edge * float(levels)


func _place(index: int, position: Vector3) -> void:
	var block: Block = BlockFactory.build(_shape, _tuning, index % OWNER_SLOT_COUNT, Color.WHITE)
	_blocks_root.add_child(block)
	block.global_position = position
	Events.block_placed.emit(block, _shape.id)
	_blocks.append(block)


func _build_schedule() -> void:
	_slice_ticks = SMOKE_SLICE_TICKS if _smoke else SLICE_TICKS
	_plan.append(PLAN_ALL_ON)
	for subsystem: int in range(SUBSYSTEM_NAMES.size()):
		for _pair: int in range(PAIRS_PER_SUBSYSTEM):
			_plan.append(subsystem)
			_plan.append(PLAN_ALL_ON)
	_phase_names = [PHASE_PRELUDE, PHASE_FROZEN, PHASE_CHURN, PHASE_ABLATE, PHASE_REMAINDER]
	_phase_ticks = [
		SMOKE_PHASE_TICKS if _smoke else PRELUDE_TICKS,
		SMOKE_PHASE_TICKS if _smoke else FROZEN_TICKS,
		SMOKE_PHASE_TICKS if _smoke else CHURN_TICKS,
		_plan.size() * _slice_ticks,
		REMAINDER_SLICES * _slice_ticks,
	]
	for ticks: int in _phase_ticks:
		_total_ticks += ticks


func _remainder_plan() -> Array[int]:
	var plan: Array[int] = []
	for i: int in range(REMAINDER_SLICES):
		plan.append(PLAN_ALL_ON if i % 2 == 0 else PLAN_ALL_OFF)
	return plan


func _on_block_removed(_block: RigidBody3D, reason: String) -> void:
	if reason == Events.REASON_KILL_PLANE:
		_kill_plane_falls += 1


func _physics_process(delta: float) -> void:
	if _finished:
		return
	var now: int = Time.get_ticks_usec()
	if _tick > 0 and _stats != null:
		_record(float(now - _last_usec) / USEC_PER_MS)
	_last_usec = now
	if _tick >= _total_ticks:
		_finish()
		return
	_enter_phase_if_due()
	if _phase_index >= 2:
		_churn()
	if not _plan.is_empty() and _phase_index >= 3:
		_advance_slice()
	_sync.host_tick(delta)
	_tick += 1


## Attributes the frame that just ended to the phase and slice of the previous tick.
func _record(ms: float) -> void:
	var tick_index: int = _tick - 1
	_stats.add(
		tick_index, ms,
		# Block.awake_blocks() is the only body-activity signal: JoltPhysicsServer3D::get_process_info
		# returns 0 for every ProcessInfo (modules/jolt_physics/jolt_physics_server_3d.cpp:1667-1669),
		# so the PHYSICS_3D active/island/pair monitors never carry data under Jolt.
		Block.awake_blocks().size(),
	)
	if _slice_index >= 0:
		_slice_sum_ms[_slice_index] += ms
		_slice_n[_slice_index] += 1


func _enter_phase_if_due() -> void:
	var due: int = _phase_index + 1
	var boundary: int = _phase_start_tick + (_phase_ticks[_phase_index] if _phase_index >= 0 else 0)
	if _phase_index >= 0 and _tick < boundary:
		return
	if due >= _phase_names.size():
		return
	if _phase_index >= 0:
		_close_phase()
	_phase_index = due
	_phase_start_tick = _tick
	_stats = PhaseStats.new(_phase_names[_phase_index])
	_slice_index = -1
	if _phase_names[_phase_index] == PHASE_REMAINDER:
		_plan = _remainder_plan()
	if _phase_names[_phase_index] == PHASE_ABLATE or _phase_names[_phase_index] == PHASE_REMAINDER:
		_slice_sum_ms.resize(_plan.size())
		_slice_n.resize(_plan.size())
		_slice_max_vy.resize(_plan.size())
		_slice_sum_ms.fill(0.0)
		_slice_n.fill(0)
		_slice_max_vy.fill(0.0)
		_connect_batch_lookup()


## The slice at the start of this tick (plan state applied once per slice).
func _advance_slice() -> void:
	var slice: int = (_tick - _phase_start_tick) / _slice_ticks
	if slice == _slice_index or slice >= _plan.size():
		return
	if _slice_index >= 0:
		_slice_max_vy[_slice_index] = _max_vertical_speed()
	_slice_index = slice
	var off: int = _plan[slice]
	for subsystem: int in range(SUBSYSTEM_NAMES.size()):
		_set_subsystem(subsystem, off != subsystem and off != PLAN_ALL_OFF)


func _set_subsystem(subsystem: int, enabled: bool) -> void:
	match subsystem:
		0:
			_manager.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
		1:
			_registry.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
		2:
			_effects.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
		3:
			_set_batch(enabled)


## Finds the BlockStepBatch hook on physics_frame (installed by the first Block).
func _connect_batch_lookup() -> void:
	if _batch_callable.is_valid():
		return
	for connection: Dictionary in get_tree().physics_frame.get_connections():
		var callable: Callable = connection["callable"] as Callable
		if callable.get_object() is BlockStepBatch:
			_batch_callable = callable


## The batch hook must stay the FIRST physics_frame listener, so re-connecting
## re-appends every other listener behind it (as BlockStepBatch.install does).
func _set_batch(enabled: bool) -> void:
	if not _batch_callable.is_valid() or enabled == _batch_connected:
		return
	var signal_frame: Signal = get_tree().physics_frame
	if not enabled:
		signal_frame.disconnect(_batch_callable)
	else:
		var others: Array = signal_frame.get_connections()
		for connection: Dictionary in others:
			signal_frame.disconnect(connection["callable"] as Callable)
		signal_frame.connect(_batch_callable)
		for connection: Dictionary in others:
			signal_frame.connect(connection["callable"] as Callable, int(connection["flags"]))
	_batch_connected = enabled


func _max_vertical_speed() -> float:
	var worst: float = 0.0
	for block: Block in Block.awake_blocks():
		worst = maxf(worst, absf(block.linear_velocity.y))
	return worst


## Drops CHURN_DROPS_PER_SECOND cubes per second at seeded positions over the pile.
func _churn() -> void:
	_churn_ticks += 1
	var due: int = _churn_ticks * CHURN_DROPS_PER_SECOND / Engine.physics_ticks_per_second
	var reach: float = _footprint_half_m * DROP_FOOTPRINT_FILL
	while _churn_dropped < due:
		_churn_dropped += 1
		var x: float = _drop_rng.randf_range(-reach, reach)
		var z: float = _drop_rng.randf_range(-reach, reach)
		_place(_blocks.size(), Vector3(x, _pile_top_y + DROP_CLEARANCE_M, z))


func _close_phase() -> void:
	var s: PhaseStats = _stats
	var scan: Dictionary = PhaseStats.split(s.residue_sum, s.residue_n)
	var snap: Dictionary = PhaseStats.split(s.parity_sum, s.parity_n)
	var probes: Dictionary = PerfProbe.drain()
	var ticks: float = float(maxi(s.ticks, 1))
	var line: String = (
		"BENCH_HOST_TICK phase=%s bodies=%d layout=%s smoke=%d ticks=%d mean_ms=%.4f p50_ms=%.2f p99_ms=%.2f p999_ms=%.2f max_ms=%.3f over_budget=%d "
		+ "awake=%.1f scan_phase=%d scan_tick_ms=%.4f other_tick_ms=%.4f "
		+ "snap_parity=%d snap_tick_ms=%.4f nonsnap_tick_ms=%.4f registry_ms=%.4f effects_ms=%.4f snapshot_ms=%.4f"
	) % [
		s.name, _blocks.size(), _layout, int(_smoke), s.ticks, s.mean_ms(),
		s.percentile_ms(0.5), s.percentile_ms(0.99), s.percentile_ms(0.999), s.max_ms, s.over_budget,
		s.awake_sum / ticks,
		int(scan["index"]), float(scan["top"]), float(scan["rest"]),
		int(snap["index"]), float(snap["top"]), float(snap["rest"]),
		_probe_ms(probes, &"registry", s.ticks), _probe_ms(probes, &"block_effects", s.ticks),
		_probe_ms(probes, &"snapshot", s.ticks),
	]
	if s.name == PHASE_ABLATE:
		line += _ablate_fields()
	elif s.name == PHASE_REMAINDER:
		line += _remainder_fields()
	print(line)
	_check_bodies(s.name)


func _probe_ms(probes: Dictionary, key: StringName, ticks: int) -> float:
	if not probes.has(key):
		return 0.0
	return float((probes[key] as Dictionary)["usec"]) / USEC_PER_MS / float(maxi(ticks, 1))


func _slice_mean(slice: int) -> float:
	return _slice_sum_ms[slice] / float(maxi(_slice_n[slice], 1))


## ablate_<x>_delta_ms (median) with _min/_max over the OFF slices, plus batch_vy_on/off.
func _ablate_fields() -> String:
	var text: String = ""
	for subsystem: int in range(SUBSYSTEM_NAMES.size()):
		var deltas: Array[float] = []
		var vy_on: float = 0.0
		var vy_off: float = 0.0
		for slice: int in range(1, _plan.size() - 1):
			if _plan[slice] != subsystem:
				continue
			deltas.append((_slice_mean(slice - 1) + _slice_mean(slice + 1)) * 0.5 - _slice_mean(slice))
			vy_off = maxf(vy_off, _slice_max_vy[slice])
			vy_on = maxf(vy_on, _slice_max_vy[slice - 1])
		deltas.sort()
		var label: String = SUBSYSTEM_NAMES[subsystem]
		text += " ablate_%s_delta_ms=%.4f ablate_%s_min_ms=%.4f ablate_%s_max_ms=%.4f" % [
			label, deltas[deltas.size() / 2], label, deltas[0], label, deltas[deltas.size() - 1],
		]
		if subsystem == SUBSYSTEM_NAMES.size() - 1:
			text += " batch_vy_on=%.3f batch_vy_off=%.3f" % [vy_on, vy_off]
	return text


func _remainder_fields() -> String:
	var off_sum: float = 0.0
	var off_n: int = 0
	var on_sum: float = 0.0
	var on_n: int = 0
	for slice: int in range(_plan.size()):
		if _plan[slice] == PLAN_ALL_OFF:
			off_sum += _slice_mean(slice)
			off_n += 1
		else:
			on_sum += _slice_mean(slice)
			on_n += 1
	return " remainder_ms=%.4f all_on_ms=%.4f" % [off_sum / float(maxi(off_n, 1)), on_sum / float(maxi(on_n, 1))]


## A body below the kill plane (the pile collapsed or was built unstably) fails the run.
func _check_bodies(phase: String) -> void:
	if _kill_plane_falls > 0:
		print("BENCH_HOST_TICK result=FAIL reason=kill_plane_fall phase=%s falls=%d" % [phase, _kill_plane_falls])
		_finished = true
		get_tree().quit(1)


func _finish() -> void:
	_close_phase()
	if _finished:
		return
	_finished = true
	print("BENCH_HOST_TICK pose_hash=%s bodies=%d churn_added=%d smoke=%d" % [
		_pose_hash(), _bodies_wanted, _blocks.size() - _bodies_wanted, int(_smoke),
	])
	print("BENCH_HOST_TICK result=DONE smoke=%d note=headless_timing_is_a_proxy_only" % int(_smoke))
	get_tree().quit(0)


## sha256 of POSE_HASH_BODIES poses spread evenly over the whole pile, rounded, for the
## reference-vs-reference diff: the first bodies are the frozen bottom layer, which no settle or
## wake change would move.
func _pose_hash() -> String:
	var text: String = ""
	var stride: int = maxi(1, _bodies_wanted / POSE_HASH_BODIES)
	for i: int in range(0, _bodies_wanted, stride):
		var block: Block = _blocks[i]
		if not is_instance_valid(block):
			text += "gone;"
			continue
		var xf: Transform3D = block.global_transform
		var q: Quaternion = xf.basis.get_rotation_quaternion()
		for v: float in [xf.origin.x, xf.origin.y, xf.origin.z, q.x, q.y, q.z, q.w]:
			text += "%s," % (snappedf(v, POSE_ROUND_STEP) + 0.0)
		text += ";"
	return text.sha256_text()
