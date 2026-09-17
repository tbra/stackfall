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
## **Texture layout.** Three single-channel R8 textures rather than one packed
## RGBA one, which costs nothing to build: TerritoryRaster.owner_bytes() and
## state_bytes() are already exactly the buffers Image.create_from_data() wants,
## so the upload does no per-cell work in GDScript at all.
##
##   territory_tex    territory_res, filter_linear  -- the owner ramp spec 3.3
##                                                     asks for, bilinearly
##                                                     upscaled; the soft edge
##                                                     and the outline read it.
##   territory_cells  cell res, filter_nearest      -- owner_bytes() unblended:
##                                                     R = team_id + 1, 0 =
##                                                     unowned. *Which* team
##                                                     owns a pixel must come
##                                                     from here, because the
##                                                     upscale invents ids
##                                                     between two teams --
##                                                     halfway between team 0
##                                                     (1) and team 2 (3) is
##                                                     team 1, which rings
##                                                     every border in a third
##                                                     player's color.
##   territory_state  cell res, both filters        -- state_bytes() verbatim,
##                                                     STATE_CONTESTED |
##                                                     STATE_HOLE. The crisp
##                                                     sampler answers "is this
##                                                     a hole", so the gap
##                                                     matches the cell whose
##                                                     collision Field switched
##                                                     off; the filtered one
##                                                     gives the rim its glow.
##
## DECISION (game/TerritoryOverlay.gd): the M2 plan describes one texture with
## R = owner and G = the state bits. Splitting them into their own textures
## keeps exactly those two channels and those two meanings, and was taken for
## cost: interleaving 14400 cells into RGBA in GDScript and upscaling four
## channels measured 11 ms per upload on map L, which is a dropped frame five
## times a second. One R8 upscale is 2 ms and the interleave disappears.

## Mirrors TerritoryRaster's bits so the overlay never has to import a rule.
const STATE_CONTESTED: int = TerritoryRaster.STATE_CONTESTED
const STATE_HOLE: int = TerritoryRaster.STATE_HOLE

const TERRITORY_SHADER: Shader = preload("res://shaders/territory.gdshader")
## Slot colors the shader's uniform array holds; MatchConfig ships eight.
const SLOT_COLOR_MAX: int = 8
## The disk centre sits at the middle of the raster square, so disk-local
## (0, 0) maps to the middle of the texture. See _apply_uv_uniforms().
const UV_CENTER: float = 0.5

var _map_def: MapDef = null
var _visuals: TerritoryVisuals = null
var _tuning: TerritoryTuning = null
var _material: ShaderMaterial = null
var _texture: ImageTexture = null
var _cell_texture: ImageTexture = null
var _state_texture: ImageTexture = null
var _raster: TerritoryRaster = null
var _cells_per_side: int = 0
var _last_image: Image = null
var _owner_cell_image: Image = null
var _state_cell_image: Image = null
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


## The cell-resolution texture the shader reads team ids from, unblended.
func cell_texture() -> ImageTexture:
	return _cell_texture


## The cell-resolution texture carrying TerritoryRaster.state_bytes() verbatim.
func state_texture() -> ImageTexture:
	return _state_texture


## The exact cell images of the last upload, for the same reason last_image()
## exists: a headless test has no rendering server to read a texture back from.
func owner_cell_image() -> Image:
	return _owner_cell_image


func state_cell_image() -> Image:
	return _state_cell_image


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
## `side` to a row -- the two arrays TerritoryRaster hands out. Field's raster
## path goes through upload_now(); tests push bytes straight in.
func push_cells(
	owner_bytes: PackedByteArray, state_bytes: PackedByteArray, side: int
) -> void:
	if _material == null or side <= 0:
		return
	var cell_total: int = side * side
	var owner_image: Image = Image.create_from_data(
		side, side, false, Image.FORMAT_R8, _sized(owner_bytes, cell_total)
	)
	var state_image: Image = Image.create_from_data(
		side, side, false, Image.FORMAT_R8, _sized(state_bytes, cell_total)
	)
	_owner_cell_image = owner_image
	_state_cell_image = state_image
	_cell_texture = _store(_cell_texture, owner_image)
	_state_texture = _store(_state_texture, state_image)
	_material.set_shader_parameter(&"territory_cells", _cell_texture)
	_material.set_shader_parameter(&"territory_state", _state_texture)
	_material.set_shader_parameter(&"territory_state_soft", _state_texture)
	_set_image(_upscaled(owner_image, side))
	_apply_uv_uniforms(side)


## A raster reports empty byte arrays before its first solve, and a stand-in
## may report a short one; Image.create_from_data() wants exactly cell_total
## bytes. The common case returns the caller's own array untouched.
func _sized(bytes: PackedByteArray, cell_total: int) -> PackedByteArray:
	if bytes.size() == cell_total:
		return bytes
	var padded: PackedByteArray = bytes.duplicate()
	padded.resize(cell_total)
	return padded


## The owner cell image blown up to MapDef.territory_res. Image.resize mutates
## in place, so it is duplicated first — the shader needs both sizes.
func _upscaled(cell_image: Image, side: int) -> Image:
	var upload_res: int = maxi(_map_def.territory_res, side)
	if upload_res == side:
		return cell_image
	var image: Image = cell_image.duplicate() as Image
	image.resize(upload_res, upload_res, Image.INTERPOLATE_BILINEAR)
	return image


func _set_blank_texture() -> void:
	var side: int = maxi(_cells_per_side, 1)
	push_cells(PackedByteArray(), PackedByteArray(), side)


func _set_image(image: Image) -> void:
	_last_image = image
	_texture = _store(_texture, image)
	_material.set_shader_parameter(&"territory_tex", _texture)


func _store(target: ImageTexture, image: Image) -> ImageTexture:
	if target == null:
		return ImageTexture.create_from_image(image)
	if (
		target.get_width() == image.get_width()
		and target.get_height() == image.get_height()
	):
		target.update(image)
	else:
		target.set_image(image)
	return target


## Disk-local (x, z) -> UV. CellGrid's square spans side * cell_size and is
## centred on the disk centre (CellGrid.half_extent), so the origin always
## lands in the middle of the texture — the offset is half a texture, never
## field_radius, which is smaller than the half extent once the grid rounds up
## to an odd number of cells.
func _apply_uv_uniforms(side: int) -> void:
	var span: float = maxf(float(side) * _map_def.cell_size, 0.001)
	_material.set_shader_parameter(&"uv_scale", 1.0 / span)
	_material.set_shader_parameter(&"uv_offset", UV_CENTER)


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
