class_name SnowDiscCover
extends Node3D
## Visual-only snow on the disc (Bontago-22y.6). No geometry of its own: it
## drives the snow layer inside the disc's own shader (shaders/territory.
## gdshader, the TerritoryOverlay material), so the composite order is
## disc -> snow -> territory tint/contour, holes stay open, and territory
## reads on snow with the same smooth contour as on bare disc.
##
## The shader's depth is an even base amount that rises with the level, plus
## a gentle low-frequency variation, deepened along plate seams, near the rim
## and around block bases (Bontago-mp0.32: no threshold, so no separate white
## blobs). The block-base bias is a one-byte-per-cell drift map this node
## rebuilds, a few blocks per frame, at each level change, and is filtered
## smooth so drifts fade out gently. Light snow is a faint frosting (low
## strength), heavy snow wind-streaked partial cover, capped so territory shows. Leaving the tree (snow cleared, match over) switches the
## layer off again. The colliding drifts are SnowCapBuilder's domes.

## Hash salts for the seed-based noise offset.
const NOISE_SALT_X: int = 0x68e31da4
const NOISE_SALT_Z: int = 0x1b56c4e9
## Noise-space range of the per-match offset (kept small: the shader hash
## loses float precision at large coordinates).
const NOISE_OFFSET_RANGE: float = 32.0

var _field: Field = null
var _grid: CellGrid = null
var _tuning: SnowTuning = null
var _seed: int = 0
var _material: ShaderMaterial = null
var _level: int = 0
var _blocks_source: Callable = Callable()
var _drift_image: Image = null
var _drift_texture: ImageTexture = null
var _drift_data: PackedByteArray = PackedByteArray()
var _drift_queue: Array = []
var _drift_head: int = 0
var _drift_building: bool = false


func configure(field: Field, seed_value: int, tuning: SnowTuning) -> void:
	_field = field
	_grid = field.grid()
	_seed = seed_value
	_tuning = tuning
	var overlay: TerritoryOverlay = field.overlay()
	_material = overlay.material() if overlay != null else null
	if _material == null:
		return
	_material.set_shader_parameter(&"snow_scale", tuning.cover_noise_scale)
	_material.set_shader_parameter(&"snow_variation", tuning.cover_variation)
	var wind: float = deg_to_rad(tuning.cover_wind_angle_deg)
	_material.set_shader_parameter(&"snow_wind_dir", Vector2(cos(wind), sin(wind)))
	_material.set_shader_parameter(&"snow_wind_stretch", tuning.cover_wind_stretch)
	_material.set_shader_parameter(&"snow_seam_bias", tuning.cover_seam_bias)
	_material.set_shader_parameter(&"snow_seam_width", tuning.cover_seam_width)
	_material.set_shader_parameter(&"snow_light_gain", tuning.cover_light_gain)
	_material.set_shader_parameter(&"snow_ambient_factor", tuning.cover_ambient_factor)
	_material.set_shader_parameter(&"snow_tone_mid_at", tuning.cover_tone_mid_at)
	_material.set_shader_parameter(&"snow_tone_lit_at", tuning.cover_tone_lit_at)
	_material.set_shader_parameter(&"snow_tone_width", tuning.cover_tone_width)
	_material.set_shader_parameter(&"snow_edge_soft", tuning.cover_edge_soft)
	_material.set_shader_parameter(&"snow_tone_mid", tuning.cover_tone_mid_color)
	_material.set_shader_parameter(&"snow_tone_shade", tuning.cover_tone_shade_color)
	_material.set_shader_parameter(&"snow_rim_start", tuning.cover_rim_start)
	_material.set_shader_parameter(&"snow_rim_bias", tuning.cover_rim_bias)
	_material.set_shader_parameter(&"snow_base_bias", tuning.cover_base_bias)
	_material.set_shader_parameter(&"snow_field_radius", field.map_definition().field_radius)
	_material.set_shader_parameter(&"snow_drift_span", float(_grid.res) * _grid.cell_size)
	_material.set_shader_parameter(&"snow_color", tuning.snow_color)
	_material.set_shader_parameter(&"snow_shade_tint", tuning.snow_shade_color)
	_material.set_shader_parameter(&"snow_offset", Vector2(
		SnowGeometry.unit_hash(seed_value, NOISE_SALT_X), SnowGeometry.unit_hash(seed_value, NOISE_SALT_Z)
	) * NOISE_OFFSET_RANGE)
	_apply_uniforms()


func _exit_tree() -> void:
	if _material != null:
		_material.set_shader_parameter(&"snow_strength", 0.0)


## Where the live blocks come from (drifts gather around their bases).
func set_blocks_source(source: Callable) -> void:
	_blocks_source = source


func set_level(level: int) -> void:
	if level != _level:
		_level = level
		_start_drift()
	_apply_uniforms()


func level() -> int:
	return _level


func material() -> ShaderMaterial:
	return _material


## 0..1 progress from the first level (frosting) to the top level (drifts).
func _level_t() -> float:
	if _tuning.depth_levels <= 1:
		return 1.0
	return float(clampi(_level, 1, _tuning.depth_levels) - 1) / float(_tuning.depth_levels - 1)


## Shader strength at the current level (0 = no snow drawn).
func strength() -> float:
	if _tuning == null or _level <= 0:
		return 0.0
	var wanted: float = lerpf(_tuning.cover_strength_light, _tuning.cover_strength_heavy, _level_t())
	return minf(wanted, max_opacity())


## Highest snow opacity: snow lightens the disc but at least cover_territory_min
## of the bare surface (territory colour, plate detail) always shows through.
func max_opacity() -> float:
	if _tuning == null:
		return 0.0
	return 1.0 - _tuning.cover_territory_min


## Even base depth of the cover at the current level (0..1); the shader adds
## gentle variation and the drift biases on top.
func amount() -> float:
	if _tuning == null:
		return 0.0
	return lerpf(_tuning.cover_amount_light, _tuning.cover_amount_heavy, _level_t())


func _apply_uniforms() -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"snow_strength", strength())
	_material.set_shader_parameter(&"snow_threshold", amount())


func _process(_delta: float) -> void:
	if _grid != null:
		_advance_drift(_tuning.cover_drift_blocks_per_frame)


## Starts rebuilding the block-base drift map from the live blocks.
func _start_drift() -> void:
	if _grid == null:
		return
	_drift_data = PackedByteArray()
	_drift_data.resize(_grid.res * _grid.res)
	_drift_queue = _blocks_source.call() if _blocks_source.is_valid() else []
	_drift_head = 0
	_drift_building = true


## Stamps up to `budget` blocks; uploads the texture when the list is done.
func _advance_drift(budget: int) -> void:
	if not _drift_building:
		return
	var side: int = _grid.res
	var reach: float = maxf(_tuning.cover_base_radius_cells, 0.5)
	var span: int = ceili(reach)
	var left: int = maxi(budget, 1)
	while left > 0 and _drift_head < _drift_queue.size():
		var entry: Variant = _drift_queue[_drift_head]
		_drift_head += 1
		left -= 1
		# Bontago-1pi.11.26: a block freed since the queue was captured (burned,
		# kill plane) must be rejected BEFORE the typed cast, which errors on a
		# freed object every frame it is hit.
		if not is_instance_valid(entry):
			continue
		var block: Node3D = entry as Node3D
		if block == null or not block.is_inside_tree():
			continue
		var center: Vector2i = _grid.world_to_cell(_field.disk_local_from_world(block.global_position))
		for dy: int in range(-span, span + 1):
			for dx: int in range(-span, span + 1):
				var cx: int = center.x + dx
				var cy: int = center.y + dy
				if not _grid.in_bounds(cx, cy):
					continue
				var falloff: float = 1.0 - sqrt(float(dx * dx + dy * dy)) / (reach + 1.0)
				if falloff <= 0.0:
					continue
				var index: int = cy * side + cx
				_drift_data[index] = maxi(_drift_data[index], int(falloff * 255.0))
	if _drift_head < _drift_queue.size():
		return
	_drift_building = false
	_drift_queue = []
	_drift_image = Image.create_from_data(side, side, false, Image.FORMAT_R8, _drift_data)
	if _drift_texture == null:
		_drift_texture = ImageTexture.create_from_image(_drift_image)
	else:
		_drift_texture.update(_drift_image)
	if _material != null:
		_material.set_shader_parameter(&"snow_drift_tex", _drift_texture)


## Test seam: finishes a pending drift rebuild at once.
func finish_drift() -> void:
	_advance_drift(_drift_queue.size() + 1)


func is_drift_building() -> bool:
	return _drift_building


## Drift bias (0..1) at a cell, for tests.
func drift_at(cell: int) -> float:
	if _drift_image == null:
		return 0.0
	var coords: Vector2i = _grid.cell_coords(cell)
	return _drift_image.get_pixel(coords.x, coords.y).r
