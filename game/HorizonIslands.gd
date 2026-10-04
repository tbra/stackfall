class_name HorizonIslands
extends Node3D
## Cosmetic ring of low-poly floating islands on the horizon
## (assets/models/horizon_islands_v1). Visual only: no collision bodies, no
## shadow casting, never networked. Placement is a pure function of the config
## seed and the map id (placements_for), so host and clients build the same
## ring. Each island carries LOD0/LOD1/LOD2 meshes switched by the engine's
## visibility ranges (no per-frame script). Lighting comes from the cel
## material reading the scene's sun/ambient, so it follows the sky/time of day.

const VARIANT_SCENES: Array[PackedScene] = [
	preload("res://assets/models/horizon_islands_v1/mesa.tscn"),
	preload("res://assets/models/horizon_islands_v1/shelf.tscn"),
	preload("res://assets/models/horizon_islands_v1/crag.tscn"),
]
const LOD_NODE_NAMES: Array[String] = ["LOD0", "LOD1", "LOD2"]
const ISLAND_SHADER: Shader = preload("res://shaders/horizon_island.gdshader")
## How often (s) the haze colour is re-read from the live sky environment.
const HAZE_REFRESH_S: float = 0.5
const DEFAULT_CONFIG: HorizonIslandsConfig = preload("res://config/horizon_islands.tres")

@export var config: HorizonIslandsConfig = DEFAULT_CONFIG

var _material: ShaderMaterial = null
var _environment: Environment = null
var _haze_timer_s: float = 0.0


## Deterministic placements: Array of Dictionary {variant:int, position:Vector3,
## yaw:float, scale:float, stretch:Vector2, tilt:Vector2}, centered on the origin (the arena center).
static func placements_for(cfg: HorizonIslandsConfig, map_id: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if cfg == null or not cfg.enabled or cfg.count <= 0:
		return result
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([cfg.seed, String(map_id)])
	var slot: float = TAU / float(cfg.count)
	var base_angle: float = rng.randf() * TAU
	for i: int in cfg.count:
		var jitter: float = (rng.randf() - 0.5) * cfg.angle_jitter
		var angle: float = base_angle + (float(i) + 0.5 + jitter) * slot
		var radius: float = rng.randf_range(cfg.radius_min_m, cfg.radius_max_m)
		var height: float = rng.randf_range(cfg.height_min_m, cfg.height_max_m)
		result.append({
			"variant": rng.randi() % VARIANT_SCENES.size(),
			"position": Vector3(cos(angle) * radius, height, sin(angle) * radius),
			"yaw": rng.randf() * TAU,
			"scale": rng.randf_range(cfg.scale_min, cfg.scale_max),
			"stretch": Vector2(
				1.0 + (rng.randf() * 2.0 - 1.0) * cfg.stretch_fraction,
				1.0 + (rng.randf() * 2.0 - 1.0) * cfg.stretch_fraction),
			"tilt": Vector2(
				(rng.randf() * 2.0 - 1.0) * deg_to_rad(cfg.tilt_max_deg),
				(rng.randf() * 2.0 - 1.0) * deg_to_rad(cfg.tilt_max_deg)),
		})
	return result


## Rebuilds the ring for a map (called whenever the world is (re)built).
func rebuild_for_map(map: MapDef, environment: Environment = null) -> void:
	if environment != null:
		_environment = environment
	_material = ShaderMaterial.new()
	_material.shader = ISLAND_SHADER
	_material.set_shader_parameter(&"haze_amount", config.haze_amount)
	_material.set_shader_parameter(&"color_gain", config.color_gain)
	_refresh_haze()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	var map_id: StringName = map.id if map != null else &""
	for entry: Dictionary in placements_for(config, map_id):
		var island: Node3D = VARIANT_SCENES[int(entry["variant"])].instantiate() as Node3D
		island.position = entry["position"] as Vector3
		var stretch: Vector2 = entry["stretch"] as Vector2
		var tilt: Vector2 = entry["tilt"] as Vector2
		island.rotation = Vector3(tilt.x, float(entry["yaw"]), tilt.y)
		island.scale = Vector3(stretch.x, 1.0, stretch.y) * float(entry["scale"])
		_setup_lods(island)
		add_child(island)


func _setup_lods(island: Node3D) -> void:
	# Visibility ranges are measured in world units from the camera and are
	# affected by the node's scale; distances are camera-to-island.
	var begins: Array[float] = [0.0, config.lod1_begin_m, config.lod2_begin_m]
	var ends: Array[float] = [config.lod1_begin_m, config.lod2_begin_m, config.visibility_end_m]
	for i: int in LOD_NODE_NAMES.size():
		var mesh: GeometryInstance3D = island.get_node_or_null(LOD_NODE_NAMES[i]) as GeometryInstance3D
		if mesh == null:
			continue
		mesh.visible = true
		mesh.material_override = _material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.visibility_range_begin = begins[i]
		mesh.visibility_range_end = ends[i]
		mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


func _process(delta: float) -> void:
	_haze_timer_s -= delta
	if _haze_timer_s <= 0.0:
		_haze_timer_s = HAZE_REFRESH_S
		_refresh_haze()


## Time-of-day tint: the live sky fog colour (Skybox writes it into the
## Environment for every theme and the day/night cycle) becomes the haze colour.
func _refresh_haze() -> void:
	if _material != null and _environment != null:
		_material.set_shader_parameter(&"haze_color", _environment.fog_light_color)
