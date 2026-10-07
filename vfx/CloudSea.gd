class_name CloudSea
extends Node3D
## Bontago-adt.1: the near/mid-field cloud sea below the floating disc --
## real 3D stylized cumulus. One MultiMeshInstance3D draws flat-bottomed
## low-poly spheres ("puffs") clustered into cumulus clumps scattered on a
## ring around and below the disc; shaders/cloud_puffs.gdshader toon-shades
## them from theme colours, drifts every clump slowly around the disc and
## billows the surfaces, all from TIME and per-instance custom data -- no
## per-frame script, so it animates in the game, the editor and the baked
## demo. Distant clumps fade into the sky panorama's own lower hemisphere
## (the far cloud sea), sampled along the view ray, so there is no seam.
##
## Placement is deterministic (SkyThemeDef.cloud_seed). Every puff top stays
## at or below SkyThemeDef.cloud_top_max_m, far under the disc's underside
## and the 0..72 m play volume. game/Skybox.gd owns one of these and calls
## configure() on theme and graphics-preset changes.

## Render layer bit the puffs live on (layer 19). game/DiscMirror.gd's
## MIRROR_CULL_MASK (also the disc ReflectionProbe's mask) excludes it: the
## planar-mirror camera sits below the disc plane, among the puffs, and
## anything below a mirror must never appear in its reflection.
const RENDER_LAYER_BIT: int = 1 << 18
## Sky-material uniforms the puff shader shares so its far fade matches the
## sky drawn behind it exactly.
const SHARED_SKY_PARAMETERS: Array[StringName] = [
	&"panorama", &"exposure", &"seam_blend_width", &"grade_amount", &"grade_dark", &"grade_mid",
	&"grade_light", &"grade_gamma",
	# Bontago-59o.16 P4: procedural sea/gradient the far fade targets when
	# procedural_sea_mix > 0 (inert at 0, so the painted look is unchanged).
	&"procedural_sea_mix", &"noise_tex", &"sun_direction", &"proc_zenith_color", &"proc_mid_color",
	&"proc_horizon_color", &"proc_gradient_mid_height", &"proc_gradient_power", &"proc_gradient_bands",
	&"proc_gradient_band_edge", &"proc_horizon_glow_color", &"proc_horizon_glow_width",
	&"proc_horizon_glow_strength", &"proc_horizon_glow_sun_bias", &"proc_sea_color_near",
	&"proc_sea_color_far", &"proc_sea_horizon_fade", &"proc_sea_params", &"proc_sea_heights",
	&"proc_sea_wind", &"proc_sea_coverage", &"proc_sea_softness", &"proc_sea_band_edge",
	&"cloud_shadow_color", &"cloud_mid_color", &"cloud_lit_color", &"cloud_rim_color",
]
const YAW_PARAMETER: StringName = &"sky_yaw_offset_deg"
const PITCH_PARAMETER: StringName = &"sky_pitch_offset_deg"
const FLAT_BASE_PARAMETER: StringName = &"flat_base"
## Bontago-mp0.93 per-instance / material parameters of the upper layer (see
## shaders/cloud_puffs.gdshader): its own base plane height, and the camera-clearance fade.
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

## Bontago-mp0.95: group the live CloudSea joins so vfx/SunFlare.gd can ask it whether the
## puffs hide the sun without a node path.
const GROUP: StringName = &"cloud_sea"
## Sun-occlusion records (see sun_ray_cloud_occlusion()): one row per puff in _occ_puffs.
## Row layout: centre x, y, z, horizontal radius, vertical radius (both inflated like the
## shader's hull), and the world Y of the flat-base cut (NO_BASE_CUT when round).
const OCC_PUFF_STRIDE: int = 6
const NO_BASE_CUT: float = -1.0e30
## The shader's `round_base_from` default: a base plane at or above it means whole ellipsoids.
const ROUND_BASE_FROM: float = 0.9
## Passed as `time_s` to read the live shader clock instead of a fixed test time.
## Sentinel for sun_ray_cloud_occlusion(): use the live drift offset.
const OCC_LIVE_DRIFT: Vector2 = Vector2(-1.0e30, -1.0e30)
const DRIFT_OFFSET_PARAMETER: StringName = &"drift_offset"
const DRIFT_EDGE_FADE_PARAMETER: StringName = &"drift_edge_fade_m"
const DRIFT_EXCLUSION_FADE_PARAMETER: StringName = &"drift_exclusion_fade_m"
const SHADER_TIME_ROLLOVER_SETTING: String = "rendering/limits/time/time_rollover_secs"
## Engine default of the setting above (the shader's TIME wraps here).
const SHADER_TIME_ROLLOVER_DEFAULT_S: float = 3600.0
## Rays flatter than this are treated as horizontal by the clump height-slab prefilter.
const OCC_FLAT_RAY: float = 1.0e-6
const OCC_DEFAULT_TUNING: SunFlareConfig = preload("res://config/sun_flare.tres")

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
	## Bontago-mp0.29: the weather-driven layer above the disc; it skips the
	## under-disc exclusion clamp and the sea's highest-top bookkeeping.
	var is_upper: bool = false
	## Bontago-mp0.92: depth class (CloudDriftMath.KIND_*) picking the layer's parallax rate.
	var kind: StringName = CloudDriftMath.KIND_SEA
	## Bontago-mp0.93 (upper layer, seen from below): the puffs' base plane in unit-sphere
	## space (1 = round bottoms), how far a puff may hang below its clump's base level,
	## and how far down the small detail puffs may sit on the big ones. Left at the
	## sea's behaviour (the theme's flat base, no sink, upper half only) elsewhere.
	var flat_base: float = 0.0
	var sink_m: float = 0.0
	var detail_min_up: float = DETAIL_MIN_UP
	## Vertical size of a puff as a share of its horizontal radius (1 = round). The upper
	## layer's round-bottomed puffs are oblate, so they stay as low as the cut flat-bottomed
	## ones were instead of growing into tall balls.
	var vertical_scale: float = 1.0


var _instance: MultiMeshInstance3D = null
var _material: ShaderMaterial = null
## Bontago-mp0.26: the cycle-mixed cloud colours last written by
## set_cycle_appearance(), keyed by shader parameter. apply_storm_tint() lerps
## from these (the colours in effect) instead of the DAY theme. Empty outside
## CYCLE (configure() clears it); keys are reused so no per-frame allocation.
var _cycle_base: Dictionary[StringName, Color] = {}
## Bontago-mp0.29: the shared cloud lighting (owned by Skybox). configure()
## re-applies its weather grade to the fresh puff material.
var lighting: CloudLighting = null
## Bontago-mp0.29: tuning of the upper (overcast) puff layer and whether the Low
## preset is active; Skybox sets both before configure().
var upper_tuning: WeatherCeilingTuning = null
var upper_low: bool = false
var _upper: MultiMeshInstance3D = null
## Lowest world Y any upper puff's nominal bottom (its base plane, or the sphere's bottom when round,
## before the shader's lumps) reaches, written by the last configure(); tracked here like _highest_top because a
## headless RenderingServer does not keep MultiMesh instance data.
var _upper_lowest_bottom: float = INF

## A cycle changes the existing puff material's palette and direction in place.
func set_cycle_appearance(day: SkyThemeDef, night_theme: SkyThemeDef, weight: float, direction: Vector3) -> void:
	if _material == null:
		return
	var day_material: ShaderMaterial = day.cloud_puff_material as ShaderMaterial
	var night_material: ShaderMaterial = night_theme.cloud_puff_material as ShaderMaterial
	if day_material == null or night_material == null:
		return
	for parameter: StringName in [&"shadow_color", &"mid_color", &"lit_color", &"rim_color"]:
		var a: Color = day_material.get_shader_parameter(parameter) as Color
		var b: Color = night_material.get_shader_parameter(parameter) as Color
		var mixed: Color = a.lerp(b, weight)
		_material.set_shader_parameter(parameter, mixed)
		_cycle_base[parameter] = mixed
	var day_sky: ShaderMaterial = day.sky_material as ShaderMaterial
	var night_sky: ShaderMaterial = night_theme.sky_material as ShaderMaterial
	if day_sky != null and night_sky != null:
		for parameter: StringName in [&"cloud_shadow_color", &"cloud_mid_color", &"cloud_lit_color", &"cloud_rim_color"]:
			var day_color: Color = day_sky.get_shader_parameter(parameter) as Color
			var night_color: Color = night_sky.get_shader_parameter(parameter) as Color
			var mixed_sky: Color = day_color.lerp(night_color, weight)
			_material.set_shader_parameter(parameter, mixed_sky)
			_cycle_base[parameter] = mixed_sky
		for parameter: StringName in [&"grade_dark", &"grade_mid", &"grade_light"]:
			_material.set_shader_parameter(parameter, night_sky.get_shader_parameter(parameter))
		_material.set_shader_parameter(&"grade_amount", weight)
		_material.set_shader_parameter(&"proc_sea_color_near", day.proc_sea_color_near.lerp(night_theme.proc_sea_color_near, weight))
		_material.set_shader_parameter(&"proc_sea_color_far", day.proc_sea_color_far.lerp(night_theme.proc_sea_color_far, weight))
	_material.set_shader_parameter(&"light_direction", direction)
	_material.set_shader_parameter(&"sun_direction", direction)
## Highest puff top written by the last configure() (tracked here because a
## headless RenderingServer does not keep MultiMesh instance data).
var _highest_top: float = -INF
## Bontago-t8x.2: set by configure() -- the shader's radius inflation (lumps +
## billow + hull margin, fraction of radius) and the disc exclusion volume.
var _inflate: float = 0.0
## Highest inflated puff top among puffs whose footprint enters the exclusion cylinder.
var _highest_top_near_disc: float = -INF
## Bontago-1pi.107: the largest disc radius (m) the clouds must clear -- the active
## (disc-size scaled) field radius; never below the largest shipped map.
var disc_radius_m: float = MapDef.RADIUS_LARGE
var _exclusion_radius_m: float = 0.0
var _disc_ceiling_m: float = 0.0
## Bontago-mp0.95 sun-occlusion bounds, recorded by configure() for every clump of both
## instances (bounds only; no physics body exists for the puffs). Clump arrays share one
## index; a clump's puffs are rows first..first+count of _occ_puffs. Positions are in the
## clump's rest frame: the shader slides each clump by drift_offset * its speed (wrapped), so
## queries shift the ray back instead of every clump forward.
var _occ_puffs: PackedFloat32Array = PackedFloat32Array()
var _occ_centre: PackedVector3Array = PackedVector3Array()
var _occ_radius: PackedFloat32Array = PackedFloat32Array()
var _occ_speed: PackedFloat32Array = PackedFloat32Array()
## Bontago-mp0.92: per clump, its rest (x, z), wrap domain half-side and exclusion radius (0 =
## none), the same numbers the shader reads from the instance colour.
var _occ_rest: PackedVector2Array = PackedVector2Array()
var _occ_domain: PackedFloat32Array = PackedFloat32Array()
var _occ_excl: PackedFloat32Array = PackedFloat32Array()
## The shared cloud wind integral last pushed by set_drift_offset().
var _drift_offset: Vector2 = Vector2.ZERO
var drift_config: CloudDriftConfig = CloudDriftState.DEFAULT_CONFIG
var _occ_y_low: PackedFloat32Array = PackedFloat32Array()
var _occ_y_high: PackedFloat32Array = PackedFloat32Array()
var _occ_first: PackedInt32Array = PackedInt32Array()
var _occ_count: PackedInt32Array = PackedInt32Array()
## 1 for clumps of the upper layer, which the shader dithers away near the camera.
var _occ_upper: PackedByteArray = PackedByteArray()
var _occ_clear_start_m: float = 0.0
var _occ_clear_end_m: float = 0.0


## Bontago-mp0.19: storm tint. Re-bases the live puff material on `base` (the
## match theme) blended toward `storm` by `amount` 0..1: puff cel colours and
## the sky cloud colours lerp between the two themes, then the shared sky
## uniforms (procedural sea colours the far fade targets) are re-copied from
## `blended_sky`, which Skybox has already tinted. Amount 0 changes nothing:
## configure() restores the theme's own look.
func apply_storm_tint(base: SkyThemeDef, storm: SkyThemeDef, amount: float, blended_sky: Material) -> void:
	if _material == null or base == null or storm == null:
		return
	var sky: ShaderMaterial = blended_sky as ShaderMaterial
	if sky != null:
		for parameter: StringName in SHARED_SKY_PARAMETERS:
			var value: Variant = sky.get_shader_parameter(parameter)
			if value != null:
				_material.set_shader_parameter(parameter, value)
	_lerp_colors(base.cloud_puff_material as ShaderMaterial, storm.cloud_puff_material as ShaderMaterial,
			[&"shadow_color", &"mid_color", &"lit_color", &"rim_color"], amount)
	_lerp_colors(base.sky_material as ShaderMaterial, storm.sky_material as ShaderMaterial,
			[&"cloud_shadow_color", &"cloud_mid_color", &"cloud_lit_color", &"cloud_rim_color"], amount)


func _lerp_colors(from: ShaderMaterial, to: ShaderMaterial, parameters: Array[StringName], weight: float) -> void:
	if from == null or to == null:
		return
	for parameter: StringName in parameters:
		var a: Variant = _cycle_base[parameter] if _cycle_base.has(parameter) else from.get_shader_parameter(parameter)
		var b: Variant = to.get_shader_parameter(parameter)
		if a is Color and b is Color:
			_material.set_shader_parameter(parameter, (a as Color).lerp(b as Color, weight))


## Bontago-mp0.29: the weather grade (overcast dim + desaturate) of the shared
## CloudLighting reaches the puffs as shader uniforms; their palette and light
## direction already arrive through set_cycle_appearance()/apply_storm_tint().
func apply_lighting(state: CloudLighting) -> void:
	lighting = state
	if _material == null or state == null:
		return
	_material.set_shader_parameter(&"weather_dim", state.dim)
	_material.set_shader_parameter(&"weather_desaturate", state.desaturate)
	_material.set_shader_parameter(&"weather_floor", state.floor_color)
	_material.set_shader_parameter(&"floor_shadow_ratio", state.floor_shadow_ratio)
	_material.set_shader_parameter(&"floor_mid_ratio", state.floor_mid_ratio)


## Weather fog changed (vfx/weather/WeatherFogShader.gd).
func refresh_weather_fog() -> void:
	WeatherFogShader.apply(_material)


## Rebuilds the puffs from `theme`. `density` (GraphicsPreset.cloud_puff_density,
## 0..1) scales the theme's clump count; 0 hides the cloud sea. `sky_material`
## is the active sky material whose panorama/grade uniforms the puffs copy.
## Bontago-mp0.92: pushes the shared integrated cloud wind (CloudDriftState.offset) to the
## puff shader and the sun-occlusion bounds.
func set_drift_offset(offset: Vector2) -> void:
	_drift_offset = offset
	if _material != null:
		_material.set_shader_parameter(DRIFT_OFFSET_PARAMETER, offset)


func drift_offset() -> Vector2:
	return _drift_offset


func configure(theme: SkyThemeDef, density: float, sky_material: Material = null, subdivisions: int = PUFF_SUBDIVISIONS) -> void:
	if _instance != null:
		_instance.queue_free()
		_instance = null
	if _upper != null:
		_upper.queue_free()
		_upper = null
	_material = null
	_cycle_base.clear()
	_highest_top = -INF
	_highest_top_near_disc = -INF
	_upper_lowest_bottom = INF
	_clear_occlusion_bounds()
	var layers: Array[_Layer] = _layers_for(theme, density)
	var clumps: int = 0
	for layer: _Layer in layers:
		clumps += layer.clumps
	if theme == null or theme.cloud_puff_material == null or clumps <= 0 or theme.cloud_puffs_per_clump <= 0:
		visible = false
		return
	_material = theme.cloud_puff_material.duplicate() as ShaderMaterial
	if _material == null:
		visible = false
		return
	_inflate = hull_inflate(_material)
	_exclusion_radius_m = exclusion_radius_m(theme, disc_radius_m)
	_disc_ceiling_m = disc_ceiling_m(theme, disc_radius_m)
	visible = true
	add_to_group(WeatherFogShader.GROUP)
	add_to_group(GROUP)
	WeatherFogShader.apply(_material)
	_material.set_shader_parameter(YAW_PARAMETER, theme.sky_yaw_offset_deg)
	_material.set_shader_parameter(DRIFT_EDGE_FADE_PARAMETER, drift_config.edge_fade_m)
	_material.set_shader_parameter(DRIFT_EXCLUSION_FADE_PARAMETER, drift_config.exclusion_fade_m)
	_material.set_shader_parameter(DRIFT_OFFSET_PARAMETER, _drift_offset)
	_material.set_shader_parameter(PITCH_PARAMETER, theme.sky_pitch_offset_deg)
	_material.set_shader_parameter(FLAT_BASE_PARAMETER, theme.cloud_flat_base)
	_material.set_shader_parameter(FAR_FADE_CAP_PARAMETER, theme.proc_far_fade_cap if theme.sky_look_procedural else 1.0)
	# Transparent-pass draw (see the shader's DECISION): first among
	# transparents, so ghosts, particles and birds blend over the clouds.
	_material.render_priority = RenderingServer.MATERIAL_RENDER_PRIORITY_MIN
	apply_lighting(lighting)
	var sky: ShaderMaterial = sky_material as ShaderMaterial
	if sky != null:
		for parameter: StringName in SHARED_SKY_PARAMETERS:
			var value: Variant = sky.get_shader_parameter(parameter)
			if value != null:
				_material.set_shader_parameter(parameter, value)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = theme.cloud_seed
	_instance = _build_instance("Puffs", layers, theme, subdivisions, rng, theme.cloud_flat_base)
	add_child(_instance)
	# Bontago-mp0.29: the same puffs, shader, material and lighting again above
	# the disc, always present (weather only changes its lighting).
	var upper_layers: Array[_Layer] = _upper_layers_for(theme, density)
	if not upper_layers.is_empty():
		rng.seed = theme.cloud_seed + upper_tuning.upper_seed_offset
		_upper = _build_instance("UpperPuffs", upper_layers, theme, subdivisions, rng, upper_layers[0].flat_base)
		add_child(_upper)
		_apply_upper_parameters()


## One MultiMeshInstance3D of `layers`' clumps drawn with the shared puff material.
func _build_instance(node_name: String, layers: Array[_Layer], theme: SkyThemeDef, subdivisions: int,
		rng: RandomNumberGenerator, flat_base: float) -> MultiMeshInstance3D:
	var clumps: int = 0
	for layer: _Layer in layers:
		clumps += layer.clumps
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.use_colors = true
	multimesh.mesh = build_puff_mesh(flat_base, subdivisions)
	multimesh.instance_count = clumps * theme.cloud_puffs_per_clump
	var index: int = 0
	for layer: _Layer in layers:
		for _clump: int in range(layer.clumps):
			index = _add_clump(multimesh, index, theme, layer, rng)
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = _material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.layers = RENDER_LAYER_BIT
	# The shader slides puffs along the wind inside the layer's square wrap domain, so the
	# culling box must cover the whole domain.
	var extent: float = 0.0
	var low: float = INF
	var high: float = -INF
	for layer: _Layer in layers:
		if layer.clumps <= 0:
			continue
		extent = maxf(extent, layer.ring_outer_m + layer.radius_max_m * 2.0)
		low = minf(low, layer.base_min_m - layer.radius_max_m)
		high = maxf(high, layer.top_max_m)
	instance.custom_aabb = AABB(Vector3(-extent, low, -extent), Vector3(extent * 2.0, high - low, extent * 2.0))
	return instance


## Per-instance shader parameters of the always-present upper puff layer.
func _apply_upper_parameters() -> void:
	_upper.set_instance_shader_parameter(&"floor_on", 1.0)
	_upper.set_instance_shader_parameter(&"edge_soft_px", upper_tuning.upper_edge_softness_px if upper_tuning != null else 0.0)
	if upper_tuning == null:
		return
	# Bontago-mp0.93: the layer's own base plane (the shader reads it per instance, the
	# sea keeps the material's flat_base), and the camera-clearance dither fade. The
	# fade uniforms live on the shared material but only the floor_on layer applies them.
	_upper.set_instance_shader_parameter(FLAT_BASE_OVERRIDE_PARAMETER, upper_tuning.upper_flat_base)
	_material.set_shader_parameter(CLEAR_FADE_START_PARAMETER, upper_tuning.upper_clear_fade_start_m)
	_material.set_shader_parameter(CLEAR_FADE_END_PARAMETER, upper_tuning.upper_clear_fade_end_m)
	_occ_clear_start_m = upper_tuning.upper_clear_fade_start_m
	_occ_clear_end_m = upper_tuning.upper_clear_fade_end_m


func upper_instance() -> MultiMeshInstance3D:
	return _upper


func upper_puff_count() -> int:
	return _upper.multimesh.instance_count if _upper != null else 0


## Largest silhouette the puff shader can carve beyond a puff's radius, as a
## fraction of it (the same sum shaders/cloud_puffs.gdshader inflates its hull by).
static func hull_inflate(material: ShaderMaterial) -> float:
	var lump_height: float = _float_param(material, &"lump_height", 0.35)
	var lump_bias: float = _float_param(material, &"lump_bias", 0.6)
	return lump_height * (1.0 - lump_bias) + _float_param(material, &"billow_amount", 0.03) + _float_param(material, &"hull_margin", 0.04)


static func _float_param(material: ShaderMaterial, name: StringName, fallback: float) -> float:
	var value: Variant = material.get_shader_parameter(name)
	return float(value) if value is float else fallback


## Clearance (m) kept around the disc: cloud_disc_clearance_ratio of the largest
## field radius.
static func disc_clearance_m(theme: SkyThemeDef, radius_m: float = MapDef.RADIUS_LARGE) -> float:
	return radius_m * theme.cloud_disc_clearance_ratio


## Radius (m) of the cylinder around the disc axis no puff may rise out of the
## under-disc ceiling inside: the largest field plus the clearance.
static func exclusion_radius_m(theme: SkyThemeDef, radius_m: float = MapDef.RADIUS_LARGE) -> float:
	return radius_m + disc_clearance_m(theme, radius_m)


## World Y no puff top inside the exclusion cylinder may exceed: the disc's
## underside (MapDef.disk_height below y 0) minus the clearance.
static func disc_ceiling_m(theme: SkyThemeDef, radius_m: float = MapDef.RADIUS_LARGE) -> float:
	return -MapDef.new().disk_height - disc_clearance_m(theme, radius_m)


## Bontago-mp0.29: the overcast layer above the disc -- clumps over a disc of
## upper_ring_outer_m around the axis, flat bases from height_m up, scaled by the
## density preset like the sea (Low also uses upper_clump_count_low).
func _upper_layers_for(theme: SkyThemeDef, density: float) -> Array[_Layer]:
	var layers: Array[_Layer] = []
	if upper_tuning == null or theme == null:
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
	# Bontago-mp0.93: round bottoms hang up to upper_base_sink_m under their clump's
	# base level, so the clumps start that much higher and nothing hangs below height_m.
	upper.flat_base = upper_tuning.upper_flat_base
	upper.sink_m = upper_tuning.upper_base_sink_m
	upper.detail_min_up = -upper_tuning.upper_belly_depth
	upper.vertical_scale = upper_tuning.upper_puff_squash
	upper.base_min_m = upper_tuning.height_m + upper.sink_m
	upper.base_max_m = upper.base_min_m + upper_tuning.upper_base_spread_m
	upper.radius_min_m = upper_tuning.upper_clump_radius_min_m
	upper.radius_max_m = upper_tuning.upper_clump_radius_max_m
	upper.top_max_m = upper.base_max_m + upper.radius_max_m * (theme.cloud_clump_height_ratio * (1.0 + SIZE_JITTER) + 1.0)
	layers.append(upper)
	return layers


## The sea layer and (when the theme has any) the cloud-bank layer, with the
## density preset applied to both clump counts.
static func _layers_for(theme: SkyThemeDef, density: float) -> Array[_Layer]:
	var layers: Array[_Layer] = []
	if theme == null:
		return layers
	var scale: float = clampf(density, 0.0, 1.0)
	var sea: _Layer = _Layer.new()
	sea.clumps = int(round(float(theme.cloud_clump_count) * scale))
	sea.ring_inner_m = theme.cloud_ring_inner_m
	sea.ring_outer_m = theme.cloud_ring_outer_m
	sea.radial_bias = theme.cloud_radial_bias
	sea.base_min_m = theme.cloud_base_min_m
	sea.base_max_m = theme.cloud_base_max_m
	# Bontago-t8x.2: the sea layer rides cloud_puff_raise_m higher; the disc
	# clearance clamp in _write_puff() keeps it clear of the disc and play volume.
	sea.base_min_m += theme.cloud_puff_raise_m
	sea.base_max_m += theme.cloud_puff_raise_m
	sea.top_max_m = theme.cloud_top_max_m + theme.cloud_puff_raise_m
	sea.radius_min_m = theme.cloud_clump_radius_min_m
	sea.radius_max_m = theme.cloud_clump_radius_max_m
	layers.append(sea)
	var banks: _Layer = _Layer.new()
	banks.clumps = int(round(float(theme.cloud_bank_count) * scale))
	banks.kind = CloudDriftMath.KIND_BANK
	banks.ring_inner_m = theme.cloud_bank_ring_inner_m
	banks.ring_outer_m = theme.cloud_bank_ring_outer_m
	banks.radial_bias = 1.0
	banks.base_min_m = theme.cloud_bank_base_min_m
	banks.base_max_m = theme.cloud_bank_base_max_m
	banks.top_max_m = theme.cloud_bank_top_max_m
	banks.radius_min_m = theme.cloud_bank_radius_min_m
	banks.radius_max_m = theme.cloud_bank_radius_max_m
	layers.append(banks)
	# DECISION (Bontago-59o.19): the below-horizon cloud sea of the procedural
	# look is a far ring of the same 3D puffs (they already read well and need no
	# new art) rather than a shader-only height field; the sky shader keeps only a
	# flat violet cloud floor and haze between them. Gated on the toggle so the
	# painted look is unchanged.
	if theme.sky_look_procedural and theme.proc_far_count > 0:
		var far: _Layer = _Layer.new()
		far.kind = CloudDriftMath.KIND_FAR
		far.clumps = int(round(float(theme.proc_far_count) * scale))
		far.ring_inner_m = theme.proc_far_ring_inner_m
		far.ring_outer_m = theme.proc_far_ring_outer_m
		far.radial_bias = theme.proc_far_radial_bias
		far.base_min_m = theme.proc_far_base_min_m
		far.base_max_m = theme.proc_far_base_max_m
		far.top_max_m = theme.proc_far_top_max_m + theme.cloud_puff_raise_m
		far.base_min_m += theme.cloud_puff_raise_m
		far.base_max_m += theme.cloud_puff_raise_m
		far.radius_min_m = theme.proc_far_radius_min_m
		far.radius_max_m = theme.proc_far_radius_max_m
		layers.append(far)
	return layers


## Writes one clump's puffs from `index`; returns the next free index.
func _add_clump(multimesh: MultiMesh, index: int, theme: SkyThemeDef, layer: _Layer, rng: RandomNumberGenerator) -> int:
	var azimuth: float = rng.randf() * TAU
	# Uniform over the ring's area, not its radius.
	# A radial bias above 1 crowds clumps toward the inner (near) edge.
	var inner_sq: float = layer.ring_inner_m * layer.ring_inner_m
	var outer_sq: float = layer.ring_outer_m * layer.ring_outer_m
	var ring_radius: float = sqrt(lerpf(inner_sq, outer_sq, pow(rng.randf(), maxf(layer.radial_bias, 0.01))))
	var centre: Vector3 = Vector3(cos(azimuth) * ring_radius, 0.0, sin(azimuth) * ring_radius)
	var clump_radius: float = rng.randf_range(layer.radius_min_m, layer.radius_max_m)
	var clump_height: float = clump_radius * theme.cloud_clump_height_ratio * rng.randf_range(1.0 - SIZE_JITTER, 1.0 + SIZE_JITTER)
	var base_y: float = rng.randf_range(layer.base_min_m, layer.base_max_m)
	base_y = minf(base_y, layer.top_max_m - clump_height)
	# Bontago-mp0.92: the clump's own speed times its layer's depth rate (near layers slide
	# faster: parallax). The shader moves it along the shared wind by drift_offset * speed.
	var speed: float = rng.randf_range(theme.cloud_drift_speed_min_mps, theme.cloud_drift_speed_max_mps)
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
	var flat: float = layer.flat_base if layer.is_upper else theme.cloud_flat_base
	var total: int = theme.cloud_puffs_per_clump
	var detail_count: int = int(float(total) * DETAIL_SHARE) if total > 2 else 0
	var body_count: int = total - detail_count
	var body_centres: Array[Vector3] = []
	var body_radii: Array[float] = []
	var first_puff: int = _occ_puffs.size() / OCC_PUFF_STRIDE
	for puff: int in range(body_count):
		var spread: float = 0.0 if puff == 0 else sqrt(rng.randf()) * SPREAD_FRACTION
		var angle: float = rng.randf() * TAU
		var offset: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * spread * clump_radius
		var radius: float = clump_radius * lerpf(CORE_RADIUS_FRACTION, RIM_RADIUS_FRACTION, spread)
		radius *= rng.randf_range(1.0 - SIZE_JITTER, 1.0 + SIZE_JITTER)
		var top: float = base_y + clump_height * (1.0 - DOME_FALLOFF * spread * spread) * rng.randf_range(TOP_JITTER_MIN, 1.0)
		var y: float = puff_centre_y(top, radius * layer.vertical_scale, base_y, flat, layer.sink_m * rng.randf() if layer.is_upper else 0.0)
		var at: Vector3 = centre + offset + Vector3(0.0, y, 0.0)
		index = _write_puff(multimesh, index, at, radius, layer, rng, angular_speed, base_y, clump_height, flat, rest)
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
		index = _write_puff(multimesh, index, at, radius, layer, rng, angular_speed, base_y, clump_height, flat, rest)
	_record_clump_bounds(first_puff, angular_speed, layer.is_upper, rest)
	return index


func _write_puff(multimesh: MultiMesh, index: int, at: Vector3, radius: float, layer: _Layer,
		rng: RandomNumberGenerator, angular_speed: float, base_y: float, clump_height: float, flat: float, rest: Color) -> int:
	# Never let a puff top rise above its layer ceiling.
	var height: float = radius * layer.vertical_scale
	at.y = minf(at.y, layer.top_max_m - height)
	var stretch: float = rng.randf_range(1.0, STRETCH_MAX)
	# Bontago-t8x.2: a puff that could reach the disc or the play volume (its
	# footprint, inflated by the shader's lumps/billow, enters the exclusion
	# cylinder) is held under the disc by the clearance. Bontago-mp0.92: the
	# shader now slides clumps along the wind, so a below-disc clump drifting inside the
	# exclusion radius dissolves instead (drift_vis); this clamp holds for the rest position.
	var inflated: float = radius * (1.0 + _inflate)
	var footprint: float = Vector2(at.x, at.z).length() - inflated * stretch
	if not layer.is_upper:
		if footprint < _exclusion_radius_m:
			at.y = minf(at.y, _disc_ceiling_m - inflated)
			_highest_top_near_disc = maxf(_highest_top_near_disc, at.y + inflated)
		_highest_top = maxf(_highest_top, at.y + radius)
	if layer.is_upper:
		# The mesh's lowest point is its base plane (flat_base of the height under the centre, 1 = round).
		_upper_lowest_bottom = minf(_upper_lowest_bottom, at.y - height * layer.flat_base)
	var basis: Basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(radius * stretch, height, radius * stretch))
	_record_puff(at, radius * stretch, height, flat)
	multimesh.set_instance_transform(index, Transform3D(basis, at))
	multimesh.set_instance_custom_data(index, Color(angular_speed, rng.randf() * TAU, base_y, clump_height))
	multimesh.set_instance_color(index, rest)
	return index + 1


## Bontago-mp0.95: appends one puff's occlusion row (a spheroid: horizontal radius
## `horizontal`, vertical radius `vertical`, both grown by the shader's hull inflation).
func _record_puff(at: Vector3, horizontal: float, vertical: float, flat: float) -> void:
	var grow: float = 1.0 + _inflate
	var cut: float = NO_BASE_CUT if flat >= ROUND_BASE_FROM else at.y - vertical * flat
	_occ_puffs.append_array(PackedFloat32Array([at.x, at.y, at.z, horizontal * grow, vertical * grow, cut]))


## Bontago-mp0.95: closes the clump whose puffs start at row `first_puff`: its bounding sphere
## (rest frame), height slab and drift speed.
func _record_clump_bounds(first_puff: int, angular_speed: float, is_upper: bool, rest: Color) -> void:
	var rows: int = _occ_puffs.size() / OCC_PUFF_STRIDE
	var low: Vector3 = Vector3(INF, INF, INF)
	var high: Vector3 = Vector3(-INF, -INF, -INF)
	for row: int in range(first_puff, rows):
		var base: int = row * OCC_PUFF_STRIDE
		var reach: Vector3 = Vector3(_occ_puffs[base + 3], _occ_puffs[base + 4], _occ_puffs[base + 3])
		var at: Vector3 = Vector3(_occ_puffs[base], _occ_puffs[base + 1], _occ_puffs[base + 2])
		low = low.min(at - reach)
		high = high.max(at + reach)
	var centre: Vector3 = (low + high) * 0.5
	var radius: float = 0.0
	for row: int in range(first_puff, rows):
		var base: int = row * OCC_PUFF_STRIDE
		var at: Vector3 = Vector3(_occ_puffs[base], _occ_puffs[base + 1], _occ_puffs[base + 2])
		radius = maxf(radius, at.distance_to(centre) + maxf(_occ_puffs[base + 3], _occ_puffs[base + 4]))
	_occ_centre.append(centre)
	_occ_radius.append(radius)
	_occ_speed.append(angular_speed)
	_occ_rest.append(Vector2(rest.r, rest.g))
	_occ_domain.append(rest.b)
	_occ_excl.append(rest.a)
	_occ_y_low.append(low.y)
	_occ_y_high.append(high.y)
	_occ_first.append(first_puff)
	_occ_count.append(rows - first_puff)
	_occ_upper.append(1 if is_upper else 0)


func _clear_occlusion_bounds() -> void:
	_occ_puffs.clear()
	_occ_centre.clear()
	_occ_radius.clear()
	_occ_speed.clear()
	_occ_rest.clear()
	_occ_domain.clear()
	_occ_excl.clear()
	_occ_y_low.clear()
	_occ_y_high.clear()
	_occ_first.clear()
	_occ_count.clear()
	_occ_upper.clear()
	_occ_clear_start_m = 0.0
	_occ_clear_end_m = 0.0


## Number of clumps / puffs with recorded sun-occlusion bounds (tests, diagnostics).
func occlusion_clump_count() -> int:
	return _occ_speed.size()


func occlusion_puff_count() -> int:
	return _occ_puffs.size() / OCC_PUFF_STRIDE


## Bontago-mp0.95: how much the puffs hide the sun seen along the ray from `from` toward the
## unit-ish `dir`, 0 (clear sky) .. 1 (fully hidden). The sun is at infinity, so the ray is a
## half-line. Cheap bounds test, no physics: clumps first by a height slab and a bounding
## sphere (each clump's wind shift undone on the ray: the shader moves clumps by
## drift_offset * their speed, wrapped), then only the few puffs of a clump the ray
## enters, as spheroids with a soft silhouette (`tuning.cloud_edge_softness`) and the
## shader's camera-clearance fade for the upper layer. Transmittances multiply, so several
## thin puffs add up. `drift` is the integrated cloud wind to evaluate at (the live one by default).
## The CloudSea node is assumed to sit at the world origin, as Skybox places it.
func sun_ray_cloud_occlusion(from: Vector3, dir: Vector3, tuning: SunFlareConfig = null, drift: Vector2 = OCC_LIVE_DRIFT) -> float:
	var clumps: int = _occ_speed.size()
	if clumps == 0 or not visible or dir.length_squared() <= 0.0:
		return 0.0
	var settings: SunFlareConfig = tuning if tuning != null else OCC_DEFAULT_TUNING
	var ray: Vector3 = dir.normalized()
	var wind: Vector2 = _drift_offset if drift == OCC_LIVE_DRIFT else drift
	var flat_ray: bool = absf(ray.y) < OCC_FLAT_RAY
	var transmittance: float = 1.0
	for clump: int in range(clumps):
		# Height slab: the half-line must reach this clump's height range at all.
		if flat_ray:
			if from.y < _occ_y_low[clump] or from.y > _occ_y_high[clump]:
				continue
		elif maxf((_occ_y_low[clump] - from.y) / ray.y, (_occ_y_high[clump] - from.y) / ray.y) < 0.0:
			continue
		var rest: Vector2 = _occ_rest[clump]
		var wrapped: Vector2 = CloudDriftMath.wrapped_position(rest, CloudDriftMath.clump_shift(wind, _occ_speed[clump]), _occ_domain[clump])
		var shown: float = CloudDriftMath.visibility(wrapped, _occ_domain[clump], _occ_excl[clump], drift_config)
		if shown <= 0.0:
			continue
		var moved: Vector2 = wrapped - rest
		var origin: Vector3 = Vector3(from.x - moved.x, from.y, from.z - moved.y)
		var heading: Vector3 = ray
		var to_centre: Vector3 = _occ_centre[clump] - origin
		var along: float = to_centre.dot(heading)
		var radius: float = _occ_radius[clump]
		if along < -radius or to_centre.length_squared() - along * along > radius * radius:
			continue
		var first: int = _occ_first[clump]
		var upper: bool = _occ_upper[clump] != 0
		for row: int in range(first, first + _occ_count[clump]):
			transmittance *= 1.0 - _puff_cover(origin, heading, row, upper, settings) * shown
		if transmittance <= 0.0:
			return 1.0
	return clampf(1.0 - transmittance, 0.0, 1.0)


## One puff's share (0..1) of hiding the ray `origin` + t * `heading` (rest frame): the ray
## through the spheroid, soft toward its silhouette, clipped to the flat base and, for the
## upper layer, faded by the shader's camera-clearance dither.
func _puff_cover(origin: Vector3, heading: Vector3, row: int, upper: bool, settings: SunFlareConfig) -> float:
	var base: int = row * OCC_PUFF_STRIDE
	var horizontal: float = _occ_puffs[base + 3]
	var vertical: float = _occ_puffs[base + 4]
	var local: Vector3 = Vector3((origin.x - _occ_puffs[base]) / horizontal, (origin.y - _occ_puffs[base + 1]) / vertical,
			(origin.z - _occ_puffs[base + 2]) / horizontal)
	var local_heading: Vector3 = Vector3(heading.x / horizontal, heading.y / vertical, heading.z / horizontal)
	var speed_sq: float = local_heading.length_squared()
	var along: float = local.dot(local_heading)
	var miss_sq: float = maxf(local.length_squared() - along * along / speed_sq, 0.0)
	if miss_sq >= 1.0:
		return 0.0
	var closest: float = -along / speed_sq
	var half_chord: float = sqrt((1.0 - miss_sq) / speed_sq)
	var t_in: float = closest - half_chord
	var t_out: float = closest + half_chord
	var cut: float = _occ_puffs[base + 5]
	if cut > NO_BASE_CUT:
		if heading.y > OCC_FLAT_RAY:
			t_in = maxf(t_in, (cut - origin.y) / heading.y)
		elif heading.y < -OCC_FLAT_RAY:
			t_out = minf(t_out, (cut - origin.y) / heading.y)
		elif origin.y < cut:
			return 0.0
	if t_out <= maxf(t_in, 0.0):
		return 0.0
	var softness: float = clampf(settings.cloud_edge_softness, 0.0, 1.0)
	var cover: float = 1.0 - smoothstep(1.0 - softness, 1.0, sqrt(miss_sq))
	if upper and _occ_clear_end_m > 0.0:
		var entry_y: float = origin.y + maxf(t_in, 0.0) * heading.y
		cover *= smoothstep(_occ_clear_start_m, maxf(_occ_clear_end_m, _occ_clear_start_m + OCC_FLAT_RAY), entry_y - origin.y)
	return cover


## The puff shader's TIME as GDScript can read it: seconds since start wrapped at the
## project's time rollover (the engine default is 3600 s).
static func shader_time_s() -> float:
	var rollover: float = float(ProjectSettings.get_setting(SHADER_TIME_ROLLOVER_SETTING, SHADER_TIME_ROLLOVER_DEFAULT_S))
	return fmod(float(Time.get_ticks_msec()) * 0.001, maxf(rollover, 1.0))


## Bontago-mp0.93: centre height of a body puff whose top would be `top`: its bottom plane (at
## `flat` of its radius below the centre) never goes under `base_y`, less `sink_m` (the upper
## layer lets round bottoms hang a little below the clump's level so they share no plane).
## With flat = 1 the puff just rests on base_y.
static func puff_centre_y(top: float, radius: float, base_y: float, flat: float, sink_m: float = 0.0) -> float:
	return maxf(top - radius, base_y + radius * flat - sink_m)


## Lowest nominal bottom of any upper puff written by the last configure() (INF without one).
func upper_lowest_bottom() -> float:
	return _upper_lowest_bottom


## Highest world Y any puff reaches (before billow), for tests and checks.
func highest_puff_top() -> float:
	return _highest_top


## Highest inflated top of any puff that could reach the disc's exclusion volume.
func highest_top_near_disc() -> float:
	return _highest_top_near_disc


func puff_count() -> int:
	return _instance.multimesh.instance_count if _instance != null else 0


func puff_instance() -> MultiMeshInstance3D:
	return _instance


func puff_material() -> ShaderMaterial:
	return _material


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


## Index of the normalized midpoint of edge a-b, appended once per edge.
static func _midpoint(vertices: Array[Vector3], cache: Dictionary[Vector2i, int], a: int, b: int) -> int:
	var key: Vector2i = Vector2i(mini(a, b), maxi(a, b))
	if cache.has(key):
		return cache[key]
	vertices.append(((vertices[a] + vertices[b]) * 0.5).normalized())
	var index: int = vertices.size() - 1
	cache[key] = index
	return index
