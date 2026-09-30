extends Node
## Bontago-1pi.11 attribution bench: frame time vs settled block count, split
## into physics step wall time, _physics_process / _process script wall time,
## render (rendering info + viewport measured CPU/GPU when windowed) and
## node counts, with one-system-at-a-time toggles.
##   godot --headless --path . res://tools/bench_perf_attrib.tscn -- [--weather=snow] [--counts=25,100,200,300]
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/bench_perf_attrib.tscn -- --agent-probe --render-size=1920x1080 ...
## Diagnostic only (tools/): not part of the running game.

const LATE_PRIORITY: int = 1000000
const SAMPLE_MIN_S: float = 2.0
const SAMPLE_MIN_FRAMES: int = 20
const SAMPLE_MAX_FRAMES: int = 90
const WARMUP_FRAMES: int = 6
const SETTLE_MAX_S: float = 12.0
const GRID_SIDE: int = 5
const GRID_SPACING_M: float = 2.6
const LAYER_HEIGHT_M: float = 3.0

var _main: Node = null
var _field: Field = null
var _spawned: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _shapes: Array[BlockShape] = []
var _players: int = 2
var _churn: int = 0
var _churn_arg: int = 0
var _churn_cursor: int = 0

# timing hooks
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
var _late_node: Node = null
var _render_vp: SubViewport = null


class LateHook:
	extends Node
	var bench: Node = null

	func _physics_process(_delta: float) -> void:
		bench.call(&"_on_late_physics")

	func _process(_delta: float) -> void:
		bench.call(&"_on_late_process")


func _ready() -> void:
	_rng.seed = 20260930
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var counts: PackedInt32Array = PackedInt32Array([25, 100, 200, 300])
	var weather: StringName = &""
	for arg: String in args:
		if arg.begins_with("--counts="):
			counts = PackedInt32Array()
			for part: String in arg.trim_prefix("--counts=").split(","):
				counts.append(int(part))
		elif arg.begins_with("--weather="):
			weather = StringName(arg.trim_prefix("--weather="))
	for arg: String in args:
		if arg.begins_with("--players="):
			_players = clampi(int(arg.trim_prefix("--players=")), 2, 8)
	for arg: String in args:
		if arg.begins_with("--churn="):
			_churn_arg = int(arg.trim_prefix("--churn="))
	var toggles: bool = not args.has("--no-toggles")
	var shot_prefix: String = ""
	for arg: String in args:
		if arg.begins_with("--shot="):
			shot_prefix = arg.trim_prefix("--shot=")
	_shapes = BlockShape.load_all_shapes()
	var preset_id: StringName = &"high"
	for arg: String in args:
		if arg.begins_with("--preset="):
			preset_id = StringName(arg.trim_prefix("--preset="))
	Settings.set_graphics_preset(preset_id)
	_main = (load("res://game/Main.tscn") as PackedScene).instantiate()
	# Bontago-fca.1: with --render-size=WxH the game renders into a SubViewport of
	# that size while the OS window stays tiny (AgentProbe).
	var host: Node = get_tree().root
	if AgentProbe.parse_render_size(args) != Vector2i.ZERO:
		_render_vp = AgentProbe.make_render_viewport(self, Vector2i.ZERO)
		host = _render_vp
	host.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_main.call(&"_start_sandbox_match_with_args", PackedStringArray(["sandbox", "players=%d" % _players]))
	while Match.state() != Match.State.PLAYING:
		await get_tree().process_frame
	_field = _main.get_node("Field") as Field
	PerfProbe.enabled = true
	RenderingServer.viewport_set_measure_render_time(_render_rid(), true)
	get_tree().physics_frame.connect(_on_physics_frame)
	get_tree().process_frame.connect(_on_process_frame)
	_late_node = LateHook.new()
	(_late_node as LateHook).bench = self
	_late_node.process_priority = LATE_PRIORITY
	_late_node.process_physics_priority = LATE_PRIORITY
	add_child(_late_node)
	if weather != &"":
		var ok: bool = Match.weather().set_debug_override(weather)
		print("ATTRIB weather=%s ok=%s" % [weather, ok])
	if args.has("--no-bake"):
		_field.overlay().set_bake_enabled_for_bench(false)
	print("ATTRIB renderer=%s headless=%s window=%s render=%s" % [DisplayServer.get_name(), DisplayServer.get_name() == "headless", DisplayServer.window_get_size(), _render_vp.size if _render_vp != null else get_viewport().get_visible_rect().size])
	for target: int in counts:
		while _spawned < target:
			_spawn_one()
			if _spawned % 10 == 0:
				await get_tree().physics_frame
		await _settle()
		await _sample("base", target)
		if shot_prefix != "":
			var shot_vp: Viewport = _render_vp if _render_vp != null else get_viewport()
			shot_vp.get_texture().get_image().save_png("%s_%d.png" % [shot_prefix, target])
		if not toggles:
			continue
		PhysicsServer3D.set_active(false)
		await _sample("physics_off", target)
		PhysicsServer3D.set_active(true)
		Match.set_sandbox_territory_mode(MatchAutoload.SANDBOX_TERRITORY_PAUSED)
		await _sample("territory_paused", target)
		Match.set_sandbox_territory_mode(MatchAutoload.SANDBOX_TERRITORY_CURRENT)
		_set_blocks_physics_process(false)
		await _sample("block_scripts_off", target)
		_set_blocks_physics_process(true)
		_set_blocks_visible(false)
		await _sample("blocks_hidden", target)
		_set_blocks_visible(true)
		var mirror_was: bool = _set_mirror(false)
		await _sample("mirror_off", target)
		_set_mirror(mirror_was)
		var lights: Array[DirectionalLight3D] = _shadow_lights()
		for light: DirectionalLight3D in lights:
			light.shadow_enabled = false
		await _sample("shadows_off", target)
		for light: DirectionalLight3D in lights:
			light.shadow_enabled = true
		var hidden: Array[CanvasItem] = _hide_ui()
		await _sample("ui_hidden", target)
		for item: CanvasItem in hidden:
			item.visible = true
		await _sample("base_again", target)
	if args.has("--deep"):
		await _deep_toggles(counts[counts.size() - 1])
	if args.has("--callcost"):
		_call_cost()
	if args.has("--subtrees"):
		await _subtree_toggles(counts[counts.size() - 1])
	if args.has("--groups"):
		await _group_toggles(counts[counts.size() - 1])
	get_tree().quit()


func _all_nodes() -> Array[Node]:
	var out: Array[Node] = []
	for node: Node in get_tree().root.find_children("*", "", true, false):
		if node == self or node == _late_node or node is Viewport:
			continue
		out.append(node)
	return out


func _deep_toggles(target: int) -> void:
	var sample_block: Node = Match.blocks_parent().get_child(0)
	var kinds: Dictionary = {}
	for node: Node in sample_block.find_children("*", "", true, false):
		kinds[node.get_class()] = int(kinds.get(node.get_class(), 0)) + 1
	print("ATTRIB block_children=%s" % [kinds])
	var by_class: Dictionary = {}
	for node: Node in get_tree().root.find_children("*", "", true, false):
		by_class[node.get_class()] = int(by_class.get(node.get_class(), 0)) + 1
	print("ATTRIB tree_classes=%s" % [by_class])
	var nodes: Array[Node] = _all_nodes()
	for node: Node in nodes:
		node.set_process(false)
		node.set_physics_process(false)
	await _sample("deep_all_process_off", target)
	for node: Node in nodes:
		node.set_process_internal(false)
		node.set_physics_process_internal(false)
	await _sample("deep_all_internal_off", target)
	for node: Node in nodes:
		node.set_process_internal(true)
		node.set_physics_process_internal(true)
		node.set_process(true)
		node.set_physics_process(true)
	Match.blocks_parent().process_mode = Node.PROCESS_MODE_DISABLED
	await _sample("deep_blocks_parent_disabled", target)
	Match.blocks_parent().process_mode = Node.PROCESS_MODE_INHERIT
	get_tree().root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	await _sample("deep_interp_off", target)
	get_tree().root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	_main.process_mode = Node.PROCESS_MODE_DISABLED
	await _sample("deep_main_disabled", target)
	_main.process_mode = Node.PROCESS_MODE_INHERIT


## Times node._process / _physics_process called directly (median of 15) for every
## processing script node: cost per node independent of frame pacing noise.
func _call_cost() -> void:
	var rows: Array = []
	for node: Node in get_tree().root.find_children("*", "", true, false):
		if node.get_script() == null or node == self or node == _late_node:
			continue
		for kind: StringName in [&"_process", &"_physics_process"]:
			var on: bool = node.is_processing() if kind == &"_process" else node.is_physics_processing()
			if not on or not node.has_method(kind):
				continue
			var times: PackedInt32Array = PackedInt32Array()
			for i: int in range(15):
				var t0: int = Time.get_ticks_usec()
				node.call(kind, 0.0166)
				times.append(Time.get_ticks_usec() - t0)
			times.sort()
			var script: Script = node.get_script() as Script
			rows.append([times[7], "%s.%s path=%s" % [script.resource_path.get_file(), kind, node.get_path()]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	var total: int = 0
	for row: Array in rows:
		total += int(row[0])
	print("ATTRIB callcost total_us=%d nodes=%d" % [total, rows.size()])
	for i: int in range(mini(14, rows.size())):
		print("ATTRIB callcost %6d us  %s" % [rows[i][0], rows[i][1]])


func _find_by_script(global_name: String) -> Node:
	for node: Node in get_tree().root.find_children("*", "", true, false):
		var script: Script = node.get_script() as Script
		if script != null and String(script.get_global_name()) == global_name:
			return node
	return get_tree().root


func _set_subtree_processing(root: Node, on: bool) -> void:
	for node: Node in [root] + root.find_children("*", "", true, false):
		node.set_process(on)
		node.set_physics_process(on)
		node.set_process_internal(on)
		node.set_physics_process_internal(on)


## One sample per direct child of Main / the window root with all processing off in
## that subtree, plus its node count (finds which subtree owns the flat CPU).
func _subtree_toggles(target: int) -> void:
	var roots: Array[Node] = []
	var parents: Array[Node] = [_main, get_tree().root]
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--subtree-of="):
			var found: Node = get_tree().root.find_child(arg.trim_prefix("--subtree-of="), true, false)
			if found != null:
				parents = [found]
	if OS.get_cmdline_user_args().has("--sandbox-children"):
		parents = [_find_by_script("Sandbox")]
	for parent: Node in parents:
		for child: Node in parent.get_children():
			if child == self or child == _main or child == _late_node or child == _render_vp:
				continue
			roots.append(child)
	for child: Node in roots:
		var count: int = 1 + child.find_children("*", "", true, false).size()
		print("ATTRIB subtree %s (%s) nodes=%d" % [child.name, child.get_class(), count])
		_set_subtree_processing(child, false)
		await _sample("sub_off_%s_n%d" % [child.name, count], target)
		_set_subtree_processing(child, true)
		await _sample("sub_recheck_base", target)


func _group_toggles(target: int) -> void:
	var classes: PackedStringArray = PackedStringArray(["TerritoryOverlay", "DiscMirror", "CameraRig", "Minimap", "HUD", "GhostPreview", "Field", "SunFlare", "Fireflies", "PerchingBirds", "DistantBirds", "HomeFlag", "GoalFlag", "Sfx", "Net", "MatchAutoload", "Sandbox", "SandboxPanel", "PerfSampler"])
	var nodes_by_class: Dictionary = {}
	for node: Node in get_tree().root.find_children("*", "", true, false):
		var script: Script = node.get_script() as Script
		if script == null:
			continue
		var name_text: String = String(script.get_global_name())
		if name_text == "":
			name_text = script.resource_path.get_file().get_basename()
		if classes.has(name_text):
			if not nodes_by_class.has(name_text):
				nodes_by_class[name_text] = []
			(nodes_by_class[name_text] as Array).append(node)
	for autoload_name: String in ["Match", "Sfx", "Net"]:
		var auto_node: Node = get_tree().root.get_node_or_null(autoload_name)
		if auto_node != null:
			nodes_by_class["autoload_" + autoload_name] = [auto_node]
	for key: String in nodes_by_class.keys():
		var list: Array = nodes_by_class[key]
		for node: Node in list:
			node.set_process(false)
		await _sample("proc_off_%s_x%d" % [key, list.size()], target)
		for node: Node in list:
			node.set_process(true)
	var homes: Array[InfluenceCircle] = []
	for circle: InfluenceCircle in Match._territory._collect_circles():
		if circle.is_home:
			homes.append(circle)
	Match.set_sandbox_territory_mode(MatchAutoload.SANDBOX_TERRITORY_PAUSED)
	var xs: PackedFloat32Array = PackedFloat32Array()
	var zs: PackedFloat32Array = PackedFloat32Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	var teams: PackedInt32Array = PackedInt32Array()
	for circle: InfluenceCircle in homes:
		xs.append(circle.center.x)
		zs.append(circle.center.y)
		radii.append(circle.radius)
		teams.append(circle.team_id)
	Match._field.set_overlay_circles(xs, zs, radii, teams, Match._territory._goal_positions, Match._territory._goal_radii, Match._territory._circle_argmax_mode)
	await _sample("shader_home_circles_only", target)
	Match.set_sandbox_territory_mode(MatchAutoload.SANDBOX_TERRITORY_CURRENT)
	await _sample("territory_resumed", target)


func _on_physics_frame() -> void:
	var now: int = Time.get_ticks_usec()
	if _t_late_phys != 0:
		_acc_phys_step += now - _t_late_phys
		_t_late_phys = 0
	_t_phys_frame = now


func _on_late_physics() -> void:
	_churn_blocks()
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
		_frames += 1
	_t_last_frame = now
	_t_proc_frame = now


func _on_late_process() -> void:
	if _t_proc_frame != 0:
		_acc_proc_scripts += Time.get_ticks_usec() - _t_proc_frame


## --churn=N: keep N blocks awake by nudging them each tick (owner shot had 6 awake).
func _churn_blocks() -> void:
	if _churn <= 0:
		return
	var list: Array[RigidBody3D] = _blocks()
	if list.is_empty():
		return
	for i: int in range(_churn):
		var body: RigidBody3D = list[(_churn_cursor + i) % list.size()]
		if body.freeze:
			continue
		body.sleeping = false
	_churn_cursor = (_churn_cursor + _churn) % list.size()


func _spawn_one() -> void:
	var slot_id: int = _spawned % _players
	var k: int = _spawned / _players
	var layer: int = k / (GRID_SIDE * GRID_SIDE)
	var cell: int = k % (GRID_SIDE * GRID_SIDE)
	var gx: float = (float(cell % GRID_SIDE) - float(GRID_SIDE - 1) * 0.5) * GRID_SPACING_M
	var gz: float = (float(cell / GRID_SIDE) - float(GRID_SIDE - 1) * 0.5) * GRID_SPACING_M
	var home: Vector2 = Match.slot(slot_id).home_position
	var local: Vector2 = home + Vector2(gx, gz) + home.normalized() * -float(GRID_SIDE) * GRID_SPACING_M * 0.5
	var height: float = _field.surface_y() + 1.5 + float(layer) * LAYER_HEIGHT_M
	var shape: BlockShape = _shapes[_rng.randi_range(0, _shapes.size() - 1)]
	var block: Block = BlockFactory.build(shape, Match._physics_tuning, slot_id, Match.slot(slot_id).color)
	Match.blocks_parent().add_child(block)
	block.global_position = _field.world_from_disk_local(local, height)
	Events.block_placed.emit(block, shape.id)
	_spawned += 1


func _blocks() -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	for child: Node in Match.blocks_parent().get_children():
		if child is RigidBody3D:
			out.append(child as RigidBody3D)
	return out


func _awake() -> int:
	var n: int = 0
	for body: RigidBody3D in _blocks():
		if not body.sleeping and not body.freeze:
			n += 1
	return n


func _settle() -> void:
	var deadline: int = Time.get_ticks_usec() + int(SETTLE_MAX_S * 1000000.0)
	while Time.get_ticks_usec() < deadline:
		await get_tree().create_timer(0.5).timeout
		if _awake() == 0:
			break
	for body: RigidBody3D in _blocks():
		body.sleeping = true
	await get_tree().create_timer(1.0).timeout


func _set_blocks_physics_process(on: bool) -> void:
	for body: RigidBody3D in _blocks():
		body.set_physics_process(on)


func _set_blocks_visible(on: bool) -> void:
	for body: RigidBody3D in _blocks():
		body.visible = on


func _set_mirror(on: bool) -> bool:
	var mirrors: Array[Node] = get_tree().root.find_children("*", "DiscMirror", true, false)
	var was: bool = true
	for node: Node in mirrors:
		var visuals: TerritoryVisuals = node.get(&"visuals") as TerritoryVisuals
		if visuals != null:
			was = visuals.mirror_enabled
			visuals.mirror_enabled = on
	return was


func _shadow_lights() -> Array[DirectionalLight3D]:
	var out: Array[DirectionalLight3D] = []
	for node: Node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		var light: DirectionalLight3D = node as DirectionalLight3D
		if light.shadow_enabled:
			out.append(light)
	return out


func _hide_ui() -> Array[CanvasItem]:
	var out: Array[CanvasItem] = []
	for node: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		for child: Node in node.get_children():
			var item: CanvasItem = child as CanvasItem
			if item != null and item.visible:
				item.visible = false
				out.append(item)
	return out


func _render_rid() -> RID:
	return (_render_vp if _render_vp != null else get_viewport()).get_viewport_rid()


func _sample(label: String, target: int) -> void:
	for i: int in range(WARMUP_FRAMES):
		await get_tree().process_frame
	PerfProbe.drain()
	_acc_phys_scripts = 0
	_acc_phys_step = 0
	_acc_proc_scripts = 0
	_acc_frame = 0
	_acc_ticks = 0
	_frames = 0
	var vp: RID = _render_rid()
	var gpu_sum: float = 0.0
	var rcpu_sum: float = 0.0
	var start: int = Time.get_ticks_usec()
	while (_frames < SAMPLE_MIN_FRAMES or Time.get_ticks_usec() - start < int(SAMPLE_MIN_S * 1000000.0)) and _frames < SAMPLE_MAX_FRAMES:
		await get_tree().process_frame
		gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		rcpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(vp)
	var f: float = maxf(float(_frames), 1.0)
	var probes: Dictionary = PerfProbe.drain()
	var probe_text: String = ""
	for key: StringName in probes.keys():
		var entry: Dictionary = probes[key]
		probe_text += " %s=%.2f/%.1f" % [key, float(entry["usec"]) / 1000.0 / f, float(entry["peak_usec"]) / 1000.0]
	var overlay: TerritoryOverlay = _field.overlay()
	print("ATTRIB n=%d mode=%s spawned=%d live=%d awake=%d frames=%d frame_ms=%.2f ticks_per_frame=%.2f phys_step_ms=%.2f phys_scripts_ms=%.2f proc_scripts_ms=%.2f rest_ms=%.2f rs_cpu_ms=%.2f gpu_ms=%.2f draws=%d objects=%d prims=%d nodes=%d objs=%d circles=%d probes(ms/frame/peak):%s" % [
		target, label, _spawned, _blocks().size(), _awake(), _frames,
		float(_acc_frame) / 1000.0 / f, float(_acc_ticks) / f,
		float(_acc_phys_step) / 1000.0 / f, float(_acc_phys_scripts) / 1000.0 / f,
		float(_acc_proc_scripts) / 1000.0 / f,
		float(_acc_frame - _acc_phys_step - _acc_phys_scripts - _acc_proc_scripts) / 1000.0 / f,
		rcpu_sum / f, gpu_sum / f,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		overlay.circle_count() if overlay != null else -1, probe_text + " engine_proc=%.2f engine_phys=%.2f" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0],
	])
