class_name SandboxConeAdapter
extends RefCounted
## The one scene-side bridge used by both sandbox snapshots and live solving.
## Core/SandboxConeExperiment remains pure; this measures block height in the
## same field-local frame as BlockRegistry's current influence circles.


## Bontago-1pi.11.28: the scene-reading half of project(): one field-local
## height per circle, measured on the main thread. {"heights"} or {"error"}.
static func measure_heights(
	circles: Array[InfluenceCircle],
	field: Field,
	registry: BlockRegistry,
	height_source: int
) -> Dictionary:
	if field == null or registry == null:
		return {"error": "Sandbox cone projection needs a field and block registry."}
	if height_source != SandboxConeExperiment.HEIGHT_CENTER and height_source != SandboxConeExperiment.HEIGHT_TOP:
		return {"error": "Unknown cone height source."}
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(circles.size())
	# Bontago-1pi.11.25: the registry's cached field-local COM height replaces
	# instance_from_id + to_local per body when it shares this field.
	var use_registry: bool = height_source == SandboxConeExperiment.HEIGHT_CENTER and registry.uses_field(field)
	var field_xform: Transform3D = registry.field_global_transform() if use_registry else Transform3D.IDENTITY
	var index: int = -1
	for circle: InfluenceCircle in circles:
		index += 1
		if circle.is_home:
			heights[index] = 0.0
			continue
		if height_source == SandboxConeExperiment.HEIGHT_TOP and circle.top_height >= 0.0:
			heights[index] = circle.top_height
			continue
		if use_registry:
			var cached: float = registry.center_height_for_body_id(circle.body_id, field_xform)
			if cached >= 0.0:
				heights[index] = cached
				continue
		var body: Block = instance_from_id(circle.body_id) as Block
		if body == null:
			return {"error": "A settled block disappeared during cone projection."}
		if height_source == SandboxConeExperiment.HEIGHT_TOP:
			heights[index] = registry.top_height_for_block(body)
		else:
			var local_com: Vector3 = field.to_local(body.global_transform * body.center_of_mass)
			heights[index] = maxf(local_com.y, 0.0)
	return {"heights": heights}


static func project(
	circles: Array[InfluenceCircle],
	field: Field,
	registry: BlockRegistry,
	angle_degrees: float,
	height_source: int,
	base_mode: int,
	tuning: TerritoryTuning,
	field_radius: float
) -> Dictionary:
	var measured: Dictionary = measure_heights(circles, field, registry, height_source)
	if measured.has("error"):
		return measured
	var heights: PackedFloat32Array = measured["heights"]
	return SandboxConeExperiment.build(
		circles, heights, angle_degrees, base_mode, tuning.influence_base,
		tuning.influence_max_fraction * field_radius
	)
