extends GutTest
## TerritoryOverlay turns the cell raster into the ImageTexture the disk shader
## samples (spec 2.10, 3.3, docs/M2_PLAN.md "Raster resolution").
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


func test_disk_defaults_to_a_mirror_like_metallic_and_roughness() -> void:
	var visuals: TerritoryVisuals = load("res://config/territory_visuals.tres")
	assert_between(
		visuals.disk_metallic, 0.6, 1.0,
		"docs/original_single-block.png and docs/original_stacked-tower.png show a strongly reflective disk.",
	)
	assert_between(
		visuals.disk_roughness, 0.0, 0.3,
		"Same reference screenshots: soft but clearly mirror-like reflections, not a diffuse matte surface.",
	)


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

func test_edge_softness_m_default_is_a_few_centimeters() -> void:
	var visuals: TerritoryVisuals = load("res://config/territory_visuals.tres")
	assert_between(
		visuals.edge_softness_m, 0.0, 0.1,
		"spec 2.10 / Bontago-xtq.14: a crisp ownership edge, a few cm at most.",
	)


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


# --- Bontago-xtq.12 step 2: the disc planar mirror ---------------------------
#
# game/DiscMirror.gd renders a mirrored camera into a SubViewport every frame
# and hands this overlay the result through set_mirror_texture(); shaders/
# territory.gdshader blends it over the disk. These tests cover this file's
# own share of that feature (the plain uniform push, same shape as
# set_slot_colors()) plus DiscMirror.mirror_transform()'s pure math, which
# that file's own class doc says is exposed here for exactly this reason.


func test_set_mirror_texture_pushes_the_shader_uniforms() -> void:
	var overlay: TerritoryOverlay = _make_overlay(_map())
	var image: Image = Image.create(4, 4, false, Image.FORMAT_RGB8)
	var texture: ImageTexture = ImageTexture.create_from_image(image)

	overlay.set_mirror_texture(texture, true, 0.7)

	assert_eq(overlay.material().get_shader_parameter(&"mirror_tex"), texture)
	assert_true(bool(overlay.material().get_shader_parameter(&"mirror_enabled")))
	assert_almost_eq(
		float(overlay.material().get_shader_parameter(&"mirror_strength")), 0.7, 0.0001
	)


func test_shader_declares_the_mirror_uniforms_and_flips_screen_uv_x() -> void:
	var overlay: TerritoryOverlay = _make_overlay(_map())
	var code: String = _shader_source_without_comments(overlay.material().shader)

	assert_true(code.contains("uniform sampler2D mirror_tex"), "expected a mirror_tex sampler uniform.")
	assert_true(code.contains("uniform bool mirror_enabled"), "expected a mirror_enabled uniform.")
	assert_true(code.contains("uniform float mirror_strength"), "expected a mirror_strength uniform.")

	var flip_sample: RegEx = RegEx.new()
	flip_sample.compile(
		"texture\\(\\s*mirror_tex\\s*,\\s*vec2\\(\\s*1\\.0\\s*-\\s*SCREEN_UV\\.x\\s*,\\s*SCREEN_UV\\.y\\s*\\)\\s*\\)"
	)
	assert_not_null(
		flip_sample.search(code),
		"mirror_tex must be sampled at a horizontally-flipped SCREEN_UV (see DiscMirror.gd's mirror_transform() DECISION)."
	)


func test_shader_default_mirror_max_luminance_matches_territory_visuals() -> void:
	# Bontago-xtq.20 (owner, 2026-09-23 20:12: "the main light source is
	# glaringly visible in the disc reflection"): game/DiscMirror.gd pushes
	# this uniform itself every frame (through TerritoryOverlay's own public
	# material() accessor, not a dedicated push method here -- see
	# tests/unit/test_disc_mirror.gd for that push), so an overlay with no
	# live DiscMirror ticking it yet (this test's _make_overlay(), same as
	# every other fixture in this file) only ever shows the shader's own
	# compiled-in default -- ShaderMaterial.get_shader_parameter() returns
	# null for a uniform no set_shader_parameter() call has ever touched, even
	# when the shader source declares a default, so this reads the literal
	# default straight out of the compiled shader source instead (the same
	# "parse the shader code" idiom
	# test_shader_declares_the_mirror_uniforms_and_flips_screen_uv_x() above
	# already uses) and checks it matches TerritoryVisuals.gd's own default.
	var visuals: TerritoryVisuals = load("res://config/territory_visuals.tres")
	var overlay: TerritoryOverlay = _make_overlay(_map())
	var code: String = _shader_source_without_comments(overlay.material().shader)

	var default_literal: RegEx = RegEx.new()
	default_literal.compile("uniform\\s+float\\s+mirror_max_luminance[^=]*=\\s*([0-9.]+)\\s*;")
	var match: RegExMatch = default_literal.search(code)
	assert_not_null(match, "expected mirror_max_luminance to declare a default literal.")
	if match != null:
		assert_almost_eq(
			match.get_string(1).to_float(), visuals.mirror_max_luminance, 0.0001,
			"the shader's compiled-in default must match TerritoryVisuals.gd's own default.",
		)


func test_default_mirror_max_luminance_only_clamps_genuinely_blown_out_highlights() -> void:
	var visuals: TerritoryVisuals = load("res://config/territory_visuals.tres")
	assert_between(
		visuals.mirror_max_luminance, 1.0, 2.0,
		"low enough to tame a clipped sun disc/specular hot spot, high enough that an ordinarily-lit block or sky patch (luminance well under 1.0) is never touched.",
	)


func test_shader_clamps_mirror_color_luminance_before_mixing_into_albedo() -> void:
	# Bontago-xtq.20: fail-before this fix -- the shader used to mix
	# mirror_color into albedo completely unclamped, so a directly-visible
	# sun disc or specular highlight read as a stark, hard-edged white blob
	# substituted straight into the disk's own mid-toned albedo.
	var overlay: TerritoryOverlay = _make_overlay(_map())
	var code: String = _shader_source_without_comments(overlay.material().shader)

	assert_true(
		code.contains("uniform float mirror_max_luminance"),
		"expected a mirror_max_luminance uniform.",
	)

	var luma_calc: RegEx = RegEx.new()
	luma_calc.compile("float\\s+mirror_luma\\s*=\\s*dot\\(\\s*mirror_color\\s*,")
	assert_not_null(
		luma_calc.search(code),
		"expected mirror_color's luminance to be computed via a dot product.",
	)

	var clamp_scale: RegEx = RegEx.new()
	clamp_scale.compile(
		"if\\s*\\(\\s*mirror_luma\\s*>\\s*mirror_max_luminance\\s*\\)\\s*\\{[\\s\\S]*?mirror_color\\s*\\*="
	)
	assert_not_null(
		clamp_scale.search(code),
		"expected mirror_color to be scaled down whenever its luminance exceeds mirror_max_luminance.",
	)

	# The clamp must run before mirror_color gets mixed into albedo, not after
	# (a clamp applied to the already-mixed albedo would also dim the
	# unrelated ownership tint/rim/shimmer colors it was mixed with).
	var mix_index: int = code.find("albedo = mix(albedo, mirror_color, mirror_amount)")
	var clamp_index: int = code.find("mirror_luma > mirror_max_luminance")
	assert_true(mix_index >= 0 and clamp_index >= 0 and clamp_index < mix_index)


func test_mirror_transform_reflects_a_camera_above_a_horizontal_plane() -> void:
	var plane: Plane = Plane(Vector3.UP, 0.0)
	var camera_origin: Vector3 = Vector3(2.0, 5.0, 3.0)
	var target: Vector3 = Vector3.ZERO
	var camera_xf: Transform3D = Transform3D.IDENTITY.translated(camera_origin).looking_at(target, Vector3.UP)

	var mirrored: Transform3D = DiscMirror.mirror_transform(camera_xf, plane)

	assert_almost_eq(
		mirrored.origin.y, -camera_origin.y, 0.0001,
		"reflecting a camera above the y=0 plane must negate its height."
	)
	assert_almost_eq(mirrored.origin.x, camera_origin.x, 0.0001, "x is unchanged by a horizontal-plane reflection.")
	assert_almost_eq(mirrored.origin.z, camera_origin.z, 0.0001, "z is unchanged by a horizontal-plane reflection.")
	assert_almost_eq(
		mirrored.basis.determinant(), 1.0, 0.0001,
		"the reflected basis must stay proper (determinant 1), or backface culling flips the wrong way."
	)

	var mirrored_target: Vector3 = target - 2.0 * plane.distance_to(target) * plane.normal
	var forward: Vector3 = -mirrored.basis.z
	var to_target: Vector3 = (mirrored_target - mirrored.origin).normalized()
	assert_almost_eq(
		forward.dot(to_target), 1.0, 0.0001,
		"the mirrored camera must look at the mirrored target, not just sit at the mirrored origin."
	)


func test_mirror_transform_reflects_across_a_tilted_plane() -> void:
	var tilt: float = deg_to_rad(10.0)
	var normal: Vector3 = Vector3(0.0, cos(tilt), sin(tilt)).normalized()
	var plane: Plane = Plane(normal, Vector3.ZERO)
	var camera_origin: Vector3 = Vector3(2.0, 5.0, 3.0)
	var camera_xf: Transform3D = Transform3D.IDENTITY.translated(camera_origin).looking_at(Vector3.ZERO, Vector3.UP)

	var mirrored: Transform3D = DiscMirror.mirror_transform(camera_xf, plane)

	var camera_distance: float = plane.distance_to(camera_origin)
	var mirrored_distance: float = plane.distance_to(mirrored.origin)
	assert_almost_eq(
		mirrored_distance, -camera_distance, 0.0001,
		"the mirrored origin must sit the same distance on the opposite side of a tilted plane."
	)
	assert_almost_eq(
		mirrored.basis.determinant(), 1.0, 0.0001,
		"the reflected basis must stay proper for a tilted plane too."
	)
