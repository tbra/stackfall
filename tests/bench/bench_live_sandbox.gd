extends Node
## Controlled whole-game frame probe. Unlike bench_rain, this keeps Match,
## the territory overlay and the render path alive while two piles settle.
## Run windowed, away from the desktop:
##   godot --path . --position 10000,10000 res://tests/bench/bench_live_sandbox.tscn

const BLOCK_COUNT: int = 260
const SETTLE_SECONDS: float = 5.0
const SAMPLE_SECONDS: float = 3.0

var _main: Node = null
var _sandbox: Sandbox = null
var _falling_only: bool = false
var _simple_colliders: bool = false
var _merged_colliders: bool = false


func _ready() -> void:
	_falling_only = OS.get_cmdline_user_args().has("falling-only")
	_simple_colliders = OS.get_cmdline_user_args().has("simple-colliders")
	_merged_colliders = OS.get_cmdline_user_args().has("merged-colliders")
	Settings.set_graphics_preset(&"high")
	_main = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	_sandbox = _main._sandbox
	Match._territory_cache_enabled = false
	while Match.state() != Match.State.PLAYING:
		await get_tree().process_frame
	_spawn_piles()
	Match._territory_cache_enabled = true
	await _sample("falling_cached")
	_sandbox._set_block_physics_frozen(true)
	await _sample("falling_frozen")
	_sandbox._set_block_physics_frozen(false)
	if _falling_only:
		get_tree().quit()
		return
	Match._territory_cache_enabled = false
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	var settle_deadline: int = Time.get_ticks_usec() + 15000000
	while _settled_count() < BLOCK_COUNT and Time.get_ticks_usec() < settle_deadline:
		await get_tree().create_timer(0.5).timeout
	print("LIVE_BENCH blocks=%d settled=%d renderer=%s" % [
		Match.blocks_parent().get_child_count(), _settled_count(), DisplayServer.get_name()
	])
	Match.set_sandbox_territory_mode(MatchAutoload.SANDBOX_TERRITORY_CURRENT)
	await _sample("current")
	Match._territory_cache_enabled = true
	await _sample("current_cached")
	_verify_cache_matches_fresh("current")
	Match._territory_cache_enabled = false
	Match.set_sandbox_territory_mode(
		MatchAutoload.SANDBOX_TERRITORY_CONE, 45.0,
		SandboxConeExperiment.HEIGHT_TOP, SandboxConeExperiment.BASE_ADDITIVE
	)
	await _sample("cones")
	Match._territory_cache_enabled = true
	await _sample("cones_cached")
	_verify_cache_matches_fresh("cones")
	Match._territory_cache_enabled = false
	var original_hz: float = Match._territory_tuning.solve_hz
	Match._territory_tuning.solve_hz = 5.0
	await _sample("cones_5hz")
	Match._territory_tuning.solve_hz = original_hz
	Match.set_sandbox_territory_mode(MatchAutoload.SANDBOX_TERRITORY_PAUSED)
	await _sample("territory_paused")
	Match.set_sandbox_territory_mode(
		MatchAutoload.SANDBOX_TERRITORY_CONE, 45.0,
		SandboxConeExperiment.HEIGHT_TOP, SandboxConeExperiment.BASE_ADDITIVE
	)
	_sandbox._set_block_physics_frozen(true)
	await _sample("cones_blocks_frozen")
	Match.set_sandbox_territory_mode(MatchAutoload.SANDBOX_TERRITORY_PAUSED)
	await _sample("both_paused")
	_sandbox._set_block_physics_frozen(false)
	get_tree().quit()


func _spawn_piles() -> void:
	var shapes: Array[BlockShape] = BlockShape.load_all_shapes()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260928
	var field: Field = _main.get_node("Field") as Field
	for i: int in range(BLOCK_COUNT):
		var slot_id: int = i % 2
		var center_x: float = -13.0 if slot_id == 0 else 13.0
		var local: Vector2 = Vector2(
			center_x + rng.randf_range(-4.0, 4.0), rng.randf_range(-4.0, 4.0)
		)
		var height: float = field.surface_y() + rng.randf_range(2.0, 22.0)
		var shape: BlockShape = shapes[rng.randi_range(0, shapes.size() - 1)]
		var block: Block = BlockFactory.build(shape, Match._physics_tuning, slot_id, Match.slot(slot_id).color)
		if _simple_colliders:
			_replace_with_enclosing_box(block)
		elif _merged_colliders:
			_replace_with_merged_boxes(block, shape)
		Match.blocks_parent().add_child(block)
		block.global_position = field.world_from_disk_local(local, height)
		Events.block_placed.emit(block, shape.id)


## Benchmark-only upper bound on collision-shape cost. This fills concavities
## and cube margins, so it must never be used as a gameplay collider.
func _replace_with_enclosing_box(block: Block) -> void:
	var minimum: Vector3 = Vector3(INF, INF, INF)
	var maximum: Vector3 = Vector3(-INF, -INF, -INF)
	var old_shapes: Array[CollisionShape3D] = []
	for child: Node in block.get_children():
		if child is CollisionShape3D:
			var collider: CollisionShape3D = child as CollisionShape3D
			var half: Vector3 = (collider.shape as BoxShape3D).size * 0.5
			minimum = minimum.min(collider.position - half)
			maximum = maximum.max(collider.position + half)
			old_shapes.append(collider)
	for collider: CollisionShape3D in old_shapes:
		block.remove_child(collider)
		collider.free()
	var merged: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = maximum - minimum
	merged.shape = box
	merged.position = (minimum + maximum) * 0.5
	block.add_child(merged)


## Benchmark-only axis-aligned cuboid cover: preserves the shape's outer
## silhouette and concavities, but fills the 0.02 m seams between joined cells.
func _replace_with_merged_boxes(block: Block, shape: BlockShape) -> void:
	if not shape.sloped_cells.is_empty():
		return
	for child: Node in block.get_children():
		if child is CollisionShape3D:
			block.remove_child(child)
			child.free()
	var remaining: Dictionary = {}
	for cell: Vector3i in shape.cells:
		remaining[cell] = true
	var cube_size: float = Match._physics_tuning.cube_size
	var margin: float = Match._physics_tuning.cube_margin
	var pivot: Vector3 = shape.bottom_center()
	while not remaining.is_empty():
		var low: Vector3i = remaining.keys()[0]
		var high: Vector3i = low
		while remaining.has(Vector3i(high.x + 1, low.y, low.z)):
			high.x += 1
		var can_extend: bool = true
		while can_extend:
			for x: int in range(low.x, high.x + 1):
				if not remaining.has(Vector3i(x, high.y + 1, low.z)):
					can_extend = false
					break
			if can_extend:
				high.y += 1
		can_extend = true
		while can_extend:
			for x: int in range(low.x, high.x + 1):
				for y: int in range(low.y, high.y + 1):
					if not remaining.has(Vector3i(x, y, high.z + 1)):
						can_extend = false
						break
			if can_extend:
				high.z += 1
		for x: int in range(low.x, high.x + 1):
			for y: int in range(low.y, high.y + 1):
				for z: int in range(low.z, high.z + 1):
					remaining.erase(Vector3i(x, y, z))
		var collider: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(high - low + Vector3i.ONE) * cube_size - Vector3.ONE * margin
		collider.shape = box
		collider.position = (Vector3(high + low) * 0.5 - pivot) * cube_size
		block.add_child(collider)


func _settled_count() -> int:
	var count: int = 0
	for entry: Variant in Match.registry()._entries.values():
		if entry.is_settled:
			count += 1
	return count


func _verify_cache_matches_fresh(label: String) -> void:
	var cached_owners: PackedByteArray = Match.raster().owner_bytes()
	var cached_states: PackedByteArray = Match.raster().state_bytes()
	Match._territory_cache_enabled = false
	Match._territory._run_territory_step(0.0)
	var fresh_owners: PackedByteArray = Match.raster().owner_bytes()
	var fresh_states: PackedByteArray = Match.raster().state_bytes()
	print("LIVE_BENCH parity mode=%s owners_equal=%s states_equal=%s" % [
		label, cached_owners == fresh_owners, cached_states == fresh_states
	])
	Match._territory_cache_enabled = true


func _sample(label: String) -> void:
	await get_tree().create_timer(0.5).timeout
	var start: int = Time.get_ticks_usec()
	var frames: int = 0
	var process_ms: float = 0.0
	var physics_ms: float = 0.0
	var territory_tick_ms: float = 0.0
	var territory_steps: int = 0
	var cache_hits_before: int = Match._territory.sandbox_profile()["cache_hits"]
	var stages: Dictionary = {"collect": 0.0, "solve": 0.0, "raster": 0.0, "overlay": 0.0, "other": 0.0, "total": 0.0}
	while Time.get_ticks_usec() - start < int(SAMPLE_SECONDS * 1000000.0):
		await get_tree().process_frame
		frames += 1
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var profile: Dictionary = Match._territory.sandbox_profile()
		if Match.sandbox_territory_mode() != MatchAutoload.SANDBOX_TERRITORY_PAUSED:
			territory_tick_ms += profile["tick_ms"]
			territory_steps += profile["steps"]
			var sample: Dictionary = profile["step_ms"]
			for key: String in stages.keys():
				stages[key] += float(sample.get(key, 0.0))
	var elapsed: float = float(Time.get_ticks_usec() - start) / 1000000.0
	var denom: float = maxf(float(frames), 1.0)
	var cache_hits: int = Match._territory.sandbox_profile()["cache_hits"] - cache_hits_before
	print("LIVE_BENCH mode=%s collider=%s fps=%.1f process_ms=%.2f physics_ms=%.2f territory_tick_ms=%.2f steps_per_frame=%.2f cache_hits=%d settled=%d frames=%d" % [
		label, "box" if _simple_colliders else ("merged" if _merged_colliders else "compound"), float(frames) / elapsed, process_ms / denom, physics_ms / denom,
		territory_tick_ms / denom, float(territory_steps) / denom, cache_hits, _settled_count(), frames
	])
	if territory_steps > 0:
		print("LIVE_BENCH stages mode=%s last_step_average_ms=%.2f collect=%.2f solve=%.2f raster=%.2f overlay=%.2f other=%.2f" % [
			label, stages["total"] / denom, stages["collect"] / denom, stages["solve"] / denom,
			stages["raster"] / denom, stages["overlay"] / denom, stages["other"] / denom
		])
