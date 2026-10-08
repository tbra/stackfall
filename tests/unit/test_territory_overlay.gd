extends GutTest
## TerritoryOverlay turns the cell raster into the ImageTexture the disk shader
## samples (spec 2.10, 3.3, docs/archive/M2_PLAN.md "Raster resolution").
##
## The raster itself is P1's; these tests drive the overlay through a stand-in
## that answers owner_bytes()/state_bytes() with hand-built cells, so they pin
## the upload path and not the solver.

## CellGrid rounds its resolution up to an odd number (see the DECISION there),
## so a test map's cells per side is odd too.
const CELLS_PER_SIDE: int = 13
## An odd upscale factor (5) so that one dest pixel lands exactly on each cell
## center, which lets a test read a cell's bytes back unblended.
const UPSCALE: int = 5
const UPLOAD_RES: int = CELLS_PER_SIDE * UPSCALE


## A TerritoryRaster whose bytes are whatever the test says they are.
class ScriptedRaster extends TerritoryRaster:
	var owners: PackedByteArray = PackedByteArray()
	var states: PackedByteArray = PackedByteArray()

	func _init(grid: CellGrid, tuning: TerritoryTuning) -> void:
		super(grid, tuning)
		var count: int = grid.cell_count()
		owners.resize(count)
		states.resize(count)

	func set_cell(index: int, owner_byte: int, state_byte: int) -> void:
		owners[index] = owner_byte
		states[index] = state_byte
		_mark_changed()

	func owner_bytes() -> PackedByteArray:
		return owners

	func state_bytes() -> PackedByteArray:
		return states


func _map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_overlay"
	map_def.field_radius = float(CELLS_PER_SIDE) * 0.5
	map_def.cell_size = 1.0
	map_def.territory_res = UPLOAD_RES
	return map_def


func _make_overlay(map_def: MapDef) -> TerritoryOverlay:
	var overlay: TerritoryOverlay = TerritoryOverlay.new()
	overlay.configure(map_def, load("res://config/territory_visuals.tres"), load("res://config/territory_tuning.tres"))
	add_child_autofree(overlay)
	return overlay


func _make_raster(map_def: MapDef) -> ScriptedRaster:
	var grid: CellGrid = CellGrid.new(map_def.field_radius, map_def.cell_size)
	return ScriptedRaster.new(grid, load("res://config/territory_tuning.tres"))


## The upscaled pixel sitting exactly on cell (cx, cy)'s center.
func _sample(image: Image, cx: int, cy: int) -> Color:
	var middle: int = floori(float(UPSCALE - 1) * 0.5)
	return image.get_pixel(cx * UPSCALE + middle, cy * UPSCALE + middle)


func test_upload_is_territory_res_square() -> void:
	var map_def: MapDef = _map()
	var overlay: TerritoryOverlay = _make_overlay(map_def)
	var raster: ScriptedRaster = _make_raster(map_def)
	overlay.set_source(raster, PackedColorArray())

	var image: Image = overlay.last_image()
	assert_not_null(image, "set_source uploads immediately.")
	assert_eq(image.get_width(), UPLOAD_RES, "Spec 3.3: uploaded at territory_res.")
	assert_eq(image.get_height(), UPLOAD_RES)
	assert_eq(overlay.texture().get_width(), UPLOAD_RES)
	assert_eq(overlay.cells_per_side(), CELLS_PER_SIDE, "The rules stay at cell resolution.")


func test_owner_bytes_survive_the_upscale() -> void:
	var map_def: MapDef = _map()
	var overlay: TerritoryOverlay = _make_overlay(map_def)
	var raster: ScriptedRaster = _make_raster(map_def)
	var grid: CellGrid = raster.grid()

	# Two overlapping-ish blocks of territory: team 0 on the left half, team 2
	# on the right, so the R channel carries 1 and 3.
	for cy: int in range(grid.res):
		for cx: int in range(grid.res):
			var owner_byte: int = 1 if cx < floori(float(grid.res) * 0.5) else 3
			raster.set_cell(grid.cell_index(cx, cy), owner_byte, 0)
	overlay.set_source(raster, PackedColorArray())

	var image: Image = overlay.last_image()
	var left: Color = _sample(image, 2, 6)
	var right: Color = _sample(image, 9, 6)
	assert_eq(left.r8, 1, "Team 0's cells read back as R = team_id + 1.")
	assert_eq(right.r8, 3, "Team 2's cells read back as R = team_id + 1.")


func test_state_bytes_go_up_verbatim() -> void:
	var map_def: MapDef = _map()
	var overlay: TerritoryOverlay = _make_overlay(map_def)
	var raster: ScriptedRaster = _make_raster(map_def)
	var grid: CellGrid = raster.grid()

	raster.set_cell(grid.cell_index(3, 3), 0, TerritoryRaster.STATE_CONTESTED)
	raster.set_cell(grid.cell_index(8, 8), 0, TerritoryRaster.STATE_HOLE)
	raster.set_cell(
		grid.cell_index(9, 9),
		0,
		TerritoryRaster.STATE_CONTESTED | TerritoryRaster.STATE_HOLE
	)
	overlay.set_source(raster, PackedColorArray())

	# The state grid goes up unblended at cell resolution: the shader's hole
	# discard has to land on exactly the cell whose collision Field switched
	# off, and an interpolated bit field cannot answer that.
	var states: Image = overlay.state_cell_image()
	assert_eq(states.get_width(), CELLS_PER_SIDE)
	assert_eq(states.get_pixel(3, 3).r8, TerritoryRaster.STATE_CONTESTED)
	assert_eq(states.get_pixel(8, 8).r8, TerritoryRaster.STATE_HOLE)
	assert_eq(
		states.get_pixel(9, 9).r8,
		TerritoryRaster.STATE_CONTESTED | TerritoryRaster.STATE_HOLE
	)
	assert_eq(states.get_pixel(0, 0).r8, 0, "An untouched cell carries no state.")


func test_owner_ids_also_go_up_unblended_at_cell_resolution() -> void:
	var map_def: MapDef = _map()
	var overlay: TerritoryOverlay = _make_overlay(map_def)
	var raster: ScriptedRaster = _make_raster(map_def)
	var grid: CellGrid = raster.grid()
	raster.set_cell(grid.cell_index(4, 4), 1, 0)
	raster.set_cell(grid.cell_index(5, 4), 3, 0)
	overlay.set_source(raster, PackedColorArray())

	# The shader reads team ids off this second texture, because the bilinear
	# upscale invents ids between two teams: halfway between 1 and 3 is 2,
	# which would ring the border in a third player's color.
	var cells: ImageTexture = overlay.cell_texture()
	assert_not_null(cells, "The overlay uploads the raw cell grid as well.")
	assert_eq(cells.get_width(), CELLS_PER_SIDE, "Unblended, at cell resolution.")
	assert_eq(cells.get_height(), CELLS_PER_SIDE)
	assert_not_null(overlay.state_texture(), "And the state grid beside it.")
	assert_eq(overlay.owner_cell_image().get_pixel(4, 4).r8, 1)
	assert_eq(overlay.owner_cell_image().get_pixel(5, 4).r8, 3)
	assert_eq(
		overlay.texture().get_width(),
		UPLOAD_RES,
		"The filtered texture is still the territory_res upload."
	)


func test_empty_raster_bytes_upload_as_unowned() -> void:
	var map_def: MapDef = _map()
	var overlay: TerritoryOverlay = _make_overlay(map_def)
	# owner_bytes()/state_bytes() empty is what a raster reports before its
	# first solve; it must upload a blank disk, not crash.
	var raster: ScriptedRaster = _make_raster(map_def)
	raster.owners = PackedByteArray()
	raster.states = PackedByteArray()
	overlay.set_source(raster, PackedColorArray())

	var image: Image = overlay.last_image()
	assert_eq(image.get_width(), UPLOAD_RES)
	assert_eq(_sample(image, 5, 5).r8, 0, "Nothing is owned yet.")


func test_slot_colors_reach_the_shader() -> void:
	var map_def: MapDef = _map()
	var overlay: TerritoryOverlay = _make_overlay(map_def)
	var colors: PackedColorArray = PackedColorArray([
		Color(0.9, 0.25, 0.25), Color(0.25, 0.55, 0.95),
	])
	overlay.set_slot_colors(colors)

	var uniform: Variant = overlay.material().get_shader_parameter(&"slot_colors")
	assert_not_null(uniform, "The shader's slot_colors array is set, not left default.")
	var stored: Array = uniform as Array
	assert_eq(stored.size(), TerritoryOverlay.SLOT_COLOR_MAX, "All eight slots are filled.")
	var first: Color = stored[0]
	assert_almost_eq(
		first.r, colors[0].srgb_to_linear().r, 0.01,
		"Colors are converted to linear, because an array uniform cannot carry source_color."
	)


func test_refresh_visual_uniforms_keeps_slot_colors() -> void:
	# Bontago-sen.4: an F4 visuals refresh used to reset every slot to the
	# goal-flag color, so territories lost their team colors.
	var overlay: TerritoryOverlay = _make_overlay(_map())
	var colors: PackedColorArray = PackedColorArray([
		Color(0.9, 0.25, 0.25), Color(0.25, 0.55, 0.95),
	])
	overlay.set_slot_colors(colors)
	overlay.refresh_visual_uniforms()
	var stored: Array = overlay.material().get_shader_parameter(&"slot_colors") as Array
	var second: Color = stored[1]
	assert_almost_eq(second.b, colors[1].srgb_to_linear().b, 0.01, "Slot 1 keeps its team color.")


func test_uv_uniforms_map_the_disk_onto_the_texture() -> void:
	var map_def: MapDef = _map()
	var overlay: TerritoryOverlay = _make_overlay(map_def)
	var raster: ScriptedRaster = _make_raster(map_def)
	overlay.set_source(raster, PackedColorArray())

	var uv_scale: float = float(overlay.material().get_shader_parameter(&"uv_scale"))
	var uv_offset: float = float(overlay.material().get_shader_parameter(&"uv_offset"))
	# CellGrid's square is centred on the disk centre and is half_extent wide
	# either way, so -half_extent maps to UV 0, the centre to 0.5 and
	# +half_extent to UV 1.
	var half_extent: float = raster.grid().half_extent
	assert_almost_eq(-half_extent * uv_scale + uv_offset, 0.0, 0.0001)
	assert_almost_eq(uv_offset, 0.5, 0.0001)
	assert_almost_eq(half_extent * uv_scale + uv_offset, 1.0, 0.0001)


# --- Bontago-cmc.5: the analytic circle list -------------------------------


func _make_overlay_with_visuals(map_def: MapDef, visuals: TerritoryVisuals) -> TerritoryOverlay:
	var overlay: TerritoryOverlay = TerritoryOverlay.new()
	overlay.configure(map_def, visuals, load("res://config/territory_tuning.tres"))
	add_child_autofree(overlay)
	return overlay


func test_set_circles_uploads_one_texel_per_circle() -> void:
	var overlay: TerritoryOverlay = _make_overlay(_map())
	var xs: PackedFloat32Array = PackedFloat32Array([1.0, -2.0, 3.0])
	var zs: PackedFloat32Array = PackedFloat32Array([0.5, 1.5, -1.5])
	var radii: PackedFloat32Array = PackedFloat32Array([2.0, 3.0, 4.0])
	var teams: PackedInt32Array = PackedInt32Array([0, 1, 0])

	overlay.set_circles(
		xs, zs, radii, teams, PackedVector2Array(), PackedFloat32Array(), false
	)

	assert_eq(overlay.circle_count(), 3, "The shader's circle_count uniform.")
	assert_eq(overlay.circle_texture().get_width(), 3, "One texel per circle, RGBAF.")
	var texel: Color = overlay.circle_image().get_pixel(1, 0)
	assert_almost_eq(texel.r, xs[1], 0.001, "R = disk-local x")
	assert_almost_eq(texel.g, zs[1], 0.001, "G = disk-local z")
	assert_almost_eq(texel.b, radii[1], 0.001, "B = radius")
	assert_almost_eq(texel.a, float(teams[1]), 0.001, "A = team id")
	assert_true(
		bool(overlay.material().get_shader_parameter(&"circles_valid")),
		"Within max_shader_circles, the analytic path is used."
	)


func test_set_circles_uploads_goal_discs_independently() -> void:
	var overlay: TerritoryOverlay = _make_overlay(_map())
	var goal_positions: PackedVector2Array = PackedVector2Array([Vector2(4.0, -4.0)])
	var goal_radii: PackedFloat32Array = PackedFloat32Array([4.0])

	overlay.set_circles(
		PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), PackedInt32Array(),
		goal_positions, goal_radii, false
	)

	assert_eq(overlay.goal_count(), 1)
	assert_eq(overlay.goal_texture().get_width(), 1)
	var texel: Color = overlay.goal_image().get_pixel(0, 0)
	assert_almost_eq(texel.r, 4.0, 0.001)
	assert_almost_eq(texel.g, -4.0, 0.001)
	assert_almost_eq(texel.b, 4.0, 0.001)


func test_a_circle_list_over_the_shader_budget_falls_back_to_the_raster_path() -> void:
	var visuals: TerritoryVisuals = load("res://config/territory_visuals.tres").duplicate() as TerritoryVisuals
	visuals.max_shader_circles = 2
	var overlay: TerritoryOverlay = _make_overlay_with_visuals(_map(), visuals)

	var xs: PackedFloat32Array = PackedFloat32Array([0.0, 1.0, 2.0])
	var zs: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])
	var radii: PackedFloat32Array = PackedFloat32Array([1.0, 1.0, 1.0])
	var teams: PackedInt32Array = PackedInt32Array([0, 0, 0])
	overlay.set_circles(xs, zs, radii, teams, PackedVector2Array(), PackedFloat32Array(), false)

	assert_eq(overlay.circle_count(), 3, "The full list still uploads, for readback.")
	assert_false(
		bool(overlay.material().get_shader_parameter(&"circles_valid")),
		"Over max_shader_circles: the shader must fall back to the raster path, spec 3.3 'Bounded cost'."
	)


func test_set_source_null_clears_the_circle_list() -> void:
	var map_def: MapDef = _map()
	var overlay: TerritoryOverlay = _make_overlay(map_def)
	overlay.set_circles(
		PackedFloat32Array([1.0]), PackedFloat32Array([1.0]), PackedFloat32Array([1.0]),
		PackedInt32Array([0]), PackedVector2Array(), PackedFloat32Array(), false
	)
	assert_eq(overlay.circle_count(), 1)

	overlay.set_source(null, PackedColorArray())

	assert_eq(overlay.circle_count(), 0, "set_source(null) must not leave a stale match's circles up.")
	assert_eq(overlay.goal_count(), 0)
	assert_false(bool(overlay.material().get_shader_parameter(&"circles_valid")))


func test_configure_starts_with_no_circles() -> void:
	var overlay: TerritoryOverlay = _make_overlay(_map())
	assert_eq(overlay.circle_count(), 0, "Before any solve, the blank disk has no circles either.")
	assert_false(bool(overlay.material().get_shader_parameter(&"circles_valid")))


func test_field_hands_its_overlay_the_source() -> void:
	var field: Field = Field.new()
	field.map_def = _map()
	add_child_autofree(field)

	var raster: ScriptedRaster = _make_raster(field.map_def)
	var grid: CellGrid = raster.grid()
	raster.set_cell(grid.cell_index(6, 6), 2, 0)
	field.set_overlay_source(raster, PackedColorArray([Color.RED, Color.BLUE]))

	var image: Image = field.overlay().last_image()
	assert_not_null(image, "Field.set_overlay_source uploads through the overlay.")
	assert_eq(_sample(image, 6, 6).r8, 2)


func test_field_hands_its_overlay_the_circle_list() -> void:
	var field: Field = Field.new()
	field.map_def = _map()
	add_child_autofree(field)

	field.set_overlay_circles(
		PackedFloat32Array([2.0]), PackedFloat32Array([3.0]), PackedFloat32Array([1.5]),
		PackedInt32Array([1]), PackedVector2Array(), PackedFloat32Array(), false
	)

	assert_eq(field.overlay().circle_count(), 1, "Field.set_overlay_circles routes to the overlay.")
	var texel: Color = field.overlay().circle_image().get_pixel(0, 0)
	assert_almost_eq(texel.a, 1.0, 0.001, "Team id survives the hand-off.")


# --- Bontago-mv0.20b: disk_mesh_segments live-apply --------------------------


func test_refresh_visual_uniforms_rebuilds_the_disk_mesh_when_segments_change() -> void:
	var visuals: TerritoryVisuals = load("res://config/territory_visuals.tres").duplicate() as TerritoryVisuals
	var overlay: TerritoryOverlay = _make_overlay_with_visuals(_map(), visuals)
	var original_cylinder: CylinderMesh = overlay.mesh as CylinderMesh
	assert_eq(original_cylinder.radial_segments, visuals.disk_mesh_segments, "fixture: configure() bakes the starting segment count.")

	visuals.disk_mesh_segments = original_cylinder.radial_segments + 8
	overlay.refresh_visual_uniforms()

	var rebuilt: CylinderMesh = overlay.mesh as CylinderMesh
	assert_eq(rebuilt.radial_segments, visuals.disk_mesh_segments, "the mesh must be rebuilt with the new segment count.")
	assert_eq(rebuilt.top_radius, original_cylinder.top_radius, "radius must be preserved across a rebuild.")


# --- Bontago-xtq.11: mirror-like opaque disk ---------------------------------
#
# Bontago-xtq.4's disk-opacity tunables and the shader uniforms they drove
# are gone (owner, 2026-09-23: "the disc is a mirror-like surface and not
# glass, so it should be reflective but not transparent"); see
# config/TerritoryVisuals.gd and shaders/territory.gdshader for the removal
# DECISIONs.


func test_configure_pushes_the_default_metallic_and_roughness() -> void:
	var visuals: TerritoryVisuals = load("res://config/territory_visuals.tres")
	var overlay: TerritoryOverlay = _make_overlay(_map())

	assert_almost_eq(
		float(overlay.material().get_shader_parameter(&"base_metallic")),
		visuals.disk_metallic, 0.0001,
	)
	assert_almost_eq(
		float(overlay.material().get_shader_parameter(&"base_roughness")),
		visuals.disk_roughness, 0.0001,
	)


## Bontago-pt.12 part 2 (owner: "the disc looks close to the mockup but it
## lacks the texture ... visible where it interacts with the sun"): the
## top-surface brushed/plank grain's own uniforms must reach the shader from
## TerritoryVisuals, the same way every other presentation number here does.
func test_configure_pushes_the_top_grain_uniforms() -> void:
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	visuals.top_grain_strength = 0.11
	visuals.top_grain_scale = 0.42
	visuals.top_grain_fine_scale = 8.5
	visuals.top_grain_roughness_strength = 0.23
	var overlay: TerritoryOverlay = TerritoryOverlay.new()
	overlay.configure(_map(), visuals, load("res://config/territory_tuning.tres"))
	add_child_autofree(overlay)

	assert_almost_eq(
		float(overlay.material().get_shader_parameter(&"top_grain_strength")), 0.11, 0.0001
	)
	assert_almost_eq(
		float(overlay.material().get_shader_parameter(&"top_grain_scale")), 0.42, 0.0001
	)
	assert_almost_eq(
		float(overlay.material().get_shader_parameter(&"top_grain_fine_scale")), 8.5, 0.0001
	)
	assert_almost_eq(
		float(overlay.material().get_shader_parameter(&"top_grain_roughness_strength")),
		0.23, 0.0001,
	)


## Bontago-adt.2: the swappable DiscSurfaceDef texture set reaches the shader,
## and a null set leaves the flat look (disc_textured false).
func test_disc_surface_pushes_texture_uniforms_and_null_disables_them() -> void:
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	var overlay: TerritoryOverlay = TerritoryOverlay.new()
	overlay.configure(_map(), visuals, load("res://config/territory_tuning.tres"))
	add_child_autofree(overlay)
	assert_false(bool(overlay.material().get_shader_parameter(&"disc_textured")))

	var surface: DiscSurfaceDef = (load("res://config/disc_surfaces/MetalPlates001.tres") as DiscSurfaceDef).duplicate() as DiscSurfaceDef
	surface.tile_size_m = 7.5
	visuals.disc_surface = surface
	overlay.refresh_visual_uniforms()
	assert_true(bool(overlay.material().get_shader_parameter(&"disc_textured")))
	assert_almost_eq(
		float(overlay.material().get_shader_parameter(&"disc_tile_size_m")), 7.5, 0.0001
	)
	assert_not_null(overlay.material().get_shader_parameter(&"disc_normal_tex"))



## Bontago-adt.2: the procedural cel plating is the shipped default, and a
## PROCEDURAL DiscSurfaceDef turns the texture path off and pushes its own
## tunables (including the packed rivet-pattern weights).
func test_procedural_disc_surface_is_default_and_pushes_its_uniforms() -> void:
	var shipped: TerritoryVisuals = load("res://config/territory_visuals.tres") as TerritoryVisuals
	assert_not_null(shipped.disc_surface)
	assert_eq(shipped.disc_surface.mode, DiscSurfaceDef.Mode.PROCEDURAL,
		"the procedural plating should be the default disc surface.")

	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	var surface: DiscSurfaceDef = (shipped.disc_surface as DiscSurfaceDef).duplicate() as DiscSurfaceDef
	surface.proc_plate_length_m = 3.25
	surface.proc_rivet_weight_rows = 0.9
	surface.proc_seam_fade_height_end_m = 55.0
	visuals.disc_surface = surface
	var overlay: TerritoryOverlay = TerritoryOverlay.new()
	overlay.configure(_map(), visuals, load("res://config/territory_tuning.tres"))
	add_child_autofree(overlay)
	var material: ShaderMaterial = overlay.material()
	assert_true(bool(material.get_shader_parameter(&"disc_procedural")))
	assert_false(bool(material.get_shader_parameter(&"disc_textured")),
		"procedural mode must not also draw the texture maps.")
	assert_almost_eq(float(material.get_shader_parameter(&"disc_proc_plate_length_m")), 3.25, 0.0001)
	assert_almost_eq(float(material.get_shader_parameter(&"disc_proc_seam_fade_height_end_m")), 55.0, 0.0001)
	var weights: Vector4 = material.get_shader_parameter(&"disc_proc_rivet_weights") as Vector4
	assert_almost_eq(weights.w, 0.9, 0.0001)

	# Switching back to a texture set disables the procedural path.
	visuals.disc_surface = load("res://config/disc_surfaces/MetalPlates001.tres") as DiscSurfaceDef
	overlay.refresh_visual_uniforms()
	assert_false(bool(material.get_shader_parameter(&"disc_procedural")))
	assert_true(bool(material.get_shader_parameter(&"disc_textured")))


## Every disc_proc_* uniform the overlay pushes must exist in the shader, so a
## renamed uniform cannot silently fall back to its shader default.
func test_procedural_disc_uniforms_all_exist_in_the_shader() -> void:
	var overlay: TerritoryOverlay = _make_overlay(_map())
	var code: String = overlay.material().shader.code
	var script_code: String = (load("res://game/TerritoryOverlay.gd") as GDScript).source_code
	var regex: RegEx = RegEx.create_from_string("&\"(disc_proc_[a-z_]+)\"")
	var found: int = 0
	for match_: RegExMatch in regex.search_all(script_code):
		found += 1
		var uniform_name: String = match_.get_string(1)
		assert_true(code.contains(" " + uniform_name + " ") or code.contains(" " + uniform_name + ";"),
			"shader is missing uniform %s" % uniform_name)
	assert_gt(found, 30, "fixture: expected the procedural uniform list in TerritoryOverlay.gd.")

## The grain is meant to be "nearly invisible in diffuse areas" and must
## never distort the territory fill/border colors -- pins that structurally
## by asserting the grain block in the shader source never writes ALBEDO or
## EMISSION (it may only touch NORMAL/ROUGHNESS), same style of source-level
## guard test_territory_shader_never_blends_or_writes_alpha() below already
## uses for the disk's opacity contract.
func test_shader_top_grain_block_never_writes_albedo_or_emission() -> void:
	var overlay: TerritoryOverlay = _make_overlay(_map())
	var shader: Shader = overlay.material().shader
	var code: String = shader.code

	var grain_start: int = code.find("float grain_h0")
	var mirror_start: int = code.find("the explicit warm-gold sheen")
	assert_true(grain_start >= 0 and mirror_start > grain_start,
		"fixture: could not locate the top-grain block in the shader source.")
	var grain_block: String = code.substr(grain_start, mirror_start - grain_start)

	assert_false(grain_block.contains("ALBEDO"),
		"the top-grain block must never write ALBEDO -- territory fill must be untouched.")
	assert_false(grain_block.contains("EMISSION"),
		"the top-grain block must never write EMISSION -- territory borders/shimmer must be untouched.")


func test_disk_defaults_to_a_glossy_polished_plate() -> void:
	# Owner 2026-10-07: the planar mirror pass is gone; the disc is a polished plate lit by
	# the Environment sky and the reflection probe. Asserted as classifications and as the
	# values the overlay actually pushes to its material, not as exact numbers.
	var visuals: TerritoryVisuals = load("res://config/territory_visuals.tres")
	var overlay: TerritoryOverlay = _make_overlay(_map())
	assert_lt(visuals.disk_roughness, 0.5, "polished, not a matte surface.")
	assert_almost_eq(float(overlay.material().get_shader_parameter(&"base_metallic")), visuals.disk_metallic, 0.0001)
	assert_almost_eq(float(overlay.material().get_shader_parameter(&"base_roughness")), visuals.disk_roughness, 0.0001)


func test_territory_shader_never_blends_or_writes_alpha() -> void:
	# Bontago-xtq.11: the earlier "glass" material queued the disk as
	# transparent (render_mode blend_mix + a written ALPHA) even once its
	# runtime alpha value was tuned to fully opaque. Writing ALPHA at all,
	# regardless of its value, keeps a Godot spatial shader in the transparent
	# draw queue, so "opaque" has to be a property of the shader source
	# itself -- assert directly on the compiled shader code.
	var overlay: TerritoryOverlay = _make_overlay(_map())
	var shader: Shader = overlay.material().shader
	# Strip `//` line comments first: this file's own DECISION comments discuss
	# "blend_mix" and "ALPHA" by name, which would otherwise false-positive a
	# naive substring search of the whole source.
	var code_lines: PackedStringArray = PackedStringArray()
	for line: String in shader.code.split("\n"):
		var stripped: String = line.strip_edges()
		if not stripped.begins_with("//"):
			code_lines.append(line.split("//")[0])
	var code: String = "\n".join(code_lines)

	assert_false(
		code.contains("blend_mix"),
		"The disk must not declare a transparent blend render_mode.",
	)
	# Matches ALPHA=, ALPHA =, ALPHA+=, ALPHA -= etc, not just the exact
	# "ALPHA =" substring, so a reintroduced accumulating ALPHA write still
	# fails this test.
	var alpha_write: RegEx = RegEx.new()
	alpha_write.compile("\\bALPHA\\s*[-+*/]?=")
	assert_null(
		alpha_write.search(code),
		"fragment() must never write ALPHA -- the disk is unconditionally opaque, not glass.",
	)


func test_refresh_visual_uniforms_does_not_reallocate_the_mesh_when_segments_are_unchanged() -> void:
	var visuals: TerritoryVisuals = load("res://config/territory_visuals.tres").duplicate() as TerritoryVisuals
	var overlay: TerritoryOverlay = _make_overlay_with_visuals(_map(), visuals)
	var before: Mesh = overlay.mesh

	# An unrelated field change, and a call with no change at all: neither
	# should allocate a new CylinderMesh instance.
	visuals.disk_metallic = visuals.disk_metallic + 0.1
	overlay.refresh_visual_uniforms()
	overlay.refresh_visual_uniforms()

	assert_eq(overlay.mesh, before, "the disk mesh instance must be reused when disk_mesh_segments has not changed.")


# --- Bontago-xtq.14: crisp ownership edge, separate from the rim glow --------
#
# Owner playtest 2026-09-23: "the edge of the area is a bit blurry, sharpen
# it." shaders/territory.gdshader's analytic circle_path() used to feather
# the ownership TINT over rim_soft_width (0.25 m, the rim glow's own width) --
# edge_softness_m below is now a separate, much smaller default so the
# boundary itself reads as crisp while the glow keeps its existing rim_*
# tunables untouched (docs/original_hover-preview.png: "hard-edged shadows/
# edges").

func test_edge_softness_m_default_is_crisp_relative_to_the_rim_glow() -> void:
	# spec 2.10 / Bontago-xtq.14: a crisp ownership edge, much narrower than the rim glow it
	# used to share a feather width with (rim_soft_width).
	var visuals: TerritoryVisuals = load("res://config/territory_visuals.tres")
	assert_gte(visuals.edge_softness_m, 0.0)
	assert_lt(visuals.edge_softness_m, visuals.rim_soft_width, "the ownership edge is sharper than the glow's feather")


func test_configure_pushes_edge_softness_m() -> void:
	var visuals: TerritoryVisuals = load("res://config/territory_visuals.tres")
	var overlay: TerritoryOverlay = _make_overlay(_map())

	assert_almost_eq(
		float(overlay.material().get_shader_parameter(&"edge_softness_m")),
		visuals.edge_softness_m, 0.0001,
	)


func test_refresh_visual_uniforms_pushes_a_changed_edge_softness_m() -> void:
	var visuals: TerritoryVisuals = load("res://config/territory_visuals.tres").duplicate() as TerritoryVisuals
	var overlay: TerritoryOverlay = _make_overlay_with_visuals(_map(), visuals)

	visuals.edge_softness_m = 0.21
	overlay.refresh_visual_uniforms()

	assert_almost_eq(
		float(overlay.material().get_shader_parameter(&"edge_softness_m")), 0.21, 0.0001,
	)


func test_shader_declares_a_separate_edge_softness_m_uniform_from_rim_soft_width() -> void:
	var overlay: TerritoryOverlay = _make_overlay(_map())
	var code: String = _shader_source_without_comments(overlay.material().shader)

	assert_true(
		code.contains("uniform float edge_softness_m"),
		"the ownership tint's own edge width must be a distinct uniform.",
	)
	# The two must not have silently become the same uniform again: circle_path()
	# feathers the tint's own coverage over edge_softness_m specifically, not
	# rim_soft_width (the rim glow's width, still declared and used separately).
	var coverage_smoothstep: RegEx = RegEx.new()
	coverage_smoothstep.compile("smoothstep\\(\\s*-edge_half_width\\s*,\\s*edge_half_width")
	assert_not_null(
		coverage_smoothstep.search(code),
		"the tint coverage smoothstep must feather over edge_softness_m (via edge_half_width), not rim_soft_width.",
	)


## Strips `//` line comments the same way test_territory_shader_never_blends_
## or_writes_alpha() above already does, factored out so this section's own
## source-text assertion can reuse it without a false-positive match against
## this file's own doc comments (which discuss the uniform names by name).
func _shader_source_without_comments(shader: Shader) -> String:
	var code_lines: PackedStringArray = PackedStringArray()
	for line: String in shader.code.split("\n"):
		var stripped: String = line.strip_edges()
		if not stripped.begins_with("//"):
			code_lines.append(line.split("//")[0])
	return "\n".join(code_lines)


# --- Owner 2026-10-07: the disc mirror pass is removed -----------------------


func test_shader_and_overlay_have_no_planar_mirror_hooks() -> void:
	var overlay: TerritoryOverlay = _make_overlay(_map())
	var code: String = overlay.material().shader.code
	assert_false(code.contains("uniform sampler2D mirror_tex"), "no mirror sampler uniform.")
	assert_false(code.contains("mirror_enabled"), "no mirror toggle uniform.")
	assert_false(overlay.has_method("set_mirror_texture"), "no mirror texture door.")
	assert_eq(overlay.layers, TerritoryOverlay.DISC_LAYER_BIT, "the disc keeps its own render layer.")


# --- Bontago-1pi.11: spatial circle bins -------------------------------------

## Reads bin k's (start, count) header and its circle indices back out of the
## flat RGF image, the same row-major walk the shader does.
func _bin_indices(image: Image, k: int) -> PackedInt32Array:
	var width: int = TerritoryOverlay.CIRCLE_BIN_TEX_WIDTH
	var header: Color = image.get_pixel(k % width, k / width)
	var start: int = int(round(header.r))
	var count: int = int(round(header.g))
	var out: PackedInt32Array = PackedInt32Array()
	for j: int in range(count):
		var ref_k: int = start + j
		out.append(int(round(image.get_pixel(ref_k % width, ref_k / width).r)))
	return out


func test_circle_bins_list_every_circle_that_can_reach_a_pixel() -> void:
	var map_def: MapDef = _map()
	var overlay: TerritoryOverlay = _make_overlay(map_def)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1611
	var xs: PackedFloat32Array = PackedFloat32Array()
	var zs: PackedFloat32Array = PackedFloat32Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	var teams: PackedInt32Array = PackedInt32Array()
	var circle_total: int = 120
	var r: float = map_def.field_radius
	for i: int in range(circle_total):
		xs.append(rng.randf_range(-r, r))
		zs.append(rng.randf_range(-r, r))
		radii.append(rng.randf_range(0.2, 2.5))
		teams.append(i % 4)

	overlay.set_circles(xs, zs, radii, teams, PackedVector2Array(), PackedFloat32Array(), false)

	assert_true(overlay.circle_bins_valid(), "A normal circle list is binned.")
	assert_true(
		bool(overlay.material().get_shader_parameter(&"circle_bins_valid")),
		"The shader is told to use the bins."
	)
	var image: Image = overlay.circle_bin_image()
	var grid: int = TerritoryOverlay.CIRCLE_BIN_GRID
	var half: float = overlay.circle_bin_half_extent()
	var margin: float = overlay.circle_bin_margin()
	var cell: float = 2.0 * half / float(grid)
	var misses: int = 0
	var unordered: int = 0
	var samples: int = 97
	for sz: int in range(samples):
		for sx: int in range(samples):
			var point: Vector2 = Vector2(
				-r + 2.0 * r * float(sx) / float(samples - 1),
				-r + 2.0 * r * float(sz) / float(samples - 1)
			)
			var col: int = int(floor((point.x + half) / cell))
			var row: int = int(floor((point.y + half) / cell))
			var listed: PackedInt32Array = _bin_indices(image, row * grid + col)
			for j: int in range(1, listed.size()):
				if listed[j] <= listed[j - 1]:
					unordered += 1
			for i: int in range(circle_total):
				var value: float = radii[i] - point.distance_to(Vector2(xs[i], zs[i]))
				if value >= -margin and not listed.has(i):
					misses += 1
	assert_eq(misses, 0, "Every circle within radius + margin of a sample point is in that point's bin.")
	assert_eq(unordered, 0, "Bin lists keep circle_tex's ascending (team-sorted) order.")


func test_an_empty_circle_list_disables_the_bins() -> void:
	var overlay: TerritoryOverlay = _make_overlay(_map())
	overlay.clear_circles()
	assert_false(overlay.circle_bins_valid(), "No circles, nothing to bin.")
	assert_false(bool(overlay.material().get_shader_parameter(&"circle_bins_valid")))


func test_refresh_visual_uniforms_disables_bins_when_any_margin_component_grows() -> void:
	var visuals: TerritoryVisuals = load("res://config/territory_visuals.tres").duplicate() as TerritoryVisuals
	var overlay: TerritoryOverlay = _make_overlay_with_visuals(_map(), visuals)
	var xs: PackedFloat32Array = PackedFloat32Array([0.0])
	var radii: PackedFloat32Array = PackedFloat32Array([1.0])
	var teams: PackedInt32Array = PackedInt32Array([0])
	for property: StringName in [&"edge_softness_m", &"rim_width", &"rim_soft_width", &"metaball_blend"]:
		overlay.set_circles(xs, xs, radii, teams, PackedVector2Array(), PackedFloat32Array(), false)
		assert_true(overlay.circle_bins_valid())
		visuals.set(property, float(visuals.get(property)) + 1.0)
		overlay.refresh_visual_uniforms()
		assert_false(overlay.circle_bins_valid(), "%s growth needs the full circle loop." % property)
		assert_false(bool(overlay.material().get_shader_parameter(&"circle_bins_valid")))
		assert_true(bool(overlay.material().get_shader_parameter(&"circles_valid")), "Analytic circles stay active.")
		overlay.set_circles(xs, xs, radii, teams, PackedVector2Array(), PackedFloat32Array(), false)
		assert_true(overlay.circle_bins_valid(), "The next circle upload restores bins with the wider margin.")
		assert_true(bool(overlay.material().get_shader_parameter(&"circle_bins_valid")))


func test_refresh_visual_uniforms_keeps_bins_when_margin_shrinks() -> void:
	var visuals: TerritoryVisuals = load("res://config/territory_visuals.tres").duplicate() as TerritoryVisuals
	visuals.edge_softness_m = 1.0
	var overlay: TerritoryOverlay = _make_overlay_with_visuals(_map(), visuals)
	overlay.set_circles(
		PackedFloat32Array([0.0]), PackedFloat32Array([0.0]), PackedFloat32Array([1.0]),
		PackedInt32Array([0]), PackedVector2Array(), PackedFloat32Array(), false
	)
	var image: Image = overlay.circle_bin_image()
	visuals.edge_softness_m = 0.01
	overlay.refresh_visual_uniforms()
	assert_true(overlay.circle_bins_valid(), "Existing bins conservatively cover a smaller margin.")
	assert_true(bool(overlay.material().get_shader_parameter(&"circle_bins_valid")))
	assert_same(overlay.circle_bin_image(), image, "No unnecessary bin rebuild.")


func test_circle_bin_overflow_keeps_analytic_full_loop_and_recovers() -> void:
	var overlay: TerritoryOverlay = _make_overlay(_map())
	var bins: int = TerritoryOverlay.CIRCLE_BIN_GRID * TerritoryOverlay.CIRCLE_BIN_GRID
	var count: int = (TerritoryOverlay.CIRCLE_BIN_TEXELS_MAX - bins) / bins + 1
	var xs: PackedFloat32Array = PackedFloat32Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	var teams: PackedInt32Array = PackedInt32Array()
	xs.resize(count)
	radii.resize(count)
	radii.fill(100.0)
	teams.resize(count)
	overlay.set_circles(xs, xs, radii, teams, PackedVector2Array(), PackedFloat32Array(), false)
	assert_false(overlay.circle_bins_valid(), "Reference overflow must fall back to the full circle loop.")
	assert_false(bool(overlay.material().get_shader_parameter(&"circle_bins_valid")))
	assert_null(overlay.circle_bin_image())
	assert_true(bool(overlay.material().get_shader_parameter(&"circles_valid")), "Overflow does not select the raster fallback.")
	assert_eq(int(overlay.material().get_shader_parameter(&"circle_count")), count, "No circles are lost.")
	overlay.set_circles(
		PackedFloat32Array([0.0]), PackedFloat32Array([0.0]), PackedFloat32Array([1.0]),
		PackedInt32Array([0]), PackedVector2Array(), PackedFloat32Array(), false
	)
	assert_true(overlay.circle_bins_valid(), "A later smaller list restores binning.")
	assert_true(bool(overlay.material().get_shader_parameter(&"circle_bins_valid")))


func test_shader_declares_the_circle_bin_uniforms() -> void:
	# Bontago-1pi.11.1: the circle/bin uniforms moved into the shared include.
	var code: String = FileAccess.get_file_as_string("res://shaders/territory_circle_field.gdshaderinc")
	assert_true(code.contains("uniform sampler2D circle_bin_tex"), "Bin texture uniform.")
	assert_true(code.contains("uniform bool circle_bins_valid"), "Bin enable uniform.")
	assert_true(
		code.contains("const int CIRCLE_BIN_TEX_WIDTH = %d;" % TerritoryOverlay.CIRCLE_BIN_TEX_WIDTH),
		"Shader and overlay agree on the bin texture width."
	)


# --- Bontago-1pi.11.1: baked circle field -----------------------------------
func test_bake_is_off_without_a_renderer_and_the_shaders_declare_it() -> void:
	var overlay: TerritoryOverlay = _make_overlay(_map())
	overlay.set_circles(
		PackedFloat32Array([0.0]), PackedFloat32Array([0.0]), PackedFloat32Array([5.0]),
		PackedInt32Array([0]), PackedVector2Array(), PackedFloat32Array(), false
	)
	assert_false(overlay.bake_valid(), "Headless has no renderer, so the direct loop stays.")
	var code: String = (load("res://shaders/territory.gdshader") as Shader).code
	assert_true(code.contains("uniform sampler2D circle_bake_linear"), "Linear bake sampler.")
	assert_true(code.contains("uniform bool bake_valid"), "Bake enable uniform.")
	var bake: String = (load("res://shaders/territory_circle_bake.gdshader") as Shader).code
	assert_true(bake.contains("circle_field("), "The bake runs the shared circle field.")


## Bontago-1pi.11.23: an unchanged revision skips the texture upload.
class CountingOverlay extends TerritoryOverlay:
	var pushes: int = 0

	func push_cells(owner_bytes: PackedByteArray, state_bytes: PackedByteArray, side: int) -> void:
		pushes += 1
		super(owner_bytes, state_bytes, side)


func test_upload_now_skips_push_cells_until_the_raster_changes() -> void:
	var map_def: MapDef = _map()
	var overlay: CountingOverlay = CountingOverlay.new()
	overlay.configure(map_def, load("res://config/territory_visuals.tres"), load("res://config/territory_tuning.tres"))
	add_child_autofree(overlay)
	var raster: ScriptedRaster = _make_raster(map_def)
	overlay.set_source(raster, PackedColorArray())
	var after_source: int = overlay.pushes
	assert_gt(after_source, 0, "set_source always uploads.")

	overlay.upload_now()
	overlay.upload_now()
	assert_eq(overlay.pushes, after_source, "Unchanged revision: no push.")

	raster.set_cell(3, 2, 0)
	overlay.upload_now()
	assert_eq(overlay.pushes, after_source + 1, "A mutation uploads once.")
	overlay.upload_now()
	assert_eq(overlay.pushes, after_source + 1)

	overlay.set_source(raster, PackedColorArray())
	assert_eq(overlay.pushes, after_source + 2, "A re-set source always uploads.")


# --- Bontago-1pi.11.67 fix2b: GPU cost of the disc shader ---------------------

## The void field is skipped while no cell is a hole; any hole cell turns it on.
func test_void_present_follows_hole_cells_in_the_upload() -> void:
	var overlay: TerritoryOverlay = _make_overlay(_map())
	var cell_total: int = CELLS_PER_SIDE * CELLS_PER_SIDE
	var owners: PackedByteArray = PackedByteArray()
	owners.resize(cell_total)
	var states: PackedByteArray = PackedByteArray()
	states.resize(cell_total)
	states[7] = TerritoryOverlay.STATE_CONTESTED
	overlay.push_cells(owners, states, CELLS_PER_SIDE)
	assert_false(bool(overlay.material().get_shader_parameter(&"void_present")),
		"contested cells alone draw no void, so the shader may skip the void field.")
	states[7] = TerritoryOverlay.STATE_HOLE | TerritoryOverlay.STATE_CONTESTED
	overlay.push_cells(owners, states, CELLS_PER_SIDE)
	assert_true(bool(overlay.material().get_shader_parameter(&"void_present")), "a hole cell needs the void field.")
	states[7] = 0
	overlay.push_cells(owners, states, CELLS_PER_SIDE)
	assert_false(bool(overlay.material().get_shader_parameter(&"void_present")), "a closed hole drops it again.")


## Low drops the plating's rivets/brush; Medium and High keep them, and a live preset
## change reaches an existing overlay.
func test_disc_fine_detail_follows_the_graphics_preset() -> void:
	_restore_preset_id = Settings.current_graphics_preset().id
	Settings.set_graphics_preset(&"high")
	var overlay: TerritoryOverlay = _make_overlay(_map())
	assert_true(overlay.disc_fine_detail())
	assert_true(bool(overlay.material().get_shader_parameter(&"disc_fine_detail")))
	Settings.set_graphics_preset(&"low")
	assert_false(overlay.disc_fine_detail())
	assert_false(bool(overlay.material().get_shader_parameter(&"disc_fine_detail")))
	Settings.set_graphics_preset(&"medium")
	assert_true(bool(overlay.material().get_shader_parameter(&"disc_fine_detail")))


## The cost cuts are exact early-outs: the shader source keeps every branch the
## shipped look needs, guarded by the uniforms the overlay pushes.
func test_shader_carries_the_fix2b_guards() -> void:
	var code: String = _shader_source_without_comments(load("res://shaders/territory.gdshader") as Shader)
	assert_true(code.contains("uniform bool void_present = true;"), "void skip defaults to the old behaviour.")
	assert_true(code.contains("uniform bool disc_fine_detail = true;"), "fine detail defaults on.")
	assert_true(code.contains("if (void_present)"))
	assert_true(code.contains("if (disc_fine_detail && rivet_fade > 0.0)"))
	assert_true(code.contains("if (panel_variation != 0.0 || panel_seam_strength != 0.0)"))


## Bontago-1pi.11.67 fix2b: a test that switches the graphics preset records the
## original here; after_each puts it back even when an assert failed midway.
var _restore_preset_id: StringName = &""


func after_each() -> void:
	if _restore_preset_id != &"":
		Settings.set_graphics_preset(_restore_preset_id)
		_restore_preset_id = &""
