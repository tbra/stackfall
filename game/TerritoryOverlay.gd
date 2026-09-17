class_name TerritoryOverlay
extends MeshInstance3D
## The disk's visible surface and the territory picture painted on it
## (spec 2.10, 3.3).
##
## This node is both the disk mesh and the overlay, deliberately: spec 3.3 asks
## the shader to discard hole pixels, and a discard only reads as a hole in the
## ground if what it discards *is* the ground. A separate quad hovering over an
## intact disk would just reveal the disk underneath.
##
## **The upload.** TerritoryRaster is authoritative at *cell* resolution (see
## docs/M2_PLAN.md, "Raster resolution"): 90x90 on map M, which is also the
## collision grid and the hole granularity. Spec 3.3's territory_res texture is
## the *upload* size, so the cell image is upscaled with
## Image.resize(INTERPOLATE_BILINEAR) — one C++ call — and that is what the
## shader samples and smoothsteps. Rebuilt at TerritoryTuning.raster_upload_hz
## (5 Hz), never per frame.
##
## **Texture layout.** R = team_id + 1 (0 = unowned), G = the raw
## TerritoryRaster state bits, exactly as the M2 plan documents them.
##
## DECISION (game/TerritoryOverlay.gd): B and A carry the hole and contested
## flags again, one per channel. The plan's packed G channel is correct as a
## description of the raster, but bilinear interpolation of packed bits is
## ambiguous — halfway between STATE_CONTESTED (1) and nothing (0) is 0.5, and
## halfway between STATE_HOLE (2) and nothing is 1.0, so no single threshold on
## G can answer "is this a hole" near an edge. Splitting the two flags into
## their own 0/255 channels puts the 0.5 threshold exactly on the cell boundary
## for both. G is still written, so a test or a debug view can compare the
## upload against TerritoryRaster.state_bytes() byte for byte.

## Mirrors TerritoryRaster's bits so the overlay never has to import a rule.
const STATE_CONTESTED: int = TerritoryRaster.STATE_CONTESTED
const STATE_HOLE: int = TerritoryRaster.STATE_HOLE

const TERRITORY_SHADER: Shader = preload("res://shaders/territory.gdshader")
## Slot colors the shader's uniform array holds; MatchConfig ships eight.
const SLOT_COLOR_MAX: int = 8

var _map_def: MapDef = null
var _visuals: TerritoryVisuals = null
var _tuning: TerritoryTuning = null
var _material: ShaderMaterial = null
var _texture: ImageTexture = null
var _raster: TerritoryRaster = null
var _cells_per_side: int = 0
## Scratch, reused every upload so a 5 Hz rebuild allocates nothing.
var _pixels: PackedByteArray = PackedByteArray()
var _last_image: Image = null
var _upload_accumulator: float = 0.0


func _process(delta: float) -> void:
	if _raster == null or _tuning == null:
		return
	var interval: float = 1.0 / maxf(_tuning.raster_upload_hz, 0.001)
	_upload_accumulator += delta
	if _upload_accumulator < interval:
		return
	# Catch up without ever uploading twice in one frame.
	_upload_accumulator = fmod(_upload_accumulator, interval)
	upload_now()


## Builds the disk mesh and its material. Called by Field before the node
## enters the tree.
func configure(map_def: MapDef, visuals: TerritoryVisuals, tuning: TerritoryTuning) -> void:
	_map_def = map_def
	_visuals = visuals
	_tuning = tuning
	_cells_per_side = map_def.cells_per_side()

	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = map_def.field_radius
	cylinder.bottom_radius = map_def.field_radius
	cylinder.height = map_def.disk_height
	cylinder.radial_segments = visuals.disk_mesh_segments
	mesh = cylinder

	_material = ShaderMaterial.new()
	_material.shader = TERRITORY_SHADER
	_apply_visual_uniforms()
	_set_blank_texture()
	material_override = _material


func material() -> ShaderMaterial:
	return _material


func texture() -> ImageTexture:
	return _texture


## The exact Image of the last upload, upscaled. Kept because
## ImageTexture.get_image() has to round-trip through the rendering server,
## which a headless test has no renderer for.
func last_image() -> Image:
	return _last_image


## Cells along one edge of the image before the upscale.
func cells_per_side() -> int:
	return _cells_per_side


## Hands the overlay the live raster to draw and the per-slot colors to draw it
## in. The raster is read, never mutated.
func set_source(raster: TerritoryRaster, slot_colors: PackedColorArray) -> void:
	_raster = raster
	var raster_grid: CellGrid = raster.grid() if raster != null else null
	if raster_grid != null:
		_cells_per_side = raster_grid.res
	set_slot_colors(slot_colors)
	upload_now()


## MatchConfig.player_colors, indexed by team/slot id. Converted to linear
## because the shader's array uniform cannot carry a source_color hint.
func set_slot_colors(slot_colors: PackedColorArray) -> void:
	if _material == null:
		return
	var linear: PackedColorArray = PackedColorArray()
	for i: int in range(SLOT_COLOR_MAX):
		var color: Color = _visuals.goal_flag_color
		if i < slot_colors.size():
			color = slot_colors[i]
		linear.append(color.srgb_to_linear())
	_material.set_shader_parameter(&"slot_colors", linear)


## Rebuilds the ImageTexture from the raster this overlay was given.
func upload_now() -> void:
	if _raster == null:
		return
	push_cells(_raster.owner_bytes(), _raster.state_bytes(), _cells_per_side)


## The low-level entry: one byte of owner and one of state per cell, row-major,
## `cells_per_side` to a row. Field's raster path goes through upload_now();
## tests and the M2 preview scene push bytes straight in.
func push_cells(
	owner_bytes: PackedByteArray, state_bytes: PackedByteArray, side: int
) -> void:
	if _material == null or side <= 0:
		return
	var cell_total: int = side * side
	var byte_total: int = cell_total * 4
	if _pixels.size() != byte_total:
		_pixels.resize(byte_total)
	var owner_count: int = owner_bytes.size()
	var state_count: int = state_bytes.size()
	for i: int in range(cell_total):
		var owner_byte: int = owner_bytes[i] if i < owner_count else 0
		var state_byte: int = state_bytes[i] if i < state_count else 0
		var base: int = i * 4
		_pixels[base] = owner_byte
		_pixels[base + 1] = state_byte
		_pixels[base + 2] = 255 if (state_byte & STATE_HOLE) != 0 else 0
		_pixels[base + 3] = 255 if (state_byte & STATE_CONTESTED) != 0 else 0

	var image: Image = Image.create_from_data(
		side, side, false, Image.FORMAT_RGBA8, _pixels
	)
	var upload_res: int = maxi(_map_def.territory_res, side)
	if upload_res != side:
		image.resize(upload_res, upload_res, Image.INTERPOLATE_BILINEAR)
	_set_image(image)
	_apply_uv_uniforms(side)


func _set_blank_texture() -> void:
	var side: int = maxi(_cells_per_side, 1)
	var image: Image = Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var upload_res: int = maxi(_map_def.territory_res, side)
	if upload_res != side:
		image.resize(upload_res, upload_res, Image.INTERPOLATE_BILINEAR)
	_set_image(image)
	_apply_uv_uniforms(side)


func _set_image(image: Image) -> void:
	_last_image = image
	if _texture == null:
		_texture = ImageTexture.create_from_image(image)
	elif (
		_texture.get_width() == image.get_width()
		and _texture.get_height() == image.get_height()
	):
		_texture.update(image)
	else:
		_texture.set_image(image)
	_material.set_shader_parameter(&"territory_tex", _texture)


## Disk-local (x, z) -> UV. CellGrid lays `side` cells of cell_size from
## -field_radius, so the square the texture covers spans side * cell_size and
## starts at -field_radius on both axes.
func _apply_uv_uniforms(side: int) -> void:
	var span: float = maxf(float(side) * _map_def.cell_size, 0.001)
	_material.set_shader_parameter(&"uv_scale", 1.0 / span)
	_material.set_shader_parameter(&"uv_offset", _map_def.field_radius / span)


func _apply_visual_uniforms() -> void:
	_material.set_shader_parameter(&"base_color", _visuals.disk_base_color)
	_material.set_shader_parameter(&"base_metallic", _visuals.disk_metallic)
	_material.set_shader_parameter(&"base_roughness", _visuals.disk_roughness)
	_material.set_shader_parameter(&"edge_softness", _visuals.edge_softness)
	_material.set_shader_parameter(&"tint_alpha", _visuals.tint_alpha)
	_material.set_shader_parameter(&"outline_width", _visuals.outline_width)
	_material.set_shader_parameter(&"outline_speed", _visuals.outline_speed)
	_material.set_shader_parameter(&"outline_strength", _visuals.outline_strength)
	_material.set_shader_parameter(&"outline_pulse_depth", _visuals.outline_pulse_depth)
	_material.set_shader_parameter(&"contested_color", _visuals.contested_color)
	_material.set_shader_parameter(
		&"contested_shimmer_rate", _visuals.contested_shimmer_rate
	)
	_material.set_shader_parameter(
		&"contested_shimmer_scale", _visuals.contested_shimmer_scale
	)
	_material.set_shader_parameter(
		&"contested_shimmer_strength", _visuals.contested_shimmer_strength
	)
	_material.set_shader_parameter(&"hole_rim_color", _visuals.hole_rim_color)
	_material.set_shader_parameter(&"hole_rim_width", _visuals.hole_rim_width)
	_material.set_shader_parameter(&"hole_rim_glow", _visuals.hole_rim_glow)
	set_slot_colors(PackedColorArray())
