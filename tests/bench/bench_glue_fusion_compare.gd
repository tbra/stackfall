extends Node3D
## Bontago-1pi.85.74.9: glue joints vs fusion comparison bench. Same scenario on both code bases
## (uses only GlueDrops.bind / Block.kick, which exist before and after fusion).
## Phases: settle (towers fall + glue), rest, topple (kick), merge (bridge bar over two towers).
## Run alone: godot --headless --path . res://tests/bench/bench_glue_fusion_compare.tscn
## Metric: Performance.TIME_PHYSICS_PROCESS (whole physics iteration: step + script), previous tick.

const TOWERS: int = 6
const TOWER_CUBES: int = 8
const RING_RADIUS_M: float = 6.0
const BRIDGE_TOWER_CUBES: int = 6
const BRIDGE_TOWER_X_M: float = 1.0
const BRIDGE_ORIGIN_M: Vector3 = Vector3(0.0, 0.0, -14.0)
const GAP_M: float = 0.03
const KICK_MPS: float = 8.0
const SETTLE_TICKS: int = 180
const REST_TICKS: int = 240
const TOPPLE_TICKS: int = 180
const MERGE_TOWER_SETTLE_TICKS: int = 120
const MERGE_TICKS: int = 120
const WARMUP_TICKS: int = 5
const SEED: int = 20261014

var _phase: String = "settle"
var _phase_ticks: int = 0
var _samples: Dictionary = {}
var _towers: Array = []
var _shapes: Dictionary = {}
var _tuning: PhysicsTuning = null
var _glue: GlueDropTuning = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _warm: int = 0


func _ready() -> void:
	add_child(Field.new())
	for shape: BlockShape in BlockShape.load_all_shapes():
		_shapes[shape.id] = shape
	_tuning = preload("res://config/physics_tuning.tres")
	_glue = preload("res://config/glue_drop_tuning.tres")
	_rng.seed = SEED
	for t: int in range(TOWERS):
		var angle: float = TAU * float(t) / float(TOWERS)
		var base: Vector3 = Vector3(cos(angle) * RING_RADIUS_M, 0.0, sin(angle) * RING_RADIUS_M)
		_towers.append(_spawn_tower(base, TOWER_CUBES))
	print("BENCH_FUSION start towers=%d cubes=%d" % [TOWERS, TOWER_CUBES])


func _spawn_tower(base: Vector3, cubes: int) -> Array[Block]:
	var result: Array[Block] = []
	for i: int in range(cubes):
		result.append(_spawn_charged(&"cube", base + Vector3(_rng.randf_range(-0.02, 0.02), 0.02 + float(i) * (1.0 + GAP_M), 0.0)))
	return result


func _spawn_charged(shape_id: StringName, pos: Vector3) -> Block:
	var block: Block = BlockFactory.build(_shapes[shape_id], _tuning) as Block
	add_child(block)
	block.global_position = pos
	var glue: GlueDrops = GlueDrops.new()
	block.add_child(glue)
	glue.bind(block, _glue)
	return block


func _physics_process(_delta: float) -> void:
	_warm += 1
	if _warm <= WARMUP_TICKS:
		return
	var ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	if not _samples.has(_phase):
		_samples[_phase] = []
	(_samples[_phase] as Array).append(ms)
	_phase_ticks += 1
	match _phase:
		"settle":
			if _phase_ticks >= SETTLE_TICKS:
				_enter("rest")
		"rest":
			if _phase_ticks == 1:
				_report_counts("rest")
			if _phase_ticks >= REST_TICKS:
				for tower: Array in _towers:
					(tower[tower.size() / 2] as Block).kick(Vector3(KICK_MPS, 0.0, 0.0))
				_enter("topple")
		"topple":
			if _phase_ticks >= TOPPLE_TICKS:
				_spawn_bridge_towers()
				_enter("merge_towers_settle")
		"merge_towers_settle":
			if _phase_ticks >= MERGE_TOWER_SETTLE_TICKS:
				_spawn_charged(&"bar3", BRIDGE_ORIGIN_M + Vector3(0.0, 0.1 + float(BRIDGE_TOWER_CUBES) * (1.0 + GAP_M), 0.0))
				_enter("merge")
		"merge":
			if _phase_ticks >= MERGE_TICKS:
				_report_counts("end")
				_finish()


func _spawn_bridge_towers() -> void:
	_spawn_tower(BRIDGE_ORIGIN_M + Vector3(-BRIDGE_TOWER_X_M, 0.0, 0.0), BRIDGE_TOWER_CUBES)
	_spawn_tower(BRIDGE_ORIGIN_M + Vector3(BRIDGE_TOWER_X_M, 0.0, 0.0), BRIDGE_TOWER_CUBES)


func _enter(next: String) -> void:
	_phase = next
	_phase_ticks = 0


func _report_counts(tag: String) -> void:
	var bodies: int = 0
	var shapes: int = 0
	var joints: int = 0
	var carriers: int = 0
	for node: Node in _all_nodes(self):
		if node is RigidBody3D:
			bodies += 1
		if node is CollisionShape3D and node.get_parent() is RigidBody3D:
			shapes += 1
		if node is Joint3D:
			joints += 1
		if node.get_class() != "" and node.get_script() != null and str((node.get_script() as Script).get_global_name()) == "FusedBody":
			carriers += 1
	print("BENCH_FUSION counts %s rigid_bodies=%d body_shapes=%d joints=%d fused_carriers=%d active_3d=%d pairs=%d" % [tag, bodies, shapes, joints, carriers, int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)), int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))])


func _all_nodes(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		out.append(n)
		stack.append_array(n.get_children())
	return out


func _finish() -> void:
	for phase: String in _samples.keys():
		var arr: Array = (_samples[phase] as Array).duplicate()
		# drop the first tick of each phase (previous-phase carry-over) except for merge, where
		# the one-off fuse spike is exactly what the worst figure is for.
		var sum: float = 0.0
		for v: float in arr:
			sum += v
		var sorted: Array = arr.duplicate()
		sorted.sort()
		var p99: float = sorted[mini(sorted.size() - 1, int(ceil(float(sorted.size()) * 0.99)) - 1)]
		print("BENCH_FUSION phase=%s ticks=%d mean_ms=%.4f p99_ms=%.4f worst_ms=%.4f" % [phase, arr.size(), sum / float(arr.size()), p99, sorted[sorted.size() - 1]])
	get_tree().quit()
