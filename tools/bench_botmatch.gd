extends Node
## Bontago-1pi.11.16: frame-cost attribution during a real headless bot match.
##   godot --headless --path . res://tools/bench_botmatch.tscn -- --headless-host --bots=4 \
##       --probe-seconds=1200 [--weather-cycle=60] [--callcost-awake=100,200] [--churn=N]
## Every second prints one BM line (frame/step/scripts/probes vs awake count); the first
## second each --callcost-awake threshold is crossed it prints per-node script call cost.
## Diagnostic only (tools/): no gameplay code is touched.

const LATE_PRIORITY: int = 1000000
const WEATHERS: Array[StringName] = [&"none", &"breeze", &"rain", &"snow", &"storm"]

var _main: Node = null
var _seconds: float = 1200.0
var _cycle_s: float = 60.0
var _weather_i: int = -1
var _callcost_marks: PackedInt32Array = PackedInt32Array()
var _churn: int = 0
var _no_win: bool = false
var _sequence: Array[StringName] = WEATHERS.duplicate()
var _t_phys_frame: int = 0
var _t_late_phys: int = 0
var _t_proc_frame: int = 0
var _t_last_frame: int = 0
var _acc_phys_scripts: int = 0
var _acc_phys_step: int = 0
var _acc_proc_scripts: int = 0
var _acc_frame: int = 0
var _acc_ticks: int = 0
var _frames: int = 0
var _peak_frame_us: int = 0
var _late_node: Node = null
## Bontago-1pi.11.24 --freeze-trace: per-tick StableBlockManager release causes.
var _freeze_trace: bool = false
var _sim_clock: bool = false
var _ft_prev_frozen: Dictionary = {}
var _ft_prev_sleep: Dictionary = {}
var _ft_prev_field: Transform3D = Transform3D.IDENTITY
var _ft: Dictionary = {}


class LateHook:
	extends Node
	var bench: Node = null

	func _physics_process(_delta: float) -> void:
		bench.call(&"_on_late_physics")

	func _process(_delta: float) -> void:
		bench.call(&"_on_late_process")


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("--probe-seconds="):
			_seconds = float(arg.trim_prefix("--probe-seconds="))
		elif arg.begins_with("--weather-cycle="):
			_cycle_s = float(arg.trim_prefix("--weather-cycle="))
		elif arg == "--freeze-trace":
			_freeze_trace = true
		elif arg == "--sim-clock":
			_sim_clock = true
		elif arg == "--no-win":
			_no_win = true
		elif arg.begins_with("--weather-seq="):
			_sequence = []
			for part: String in arg.trim_prefix("--weather-seq=").split(","):
				_sequence.append(StringName(part))
		elif arg.begins_with("--churn="):
			_churn = int(arg.trim_prefix("--churn="))
		elif arg.begins_with("--callcost-awake="):
			for part: String in arg.trim_prefix("--callcost-awake=").split(","):
				_callcost_marks.append(int(part))
	_main = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	PerfProbe.enabled = true
	get_tree().physics_frame.connect(_on_physics_frame)
	get_tree().process_frame.connect(_on_process_frame)
	_late_node = LateHook.new()
	(_late_node as LateHook).bench = self
	_late_node.process_priority = LATE_PRIORITY
	_late_node.process_physics_priority = LATE_PRIORITY
	add_child(_late_node)
	await _run()
	get_tree().quit()


func _run() -> void:
	var start: int = Time.get_ticks_msec()
	var last_sec: int = 0
	var sim_t: int = 0
	while (float(sim_t) if _sim_clock else float(Time.get_ticks_msec() - start) / 1000.0) < _seconds:
		await get_tree().create_timer(1.0).timeout
		sim_t += 1
		var t: int = sim_t if _sim_clock else (Time.get_ticks_msec() - start) / 1000
		if _cycle_s > 0.0 and int(float(t) / _cycle_s) != _weather_i:
			_weather_i = int(float(t) / _cycle_s)
			var id: StringName = _sequence[_weather_i % _sequence.size()]
			print("BM weather -> %s ok=%s" % [id, Match.weather().set_debug_override(id if id != &"none" else &"")])
		if _no_win and Match._territory._win_checker != null:
			# Keeps the match alive (goal capture would end it): hold never completes.
			Match._territory._win_checker._capture_hold = 1.0e9
		_report(t, t - last_sec)
		if _freeze_trace:
			_ft_report(t)
		last_sec = t
		var awake: int = _awake()
		for i: int in range(_callcost_marks.size() - 1, -1, -1):
			if awake >= _callcost_marks[i]:
				print("BM callcost_at_awake>=%d (awake=%d)" % [_callcost_marks[i], awake])
				_call_cost(12)
				_callcost_marks.remove_at(i)
		if Match.state() != Match.State.PLAYING and t > 30:
			print("BM match state=%s" % [Match.state()])
			break


func _blocks() -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	var parent: Node = Match.blocks_parent()
	if parent == null:
		return out
	for child: Node in parent.get_children():
		if child is RigidBody3D:
			out.append(child as RigidBody3D)
	return out


func _awake() -> int:
	var n: int = 0
	for body: RigidBody3D in _blocks():
		if not body.sleeping and not body.freeze:
			n += 1
	return n


func _report(t: int, dt: int) -> void:
	var f: float = maxf(float(_frames), 1.0)
	var ticks: float = maxf(float(_acc_ticks), 1.0)
	var probes: Dictionary = PerfProbe.drain()
	var text: String = ""
	for key: StringName in probes.keys():
		var e: Dictionary = probes[key]
		# ms per physics tick, calls per second, worst single call ms
		text += " %s=%.2f/%d/%.1f" % [key, float(e["usec"]) / 1000.0 / ticks, int(e["calls"]) / maxi(dt, 1), float(e["peak_usec"]) / 1000.0]
	var blocks: Array[RigidBody3D] = _blocks()
	var frozen: int = 0
	var awake: int = 0
	var moving: int = 0
	var speed_sum: float = 0.0
	for body: RigidBody3D in blocks:
		if body.freeze:
			frozen += 1
		elif not body.sleeping:
			awake += 1
			speed_sum += body.linear_velocity.length()
			if body.linear_velocity.length() > 0.15:
				moving += 1
	print("BM t=%d weather=%s blocks=%d awake=%d moving=%d speed=%.3f frozen=%d frames=%d ticks/frame=%.2f frame_ms=%.2f peak_ms=%.1f step_ms/tick=%.2f scripts_ms/tick=%.2f proc_scripts_ms=%.2f active=%d pairs=%d islands=%d eng_phys=%.1f fps=%d probes(ms/tick,calls/s,peak):%s" % [
		t, Match.weather().active_id(), blocks.size(), awake, moving, speed_sum / maxf(float(awake), 1.0), frozen, _frames, float(_acc_ticks) / f,
		float(_acc_frame) / 1000.0 / f, float(_peak_frame_us) / 1000.0,
		float(_acc_phys_step) / 1000.0 / ticks, float(_acc_phys_scripts) / 1000.0 / ticks,
		float(_acc_proc_scripts) / 1000.0 / f,
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)),
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.TIME_FPS)), text,
	])
	_acc_phys_scripts = 0
	_acc_phys_step = 0
	_acc_proc_scripts = 0
	_acc_frame = 0
	_acc_ticks = 0
	_frames = 0
	_peak_frame_us = 0


func _on_physics_frame() -> void:
	var now: int = Time.get_ticks_usec()
	if _t_late_phys != 0:
		_acc_phys_step += now - _t_late_phys
		_t_late_phys = 0
	_t_phys_frame = now


func _manager() -> Node:
	return _main.get(&"_stable_block_manager") as Node if _main != null else null


func _ft_add(key: String, n: int = 1) -> void:
	_ft[key] = int(_ft.get(key, 0)) + n


func _ft_tick() -> void:
	var mgr: Node = _manager()
	if mgr == null or mgr.get(&"_registry") == null:
		return
	var registry: BlockRegistry = mgr.get(&"_registry") as BlockRegistry
	var field_now: Transform3D = registry.field_global_transform()
	var field_moved: bool = field_now != _ft_prev_field
	if field_moved:
		_ft_add("pose_ticks")
		_ft["tilt_deg"] = maxf(float(_ft.get("tilt_deg", 0.0)), rad_to_deg(field_now.basis.y.angle_to(Vector3.UP)))
	_ft_prev_field = field_now
	var scanned: bool = float(mgr.get(&"_scan_accumulator")) == 0.0
	for block: Block in registry.all_blocks():
		var id: int = block.get_instance_id()
		var frozen: bool = block.freeze
		var was_frozen: bool = bool(_ft_prev_frozen.get(id, false))
		if was_frozen and not frozen:
			if field_moved:
				_ft_add("rel_field")
			elif scanned:
				_ft_add("rel_scan")
			else:
				_ft_add("rel_other")
		elif frozen and not was_frozen:
			_ft_add("freeze")
		_ft_prev_frozen[id] = frozen
		if not frozen:
			var was_sleep: bool = bool(_ft_prev_sleep.get(id, false))
			if was_sleep and not block.sleeping:
				_ft_add("wake")
				var elapsed: float = float((mgr.get(&"_asleep_elapsed") as Dictionary).get(id, 0.0))
				if elapsed >= 5.0:
					_ft_add("wake_after5s")
			elif block.sleeping and not was_sleep:
				_ft_add("sleep")
		_ft_prev_sleep[id] = block.sleeping and not frozen


func _ft_report(t: int) -> void:
	var mgr: Node = _manager()
	if mgr == null:
		return
	var elapsed_map: Dictionary = mgr.get(&"_asleep_elapsed") as Dictionary
	var frozen: int = 0
	var asleep: int = 0
	var awake: int = 0
	var bins: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
	for body: RigidBody3D in _blocks():
		if body.freeze:
			frozen += 1
		elif body.sleeping:
			asleep += 1
			var e: float = float(elapsed_map.get(body.get_instance_id(), 0.0))
			bins[0 if e < 2.0 else (1 if e < 10.0 else (2 if e < 20.0 else 3))] += 1
		else:
			awake += 1
	print("FT t=%d frozen=%d asleep=%d awake=%d asleep_age[<2,<10,<20,>=20]=%s pose_ticks=%d tilt_deg=%.2f rel_field=%d rel_scan=%d rel_other=%d freeze=%d wake=%d wake_after5s=%d sleep=%d" % [
		t, frozen, asleep, awake, bins, int(_ft.get("pose_ticks", 0)), float(_ft.get("tilt_deg", 0.0)),
		int(_ft.get("rel_field", 0)), int(_ft.get("rel_scan", 0)), int(_ft.get("rel_other", 0)),
		int(_ft.get("freeze", 0)), int(_ft.get("wake", 0)), int(_ft.get("wake_after5s", 0)), int(_ft.get("sleep", 0)),
	])
	_ft.clear()


func _on_late_physics() -> void:
	if _freeze_trace:
		_ft_tick()
	if _churn > 0:
		var list: Array[RigidBody3D] = _blocks()
		for i: int in range(mini(_churn, list.size())):
			if not list[i].freeze:
				list[i].sleeping = false
	var now: int = Time.get_ticks_usec()
	if _t_phys_frame != 0:
		_acc_phys_scripts += now - _t_phys_frame
		_acc_ticks += 1
	_t_late_phys = now


func _on_process_frame() -> void:
	var now: int = Time.get_ticks_usec()
	if _t_late_phys != 0:
		_acc_phys_step += now - _t_late_phys
		_t_late_phys = 0
	if _t_last_frame != 0:
		_acc_frame += now - _t_last_frame
		_peak_frame_us = maxi(_peak_frame_us, now - _t_last_frame)
		_frames += 1
	_t_last_frame = now
	_t_proc_frame = now


func _on_late_process() -> void:
	if _t_proc_frame != 0:
		_acc_proc_scripts += Time.get_ticks_usec() - _t_proc_frame


func _call_cost(top: int) -> void:
	var rows: Array = []
	for node: Node in get_tree().root.find_children("*", "", true, false):
		if node.get_script() == null or node == self or node == _late_node:
			continue
		for kind: StringName in [&"_process", &"_physics_process"]:
			var on: bool = node.is_processing() if kind == &"_process" else node.is_physics_processing()
			if not on or not node.has_method(kind):
				continue
			var times: PackedInt32Array = PackedInt32Array()
			for i: int in range(7):
				var t0: int = Time.get_ticks_usec()
				node.call(kind, 0.0166)
				times.append(Time.get_ticks_usec() - t0)
			times.sort()
			var script: Script = node.get_script() as Script
			rows.append([times[3], "%s.%s" % [script.resource_path.get_file(), kind], node.name])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	var total: int = 0
	var phys_total: int = 0
	var proc_total: int = 0
	for row: Array in rows:
		total += int(row[0])
		if String(row[1]).ends_with("_physics_process"):
			phys_total += int(row[0])
		else:
			proc_total += int(row[0])
	print("BM callcost total_us=%d phys_us=%d proc_us=%d nodes=%d" % [total, phys_total, proc_total, rows.size()])
	for i: int in range(mini(top, rows.size())):
		print("BM callcost %6d us  %s (%s)" % [rows[i][0], rows[i][1], rows[i][2]])
