class_name CloudShadows
extends Node3D
## Bontago-mp0.127 (owner playtest: "clouds should cast shadows on arena when they cover the
## sun"): soft cloud shadows sweeping the disc and blocks by day, and a brief dimming of the
## direct sun light while a cloud covers the sun direction.
##
## DECISION: two cross-fading Decal nodes projected along the sun direction, textured with
## tiling-free noise masks. A Decal darkens the albedo of every mesh inside its box
## (disc, blocks, props) with one cheap Forward+ pass, needs no edit to any block / disc
## shader and gives the right oblique stretch at low sun for free. A light projector is not
## available on a DirectionalLight3D, and per-shader shadow terms would touch every material.
## The two layers use different noise and cross-fade (core/CloudShadowMath.gd) while each
## drifts along the cloud wind (Bontago-mp0.92: heading and speed from the Skybox's shared
## CloudDriftState, so shadows follow the visible clouds and the storm wind; the config
## heading is only the fallback), so no decal edge is ever visible. Territory colours stay readable: the shadow
## only multiplies albedo by a tint at <= max_strength alpha.
## DECISION: the sun dimming uses the real puff bounds (CloudSea.sun_ray_cloud_occlusion, the
## same query the sun flare uses) cast from the arena toward the sun, smoothed, and is applied
## through Skybox.set_sun_cloud_scale() so the one light-energy writer stays Skybox.
## Off on the Low graphics preset (GraphicsPreset.cloud_shadows_enabled).

const CONFIG: CloudShadowConfig = preload("res://config/cloud_shadows.tres")
const LAYER_COUNT: int = 2
## Layers fainter than this alpha are hidden (cannot be seen).
const MIN_VISIBLE_ALPHA: float = 0.004
## Seed spacing between the two layers' noise.
const LAYER_SEED_STEP: int = 7919
const NOISE_OCTAVES: int = 3

@export var field_path: NodePath
@export var config: CloudShadowConfig = CONFIG

var _decals: Array[Decal] = []
## Unit ground wind of the last step (the Skybox's shared cloud drift heading).
var _wind: Vector2 = Vector2.RIGHT
var _skybox: Skybox = null
var _cloud_sea: CloudSea = null
var _enabled: bool = true
var _field_radius: float = MapDef.RADIUS_MEDIUM
var _time_s: float = 0.0
var _time_seeded: bool = false
## Range (s) of the seeded start offset of the shadow sweep.
const SEED_PHASE_RANGE_S: int = 600
## Cached disc overlay (refreshed when freed).
var _overlay: TerritoryOverlay = null
var _query_age_s: float = 0.0
var _occlusion: float = 0.0
var _dim_follow: float = 1.0
var _sun_dim_applied: bool = false
## True once the disc shader term was last pushed empty (skips redundant material writes).
var _disc_clear: bool = false


func _ready() -> void:
	top_level = true
	var preset: GraphicsPreset = Settings.current_graphics_preset()
	_enabled = preset == null or preset.cloud_shadows_enabled
	# Decals and noise textures are only built while enabled (lazily on a preset change).
	if _enabled:
		_build_layers()
	Settings.graphics_preset_changed.connect(_on_graphics_preset_changed)
	Events.match_scope_reset.connect(_on_match_scope_reset)


func _build_layers() -> void:
	if not _decals.is_empty():
		return
	for index: int in range(LAYER_COUNT):
		var decal: Decal = Decal.new()
		decal.texture_albedo = _build_noise_texture(index)
		decal.upper_fade = 0.0
		decal.lower_fade = 0.0
		decal.normal_fade = 0.0
		# The disc is darkened by its own shader term (EMISSION-dominated); keep the decal off it.
		decal.cull_mask = decal.cull_mask & ~DiscMirror.DISC_LAYER_BIT
		decal.visible = false
		add_child(decal)
		_decals.append(decal)


func _exit_tree() -> void:
	if Settings.graphics_preset_changed.is_connected(_on_graphics_preset_changed):
		Settings.graphics_preset_changed.disconnect(_on_graphics_preset_changed)
	if Events.match_scope_reset.is_connected(_on_match_scope_reset):
		Events.match_scope_reset.disconnect(_on_match_scope_reset)
	_release_sun()


func is_enabled() -> bool:
	return _enabled


## Smoothed direct-sun scale this node last computed (1 = clear).
func sun_scale() -> float:
	return _dim_follow


func decals() -> Array[Decal]:
	return _decals


func _on_graphics_preset_changed(preset: GraphicsPreset) -> void:
	_enabled = preset == null or preset.cloud_shadows_enabled
	if _enabled:
		_build_layers()
	else:
		_hide_all()
		_release_sun()


func _on_match_scope_reset() -> void:
	_occlusion = 0.0
	_query_age_s = 0.0
	_time_seeded = false
	_release_sun()


func _process(delta: float) -> void:
	if not _enabled:
		return
	_time_s += delta
	if _skybox == null or not is_instance_valid(_skybox):
		_skybox = get_tree().get_first_node_in_group(Skybox.OVERCAST_GROUP) as Skybox
		if _skybox == null:
			return
		_time_seeded = false
	if not _time_seeded:
		# Cosmetic start phase from the match's sky variation seed (differs per match, no sync).
		_time_s = float(absi(hash(_skybox.variation_seed())) % SEED_PHASE_RANGE_S)
		_time_seeded = true
	step(delta, _skybox.sun_direction(), _skybox.daylight(), _skybox.cloud_drift_speed_mps(), _skybox.cloud_wind_dir())


## One frame (also the test seam): places the decals for the sun at unit `sun_dir` with
## `daylight` 0..1 and mean cloud drift `drift_mps` along the unit ground wind `wind` (the
## Skybox's shared cloud drift; ZERO = the config's fallback heading), and updates the sun dimming.
func step(delta: float, sun_dir: Vector3, daylight: float, drift_mps: float, wind: Vector2 = Vector2.ZERO) -> void:
	var known: bool = sun_dir.length_squared() > 0.0
	var strength: float = CloudShadowMath.strength(sun_dir.normalized().y, daylight, config) if known else 0.0
	_wind = wind.normalized() if wind.length_squared() > 0.0 else CloudShadowMath.wind_dir(config.wind_heading_deg)
	_update_decals(sun_dir.normalized(), strength, drift_mps)
	_update_sun_dim(delta, sun_dir, daylight)


func _update_decals(sun_dir: Vector3, strength: float, drift_mps: float) -> void:
	if strength <= MIN_VISIBLE_ALPHA:
		_hide_all()
		return
	_refresh_field_radius()
	var travel: float = minf(drift_mps * config.speed_scale * config.layer_period_s,
			CloudShadowMath.max_travel(_field_radius, config))
	var size_xz: float = CloudShadowMath.span(_field_radius, config)
	var size_y: float = 2.0 * (_field_radius + config.volume_height_m)
	# A Decal projects along its local -Y; light travels along -sun_dir, so local +Y points
	# toward the sun and local X is the in-plane axis along the wind.
	var along: Vector3 = Vector3(_wind.x, 0.0, _wind.y)
	along = (along - sun_dir * along.dot(sun_dir)).normalized()
	var basis_sun: Basis = Basis(along, sun_dir, along.cross(sun_dir).normalized())
	var centre: Vector3 = Vector3(0.0, config.volume_height_m * 0.5, 0.0)
	var to_unit: Array[Transform3D] = []
	var alphas: Array[float] = []
	var textures: Array[Texture2D] = []
	for index: int in range(_decals.size()):
		var decal: Decal = _decals[index]
		var phase: float = CloudShadowMath.layer_phase(_time_s, config.layer_period_s, index)
		var alpha: float = strength * CloudShadowMath.layer_weight(phase)
		decal.visible = alpha > MIN_VISIBLE_ALPHA
		if not decal.visible:
			continue
		decal.size = Vector3(size_xz, size_y, size_xz)
		decal.global_transform = Transform3D(basis_sun, centre + along * CloudShadowMath.layer_offset(phase, travel))
		decal.modulate = Color(config.shadow_color.r, config.shadow_color.g, config.shadow_color.b, alpha)
		to_unit.append(Transform3D(Basis.from_scale(Vector3(1.0 / size_xz, 1.0 / size_y, 1.0 / size_xz)), Vector3.ZERO) 				* decal.global_transform.affine_inverse())
		alphas.append(alpha)
		textures.append(decal.texture_albedo)
	_push_disc(textures, to_unit, alphas)


func _update_sun_dim(delta: float, sun_dir: Vector3, daylight: float) -> void:
	_query_age_s += delta
	var target: float = 0.0
	if daylight > 0.0 and sun_dir.y > 0.0:
		if _query_age_s >= config.occlusion_refresh_s:
			_query_age_s = 0.0
			if (_cloud_sea == null or not is_instance_valid(_cloud_sea)) and is_inside_tree():
				_cloud_sea = get_tree().get_first_node_in_group(CloudSea.GROUP) as CloudSea
			if _cloud_sea != null:
				_occlusion = _cloud_sea.sun_ray_cloud_occlusion(
						Vector3(0.0, config.sun_ray_origin_height_m, 0.0), sun_dir.normalized())
			else:
				_occlusion = 0.0
		target = _occlusion
	else:
		_occlusion = 0.0
	var wanted: float = CloudShadowMath.sun_scale(target, config)
	_dim_follow = CloudShadowMath.follow(_dim_follow, wanted, config.sun_dim_rate, delta)
	if _skybox != null and is_instance_valid(_skybox):
		_skybox.set_sun_cloud_scale(_dim_follow)
		_sun_dim_applied = true


func _release_sun() -> void:
	if _sun_dim_applied and _skybox != null and is_instance_valid(_skybox):
		_skybox.set_sun_cloud_scale(1.0)
	_sun_dim_applied = false
	_dim_follow = 1.0


func _hide_all() -> void:
	for decal: Decal in _decals:
		decal.visible = false
	_push_disc([], [], [])


## Feeds the visible layers to the disc shader (see set_cloud_shadows); an empty set clears it.
func _push_disc(textures: Array[Texture2D], to_unit: Array[Transform3D], alphas: Array[float]) -> void:
	if not is_inside_tree() or (alphas.is_empty() and _disc_clear):
		return
	_disc_clear = alphas.is_empty()
	if _overlay == null or not is_instance_valid(_overlay) or not _overlay.is_inside_tree():
		_overlay = get_tree().get_first_node_in_group(TerritoryOverlay.WET_GROUP) as TerritoryOverlay
	var overlay: TerritoryOverlay = _overlay
	if overlay == null:
		return
	var none: Transform3D = Transform3D.IDENTITY
	var first: bool = not alphas.is_empty()
	var second: bool = alphas.size() > 1
	overlay.set_cloud_shadows(
		textures[0] if first else null, textures[1] if second else null,
		to_unit[0] if first else none, to_unit[1] if second else none,
		alphas[0] if first else 0.0, alphas[1] if second else 0.0, config.shadow_color)


func _refresh_field_radius() -> void:
	if field_path.is_empty():
		return
	var field_node: Field = get_node_or_null(field_path) as Field
	if field_node != null:
		_field_radius = field_node.map_definition().field_radius


## Cloud-shaped alpha mask: white with alpha from fractal noise above the coverage threshold,
## softened by edge_softness. Each layer gets its own seed so the cross-fade morphs shapes.
func _build_noise_texture(index: int) -> NoiseTexture2D:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = config.noise_seed + index * LAYER_SEED_STEP
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = NOISE_OCTAVES
	var size: float = CloudShadowMath.span(MapDef.RADIUS_MEDIUM, config)
	noise.frequency = size / (float(config.noise_texture_size) * maxf(config.feature_size_m, 1.0))
	var ramp: Gradient = Gradient.new()
	var edge_low: float = clampf(1.0 - config.coverage - config.edge_softness * 0.5, 0.0, 0.98)
	var edge_high: float = clampf(edge_low + config.edge_softness, edge_low + 0.01, 1.0)
	ramp.offsets = PackedFloat32Array([edge_low, edge_high])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1)])
	var texture: NoiseTexture2D = NoiseTexture2D.new()
	texture.width = config.noise_texture_size
	texture.height = config.noise_texture_size
	texture.noise = noise
	texture.color_ramp = ramp
	texture.seamless = false
	return texture
