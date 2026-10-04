class_name HorizonStormCells
extends Node3D
## Bontago-mp0.126: one or two distant storm cells (vfx/weather/horizon_storm_cell_v1)
## on the horizon while the storm weather runs. StormPresentation owns one and feeds
## it the replicated storm intensity; the cells fade with it. Silhouette, count and
## bearing come from the match seed (pure `layout`), so host and clients agree,
## though the look is cosmetic and client-local. No collision, no shadows;
## lightning is each cell's own randomized timer and only lights the cell itself
## (its light range is far shorter than the distance to the arena).

const CONFIG: HorizonStormConfig = preload("res://config/horizon_storm.tres")
const CELL_SCENE: PackedScene = preload("res://vfx/weather/horizon_storm_cell_v1/storm_cell.tscn")
const SILHOUETTE_COUNT: int = 3
const FULL_CIRCLE_DEG: float = 360.0
const MAX_PLACEMENT_TRIES: int = 16

var config: HorizonStormConfig = CONFIG
var intensity: float = 0.0
var opacity: float = 0.0
var _cells: Array[Node3D] = []
var _seed: int = 0
var _seed_locked: bool = false


## Pure layout: [{bearing_deg, distance_m, style, seed, first_flash_s}] from `seed_value`.
static func layout(seed_value: int, cfg: HorizonStormConfig) -> Array[Dictionary]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([seed_value, cfg.seed_salt])
	var count: int = rng.randi_range(maxi(cfg.cell_count_min, 1), maxi(cfg.cell_count_max, cfg.cell_count_min))
	var out: Array[Dictionary] = []
	var styles: Array[int] = []
	for i: int in range(SILHOUETTE_COUNT):
		styles.append(i)
	for i: int in range(SILHOUETTE_COUNT - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = styles[i]
		styles[i] = styles[j]
		styles[j] = tmp
	var bearings: Array[float] = []
	for i: int in range(count):
		var bearing: float = rng.randf_range(0.0, FULL_CIRCLE_DEG)
		for _try: int in range(MAX_PLACEMENT_TRIES):
			var clear: bool = true
			for other: float in bearings:
				if absf(angle_difference(deg_to_rad(bearing), deg_to_rad(other))) < deg_to_rad(cfg.min_bearing_separation_deg):
					clear = false
			if clear:
				break
			bearing = rng.randf_range(0.0, FULL_CIRCLE_DEG)
		bearings.append(bearing)
		out.append({
			"bearing_deg": bearing,
			"distance_m": cfg.distance_m + rng.randf_range(-cfg.distance_jitter_m, cfg.distance_jitter_m),
			"style": styles[i % SILHOUETTE_COUNT],
			"seed": rng.randi(),
			"first_flash_s": rng.randf_range(cfg.first_flash_min_s, cfg.first_flash_max_s),
		})
	return out


func _ready() -> void:
	if not _seed_locked and is_inside_tree() and Match != null and Match.weather() != null:
		_seed = Match.weather().seed_value()
	_build()


## Tests and probes: fix the seed and rebuild.
func configure(seed_value: int, cfg: HorizonStormConfig = null) -> void:
	_seed = seed_value
	_seed_locked = true
	if cfg != null:
		config = cfg
	if is_inside_tree():
		_build()


func cells() -> Array[Node3D]:
	return _cells


func set_intensity(value: float) -> void:
	intensity = value


func _process(delta: float) -> void:
	var target: float = intensity if intensity >= config.min_intensity else 0.0
	opacity = move_toward(opacity, target, config.fade_rate_per_s * delta)
	_apply_opacity()


func _apply_opacity() -> void:
	visible = opacity > 0.0
	# Instance transparency (0 = opaque) dithers every part of the cell, rain and bolt included.
	var transparency: float = 1.0 - opacity
	for cell: Node3D in _cells:
		for child: Node in cell.get_children():
			var geometry: GeometryInstance3D = child as GeometryInstance3D
			if geometry != null:
				geometry.transparency = transparency


func _build() -> void:
	for cell: Node3D in _cells:
		if is_instance_valid(cell):
			remove_child(cell)
			cell.free()
	_cells.clear()
	for entry: Dictionary in layout(_seed, config):
		var cell: Node3D = CELL_SCENE.instantiate() as Node3D
		cell.set("seed_value", int(entry["seed"]))
		cell.set("silhouette_style", int(entry["style"]))
		cell.set("first_flash_delay_s", float(entry["first_flash_s"]))
		cell.set("flash_interval_min_s", config.flash_interval_min_s)
		cell.set("flash_interval_max_s", config.flash_interval_max_s)
		cell.scale = Vector3.ONE * config.cell_scale
		var bearing: float = deg_to_rad(float(entry["bearing_deg"]))
		var dist: float = float(entry["distance_m"])
		cell.position = Vector3(sin(bearing) * dist, config.elevation_m, -cos(bearing) * dist)
		add_child(cell)
		# The authored cell shows its rain-and-bolt side toward +Z; face the arena.
		cell.look_at(Vector3(0.0, config.elevation_m, 0.0), Vector3.UP, true)
		_cells.append(cell)
	_apply_opacity()
