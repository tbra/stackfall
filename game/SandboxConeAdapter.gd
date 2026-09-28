class_name SandboxConeAdapter
extends RefCounted
## The one scene-side bridge used by both sandbox snapshots and live solving.
## Core/SandboxConeExperiment remains pure; this measures block height in the
## same field-local frame as BlockRegistry's current influence circles.


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
	if field == null or registry == null:
		return {"error": "Sandbox cone projection needs a field and block registry."}
	if height_source != SandboxConeExperiment.HEIGHT_CENTER and height_source != SandboxConeExperiment.HEIGHT_TOP:
		return {"error": "Unknown cone height source."}
	var heights: PackedFloat32Array = PackedFloat32Array()
	for circle: InfluenceCircle in circles:
		if circle.is_home:
			heights.append(0.0)
			continue
		var body: Block = instance_from_id(circle.body_id) as Block
		if body == null:
			return {"error": "A settled block disappeared during cone projection."}
		if height_source == SandboxConeExperiment.HEIGHT_TOP:
			heights.append(registry.top_height_for_block(body))
		else:
			var local_com: Vector3 = field.to_local(body.global_transform * body.center_of_mass)
			heights.append(maxf(local_com.y, 0.0))
	return SandboxConeExperiment.build(
		circles, heights, angle_degrees, base_mode, tuning.influence_base,
		tuning.influence_max_fraction * field_radius
	)
