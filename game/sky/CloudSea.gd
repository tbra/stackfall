class_name CloudSea
extends Node3D
## The near/mid-field cloud sea below the floating disc --
## real 3D stylized cumulus. One MultiMeshInstance3D draws flat-bottomed
## low-poly spheres ("puffs") clustered into cumulus clumps scattered on a
## ring around and below the disc; shaders/sky/cloud_puffs.gdshader toon-shades
## them from cycle colours, drifts every clump slowly around the disc and
## billows the surfaces, all from TIME and per-instance custom data -- no
## per-frame script, so it animates in the game, the editor and the baked
## demo. Distant clumps fade into the procedural far cloud sea
## (sampled along the view ray in the puff shader), so there is no seam.
##
## Placement is deterministic (SkyCycleDef.cloud_seed). Every puff top stays
## at or below SkyCycleDef.cloud_top_max_m, far under the disc's underside
## and the 0..72 m play volume. game/sky/Skybox.gd owns one of these and calls
## configure_cycle() on cycle and graphics-preset changes.

## Render layer bit the puffs live on (layer 19). Skybox.PROBE_CULL_MASK (the disc ReflectionProbe's mask) excludes it: the
## puffs sit below the disc plane and must never appear in its reflection.
const RENDER_LAYER_BIT: int = 1 << 18
## Sky-material uniforms the puff shader shares so its far fade matches the
## sky drawn behind it exactly.
const SHARED_SKY_PARAMETERS: Array[StringName] = [
	&"exposure", &"grade_amount", &"grade_dark", &"grade_mid",
	&"grade_light", &"grade_gamma",
	# Procedural sea/gradient the far fade targets.
	&"procedural_sea_mix", &"noise_tex", &"sun_direction", &"proc_zenith_color", &"proc_mid_color",
	&"proc_horizon_color", &"proc_gradient_mid_height", &"proc_gradient_power", &"proc_gradient_bands",
	&"proc_gradient_band_edge", &"proc_horizon_glow_color", &"proc_horizon_glow_width",
	&"proc_horizon_glow_strength", &"proc_horizon_glow_sun_bias", &"proc_sea_color_near",
	&"proc_sea_color_far", &"proc_sea_horizon_fade", &"proc_sea_params", &"proc_sea_heights",
	&"proc_sea_wind", &"proc_sea_coverage", &"proc_sea_softness", &"proc_sea_band_edge",
	&"cloud_shadow_color", &"cloud_mid_color", &"cloud_lit_color", &"cloud_rim_color",
]
const FLAT_BASE_PARAMETER: StringName = &"flat_base"
## Per-instance / material parameters of the upper layer (see
## shaders/sky/cloud_puffs.gdshader): its own base plane height, and the camera-clearance fade.
const FLAT_BASE_OVERRIDE_PARAMETER: StringName = &"flat_base_override"
const CLEAR_FADE_START_PARAMETER: StringName = &"base_clear_start_m"
const CLEAR_FADE_END_PARAMETER: StringName = &"base_clear_end_m"
const FAR_FADE_CAP_PARAMETER: StringName = &"far_fade_cap"
## Default/maximum icosphere subdivision of the puff mesh (2 = 320 triangles;
## 1 = 80, see GraphicsPreset.cloud_puff_subdivisions). The mesh is
## only a hull: the shader carves the round, lumpy silhouette per pixel
## (its hull_margin covers this tessellation's chord error).
const PUFF_SUBDIVISIONS: int = 2
## Puff layout inside a clump, as fractions of the clump radius / height:
## centre and rim puff radius, dome fall-off of the tops toward the rim,
## horizontal spread, and the share/size/placement of the small
## "cauliflower" puffs sitting on the bigger ones.
const CORE_RADIUS_FRACTION: float = 0.58
const RIM_RADIUS_FRACTION: float = 0.3
const DOME_FALLOFF: float = 0.7
const SPREAD_FRACTION: float = 0.9
const DETAIL_SHARE: float = 0.4
const DETAIL_RADIUS_MIN_FRACTION: float = 0.3
const DETAIL_RADIUS_MAX_FRACTION: float = 0.5
const DETAIL_SURFACE_OFFSET: float = 0.8
const DETAIL_MIN_UP: float = 0.25
const SIZE_JITTER: float = 0.15
const TOP_JITTER_MIN: float = 0.82
const STRETCH_MAX: float = 1.2

## Per-instance shader flag marking the hexagon-impostor instances.
const BILLBOARD_PARAMETER: StringName = &"billboard"
## Hexagon impostor (UV = corner): circumradius over inradius 1 is 2 / sqrt(3), so the polygon
## contains the unit circle the shader sizes to the puff silhouette (1 / cos(PI / corners)).
const BILLBOARD_CORNERS: int = 6

## group the live CloudSea joins so game/sky/SunFlare.gd can ask it whether the
## puffs hide the sun without a node path.
const GROUP: StringName = &"cloud_sea"
## Sentinel for sun_ray_cloud_occlusion(): use the live drift offset.
const OCC_LIVE_DRIFT: Vector2 = Vector2(-1.0e30, -1.0e30)
const DRIFT_OFFSET_PARAMETER: StringName = &"drift_offset"
const DRIFT_EDGE_FADE_PARAMETER: StringName = &"drift_edge_fade_m"
const DRIFT_EXCLUSION_FADE_PARAMETER: StringName = &"drift_exclusion_fade_m"
## One placement layer: the sea below the disc, or the cloud banks past its
## edge. Both draw through the same MultiMesh.
class _Layer:
	extends RefCounted
	var clumps: int = 0
	var ring_inner_m: float = 0.0
	var ring_outer_m: float = 0.0
	var radial_bias: float = 1.0
	var base_min_m: float = 0.0
	var base_max_m: float = 0.0
	var top_max_m: float = 0.0
	var radius_min_m: float = 1.0
	var radius_max_m: float = 1.0
	## the weather-driven layer above the disc; it skips the
	## under-disc exclusion clamp and the sea's highest-top bookkeeping.
	var is_upper: bool = false
	## depth class (CloudDriftMath.KIND_*) picking the layer's parallax rate.
	var kind: StringName = CloudDriftMath.KIND_SEA
	## upper layer, seen from below: the puffs' base plane in unit-sphere
	## space (1 = round bottoms), how far a puff may hang below its clump's base level,
	## and how far down the small detail puffs may sit on the big ones. Left at the
	## sea's behaviour (the cycle's flat base, no sink, upper half only) elsewhere.
	var flat_base: float = 0.0
	var sink_m: float = 0.0
	var detail_min_up: float = DETAIL_MIN_UP
	## Vertical size of a puff as a share of its horizontal radius (1 = round). The upper
	## layer's round-bottomed puffs are oblate, so they stay as low as the cut flat-bottomed
	## ones were instead of growing into tall balls.
	var vertical_scale: float = 1.0


## One instance's puffs while they are generated (clumps pick their instance by distance).
class _Stage:
	extends RefCounted
	var transforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	var colors: Array[Color] = []


var _instance: MultiMeshInstance3D = null
## the impostor twins of _instance / _upper (null when no clump is that far).
var _far: MultiMeshInstance3D = null
var _upper_far: MultiMeshInstance3D = null
## GraphicsPreset.cloud_billboard_distance_m of the last configure() (0 = hulls only).
var _billboard_distance_m: float = 0.0
var _material: ShaderMaterial = null
## The cycle's authored sky material (static uniforms the puffs' far fade copies).
var _static_sky: ShaderMaterial = null
## The shared cloud lighting (owned by Skybox); the configure step
## re-applies its weather grade to the fresh puff material.
var lighting: CloudLighting = null
## tuning of the upper (overcast) puff layer and whether the Low
## preset is active; Skybox sets both before configure().
var upper_tuning: WeatherCeilingTuning = null
var upper_low: bool = false
var _upper: MultiMeshInstance3D = null
## Set by configure_cycle(): the shader's radius inflation (lumps + billow + hull margin, fraction
## of radius), from hull_inflate().
var _inflate: float = 0.0
## the largest disc radius (m) the clouds must clear -- the active
## (disc-size scaled) field radius; never below the largest shipped map.
var disc_radius_m: float = MapDef.RADIUS_LARGE
var _exclusion_radius_m: float = 0.0
var _disc_ceiling_m: float = 0.0
## sun-occlusion bounds, recorded by configure() for every clump of both instances (bounds only;
## no physics body exists for the puffs).
var _bounds: CloudOcclusionBounds = CloudOcclusionBounds.new()
## The shared cloud wind integral last pushed by set_drift_offset().
var _drift_offset: Vector2 = Vector2.ZERO
var drift_config: CloudDriftConfig = CloudDriftState.DEFAULT_CONFIG


## the weather grade (overcast dim + desaturate) of the shared
## CloudLighting reaches the puffs as shader uniforms; their palette and light
## direction already arrive through apply_frame().
func apply_lighting(state: CloudLighting) -> void:
	lighting = state
	if _material == null or state == null:
		return
	_material.set_shader_parameter(&"weather_dim", state.dim)
	_material.set_shader_parameter(&"weather_desaturate", state.desaturate)
	_material.set_shader_parameter(&"weather_floor", state.floor_color)
	_material.set_shader_parameter(&"floor_shadow_ratio", state.floor_shadow_ratio)
	_material.set_shader_parameter(&"floor_mid_ratio", state.floor_mid_ratio)


## Weather fog changed (game/weather/WeatherFogShader.gd).
func refresh_weather_fog() -> void:
	WeatherFogShader.apply(_material)


## Pushes the shared integrated cloud wind (CloudDriftState.offset) to the
## puff shader and the sun-occlusion bounds.
func set_drift_offset(offset: Vector2) -> void:
	_drift_offset = offset
	if _material != null:
		_material.set_shader_parameter(DRIFT_OFFSET_PARAMETER, offset)


## Writes the puff channel of an evaluated frame (plan 4.1 steps 6-7), the cycle's tick values:
## cel tones, sky cloud tones, moonlit grade, the live sky gradient and sea colours the far fade
## targets, exposure, sea coverage, light and sun direction. Every write comes from the frame, so
## the far fade follows the sky each tick, a storm included (the frame's tones are already
## storm-lerped; its sea colours and exposure stay the tick's).
func apply_frame(frame: SkyFrame) -> void:
	if _material == null or frame == null:
		return
	_write_tones(frame)
	_material.set_shader_parameter(&"grade_dark", frame.puff_grade_dark)
	_material.set_shader_parameter(&"grade_mid", frame.puff_grade_mid)
	_material.set_shader_parameter(&"grade_light", frame.puff_grade_light)
	_material.set_shader_parameter(&"grade_amount", frame.puff_grade_amount)
	_material.set_shader_parameter(&"proc_zenith_color", frame.proc_zenith_color)
	_material.set_shader_parameter(&"proc_mid_color", frame.proc_mid_color)
	_material.set_shader_parameter(&"proc_horizon_color", frame.proc_horizon_color)
	_material.set_shader_parameter(&"proc_gradient_mid_height", frame.proc_gradient_mid_height)
	_material.set_shader_parameter(&"proc_gradient_power", frame.proc_gradient_power)
	_material.set_shader_parameter(&"proc_horizon_glow_color", frame.proc_horizon_glow_color)
	_material.set_shader_parameter(&"proc_horizon_glow_width", frame.proc_horizon_glow_width)
	_material.set_shader_parameter(&"proc_sea_horizon_fade", frame.proc_sea_horizon_fade)
	_material.set_shader_parameter(&"proc_sea_color_near", frame.puff_sea_color_near)
	_material.set_shader_parameter(&"proc_sea_color_far", frame.puff_sea_color_far)
	_material.set_shader_parameter(&"light_direction", frame.puff_light_direction)
	_material.set_shader_parameter(&"sun_direction", frame.puff_sun_direction)
	_material.set_shader_parameter(&"exposure", frame.puff_exposure)
	_material.set_shader_parameter(&"proc_sea_coverage", frame.puff_sea_coverage)


## The puff cel tones and the sky cloud tones of `frame`.
func _write_tones(frame: SkyFrame) -> void:
	_material.set_shader_parameter(&"shadow_color", frame.puff_shadow_color)
	_material.set_shader_parameter(&"mid_color", frame.puff_mid_color)
	_material.set_shader_parameter(&"lit_color", frame.puff_lit_color)
	_material.set_shader_parameter(&"rim_color", frame.puff_rim_color)
	_material.set_shader_parameter(&"cloud_shadow_color", frame.puff_cloud_shadow_color)
	_material.set_shader_parameter(&"cloud_mid_color", frame.puff_cloud_mid_color)
	_material.set_shader_parameter(&"cloud_lit_color", frame.puff_cloud_lit_color)
	_material.set_shader_parameter(&"cloud_rim_color", frame.puff_cloud_rim_color)


## Copies the cycle's authored sky-material values the puff far fade shares onto the puff material
## (the static ones the frame does not carry: gradient bands, sea shape, noise; the frame-carried
## ones start from here and apply_frame() overwrites them every tick).
func _copy_static_sky() -> void:
	for parameter: StringName in SHARED_SKY_PARAMETERS:
		var value: Variant = _static_sky_value(parameter)
		if value != null:
			_material.set_shader_parameter(parameter, value)


func _static_sky_value(parameter: StringName) -> Variant:
	if parameter == &"procedural_sea_mix":
		return SkyDomeWriter.PROCEDURAL_SEA_MIX
	if _static_sky == null:
		return null
	return _static_sky.get_shader_parameter(parameter)


## Rebuilds the puffs from `def`. `frame` (null before the first tick) is written onto the fresh
## material so the far fade matches the live sky at once; the next tick writes it anyway.
## `density` scales the clump counts; 0 hides the cloud sea.
func configure_cycle(def: SkyCycleDef, frame: SkyFrame, density: float, subdivisions: int = PUFF_SUBDIVISIONS,
		billboard_distance_m: float = 0.0) -> void:
	_billboard_distance_m = maxf(billboard_distance_m, 0.0)
	_static_sky = def.sky_material if def != null else null
	for node: MultiMeshInstance3D in [_instance, _far, _upper, _upper_far]:
		if node != null:
			node.queue_free()
	_instance = null
	_far = null
	_upper = null
	_upper_far = null
	_material = null
	_bounds.clear()
	var layers: Array[_Layer] = _layers_for(def, density)
	var clumps: int = 0
	for layer: _Layer in layers:
		clumps += layer.clumps
	if def == null or def.cloud_puff_material == null or clumps <= 0 or def.cloud_puffs_per_clump <= 0:
		visible = false
		return
	_material = def.cloud_puff_material.duplicate() as ShaderMaterial
	if _material == null:
		visible = false
		return
	_inflate = hull_inflate(_material)
	_bounds.inflate = _inflate
	_bounds.drift_config = drift_config
	_exclusion_radius_m = exclusion_radius_m(def, disc_radius_m)
	_disc_ceiling_m = disc_ceiling_m(def, disc_radius_m)
	visible = true
	add_to_group(WeatherFogShader.GROUP)
	add_to_group(GROUP)
	WeatherFogShader.apply(_material)
	_material.set_shader_parameter(DRIFT_EDGE_FADE_PARAMETER, drift_config.edge_fade_m)
	_material.set_shader_parameter(DRIFT_EXCLUSION_FADE_PARAMETER, drift_config.exclusion_fade_m)
	_material.set_shader_parameter(DRIFT_OFFSET_PARAMETER, _drift_offset)
	_material.set_shader_parameter(FLAT_BASE_PARAMETER, def.cloud_flat_base)
	_material.set_shader_parameter(FAR_FADE_CAP_PARAMETER, def.proc_far_fade_cap)
	# Transparent-pass draw (see the shader's DECISION): first among
	# transparents, so ghosts, particles and birds blend over the clouds.
	_material.render_priority = RenderingServer.MATERIAL_RENDER_PRIORITY_MIN
	apply_lighting(lighting)
	_copy_static_sky()
	apply_frame(frame)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = def.cloud_seed
	var sea_nodes: Array[MultiMeshInstance3D] = _build_instances("Puffs", layers, def, subdivisions, rng, def.cloud_flat_base)
	_instance = sea_nodes[0]
	_far = sea_nodes[1]
	add_child(_instance)
	if _far != null:
		add_child(_far)
	# the same puffs, shader, material and lighting again above
	# the disc, always present (weather only changes its lighting).
	var upper_layers: Array[_Layer] = _upper_layers_for(def, density)
	if not upper_layers.is_empty():
		rng.seed = def.cloud_seed + upper_tuning.upper_seed_offset
		var upper_nodes: Array[MultiMeshInstance3D] = _build_instances("UpperPuffs", upper_layers, def, subdivisions, rng, upper_layers[0].flat_base)
		_upper = upper_nodes[0]
		_upper_far = upper_nodes[1]
		add_child(_upper)
		if _upper_far != null:
			add_child(_upper_far)
		_apply_upper_parameters()


## The MultiMeshInstance3Ds of the clumps of `layers`, drawn with the shared puff material:
## [hull puffs, impostor puffs]. Clumps at or beyond _billboard_distance_m go to the impostor
## instance (null when none does); the hull instance always exists.
func _build_instances(node_name: String, layers: Array[_Layer], def: SkyCycleDef, subdivisions: int,
		rng: RandomNumberGenerator, flat_base: float) -> Array[MultiMeshInstance3D]:
	var near: _Stage = _Stage.new()
	var far: _Stage = _Stage.new()
	for layer: _Layer in layers:
		for _clump: int in range(layer.clumps):
			_add_clump(near, far, def, layer, rng)
	# The culling box must cover the whole wrap domain the shader slides puffs inside.
	var extent: float = 0.0
	var low: float = INF
	var high: float = -INF
	for layer: _Layer in layers:
		if layer.clumps <= 0:
			continue
		extent = maxf(extent, layer.ring_outer_m + layer.radius_max_m * 2.0)
		low = minf(low, layer.base_min_m - layer.radius_max_m)
		high = maxf(high, layer.top_max_m)
	var box: AABB = AABB(Vector3(-extent, low, -extent), Vector3(extent * 2.0, high - low, extent * 2.0))
	var result: Array[MultiMeshInstance3D] = [null, null]
	result[0] = _make_instance(node_name, near, build_puff_mesh(flat_base, subdivisions), box, false)
	if not far.transforms.is_empty():
		result[1] = _make_instance(node_name + "Far", far, build_billboard_mesh(), box, true)
	return result


func _make_instance(node_name: String, stage: _Stage, mesh: Mesh, box: AABB, billboard: bool) -> MultiMeshInstance3D:
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = stage.transforms.size()
	for index: int in range(stage.transforms.size()):
		multimesh.set_instance_transform(index, stage.transforms[index])
		multimesh.set_instance_custom_data(index, stage.customs[index])
		multimesh.set_instance_color(index, stage.colors[index])
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = _material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.layers = RENDER_LAYER_BIT
	instance.custom_aabb = box
	if billboard:
		instance.set_instance_shader_parameter(BILLBOARD_PARAMETER, 1.0)
	return instance


## Per-instance shader parameters of the always-present upper puff layer.
func _apply_upper_parameters() -> void:
	for node: MultiMeshInstance3D in [_upper, _upper_far]:
		if node != null:
			_apply_upper_parameters_to(node)
	if upper_tuning == null:
		return
	_material.set_shader_parameter(CLEAR_FADE_START_PARAMETER, upper_tuning.upper_clear_fade_start_m)
	_material.set_shader_parameter(CLEAR_FADE_END_PARAMETER, upper_tuning.upper_clear_fade_end_m)
	_bounds.set_clear_fade(upper_tuning.upper_clear_fade_start_m, upper_tuning.upper_clear_fade_end_m)


func _apply_upper_parameters_to(node: MultiMeshInstance3D) -> void:
	node.set_instance_shader_parameter(&"floor_on", 1.0)
	node.set_instance_shader_parameter(&"edge_soft_px", upper_tuning.upper_edge_softness_px if upper_tuning != null else 0.0)
	if upper_tuning == null:
		return
	# the layer's own base plane (the shader reads it per instance, the
	# sea keeps the material's flat_base), and the camera-clearance dither fade. The
	# fade uniforms live on the shared material but only the floor_on layer applies them.
	node.set_instance_shader_parameter(FLAT_BASE_OVERRIDE_PARAMETER, upper_tuning.upper_flat_base)


## Largest silhouette the puff shader can carve beyond a puff's radius, as a
## fraction of it (the same sum shaders/sky/cloud_puffs.gdshader inflates its hull by).
static func hull_inflate(material: ShaderMaterial) -> float:
	var lump_height: float = _float_param(material, &"lump_height", 0.35)
	var lump_bias: float = _float_param(material, &"lump_bias", 0.6)
	return lump_height * (1.0 - lump_bias) + _float_param(material, &"billow_amount", 0.03) + _float_param(material, &"hull_margin", 0.04)


static func _float_param(material: ShaderMaterial, name: StringName, fallback: float) -> float:
	var value: Variant = material.get_shader_parameter(name)
	return float(value) if value is float else fallback


## Clearance (m) kept around the disc: cloud_disc_clearance_ratio of the largest
## field radius.
static func disc_clearance_m(def: SkyCycleDef, radius_m: float = MapDef.RADIUS_LARGE) -> float:
	return radius_m * def.cloud_disc_clearance_ratio


## Radius (m) of the cylinder around the disc axis no puff may rise out of the
## under-disc ceiling inside: the largest field plus the clearance.
static func exclusion_radius_m(def: SkyCycleDef, radius_m: float = MapDef.RADIUS_LARGE) -> float:
	return radius_m + disc_clearance_m(def, radius_m)


## World Y no puff top inside the exclusion cylinder may exceed: the disc's
## underside (MapDef.disk_height below y 0) minus the clearance.
static func disc_ceiling_m(def: SkyCycleDef, radius_m: float = MapDef.RADIUS_LARGE) -> float:
	return -MapDef.new().disk_height - disc_clearance_m(def, radius_m)


## The overcast layer above the disc -- clumps over a disc of
## upper_ring_outer_m around the axis, flat bases from height_m up, scaled by the
## density preset like the sea (Low also uses upper_clump_count_low).
func _upper_layers_for(def: SkyCycleDef, density: float) -> Array[_Layer]:
	var layers: Array[_Layer] = []
	if upper_tuning == null or def == null:
		return layers
	var upper: _Layer = _Layer.new()
	var count: int = upper_tuning.upper_clump_count_low if upper_low else upper_tuning.upper_clump_count
	upper.clumps = int(round(float(count) * clampf(density, 0.0, 1.0)))
	if upper.clumps <= 0:
		return layers
	upper.is_upper = true
	upper.kind = CloudDriftMath.KIND_UPPER
	upper.ring_inner_m = 0.0
	upper.ring_outer_m = upper_tuning.upper_ring_outer_m
	upper.radial_bias = 1.0
	# round bottoms hang up to upper_base_sink_m under their clump's
	# base level, so the clumps start that much higher and nothing hangs below height_m.
	upper.flat_base = upper_tuning.upper_flat_base
	upper.sink_m = upper_tuning.upper_base_sink_m
	upper.detail_min_up = -upper_tuning.upper_belly_depth
	upper.vertical_scale = upper_tuning.upper_puff_squash
	upper.base_min_m = upper_tuning.height_m + upper.sink_m
	upper.base_max_m = upper.base_min_m + upper_tuning.upper_base_spread_m
	upper.radius_min_m = upper_tuning.upper_clump_radius_min_m
	upper.radius_max_m = upper_tuning.upper_clump_radius_max_m
	upper.top_max_m = upper.base_max_m + upper.radius_max_m * (def.cloud_clump_height_ratio * (1.0 + SIZE_JITTER) + 1.0)
	layers.append(upper)
	return layers


## The sea layer and (when the cycle has any) the cloud-bank layer, with the
## density preset applied to both clump counts.
static func _layers_for(def: SkyCycleDef, density: float) -> Array[_Layer]:
	var layers: Array[_Layer] = []
	if def == null:
		return layers
	var scale: float = clampf(density, 0.0, 1.0)
	var sea: _Layer = _Layer.new()
	sea.clumps = int(round(float(def.cloud_clump_count) * scale))
	sea.ring_inner_m = def.cloud_ring_inner_m
	sea.ring_outer_m = def.cloud_ring_outer_m
	sea.radial_bias = def.cloud_radial_bias
	sea.base_min_m = def.cloud_base_min_m
	sea.base_max_m = def.cloud_base_max_m
	# the sea layer rides cloud_puff_raise_m higher; the disc
	# clearance clamp in _write_puff() keeps it clear of the disc and play volume.
	sea.base_min_m += def.cloud_puff_raise_m
	sea.base_max_m += def.cloud_puff_raise_m
	sea.top_max_m = def.cloud_top_max_m + def.cloud_puff_raise_m
	sea.radius_min_m = def.cloud_clump_radius_min_m
	sea.radius_max_m = def.cloud_clump_radius_max_m
	layers.append(sea)
	var banks: _Layer = _Layer.new()
	banks.clumps = int(round(float(def.cloud_bank_count) * scale))
	banks.kind = CloudDriftMath.KIND_BANK
	banks.ring_inner_m = def.cloud_bank_ring_inner_m
	banks.ring_outer_m = def.cloud_bank_ring_outer_m
	banks.radial_bias = 1.0
	banks.base_min_m = def.cloud_bank_base_min_m
	banks.base_max_m = def.cloud_bank_base_max_m
	banks.top_max_m = def.cloud_bank_top_max_m
	banks.radius_min_m = def.cloud_bank_radius_min_m
	banks.radius_max_m = def.cloud_bank_radius_max_m
	layers.append(banks)
	# DECISION: the below-horizon cloud sea of the procedural
	# look is a far ring of the same 3D puffs (they already read well and need no
	# new art) rather than a shader-only height field; the sky shader keeps only a
	# flat violet cloud floor and haze between them. Gated on the toggle so the
	# painted look is unchanged.
	if def.proc_far_count > 0:
		var far: _Layer = _Layer.new()
		far.kind = CloudDriftMath.KIND_FAR
		far.clumps = int(round(float(def.proc_far_count) * scale))
		far.ring_inner_m = def.proc_far_ring_inner_m
		far.ring_outer_m = def.proc_far_ring_outer_m
		far.radial_bias = def.proc_far_radial_bias
		far.base_min_m = def.proc_far_base_min_m
		far.base_max_m = def.proc_far_base_max_m
		far.top_max_m = def.proc_far_top_max_m + def.cloud_puff_raise_m
		far.base_min_m += def.cloud_puff_raise_m
		far.base_max_m += def.cloud_puff_raise_m
		far.radius_min_m = def.proc_far_radius_min_m
		far.radius_max_m = def.proc_far_radius_max_m
		layers.append(far)
	return layers


## Adds one clump's puffs to the `near` or `far` stage.
func _add_clump(near: _Stage, far: _Stage, def: SkyCycleDef, layer: _Layer, rng: RandomNumberGenerator) -> void:
	var azimuth: float = rng.randf() * TAU
	# Uniform over the ring's area, not its radius.
	# A radial bias above 1 crowds clumps toward the inner (near) edge.
	var inner_sq: float = layer.ring_inner_m * layer.ring_inner_m
	var outer_sq: float = layer.ring_outer_m * layer.ring_outer_m
	var ring_radius: float = sqrt(lerpf(inner_sq, outer_sq, pow(rng.randf(), maxf(layer.radial_bias, 0.01))))
	var centre: Vector3 = Vector3(cos(azimuth) * ring_radius, 0.0, sin(azimuth) * ring_radius)
	var clump_radius: float = rng.randf_range(layer.radius_min_m, layer.radius_max_m)
	var clump_height: float = clump_radius * def.cloud_clump_height_ratio * rng.randf_range(1.0 - SIZE_JITTER, 1.0 + SIZE_JITTER)
	var base_y: float = rng.randf_range(layer.base_min_m, layer.base_max_m)
	base_y = minf(base_y, layer.top_max_m - clump_height)
	# the clump's own speed times its layer's depth rate (near layers slide
	# faster: parallax). The shader moves it along the shared wind by drift_offset * speed.
	var speed: float = rng.randf_range(def.cloud_drift_speed_min_mps, def.cloud_drift_speed_max_mps)
	var angular_speed: float = speed * CloudDriftMath.layer_rate(layer.kind, drift_config)
	# A below-disc clump that starts clear of the exclusion cylinder is not height-clamped, so
	# it must dissolve before it drifts into the play volume (the shader reads the radius at
	# which it is fully gone from the instance colour). Clumps that start inside are clamped
	# under the disc ceiling at build and keep their look (no dissolve).
	var reach: float = clump_radius * (SPREAD_FRACTION + (1.0 + _inflate) * STRETCH_MAX)
	var excl_gone: float = 0.0
	if not layer.is_upper and ring_radius - reach >= _exclusion_radius_m:
		excl_gone = _exclusion_radius_m + reach
	var rest: Color = Color(centre.x, centre.z, layer.ring_outer_m, excl_gone)
	var stage: _Stage = far if _billboard_distance_m > 0.0 and ring_radius >= _billboard_distance_m else near
	var flat: float = layer.flat_base if layer.is_upper else def.cloud_flat_base
	var total: int = def.cloud_puffs_per_clump
	var detail_count: int = int(float(total) * DETAIL_SHARE) if total > 2 else 0
	# DECISION: an impostor clump is far away, where the small cauliflower
	# puffs sitting on the big ones are a few pixels at most: it draws its body puffs only.
	var distant: bool = stage == far
	if distant:
		total -= detail_count
		detail_count = 0
	var body_count: int = total - detail_count
	var body_centres: Array[Vector3] = []
	var body_radii: Array[float] = []
	var first_puff: int = _bounds.puff_rows()
	for puff: int in range(body_count):
		var spread: float = 0.0 if puff == 0 else sqrt(rng.randf()) * SPREAD_FRACTION
		var angle: float = rng.randf() * TAU
		var offset: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * spread * clump_radius
		var radius: float = clump_radius * lerpf(CORE_RADIUS_FRACTION, RIM_RADIUS_FRACTION, spread)
		radius *= rng.randf_range(1.0 - SIZE_JITTER, 1.0 + SIZE_JITTER)
		var top: float = base_y + clump_height * (1.0 - DOME_FALLOFF * spread * spread) * rng.randf_range(TOP_JITTER_MIN, 1.0)
		var y: float = puff_centre_y(top, radius * layer.vertical_scale, base_y, flat, layer.sink_m * rng.randf() if layer.is_upper else 0.0)
		var at: Vector3 = centre + offset + Vector3(0.0, y, 0.0)
		_write_puff(stage, at, radius, layer, rng, angular_speed, base_y, clump_height, flat, rest)
		body_centres.append(at)
		body_radii.append(radius)
	for _detail: int in range(detail_count):
		var host: int = rng.randi_range(0, body_centres.size() - 1)
		var up: float = rng.randf_range(layer.detail_min_up, 1.0)
		var around: float = rng.randf() * TAU
		var side: float = sqrt(maxf(1.0 - up * up, 0.0))
		var direction: Vector3 = Vector3(cos(around) * side, up, sin(around) * side)
		var radius: float = body_radii[host] * rng.randf_range(DETAIL_RADIUS_MIN_FRACTION, DETAIL_RADIUS_MAX_FRACTION)
		direction.y *= layer.vertical_scale
		var at: Vector3 = body_centres[host] + direction * body_radii[host] * DETAIL_SURFACE_OFFSET
		_write_puff(stage, at, radius, layer, rng, angular_speed, base_y, clump_height, flat, rest)
	_bounds.record_clump(first_puff, angular_speed, layer.is_upper, rest)


func _write_puff(stage: _Stage, at: Vector3, radius: float, layer: _Layer,
		rng: RandomNumberGenerator, angular_speed: float, base_y: float, clump_height: float, flat: float, rest: Color) -> void:
	# Never let a puff top rise above its layer ceiling.
	var height: float = radius * layer.vertical_scale
	at.y = minf(at.y, layer.top_max_m - height)
	var stretch: float = rng.randf_range(1.0, STRETCH_MAX)
	# A puff that could reach the disc or the play volume (its
	# footprint, inflated by the shader's lumps/billow, enters the exclusion
	# cylinder) is held under the disc by the clearance. A below-disc clump drifting
	# inside the exclusion radius dissolves instead (drift_vis); this clamp holds for
	# the rest position.
	var inflated: float = radius * (1.0 + _inflate)
	var footprint: float = Vector2(at.x, at.z).length() - inflated * stretch
	if not layer.is_upper and footprint < _exclusion_radius_m:
		at.y = minf(at.y, _disc_ceiling_m - inflated)
	var basis: Basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(radius * stretch, height, radius * stretch))
	_bounds.record_puff(at, radius * stretch, height, flat)
	stage.transforms.append(Transform3D(basis, at))
	stage.customs.append(Color(angular_speed, rng.randf() * TAU, base_y, clump_height))
	stage.colors.append(rest)


## How much the puffs hide the sun seen along the ray from `from` toward `dir`, 0 (clear sky) ..
## 1 (fully hidden); see CloudOcclusionBounds.query(). `drift` is the integrated cloud wind to
## evaluate at (the live one by default). The CloudSea node is assumed to sit at the world origin,
## as Skybox places it.
func sun_ray_cloud_occlusion(from: Vector3, dir: Vector3, tuning: SunFlareConfig = null, drift: Vector2 = OCC_LIVE_DRIFT) -> float:
	if not visible:
		return 0.0
	var wind: Vector2 = _drift_offset if drift == OCC_LIVE_DRIFT else drift
	return _bounds.ray_cover(from, dir, tuning, wind)


## Centre height of a body puff whose top would be `top`: its bottom plane (at
## `flat` of its radius below the centre) never goes under `base_y`, less `sink_m` (the upper
## layer lets round bottoms hang a little below the clump's level so they share no plane).
## With flat = 1 the puff just rests on base_y.
static func puff_centre_y(top: float, radius: float, base_y: float, flat: float, sink_m: float = 0.0) -> float:
	return maxf(top - radius, base_y + radius * flat - sink_m)


## Unit icosphere whose part below y = -`flat_base` is squashed onto that
## plane (a cumulus's flat base). Smooth radial normals; base vertices face
## straight down.
static func build_puff_mesh(flat_base: float, subdivisions: int = PUFF_SUBDIVISIONS) -> ArrayMesh:
	var golden: float = (1.0 + sqrt(5.0)) * 0.5
	var vertices: Array[Vector3] = [
		Vector3(-1, golden, 0), Vector3(1, golden, 0), Vector3(-1, -golden, 0), Vector3(1, -golden, 0),
		Vector3(0, -1, golden), Vector3(0, 1, golden), Vector3(0, -1, -golden), Vector3(0, 1, -golden),
		Vector3(golden, 0, -1), Vector3(golden, 0, 1), Vector3(-golden, 0, -1), Vector3(-golden, 0, 1),
	]
	for i: int in range(vertices.size()):
		vertices[i] = vertices[i].normalized()
	var faces: PackedInt32Array = PackedInt32Array([
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
	])
	for _level: int in range(clampi(subdivisions, 1, PUFF_SUBDIVISIONS)):
		var midpoints: Dictionary[Vector2i, int] = {}
		var next: PackedInt32Array = PackedInt32Array()
		for f: int in range(0, faces.size(), 3):
			var a: int = faces[f]
			var b: int = faces[f + 1]
			var c: int = faces[f + 2]
			var ab: int = _midpoint(vertices, midpoints, a, b)
			var bc: int = _midpoint(vertices, midpoints, b, c)
			var ca: int = _midpoint(vertices, midpoints, c, a)
			next.append_array(PackedInt32Array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca]))
		faces = next
	var positions: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	for v: Vector3 in vertices:
		if v.y < -flat_base:
			positions.append(Vector3(v.x, -flat_base, v.z))
			normals.append(Vector3.DOWN)
		else:
			positions.append(v)
			normals.append(v)
	# Godot treats clockwise triangles as front faces; the table above is
	# counter-clockwise seen from outside, so swap two corners of each.
	for f: int in range(0, faces.size(), 3):
		var swap: int = faces[f + 1]
		faces[f + 1] = faces[f + 2]
		faces[f + 2] = swap
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = faces
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The impostor polygon, a hexagon in the XY plane whose UV is its corner
## inradius 1: 4 triangles. The vertex stage places it facing the camera; see the shader.
static func build_billboard_mesh() -> ArrayMesh:
	var positions: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var normals: PackedVector3Array = PackedVector3Array()
	for corner: int in range(BILLBOARD_CORNERS):
		var angle: float = TAU * float(corner) / float(BILLBOARD_CORNERS)
		var at: Vector2 = Vector2(cos(angle), sin(angle)) / cos(PI / float(BILLBOARD_CORNERS))
		positions.append(Vector3(at.x, at.y, 0.0))
		uvs.append(at)
		normals.append(Vector3.UP)
	var faces: PackedInt32Array = PackedInt32Array()
	for corner: int in range(1, BILLBOARD_CORNERS - 1):
		faces.append_array(PackedInt32Array([0, corner + 1, corner]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = faces
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Index of the normalized midpoint of edge a-b, appended once per edge.
static func _midpoint(vertices: Array[Vector3], cache: Dictionary[Vector2i, int], a: int, b: int) -> int:
	var key: Vector2i = Vector2i(mini(a, b), maxi(a, b))
	if cache.has(key):
		return cache[key]
	vertices.append(((vertices[a] + vertices[b]) * 0.5).normalized())
	var index: int = vertices.size() - 1
	cache[key] = index
	return index
