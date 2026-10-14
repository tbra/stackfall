class_name BotStackProbe
extends RefCounted
## Bontago-1t5.53b (docs/BOT_TOWER_PLAN.md C "1t5.53b"): collects the bodies the bot's tower statics
## model (core/ai/BotStack.gd) analyses. Scene-facing, hence in game/ and not in core/ai/.
##
## build() snapshots every simulating body (unfused blocks and one FusedBody carrier per group) of ANY
## team whose centre of mass lies within BotStackTuning.snapshot_radius_m of a tower source, nearest
## first, capped at snapshot_max_bodies. Cubes come from the body's CollisionShape3D children, so fused
## and gift bodies are covered without special cases. The cube list of a body is cached per instance,
## keyed on its global transform, the field's transform and its child count: a sleeping block costs one
## comparison per think. The analysis itself is sliced by BotThink's STACK phase (analyse_step).
## DECISION: the shipped disc surface is field-local y = 0 (probe heights are field-local, "above the
## disc"), so ground_y stays 0.

## Body instance id -> {xform, field_xform, child_count, cubes, basis}.
static var _cache: Dictionary = {}


## `registry` and `field` null (or no `centres`) give null: no tower statics. `team_of` maps an owner
## slot to its team (Callable(int) -> int; slots < 0 get team -1).
static func build(
	registry: BlockRegistry, field: Node3D, centres: PackedVector2Array, tuning: BotStackTuning,
	cube_size: float, team_of: Callable
) -> BotStack:
	if registry == null or field == null or centres.is_empty():
		return null
	var field_xform: Transform3D = field.global_transform
	var field_basis_inv: Basis = field_xform.basis.orthonormalized().inverse()
	var near: Array[Dictionary] = []
	var radius_sq: float = tuning.snapshot_radius_m * tuning.snapshot_radius_m
	for body: Block in registry.physics_bodies():
		if not is_instance_valid(body) or not body.is_inside_tree():
			continue
		var local_com: Vector3 = field.to_local(body.global_transform * body.center_of_mass)
		var com_xz: Vector2 = Vector2(local_com.x, local_com.z)
		var best_sq: float = INF
		for centre: Vector2 in centres:
			best_sq = minf(best_sq, com_xz.distance_squared_to(centre))
		if best_sq <= radius_sq:
			near.append({"body": body, "dist": best_sq})
	near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["dist"] != b["dist"]:
			return (a["dist"] as float) < (b["dist"] as float)
		return (a["body"] as Block).get_instance_id() < (b["body"] as Block).get_instance_id()
	)
	var stack: BotStack = BotStack.new()
	stack.cube_size = cube_size
	stack.ground_y = 0.0
	if _cache.size() > tuning.probe_cache_limit:
		_cache.clear()
	for entry: Dictionary in near.slice(0, maxi(tuning.snapshot_max_bodies, 0)):
		var body: Block = entry["body"] as Block
		var data: Dictionary = _cubes_of(body, field, field_xform, field_basis_inv)
		var cubes: PackedVector3Array = data["cubes"] as PackedVector3Array
		var team: int = int(team_of.call(body.owner_slot)) if body.owner_slot >= 0 else -1
		var settled: bool = body.sleeping or body.freeze or body.linear_velocity.length() <= tuning.settled_speed_mps
		stack.add_body(body.get_instance_id(), team, data["basis"] as Basis, cubes, body.mass, settled)
	return stack


## The disk-local cube centres and basis of `body` (cached while its transforms and children hold).
static func _cubes_of(body: Block, field: Node3D, field_xform: Transform3D, field_basis_inv: Basis) -> Dictionary:
	var id: int = body.get_instance_id()
	var xform: Transform3D = body.global_transform
	var child_count: int = body.get_child_count()
	var cached: Dictionary = _cache.get(id, {}) as Dictionary
	if (
		not cached.is_empty() and cached["xform"] == xform and cached["field_xform"] == field_xform
		and cached["child_count"] == child_count
	):
		return cached
	var cubes: PackedVector3Array = PackedVector3Array()
	for child: Node in body.get_children():
		var shape: CollisionShape3D = child as CollisionShape3D
		if shape != null and not shape.disabled:
			cubes.append(field.to_local(xform * shape.position))
	var data: Dictionary = {
		"xform": xform, "field_xform": field_xform, "child_count": child_count, "cubes": cubes,
		"basis": field_basis_inv * xform.basis.orthonormalized(),
	}
	_cache[id] = data
	return data
