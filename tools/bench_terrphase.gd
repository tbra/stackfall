extends Node
## Bontago-1pi.11.21: territory solve phase profile on a real Main/Match host.
##   godot --headless --path . res://tools/bench_terrphase.tscn -- --headless-host --bots=4 \
##       --match-config=res://tools/botmatch_large.tres [--targets=100,200,300] [--live-seconds=40]
## Adds frozen (hence settled) towers until the registry tracks each target count, then times
## every phase of MatchTerritory._run_territory_step() separately (median of REPS, on fresh
## scratch solver/raster/checker so live state is untouched), then watches live play for
## --live-seconds counting solve steps and territory_revision bump causes.
## Diagnostic only (tools/): no gameplay code is touched.

const REPS: int = 7
const LATE_PRIORITY: int = 1000000
const TOWER_MAX: int = 6

var _targets: PackedInt32Array = PackedInt32Array([100, 200, 300])
var _live_seconds: float = 40.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _shape: BlockShape = null
## Live cause tracker: instance id -> [is_settled, marked_transform, owner_slot]
var _prev: Dictionary = {}
var _prev_rev: int = -1
var _causes: Dictionary = {}
var _tracking: bool = false


class LateHook:
	extends Node
	var bench: Node = null

	func _physics_process(_delta: float) -> void:
		bench.call(&"_on_late_physics")


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--targets="):
			_targets = PackedInt32Array()
			for part: String in arg.trim_prefix("--targets=").split(","):
				_targets.append(int(part))
		elif arg.begins_with("--live-seconds="):
			_live_seconds = float(arg.trim_prefix("--live-seconds="))
	_rng.seed = 1121
	_shape = load("res://config/blocks/cube.tres") as BlockShape
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	while Match.state() != Match.State.PLAYING:
		await get_tree().process_frame
	var hook: LateHook = LateHook.new()
	hook.bench = self
	hook.process_physics_priority = LATE_PRIORITY
	add_child(hook)
	if Match._territory._win_checker != null:
		Match._territory._win_checker._capture_hold = 1.0e9
	for target: int in _targets:
		await _grow_to(target)
		_profile(target)
	await _live()
	get_tree().quit()


func _registry() -> BlockRegistry:
	return Match._registry


func _grow_to(target: int) -> void:
	var field: Field = Match.field()
	var radius: float = Match.config.map_def().field_radius
	var slots: int = Match.slot_count()
	while _registry().tracked_block_count() < target:
		var slot_id: int = _rng.randi_range(0, slots - 1)
		var r: float = sqrt(_rng.randf()) * radius * 0.8
		var a: float = _rng.randf() * TAU
		var height: int = _rng.randi_range(1, TOWER_MAX)
		for k: int in range(height):
			var block: Block = BlockFactory.build(_shape, Match._physics_tuning, slot_id, Color.WHITE)
			block.freeze = true
			Match.blocks_parent().add_child(block)
			var local: Vector3 = Vector3(cos(a) * r, 0.5 + float(k), sin(a) * r)
			block.global_transform = Transform3D(field.global_basis, field.to_global(local))
			Events.block_placed.emit(block, _shape.id)
	# Let the settled rule accept the frozen bodies (sleep_settle_time + margin).
	for i: int in range(60):
		await get_tree().physics_frame


func _median_us(c: Callable) -> float:
	var times: Array[int] = []
	for i: int in range(REPS):
		var t0: int = Time.get_ticks_usec()
		c.call()
		times.append(Time.get_ticks_usec() - t0)
	times.sort()
	return float(times[REPS / 2]) / 1000.0


func _profile(target: int) -> void:
	var terr: MatchTerritory = Match._territory
	var tuning: TerritoryTuning = Match._territory_tuning
	var map_def: MapDef = Match.config.map_def()
	var reg: BlockRegistry = _registry()
	var holder: Dictionary = {}
	var sig_ms: float = _median_us(func() -> void: holder["sig"] = terr._territory_source_signature())
	var cmp_ms: float = _median_us(func() -> void: holder["eq"] = holder["sig"] == terr._cached_sources)
	var home_ms: float = _median_us(func() -> void:
		var hs: Array[InfluenceCircle] = []
		for slot_item: PlayerSlot in Match._lifecycle._slots:
			if slot_item.home_flag_alive:
				hs.append(InfluenceCircle.for_home(slot_item.home_position, slot_item.team_id, slot_item.slot_id, tuning))
		holder["homes"] = hs)
	var reg_ms: float = _median_us(func() -> void:
		holder["blocks"] = reg.influence_circles(Match._lifecycle._slots, tuning, map_def))
	var raw: Array[InfluenceCircle] = []
	raw.append_array(holder["homes"])
	raw.append_array(holder["blocks"])
	var cone_ms: float = _median_us(func() -> void:
		holder["proj"] = SandboxConeAdapter.project(raw, Match._field, reg, Match._sandbox_cone_angle,
			Match._sandbox_cone_height_source, Match._sandbox_cone_base_mode, tuning, map_def.field_radius))
	var proj: Dictionary = holder["proj"]
	var circles: Array[InfluenceCircle] = proj["circles"]
	var solver: TerritorySolver = TerritorySolver.new(tuning)
	var solve_ms: float = _median_us(func() -> void: holder["groups"] = solver.solve(circles))
	var groups: TerritoryGroups = holder["groups"]
	var raster: TerritoryRaster = TerritoryRaster.new(terr._cell_grid, tuning)
	raster.set_goal_zones(terr._goal_positions, tuning.goal_zone_radius)
	var raster_ms: float = _median_us(func() -> void: raster.update(circles, groups, 0.05, false, false))
	var checker: WinChecker = WinChecker.new(terr._goal_positions, 1.0e9)
	var win_ms: float = _median_us(func() -> void: checker.update(raster, 0.05))
	var render_ms: float = _median_us(func() -> void: terr._update_circle_render(circles, groups))
	var arrays: Dictionary = terr.circle_render_arrays()
	var upload_ms: float = _median_us(func() -> void:
		Match._field.set_overlay_circles(arrays["xs"], arrays["zs"], arrays["radii"], arrays["teams"],
			arrays["goal_positions"], arrays["goal_radii"], arrays["argmax_mode"]))
	var live_raster: TerritoryRaster = terr._raster
	var event_ms: float = _median_us(func() -> void:
		Events.territory_updated.emit(live_raster, terr._last_groups)
		var shares: PackedFloat32Array = PackedFloat32Array()
		for t: int in range(Match.config.team_count()):
			shares.append(live_raster.team_share(t))
		Events.territory_share_changed.emit(shares)
		Events.goal_capture_progress.emit(terr._win_checker.capturing_team(), terr._win_checker.capture_progress()))
	var last_o: PackedByteArray = live_raster.owner_bytes().duplicate()
	var last_s: PackedByteArray = live_raster.state_bytes().duplicate()
	var diff_ms: float = _median_us(func() -> void:
		var o: PackedByteArray = live_raster.owner_bytes().duplicate()
		var s: PackedByteArray = live_raster.state_bytes().duplicate()
		var changed: PackedInt32Array = PackedInt32Array()
		for i: int in range(o.size()):
			if o[i] != last_o[i] or s[i] != last_s[i]:
				changed.append(i))
	# Work counters for per-item cost.
	var visits: int = 0
	var kept: int = 0
	for g: int in range(groups.group_count()):
		for ci: int in groups.circles_of(g):
			kept += 1
			var rr: float = circles[ci].radius
			visits += int(PI * rr * rr / (terr._cell_grid.cell_size * terr._cell_grid.cell_size))
	# One real full step (cache invalidated) with the built-in profile, for cross-checking.
	Match._sandbox_territory_profile_enabled = true
	terr._cached_groups = null
	terr.mark_dirty()
	terr._run_territory_step(0.05)
	var step: Dictionary = terr.sandbox_profile()["step_ms"]
	Match._sandbox_territory_profile_enabled = false
	print("TP blocks=%d raw=%d projected=%d anchored=%d cells=%d cell_visits~%d cone_cmp=%d pairs=%d" % [
		reg.tracked_block_count(), raw.size(), circles.size(), kept, terr._cell_grid.in_disk_cell_count(),
		visits, int(proj["comparison_count"]), solver.last_pair_count()])
	print("TP ms sig=%.2f sig_cmp=%.2f homes=%.2f reg_circles=%.2f cone=%.2f solve=%.2f raster=%.2f win=%.2f render_total=%.2f overlay_upload=%.2f events=%.2f repl_diff=%.2f" % [
		sig_ms, cmp_ms, home_ms, reg_ms, cone_ms, solve_ms, raster_ms, win_ms, render_ms, upload_ms, event_ms, diff_ms])
	print("TP live_step %s" % [step])


func _live() -> void:
	var terr: MatchTerritory = Match._territory
	_prev.clear()
	_snapshot_entries(_prev)
	_prev_rev = _registry().territory_revision()
	_tracking = true
	var steps0: int = terr.solve_step_count()
	var skips0: int = terr.clean_skip_count()
	PerfProbe.enabled = true
	PerfProbe.drain()
	Match._sandbox_territory_profile_enabled = true
	get_tree().process_frame.connect(_on_frame)
	var start: int = Time.get_ticks_msec()
	var last_steps: int = steps0
	var last_skips: int = skips0
	while float(Time.get_ticks_msec() - start) / 1000.0 < _live_seconds:
		await get_tree().create_timer(5.0).timeout
		var probes: Dictionary = PerfProbe.drain()
		var terr_probe: Dictionary = probes.get(&"territory", {})
		print("TL t=%d blocks=%d steps/s=%.1f clean_skips/s=%.1f terr_probe_peak_ms=%.1f terr_usec_sum_ms=%.1f causes=%s" % [
			(Time.get_ticks_msec() - start) / 1000, _registry().tracked_block_count(),
			float(terr.solve_step_count() - last_steps) / 5.0, float(terr.clean_skip_count() - last_skips) / 5.0,
			float(terr_probe.get("peak_usec", 0)) / 1000.0, float(terr_probe.get("usec", 0)) / 1000.0, _causes])
		last_steps = terr.solve_step_count()
		last_skips = terr.clean_skip_count()
		_causes.clear()
	_tracking = false
	Match._sandbox_territory_profile_enabled = false


var _seen_steps: int = -1


## Prints every live tick that ran a real solve step (profile on), with its split.
func _on_frame() -> void:
	var terr: MatchTerritory = Match._territory
	if terr.solve_step_count() == _seen_steps:
		return
	_seen_steps = terr.solve_step_count()
	var prof: Dictionary = terr.sandbox_profile()
	print("TS steps=%d tick_ms=%.2f n=%d cache_hits=%d last=%s" % [_seen_steps, prof["tick_ms"], prof["steps"], prof["cache_hits"], prof["step_ms"]])


func _snapshot_entries(out: Dictionary) -> void:
	var entries: Dictionary = _registry()._entries
	for id: Variant in entries.keys():
		var e: Variant = entries[id]
		out[id] = [e.is_settled, e.marked_transform, e.owner_slot]


func _bump(cause: String) -> void:
	_causes[cause] = int(_causes.get(cause, 0)) + 1


## Classifies this physics tick's revision bumps by diffing the registry entries.
func _on_late_physics() -> void:
	if not _tracking:
		return
	var rev: int = _registry().territory_revision()
	if rev == _prev_rev:
		return
	var now: Dictionary = {}
	_snapshot_entries(now)
	var explained: int = 0
	for id: Variant in now.keys():
		var cur: Array = now[id]
		if not _prev.has(id):
			_bump("placed")
			explained += 1
			continue
		var old: Array = _prev[id]
		if cur[0] != old[0]:
			_bump("settle_on" if cur[0] else "settle_off")
			explained += 1
		elif cur[0] and cur[1] != old[1]:
			_bump("moved_eps")
			explained += 1
		if cur[2] != old[2]:
			_bump("owner")
			explained += 1
	for id: Variant in _prev.keys():
		if not now.has(id):
			_bump("removed")
			explained += 1
	_bump("ticks_bumped")
	if explained < rev - _prev_rev:
		_bump("unexplained")
	_prev = now
	_prev_rev = rev
