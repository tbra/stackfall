extends Node
## Bontago-1pi.11 diagnostic: instances the real Main.tscn under a
## `-- --headless-host --bots=<n>` command line and samples engine object
## counters over time, then restarts the match (abort -> start) a few times.
## Run:
##   godot --headless --path . res://tools/pt11_leak_probe.tscn -- --headless-host --bots=8
## Not part of the game; diagnostics only.

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")
const SAMPLE_INTERVAL_S: float = 5.0
var MATCH_SECONDS: float = 40.0
var MATCH_COUNT: int = 3

var _main: Node = null
var _elapsed: float = 0.0
var _next_sample: float = 0.0
var _match_index: int = 0
var _match_elapsed: float = 0.0
var _baseline_hist: Dictionary = {}
var _placements: int = 0
var _profile: bool = false
var _ab: bool = false
const AB_THRESHOLDS: Array[int] = [40, 90, 150, 190]
const AB_VARIANTS: Array[String] = ["base", "mirror_off", "fx_off", "circles_off", "all_off", "base2"]
const AB_SETTLE_FRAMES: int = 15
const AB_FRAMES: int = 120
var _ab_threshold_index: int = 0
var _ab_variant: int = -1
var _ab_frame: int = 0
var _ab_us: int = 0
var _ab_draws: int = 0
var _ab_prims: int = 0
var _ab_objs: int = 0
var _ab_phys: float = 0.0
var _ab_proc: float = 0.0
var _ab_last_us: int = 0
var _ab_saved_threshold: float = 0.0
var _ab_saved_circles: int = 0
var _profile_groups: Array = []
var _profile_index: int = -2
var _profile_frames: int = 0
var _profile_accum_us: int = 0
var _profile_last_us: int = 0
var PROFILE_WARMUP_S: float = 15.0
var _win_frames: int = 0
var _win_us: int = 0
var _win_last_us: int = 0
const PROFILE_FRAMES: int = 40


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for raw: String in OS.get_cmdline_user_args():
		if raw.begins_with("--probe-seconds="):
			MATCH_SECONDS = float(raw.get_slice("=", 1))
		elif raw.begins_with("--probe-profile-at="):
			PROFILE_WARMUP_S = float(raw.get_slice("=", 1))
		elif raw == "--probe-ab":
			_ab = true
		elif raw == "--probe-profile":
			_profile = true
		elif raw.begins_with("--probe-matches="):
			MATCH_COUNT = int(raw.get_slice("=", 1))
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	Events.block_placed.connect(func(_b: RigidBody3D, _s: StringName) -> void: _placements += 1)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	_match_elapsed += delta
	if _elapsed >= _next_sample:
		_next_sample += SAMPLE_INTERVAL_S
		_sample()
	if _match_elapsed >= MATCH_SECONDS:
		_match_elapsed = 0.0
		_match_index += 1
		_print_hist_diff()
		if _match_index >= MATCH_COUNT:
			get_tree().quit(0)
			return
		var config: MatchConfig = Match.config
		Match.abort_match()
		print("PT11 restart match %d" % _match_index)
		Match.start_match(config)


func _sample() -> void:
	var reg: BlockRegistry = Match.registry()
	var tracked: int = reg.tracked_block_count() if reg != null else -1
	var frame_ms: float = float(_win_us) / float(maxi(_win_frames, 1)) / 1000.0
	_win_us = 0
	_win_frames = 0
	print("PT11 wall_frame_ms=%.2f" % frame_ms)
	if Match._territory != null and Match._territory._solver != null and Match.state() == Match.State.PLAYING:
		var t0: int = Time.get_ticks_usec()
		var circles: Array[InfluenceCircle] = Match._territory._collect_circles()
		var t1: int = Time.get_ticks_usec()
		Match._territory._solver.solve(circles)
		var t2: int = Time.get_ticks_usec()
		Match._territory._run_territory_step(1.0 / 20.0)
		var t3: int = Time.get_ticks_usec()
		print("PT11 terr circles=%d collect_ms=%.2f solve_ms=%.2f full_step_ms=%.2f" % [circles.size(), (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0])
	print("PT11 t=%.0f m=%d state=%s placed=%d tracked=%d obj=%d nodes=%d orphan=%d res=%d phys_active=%d proc_ms=%.2f phys_ms=%.2f draws=%d prims=%d" % [
		_elapsed, _match_index, str(Match.State.find_key(Match.state())), _placements, tracked,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
	])


func _histogram() -> Dictionary:
	var hist: Dictionary = {}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var key: String = n.get_class()
		var s: Script = n.get_script() as Script
		if s != null:
			key = s.resource_path.get_file()
		hist[key] = int(hist.get(key, 0)) + 1
		for c: Node in n.get_children(true):
			stack.append(c)
	return hist


func _print_hist_diff() -> void:
	var hist: Dictionary = _histogram()
	if _baseline_hist.is_empty():
		_baseline_hist = hist
		var keys: Array = hist.keys()
		var parts: PackedStringArray = []
		for k: Variant in keys:
			if int(hist[k]) >= 5:
				parts.append("%s=%d" % [k, hist[k]])
		print("PT11 hist m=%d %s" % [_match_index, ", ".join(parts)])
		return
	var parts2: PackedStringArray = []
	for k: Variant in hist.keys():
		var d: int = int(hist[k]) - int(_baseline_hist.get(k, 0))
		if d != 0:
			parts2.append("%s%+d(=%d)" % [k, d, hist[k]])
	for k: Variant in _baseline_hist.keys():
		if not hist.has(k):
			parts2.append("%s-%d(=0)" % [k, _baseline_hist[k]])
	print("PT11 histdiff m=%d vs m=0: %s" % [_match_index, ", ".join(parts2)])


func _process(_delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _ab:
		_ab_step()
	var t_now: int = Time.get_ticks_usec()
	if _win_last_us > 0:
		_win_frames += 1
		_win_us += t_now - _win_last_us
	_win_last_us = t_now
	if not _profile or _elapsed < PROFILE_WARMUP_S:
		return
	var now: int = Time.get_ticks_usec()
	var dt: int = now - _profile_last_us
	_profile_last_us = now
	if _profile_index == -2:
		_build_profile_groups()
		_profile_index = -1
		_profile_frames = 0
		_profile_accum_us = 0
		return
	_profile_frames += 1
	_profile_accum_us += dt
	if _profile_frames < PROFILE_FRAMES:
		return
	var label: String = "baseline" if _profile_index < 0 else String(_profile_groups[_profile_index]["name"])
	print("PT11 profile %s avg_frame_ms=%.2f" % [label, float(_profile_accum_us) / float(_profile_frames) / 1000.0])
	if _profile_index >= 0:
		_set_group(_profile_groups[_profile_index], true)
	_profile_index += 1
	_profile_frames = 0
	_profile_accum_us = 0
	if _profile_index >= _profile_groups.size():
		_profile_index = -1
		_profile = false
		print("PT11 profile done")
		return
	_set_group(_profile_groups[_profile_index], false)


func _set_group(group: Dictionary, enabled: bool) -> void:
	for n: Node in group["nodes"]:
		if not is_instance_valid(n):
			continue
		if group["physics"]:
			n.set_physics_process(enabled)
		else:
			n.set_process(enabled)


func _build_profile_groups() -> void:
	var by_key: Dictionary = {}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c: Node in n.get_children(true):
			stack.append(c)
		if n == self:
			continue
		var s: Script = n.get_script() as Script
		var key: String = s.resource_path.get_file() if s != null else n.get_class()
		if n.is_processing():
			var k: String = key + ":process"
			if not by_key.has(k):
				by_key[k] = {"name": k, "physics": false, "nodes": []}
			by_key[k]["nodes"].append(n)
		if n.is_physics_processing():
			var k2: String = key + ":physics"
			if not by_key.has(k2):
				by_key[k2] = {"name": k2, "physics": true, "nodes": []}
			by_key[k2]["nodes"].append(n)
	_profile_groups = by_key.values()
	var names: PackedStringArray = []
	for g: Dictionary in _profile_groups:
		names.append("%s x%d" % [g["name"], g["nodes"].size()])
	print("PT11 profile groups: %s" % ", ".join(names))


func _find_first(script_file: String) -> Node:
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var sc: Script = n.get_script() as Script
		if sc != null and sc.resource_path.get_file() == script_file:
			return n
		for c: Node in n.get_children(true):
			stack.append(c)
	return null


func _ab_apply(variant: String) -> void:
	var mirror: DiscMirror = _find_first("DiscMirror.gd") as DiscMirror
	var fx: BlockEffectsManager = _find_first("BlockEffectsManager.gd") as BlockEffectsManager
	var visuals: TerritoryVisuals = load("res://config/territory_visuals.tres") as TerritoryVisuals
	var mirror_off: bool = variant == "mirror_off" or variant == "all_off"
	var fx_off: bool = variant == "fx_off" or variant == "all_off"
	var circles_off: bool = variant == "circles_off" or variant == "all_off"
	if mirror != null:
		mirror.visuals.mirror_enabled = not mirror_off
	if fx != null:
		if _ab_saved_threshold <= 0.0:
			_ab_saved_threshold = fx.config.dust_impact_speed_threshold
		fx.config.dust_impact_speed_threshold = 1.0e9 if fx_off else _ab_saved_threshold
		fx._trail_effects_enabled = not fx_off
	if _ab_saved_circles <= 0:
		_ab_saved_circles = visuals.max_shader_circles
	visuals.max_shader_circles = 0 if circles_off else _ab_saved_circles


func _ab_step() -> void:
	var now: int = Time.get_ticks_usec()
	var dt: int = now - _ab_last_us
	_ab_last_us = now
	if _ab_threshold_index >= AB_THRESHOLDS.size():
		return
	var reg: BlockRegistry = Match.registry()
	var tracked: int = reg.tracked_block_count() if reg != null else 0
	if _ab_variant < 0:
		if tracked < AB_THRESHOLDS[_ab_threshold_index]:
			return
		_ab_variant = 0
		_ab_frame = 0
		_ab_apply(AB_VARIANTS[0])
		print("PT11 AB begin threshold=%d tracked=%d" % [AB_THRESHOLDS[_ab_threshold_index], tracked])
		return
	_ab_frame += 1
	if _ab_frame <= AB_SETTLE_FRAMES:
		_ab_us = 0
		_ab_draws = 0
		_ab_prims = 0
		_ab_objs = 0
		_ab_phys = 0.0
		_ab_proc = 0.0
		return
	_ab_us += dt
	_ab_draws += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_ab_prims += int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_ab_objs += int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_ab_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	_ab_proc += Performance.get_monitor(Performance.TIME_PROCESS)
	var n: int = _ab_frame - AB_SETTLE_FRAMES
	if n < AB_FRAMES:
		return
	print("PT11 AB tracked=%d variant=%s frame_ms=%.2f draws=%d prims=%d objs=%d phys_ms=%.2f proc_ms=%.2f active=%d" % [
		tracked, AB_VARIANTS[_ab_variant], float(_ab_us) / n / 1000.0,
		_ab_draws / n, _ab_prims / n, _ab_objs / n, _ab_phys / n * 1000.0, _ab_proc / n * 1000.0,
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
	])
	_ab_variant += 1
	_ab_frame = 0
	if _ab_variant >= AB_VARIANTS.size():
		_ab_apply("base")
		_ab_variant = -1
		_ab_threshold_index += 1
		if _ab_threshold_index >= AB_THRESHOLDS.size():
			print("PT11 AB done")
			get_tree().quit(0)
		return
	_ab_apply(AB_VARIANTS[_ab_variant])
