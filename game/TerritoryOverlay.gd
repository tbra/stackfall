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
## docs/archive/M2_PLAN.md, "Raster resolution"): 90x90 on map M, which is also the
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

## Render layer the disc (overlay top + DiscBody rim) lives on alone, so the disc
## ReflectionProbe (Skybox.PROBE_CULL_MASK) and the decals skip it. Moved here from
## the removed DiscMirror (owner 2026-10-07).
const DISC_LAYER_BIT: int = 1 << 19
const TERRITORY_SHADER: Shader = preload("res://shaders/territory.gdshader")
const CIRCLE_BAKE_SHADER: Shader = preload("res://shaders/territory_circle_bake.gdshader")
## Frames the first bake is given to reach the render target before the disc
## shader is told to trust it (the SubViewport draws on the frame after the
## request at the latest).
const BAKE_SETTLE_FRAMES: int = 2
## Smallest bake edge in texels, and a cap so a huge map x a high density can
## never allocate an absurd render target.
const BAKE_SIZE_MIN: int = 16
const BAKE_SIZE_MAX: int = 2048
## Slot colors the shader's uniform array holds; MatchConfig ships eight.
const SLOT_COLOR_MAX: int = 8
## Weather wetness (Bontago-22y.5) finds the overlay through this group.
const WET_GROUP: StringName = &"weather_territory"
## Wet-disc request, presentation only: extra sheen and a roughness factor
## layered over TerritoryVisuals. _apply_visual_uniforms() re-applies it, so a
## visuals refresh (F4 panel) mid-rain never drops it.
var _wet_amount: float = 0.0
var _wet_sheen_add: float = 0.0
var _wet_roughness_scale: float = 1.0
var _wet_darken: float = 0.0
## Last per-slot colors handed in (Bontago-sen.4). _apply_visual_uniforms()
## re-pushes these; it used to reset every slot to goal_flag_color, wiping the
## team colors whenever the F4 panel / a graphics refresh called
## refresh_visual_uniforms() mid-match.
var _slot_colors: PackedColorArray = PackedColorArray()
## The disk centre sits at the middle of the raster square, so disk-local
## (0, 0) maps to the middle of the texture. See _apply_uv_uniforms().
const UV_CENTER: float = 0.5

## Goal records the shader loops per pixel; a wire safety cap mirroring
## core/net/CircleWire.gd's GOAL_COUNT_MAX, and far above spec 2.2's 1-5
## goal flags.
const GOAL_TEXELS_MAX: int = 8

## Bontago-1pi.11 (owner playtest: "the game slows down a lot after a
## while"): the analytic circle path used to loop every circle for every disk
## pixel, so its GPU cost grew with the live block count (windowed probe,
## 1920x1080: ~95-120 ms/frame at 60-160 blocks, ~15-30 ms with the loop
## skipped). _pack_circle_bins() buckets the list into a coarse square grid
## over the disk so each pixel only loops the circles that can reach it.
## DECISION (game/TerritoryOverlay.gd): implementation constants of the
## acceleration structure, not presentation or rule tunables, kept here the
## same way GOAL_TEXELS_MAX is. CIRCLE_BIN_TEX_WIDTH must match the shader's
## own const of the same name.
const CIRCLE_BIN_GRID: int = 24
const CIRCLE_BIN_TEX_WIDTH: int = 256
## Upper bound on bin texels (headers + references); a list that would need
## more simply falls back to the full per-pixel loop (circle_bins_valid off).
const CIRCLE_BIN_TEXELS_MAX: int = CIRCLE_BIN_TEX_WIDTH * CIRCLE_BIN_TEX_WIDTH
## Extra slack past the half extent so a pixel exactly on the rim still lands
## in the last bin rather than taking the full-loop path.
const CIRCLE_BIN_EDGE_SLACK_M: float = 0.01
## How many metaball_blend widths of extra margin a circle is binned with.
## A circle whose value is below -(edge + rim + rim_soft + this * blend)
## everywhere in a bin can shift a team's smooth max only inside a band no
## drawn effect reads (the tint starts at -edge_softness_m, the rim band ends
## at rim_width), so dropping it from that bin leaves every pixel unchanged.
const CIRCLE_BIN_BLEND_MARGIN_FACTOR: float = 4.0

var _map_def: MapDef = null
var _visuals: TerritoryVisuals = null
## Bontago-1pi.11.42: look of the animated void on hole cells (the disc stays
## solid; the shader draws the hole). Pushed by _apply_hole_void_uniforms().
@export var hole_visuals: HoleVisualTuning = preload("res://config/hole_visual_tuning.tres")
## GraphicsPreset.hole_void_animated: false = flat void + rim (Low).
var _void_animated: bool = true
## GraphicsPreset.disc_fine_detail_enabled: false = plating without rivets and
## brushed streaks (Low; Bontago-1pi.11.67 fix2b).
var _disc_fine_detail: bool = true
var _tuning: TerritoryTuning = null
var _material: ShaderMaterial = null
var _texture: ImageTexture = null
var _cell_texture: ImageTexture = null
var _state_texture: ImageTexture = null
## Bontago-1pi.11.44: hole + contested bits as an RG8 mask (0/255), bound
## linear-filtered so the void shader reads a smooth hole field.
var _hole_texture: ImageTexture = null
var _hole_cell_image: Image = null
## Bontago-1pi.11.67 fix2b: whether the last uploaded hole mask has any hole cell
## (the shader's void_present uniform).
var _hole_any: bool = false
var _raster: TerritoryRaster = null
## Bontago-1pi.11.23: raster revision last pushed to the textures; -1 = none.
var _pushed_revision: int = -1
var _cells_per_side: int = 0
var _last_image: Image = null
var _owner_cell_image: Image = null
var _state_cell_image: Image = null
var _upload_accumulator: float = 0.0
## The disk_mesh_segments value baked into the current CylinderMesh, so
## refresh_visual_uniforms() only calls rebuild_disk_mesh() when it actually
## changed (Bontago-mv0.20b) -- an unrelated visuals field (color, tint,
## outline...) must not reallocate a mesh at raster_upload_hz. -1 before
## configure() ever runs.
var _baked_mesh_segments: int = -1

## Bontago-cmc.5: the analytic circle list (see set_circles()'s doc). Kept
## the same way _owner_cell_image is — a headless test has no rendering
## server to read a texture back from.
var _circle_texture: ImageTexture = null
var _goal_texture: ImageTexture = null
var _circle_image: Image = null
var _goal_image: Image = null
var _circle_count: int = 0
var _circle_bin_texture: ImageTexture = null
var _circle_bin_image: Image = null
var _circle_bins_valid: bool = false
var _circle_bin_baked_margin: float = 0.0
var _goal_count: int = 0
## Bontago-1pi.11.1 circle-field bake (see _request_bake()).
var _bake_viewport: SubViewport = null
var _bake_rect: ColorRect = null
var _bake_material: ShaderMaterial = null
var _bake_key: Array = []
var _bake_settle_left: int = 0
var _bake_wanted: bool = false
## Bontago-1pi.11.33: bake-on-settle. While blocks churn, a changed circle field
## is parked (_bake_pending) and baked once on settle, or at a deadline shared
## with the solve deferral: solve wait + bake wait never exceeds
## TerritoryTuning.solve_defer_max_s, whichever comes first.
var _churning: bool = false
var _bake_pending: bool = false
var _last_bake_msec: int = 0
## How long the solve behind the current upload already waited (set by the host
## with the churn flag); the bake only gets what is left of the shared cap.
var _solve_waited_msec: int = 0
var _bake_deadline_msec: int = 0
var _bake_count: int = 0
var _bake_deferred_count: int = 0
## Tests/bench only: treat a headless run as bake-capable so the gating counts.
var _bake_headless_ok: bool = false


func _process(delta: float) -> void:
	_flush_pending_bake(false)
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
	layers = DISC_LAYER_BIT
	_pushed_revision = -1
	_map_def = map_def
	_visuals = visuals
	_tuning = tuning
	_cells_per_side = map_def.cells_per_side()
	add_to_group(WET_GROUP)
	var preset: GraphicsPreset = Settings.current_graphics_preset()
	_void_animated = preset == null or preset.hole_void_animated
	_disc_fine_detail = preset == null or preset.disc_fine_detail_enabled
	if not Settings.graphics_preset_changed.is_connected(_on_graphics_preset_changed):
		Settings.graphics_preset_changed.connect(_on_graphics_preset_changed)

	rebuild_disk_mesh()

	_material = ShaderMaterial.new()
	_material.shader = TERRITORY_SHADER
	_apply_visual_uniforms()
	_set_blank_texture()
	_build_bake_viewport()
	clear_circles()
	material_override = _material


## Recreates the disk's CylinderMesh with the current
## _visuals.disk_mesh_segments, keeping the same radius/height configure()
## built it with (Bontago-mv0.20b, F4 tuning panel live-apply). Public so
## configure() and refresh_visual_uniforms() share one place that knows the
## disk's actual dimensions; a no-op-safe call before configure() simply does
## nothing (there is no _map_def/_visuals yet to build from).
func rebuild_disk_mesh() -> void:
	if _map_def == null or _visuals == null:
		return
	# Bontago-1pi.60: RING/TWIN/CROSS draw their real cell shape, not the disc.
	if DiskShapeMesh.needs_cell_mesh(_map_def):
		mesh = DiskShapeMesh.build(_map_def, _map_def.disk_height)
		_baked_mesh_segments = _visuals.disk_mesh_segments
		return
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = _map_def.field_radius
	cylinder.bottom_radius = _map_def.field_radius
	cylinder.height = _map_def.disk_height
	cylinder.radial_segments = _visuals.disk_mesh_segments
	mesh = cylinder
	_baked_mesh_segments = _visuals.disk_mesh_segments


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
##
## A null raster (Field.clear_match_state(), spec 3.7's End -> Lobby) also
## drops whatever circle list the last match left uploaded — otherwise the
## disk sitting idle behind the main menu would keep showing the previous
## match's last analytic frame, the one part of the overlay upload_now() by
## itself never touches (Bontago-cmc.5).
func set_source(raster: TerritoryRaster, slot_colors: PackedColorArray) -> void:
	_raster = raster
	_pushed_revision = -1
	var raster_grid: CellGrid = raster.grid() if raster != null else null
	if raster_grid != null:
		_cells_per_side = raster_grid.res
	set_slot_colors(slot_colors)
	upload_now()
	if raster == null:
		clear_circles()


## MatchConfig.player_colors, indexed by team/slot id. Converted to linear
## because the shader's array uniform cannot carry a source_color hint.
func set_slot_colors(slot_colors: PackedColorArray) -> void:
	_slot_colors = slot_colors
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
	var revision: int = _raster.content_revision()
	if revision == _pushed_revision:
		return
	push_cells(_raster.owner_bytes(), _raster.state_bytes(), _cells_per_side)
	_pushed_revision = revision


## The low-level entry: one byte of owner and one of state per cell, row-major,
## `side` to a row -- the two arrays TerritoryRaster hands out. Field's raster
## path goes through upload_now(); tests push bytes straight in.
func push_cells(
	owner_bytes: PackedByteArray, state_bytes: PackedByteArray, side: int
) -> void:
	_pushed_revision = -1
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
	_hole_cell_image = _hole_mask_image(state_image.get_data(), side)
	_hole_texture = _store(_hole_texture, _hole_cell_image)
	_material.set_shader_parameter(&"territory_hole", _hole_texture)
	# Bontago-1pi.11.67 fix2b: lets the shader skip the void field (a texture
	# fetch + fwidth per disc pixel) while no cell is a hole.
	_material.set_shader_parameter(&"void_present", _hole_any)
	_material.set_shader_parameter(&"territory_cells", _cell_texture)
	_material.set_shader_parameter(&"territory_state", _state_texture)
	_material.set_shader_parameter(&"territory_state_soft", _state_texture)
	_set_image(_upscaled(owner_image, side))
	_apply_uv_uniforms(side)


## Bontago-1pi.11.44: R = STATE_HOLE, G = STATE_CONTESTED of each state byte
## (0/255), the texture shaders/territory.gdshader's void samples with a
## linear filter (G tells a hole inside an overlap from one outside any).
func _hole_mask_image(state_bytes: PackedByteArray, side: int) -> Image:
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(state_bytes.size() * 2)
	_hole_any = false
	for i: int in range(state_bytes.size()):
		if (state_bytes[i] & STATE_HOLE) != 0:
			mask[i * 2] = 255
			_hole_any = true
		if (state_bytes[i] & STATE_CONTESTED) != 0:
			mask[i * 2 + 1] = 255
	return Image.create_from_data(side, side, false, Image.FORMAT_RG8, mask)


## The smoothed hole mask texture (tests read it).
func hole_mask_texture() -> ImageTexture:
	return _hole_texture


## CPU copy of the hole mask (ImageTexture.get_image() is empty headless).
func hole_mask_image() -> Image:
	return _hole_cell_image


## Bontago-cmc.5: the analytic circle list a solve step just produced —
## autoload/Match.gd's home-anchored circles (the same ones TerritoryGroups
## kept, already capped at TerritoryTuning.max_circles) plus the goal
## no-build discs, so shaders/territory.gdshader can draw the territory
## border as the union of real circles instead of smoothstepping the
## upscaled cell grid above. `xs`/`zs`/`radii`/`teams` are disk-local and the
## same length (a caller that built them any other way gets a texture sized
## to the shortest of the four, matching push_cells()'s own
## "never half-crash" style); `argmax_mode` is MatchConfig.HoleMode.OFF,
## which the shader must colour with a single-owner argmax instead of a
## union + contested test (spec 3.3's v2 alternative).
##
## Circles are packed one per texel of an RGBAF image — R/G = disk-local
## x/z, B = radius, A = team id — rather than a shader array uniform: a
## uniform array needs a compile-time size and a second cap to keep in sync
## with TerritoryTuning.max_circles, where a sampler2D's width is just
## however many texels this call uploads (docs/TERRITORY_V2_PLAN.md's
## rendering section rejected this shape for the *raster* renderer on cost
## grounds that do not apply here: 400 texels is a few KB, not a resize()).
## texelFetch(), not a filtered sample, reads them back exactly.
func set_circles(
	xs: PackedFloat32Array,
	zs: PackedFloat32Array,
	radii: PackedFloat32Array,
	teams: PackedInt32Array,
	goal_positions: PackedVector2Array,
	goal_radii: PackedFloat32Array,
	argmax_mode: bool
) -> void:
	if _material == null:
		return
	var count: int = mini(mini(xs.size(), zs.size()), mini(radii.size(), teams.size()))
	_circle_count = count
	_circle_image = _pack_circle_image(xs, zs, radii, teams, count)
	_circle_texture = _store(_circle_texture, _circle_image)

	var goal_count: int = mini(goal_positions.size(), goal_radii.size())
	goal_count = mini(goal_count, GOAL_TEXELS_MAX)
	_goal_count = goal_count
	_goal_image = _pack_goal_image(goal_positions, goal_radii, goal_count)
	_goal_texture = _store(_goal_texture, _goal_image)

	# A list longer than the shader's own budget (TerritoryVisuals.
	# max_shader_circles, independently tunable below TerritoryTuning.
	# max_circles for a weaker GPU) falls back to the cell-raster path for
	# that frame rather than silently truncating the circle list and
	# drawing a wrong boundary (spec 3.3, "Bounded cost").
	var valid: bool = count > 0 and count <= _visuals.max_shader_circles
	_material.set_shader_parameter(&"circle_tex", _circle_texture)
	_material.set_shader_parameter(&"circle_count", count)
	_update_circle_bins(xs, zs, radii, mini(count, _visuals.max_shader_circles))
	_material.set_shader_parameter(&"max_shader_circles", _visuals.max_shader_circles)
	_material.set_shader_parameter(&"circles_valid", valid)
	_material.set_shader_parameter(&"argmax_mode", argmax_mode)
	_material.set_shader_parameter(&"goal_tex", _goal_texture)
	_material.set_shader_parameter(&"goal_count", goal_count)
	_material.set_shader_parameter(&"metaball_blend", _visuals.metaball_blend)
	_material.set_shader_parameter(&"rim_soft_width", _visuals.rim_soft_width)
	_material.set_shader_parameter(&"rim_width", _visuals.rim_width)
	_material.set_shader_parameter(&"rim_strength", _visuals.rim_strength)
	_material.set_shader_parameter(&"rim_pulse_depth", _visuals.rim_pulse_depth)
	_material.set_shader_parameter(&"rim_speed", _visuals.rim_speed)
	_request_bake(valid)


## Drops the circle list: circle_count/goal_count go to 0, so the shader's
## `circles_valid` test fails and it falls back to the raster path, exactly
## as an overflowing list would. configure() calls this once for the blank
## disk before any match starts; set_source(null, ...) calls it again when a
## match ends.
func clear_circles() -> void:
	set_circles(
		PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), PackedInt32Array(),
		PackedVector2Array(), PackedFloat32Array(), false
	)


## Circles currently uploaded (the shader's circle_count uniform).
func circle_count() -> int:
	return _circle_count


## Goal discs currently uploaded (the shader's goal_count uniform).
func goal_count() -> int:
	return _goal_count


## Bontago-1pi.11: the per-bin circle lists the shader reads (see
## _pack_circle_bins()); null before the first set_circles().
func circle_bin_image() -> Image:
	return _circle_bin_image


func circle_bins_valid() -> bool:
	return _circle_bins_valid


func circle_bin_half_extent() -> float:
	return _map_def.field_radius + CIRCLE_BIN_EDGE_SLACK_M if _map_def != null else 1.0


## Margin (m) past a circle's radius within which it still reaches a bin;
## see CIRCLE_BIN_BLEND_MARGIN_FACTOR.
func circle_bin_margin() -> float:
	return (
		maxf(_visuals.edge_softness_m, 0.0) + maxf(_visuals.rim_width, 0.0)
		+ maxf(_visuals.rim_soft_width, 0.0)
		+ CIRCLE_BIN_BLEND_MARGIN_FACTOR * maxf(_visuals.metaball_blend, 0.0)
	)


func _update_circle_bins(
	xs: PackedFloat32Array, zs: PackedFloat32Array, radii: PackedFloat32Array, count: int
) -> void:
	_circle_bin_image = _pack_circle_bins(xs, zs, radii, count)
	_circle_bin_baked_margin = circle_bin_margin()
	_circle_bins_valid = _circle_bin_image != null
	if _circle_bins_valid:
		_circle_bin_texture = _store(_circle_bin_texture, _circle_bin_image)
		_material.set_shader_parameter(&"circle_bin_tex", _circle_bin_texture)
	_material.set_shader_parameter(&"circle_bins_valid", _circle_bins_valid)
	_material.set_shader_parameter(&"circle_bin_grid", CIRCLE_BIN_GRID)
	_material.set_shader_parameter(&"circle_bin_half_extent", circle_bin_half_extent())


## RGF, CIRCLE_BIN_TEX_WIDTH texels wide, read row-major as one flat array:
## texel k < CIRCLE_BIN_GRID^2 is (start, count) for bin k (bin k covers
## column k % grid, row k / grid of the square [-half, half]^2 in disk-local
## x/z); texels from `start` hold that bin's circle indices, ascending, so the
## shader walks them in the same team-sorted order as circle_tex. A circle is
## listed in every bin whose rectangle comes within radius + margin of its
## centre. Returns null (full-loop fallback) when there is nothing to bin or
## the lists would overflow CIRCLE_BIN_TEXELS_MAX.
func _pack_circle_bins(
	xs: PackedFloat32Array, zs: PackedFloat32Array, radii: PackedFloat32Array, count: int
) -> Image:
	if count <= 0 or _map_def == null:
		return null
	var grid: int = CIRCLE_BIN_GRID
	var bins: int = grid * grid
	var half: float = circle_bin_half_extent()
	var cell: float = 2.0 * half / float(grid)
	var margin: float = circle_bin_margin()
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(bins)
	# Two passes (count, then fill) over the same per-circle bin walk, so the
	# flat reference list needs no per-bin arrays.
	var height: int = 1
	for pass_index: int in range(2):
		var cursor: PackedInt32Array = PackedInt32Array()
		var flat: PackedFloat32Array = PackedFloat32Array()
		var total: int = 0
		if pass_index == 1:
			var starts: PackedInt32Array = PackedInt32Array()
			starts.resize(bins)
			total = bins
			for k: int in range(bins):
				starts[k] = total
				total += counts[k]
			if total > CIRCLE_BIN_TEXELS_MAX:
				return null
			height = maxi(ceili(float(total) / float(CIRCLE_BIN_TEX_WIDTH)), 1)
			flat.resize(CIRCLE_BIN_TEX_WIDTH * height * 2)
			for k: int in range(bins):
				flat[k * 2] = float(starts[k])
				flat[k * 2 + 1] = float(counts[k])
			cursor = starts
		for i: int in range(count):
			var reach: float = maxf(radii[i], 0.0) + margin
			var cx: float = xs[i]
			var cz: float = zs[i]
			var col_lo: int = clampi(int(floor((cx - reach + half) / cell)), 0, grid - 1)
			var col_hi: int = clampi(int(floor((cx + reach + half) / cell)), 0, grid - 1)
			var row_lo: int = clampi(int(floor((cz - reach + half) / cell)), 0, grid - 1)
			var row_hi: int = clampi(int(floor((cz + reach + half) / cell)), 0, grid - 1)
			if cx + reach < -half or cx - reach > half or cz + reach < -half or cz - reach > half:
				continue
			for row: int in range(row_lo, row_hi + 1):
				var z0: float = -half + float(row) * cell
				var dz: float = maxf(maxf(z0 - cz, cz - (z0 + cell)), 0.0)
				for col: int in range(col_lo, col_hi + 1):
					var x0: float = -half + float(col) * cell
					var dx: float = maxf(maxf(x0 - cx, cx - (x0 + cell)), 0.0)
					if dx * dx + dz * dz > reach * reach:
						continue
					var k: int = row * grid + col
					if pass_index == 0:
						counts[k] += 1
					else:
						flat[cursor[k] * 2] = float(i)
						cursor[k] += 1
		if pass_index == 1:
			return Image.create_from_data(
				CIRCLE_BIN_TEX_WIDTH, height, false, Image.FORMAT_RGF, flat.to_byte_array()
			)
	return null


## Bontago-1pi.11.1 DECISION (game/TerritoryOverlay.gd): the circle loop that
## dominated the disc's GPU time (home-only circles: 16.4 -> 7.6 ms at 300
## blocks) is baked into a render texture only when the circle set changes,
## via a SubViewport + ColorRect running territory_circle_bake.gdshader. A
## GPU bake was chosen over the host's TerritoryRaster because (a) clients have
## no raster, only the replicated circles every peer feeds set_circles(), and
## (b) the raster is a 1 m cell grid, while the bake keeps the continuous
## signed distance that gives the sub-centimetre edge. The bake is skipped
## (and the disc shader loops circles as before) with no renderer (headless),
## when disabled in TerritoryVisuals, or until the first bake has rendered.
func _build_bake_viewport() -> void:
	if _bake_viewport != null or _map_def == null:
		return
	_bake_viewport = SubViewport.new()
	_bake_viewport.disable_3d = true
	_bake_viewport.use_hdr_2d = true
	_bake_viewport.transparent_bg = false
	_bake_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_bake_viewport.size = Vector2i(BAKE_SIZE_MIN, BAKE_SIZE_MIN)
	_bake_material = ShaderMaterial.new()
	_bake_material.shader = CIRCLE_BAKE_SHADER
	_bake_rect = ColorRect.new()
	_bake_rect.material = _bake_material
	_bake_rect.size = Vector2(_bake_viewport.size)
	_bake_viewport.add_child(_bake_rect)
	add_child(_bake_viewport)


## Bench/test hook: flips TerritoryVisuals.circle_bake_enabled on the live
## resource and re-requests the bake.
func set_bake_enabled_for_bench(enabled: bool) -> void:
	_visuals.circle_bake_enabled = enabled
	_request_bake(_bake_wanted)


## Host-side signal (autoload/match/MatchTerritory.gd): true while any tracked
## block is awake. Leaving churn flushes a parked bake at once.
func set_churning(churning: bool, solve_waited_s: float = 0.0) -> void:
	_churning = churning
	_solve_waited_msec = int(maxf(solve_waited_s, 0.0) * 1000.0)
	_flush_pending_bake(false)


func bake_count() -> int:
	return _bake_count


func bake_deferred_count() -> int:
	return _bake_deferred_count


func bake_pending() -> bool:
	return _bake_pending


func _bake_age_cap_msec() -> int:
	if _tuning == null:
		return 0
	return int(maxf(_tuning.solve_defer_max_s, 0.0) * 1000.0)


func _flush_pending_bake(force: bool) -> void:
	if not _bake_pending:
		return
	if not force and _churning and Time.get_ticks_msec() < _bake_deadline_msec:
		return
	_bake_pending = false
	_request_bake(_bake_wanted, true)


func bake_valid() -> bool:
	return _bake_viewport != null and bool(_material.get_shader_parameter(&"bake_valid"))


func _bake_extent() -> Vector2:
	var z_scale: float = 1.0
	if _map_def.map_shape == MapDef.MapShape.OVAL:
		z_scale = _map_def.oval_aspect
	return Vector2(_map_def.field_radius, _map_def.field_radius * z_scale)


## Re-renders the bake if the circle field it would hold changed (or the
## visuals that shape it did); otherwise a no-op, so a steady 5 Hz re-upload of
## an unchanged set costs nothing.
func _request_bake(circles_ok: bool, flushing: bool = false) -> void:
	_bake_wanted = circles_ok
	var usable: bool = (
		circles_ok and _bake_viewport != null and _visuals.circle_bake_enabled
		and (DisplayServer.get_name() != "headless" or _bake_headless_ok)
	)
	if not usable:
		_bake_pending = false
		_bake_key = []
		_bake_settle_left = 0
		_material.set_shader_parameter(&"bake_valid", false)
		return
	var extent: Vector2 = _bake_extent()
	var key: Array = [
		_circle_image.get_data(), _visuals.metaball_blend, _visuals.rim_soft_width,
		_circle_bins_valid, _circle_bin_image.get_data() if _circle_bins_valid else null,
		extent, _visuals.circle_bake_texels_per_m, _circle_count,
	]
	if key == _bake_key:
		_bake_pending = false
		return
	# DECISION (Bontago-1pi.11.33): skip the re-bake while blocks churn and bake
	# once on settle. The previous bake stays visible meanwhile, never longer
	# than solve_defer_max_s (0.5 s), so the visible cadence is unchanged in the
	# worst case. The very first bake (nothing valid yet) is never deferred.
	# DECISION (Bontago-1pi.11.33 review F4): the bake shares the solve's 0.5 s
	# cap. A solve applied after waiting W seconds may park the bake for at most
	# cap - W, so the visible territory delay stays <= solve_defer_max_s; a solve
	# that already waited the full cap bakes right away.
	var budget_msec: int = _bake_age_cap_msec() - _solve_waited_msec
	if not flushing and _churning and budget_msec > 0 and not _bake_key.is_empty():
		var deadline: int = Time.get_ticks_msec() + budget_msec
		_bake_deadline_msec = mini(_bake_deadline_msec, deadline) if _bake_pending else deadline
		_bake_pending = true
		_bake_deferred_count += 1
		return
	_bake_pending = false
	_bake_count += 1
	_last_bake_msec = Time.get_ticks_msec()
	var first: bool = _bake_key.is_empty() or not bool(_material.get_shader_parameter(&"bake_valid"))
	_bake_key = key
	var edge_x: int = clampi(ceili(extent.x * 2.0 * _visuals.circle_bake_texels_per_m), BAKE_SIZE_MIN, BAKE_SIZE_MAX)
	var edge_y: int = clampi(ceili(extent.y * 2.0 * _visuals.circle_bake_texels_per_m), BAKE_SIZE_MIN, BAKE_SIZE_MAX)
	_bake_viewport.size = Vector2i(edge_x, edge_y)
	_bake_rect.size = Vector2(edge_x, edge_y)
	_bake_material.set_shader_parameter(&"circle_tex", _circle_texture)
	_bake_material.set_shader_parameter(&"circle_count", _circle_count)
	_bake_material.set_shader_parameter(&"max_shader_circles", _visuals.max_shader_circles)
	_bake_material.set_shader_parameter(&"circle_bins_valid", _circle_bins_valid)
	if _circle_bins_valid:
		_bake_material.set_shader_parameter(&"circle_bin_tex", _circle_bin_texture)
	_bake_material.set_shader_parameter(&"circle_bin_grid", CIRCLE_BIN_GRID)
	_bake_material.set_shader_parameter(&"circle_bin_half_extent", circle_bin_half_extent())
	_bake_material.set_shader_parameter(&"metaball_blend", _visuals.metaball_blend)
	_bake_material.set_shader_parameter(&"rim_soft_width", _visuals.rim_soft_width)
	_bake_material.set_shader_parameter(&"bake_half_extent", extent)
	_material.set_shader_parameter(&"bake_half_extent", extent)
	var baked: ViewportTexture = _bake_viewport.get_texture()
	_material.set_shader_parameter(&"circle_bake_linear", baked)
	_material.set_shader_parameter(&"circle_bake_near", baked)
	_bake_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if first:
		# Until a bake has rendered, keep drawing with the direct loop.
		_material.set_shader_parameter(&"bake_valid", false)
		_bake_settle_left = BAKE_SETTLE_FRAMES
		if not RenderingServer.frame_post_draw.is_connected(_on_bake_frame_drawn):
			RenderingServer.frame_post_draw.connect(_on_bake_frame_drawn)


func _on_bake_frame_drawn() -> void:
	_bake_settle_left -= 1
	if _bake_settle_left > 0:
		return
	RenderingServer.frame_post_draw.disconnect(_on_bake_frame_drawn)
	if _bake_key.is_empty():
		return
	_material.set_shader_parameter(&"bake_valid", true)


func circle_texture() -> ImageTexture:
	return _circle_texture


func goal_texture() -> ImageTexture:
	return _goal_texture


## The exact circle/goal Images of the last upload, for the same headless-
## test reason owner_cell_image() exists.
func circle_image() -> Image:
	return _circle_image


func goal_image() -> Image:
	return _goal_image


## RGBAF, one texel per circle: (x, z, radius, team). Width is always at
## least 1 (an empty image is invalid), so an unused caller texel carries
## team -1.0 — circle_count staying 0 is what actually keeps the shader from
## reading it, the same "the count decides, not the texture" contract
## push_cells()'s _sized() padding relies on for the raster path.
func _pack_circle_image(
	xs: PackedFloat32Array,
	zs: PackedFloat32Array,
	radii: PackedFloat32Array,
	teams: PackedInt32Array,
	count: int
) -> Image:
	var width: int = maxi(count, 1)
	var floats: PackedFloat32Array = PackedFloat32Array()
	floats.resize(width * 4)
	if count == 0:
		floats[3] = -1.0
	for i: int in range(count):
		var base: int = i * 4
		floats[base] = xs[i]
		floats[base + 1] = zs[i]
		floats[base + 2] = radii[i]
		floats[base + 3] = float(teams[i])
	return Image.create_from_data(width, 1, false, Image.FORMAT_RGBAF, floats.to_byte_array())


## RGBAF, one texel per goal disc: (x, z, radius, unused).
func _pack_goal_image(
	goal_positions: PackedVector2Array, goal_radii: PackedFloat32Array, count: int
) -> Image:
	var width: int = maxi(count, 1)
	var floats: PackedFloat32Array = PackedFloat32Array()
	floats.resize(width * 4)
	for i: int in range(count):
		var base: int = i * 4
		floats[base] = goal_positions[i].x
		floats[base + 1] = goal_positions[i].y
		floats[base + 2] = goal_radii[i]
		floats[base + 3] = 0.0
	return Image.create_from_data(width, 1, false, Image.FORMAT_RGBAF, floats.to_byte_array())


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
func _on_graphics_preset_changed(preset: GraphicsPreset) -> void:
	_void_animated = preset == null or preset.hole_void_animated
	_disc_fine_detail = preset == null or preset.disc_fine_detail_enabled
	if _material != null:
		_material.set_shader_parameter(&"void_animated", 1.0 if _void_animated else 0.0)
		_material.set_shader_parameter(&"disc_fine_detail", _disc_fine_detail)


## Whether the disc plating draws its rivets and brushed streaks (graphics
## preset, Bontago-1pi.11.67 fix2b); tests read it.
func disc_fine_detail() -> bool:
	return _disc_fine_detail


## Whether the hole void swirl is animating (graphics preset); tests read it.
func void_animated() -> bool:
	return _void_animated


## Bontago-1pi.11.42: pushes HoleVisualTuning's void look onto the disc shader.
func _apply_hole_void_uniforms() -> void:
	var hv: HoleVisualTuning = hole_visuals
	if hv == null:
		return
	_material.set_shader_parameter(&"void_deep_color", hv.void_deep_color)
	_material.set_shader_parameter(&"void_mid_color", hv.void_mid_color)
	_material.set_shader_parameter(&"void_rim_color", hv.void_rim_color)
	_material.set_shader_parameter(&"void_rim_width_cells", hv.void_rim_width_cells)
	_material.set_shader_parameter(&"void_rim_glow", hv.void_rim_glow)
	_material.set_shader_parameter(&"void_swirl_scale", hv.void_swirl_scale)
	_material.set_shader_parameter(&"void_swirl_speed", hv.void_swirl_speed)
	_material.set_shader_parameter(&"void_swirl_twist", hv.void_swirl_twist)
	_material.set_shader_parameter(&"void_band_count", hv.void_band_count)
	_material.set_shader_parameter(&"void_band_softness", hv.void_band_softness)
	_material.set_shader_parameter(&"void_mid_amount", hv.void_mid_amount)
	_material.set_shader_parameter(&"void_animated", 1.0 if _void_animated else 0.0)


func _apply_uv_uniforms(side: int) -> void:
	_material.set_shader_parameter(&"hole_cell_uv", 1.0 / maxf(float(side), 1.0))
	var span: float = maxf(float(side) * _map_def.cell_size, 0.001)
	_material.set_shader_parameter(&"uv_scale", 1.0 / span)
	_material.set_shader_parameter(&"uv_offset", UV_CENTER)


## Bontago-mv0.18 (in-game tuning panel): the public door ui/TuningPanel.gd
## uses to push a live TerritoryVisuals edit onto the shader immediately,
## instead of waiting for the next set_circles() upload (which only ever
## rewrites the analytic-circle-path uniforms, not these -- see that
## function's own comment on why the two are split). Everything
## _apply_visual_uniforms() touches is a pure presentation number
## (TerritoryVisuals' own class doc: "nothing here may change a rule"), so
## calling it again mid-match is always safe. A no-op before configure() has
## built _material (there is nothing yet to refresh).
##
## Bontago-mv0.20b: disk_mesh_segments is baked into the CylinderMesh, not a
## shader uniform, so it needs its own rebuild -- but only when the segment
## count actually changed from what's currently baked (_baked_mesh_segments),
## so an unrelated visuals edit (color, tint, outline...) does not reallocate
## a mesh at raster_upload_hz.
func refresh_visual_uniforms() -> void:
	if _material == null:
		return
	if _visuals.disk_mesh_segments != _baked_mesh_segments:
		rebuild_disk_mesh()
	_apply_visual_uniforms()
	# A wider visual band can reach circles excluded by the last bin upload.
	# Use the exact full loop until the next solve rebuilds its circle bins.
	if _circle_bins_valid and circle_bin_margin() > _circle_bin_baked_margin:
		_circle_bins_valid = false
		_material.set_shader_parameter(&"circle_bins_valid", false)
	_request_bake(_bake_wanted)


func _apply_visual_uniforms() -> void:
	_apply_disc_surface()
	_material.set_shader_parameter(&"base_color", _visuals.disk_base_color)
	_material.set_shader_parameter(&"base_metallic", _visuals.disk_metallic)
	_material.set_shader_parameter(&"base_roughness", _visuals.disk_roughness)
	# Bontago-pt.12 part 2: top-surface brushed/plank grain -- see
	# shaders/territory.gdshader's own top_grain_* uniform DECISION.
	_material.set_shader_parameter(&"top_grain_strength", _visuals.top_grain_strength)
	_material.set_shader_parameter(&"top_grain_scale", _visuals.top_grain_scale)
	_material.set_shader_parameter(&"top_grain_fine_scale", _visuals.top_grain_fine_scale)
	_material.set_shader_parameter(
		&"top_grain_roughness_strength", _visuals.top_grain_roughness_strength
	)
	# Bontago-mp0.3.8: disc top color/sheen fix -- see shaders/territory.
	# gdshader's own disk_sheen_*/disk_diffuse_* uniform DECISION.
	_material.set_shader_parameter(&"disk_ambient_scale", _visuals.disk_ambient_scale)
	_material.set_shader_parameter(&"disk_specular", _visuals.disk_specular)
	_material.set_shader_parameter(&"panel_size_m", _visuals.panel_size_m)
	_material.set_shader_parameter(&"panel_seam_width_px", _visuals.panel_seam_width_px)
	_material.set_shader_parameter(&"panel_seam_strength", _visuals.panel_seam_strength)
	_material.set_shader_parameter(&"panel_variation", _visuals.panel_variation)
	_material.set_shader_parameter(&"panel_fade_px", _visuals.panel_fade_px)
	_material.set_shader_parameter(&"tint_fill_emission", _visuals.tint_fill_emission)
	_material.set_shader_parameter(&"disk_sheen_color", _visuals.disk_sheen_color)
	_material.set_shader_parameter(&"disk_fill_color", _visuals.disk_fill_color)
	_material.set_shader_parameter(&"disk_sky_sheen_color", _visuals.disk_sky_sheen_color)
	_material.set_shader_parameter(&"disk_sky_sheen_strength", _visuals.disk_sky_sheen_strength)
	_material.set_shader_parameter(&"disk_sky_sheen_power", _visuals.disk_sky_sheen_power)
	_material.set_shader_parameter(&"disk_sheen_strength", _visuals.disk_sheen_strength)
	_material.set_shader_parameter(&"disk_sheen_exponent", _visuals.disk_sheen_exponent)
	_material.set_shader_parameter(&"disk_diffuse_response", _visuals.disk_diffuse_response)
	_material.set_shader_parameter(&"disk_diffuse_desaturate", _visuals.disk_diffuse_desaturate)
	_material.set_shader_parameter(&"edge_softness", _visuals.edge_softness)
	# Bontago-xtq.14: pushed here (configure()/refresh_visual_uniforms()),
	# not alongside rim_soft_width/rim_width in set_circles() below, so a
	# freshly configured overlay already renders a crisp boundary before the
	# first 5 Hz circle upload ever runs, exactly like edge_softness (raster)
	# right above it.
	_material.set_shader_parameter(&"edge_softness_m", _visuals.edge_softness_m)
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
	_apply_hole_void_uniforms()
	# Bontago-mp0.3.2: MapDef.MapShape.OVAL's true shape is an ellipse
	# (field_radius in x, field_radius * oval_aspect in z) -- see the
	# shader's own disc_z_scale uniform DECISION for why the vertex shader,
	# not a node Transform, has to do this warp. Every other MapShape keeps a
	# plain circle (1.0), same shape rebuild_disk_mesh() above already draws
	# for them.
	var z_scale: float = 1.0
	if _map_def != null and _map_def.map_shape == MapDef.MapShape.OVAL:
		z_scale = _map_def.oval_aspect
	_material.set_shader_parameter(&"disc_z_scale", z_scale)
	set_slot_colors(_slot_colors)
	_apply_wet()


## Bontago-adt.2: pushes the DiscSurfaceDef texture set (or clears it).
func _apply_disc_surface() -> void:
	var surface: DiscSurfaceDef = _visuals.disc_surface
	var procedural: bool = surface != null and surface.mode == DiscSurfaceDef.Mode.PROCEDURAL
	var textured: bool = surface != null and not procedural and surface.albedo_texture != null
	_material.set_shader_parameter(&"disc_textured", textured)
	_material.set_shader_parameter(&"disc_procedural", procedural)
	_material.set_shader_parameter(&"disc_fine_detail", _disc_fine_detail)
	if procedural:
		_apply_procedural_disc(surface)
	if not textured:
		return
	_material.set_shader_parameter(&"disc_albedo_tex", surface.albedo_texture)
	_material.set_shader_parameter(&"disc_normal_tex", surface.normal_texture)
	_material.set_shader_parameter(&"disc_roughness_tex", surface.roughness_texture)
	_material.set_shader_parameter(&"disc_metalness_tex", surface.metalness_texture)
	_material.set_shader_parameter(&"disc_tile_size_m", surface.tile_size_m)
	_material.set_shader_parameter(&"disc_rotation_deg", surface.rotation_deg)
	_material.set_shader_parameter(&"disc_albedo_strength", surface.albedo_strength)
	_material.set_shader_parameter(&"disc_albedo_gain", surface.albedo_gain)
	_material.set_shader_parameter(&"disc_albedo_contrast", surface.albedo_contrast)
	_material.set_shader_parameter(&"disc_normal_strength", surface.normal_strength)
	_material.set_shader_parameter(&"disc_roughness_min", surface.roughness_min)
	_material.set_shader_parameter(&"disc_roughness_max", surface.roughness_max)
	_material.set_shader_parameter(&"disc_metalness_map_mix", surface.metalness_map_mix)
	_material.set_shader_parameter(&"disc_metalness_scale", surface.metalness_scale)
	_material.set_shader_parameter(&"disc_detail_fade_px", surface.detail_fade_px)


## Bontago-adt.2: pushes DiscSurfaceDef's procedural cel-plating tunables
## (shaders/territory.gdshader disc_proc_* uniforms, see proc_plating()).
func _apply_procedural_disc(surface: DiscSurfaceDef) -> void:
	var params: Dictionary = {
		&"disc_proc_base_tint": surface.proc_base_tint,
		&"disc_proc_hub_radius_m": surface.proc_hub_radius_m,
		&"disc_proc_ring_width_m": surface.proc_ring_width_m,
		&"disc_proc_plate_length_m": surface.proc_plate_length_m,
		&"disc_proc_plate_count_jitter": surface.proc_plate_count_jitter,
		&"disc_proc_split_chance": surface.proc_split_chance,
		&"disc_proc_tone_variation": surface.proc_tone_variation,
		&"disc_proc_hatch_chance": surface.proc_hatch_chance,
		&"disc_proc_hatch_inset_m": surface.proc_hatch_inset_m,
		&"disc_proc_hatch_tone": surface.proc_hatch_tone,
		&"disc_proc_seam_width_px": surface.proc_seam_width_px,
		&"disc_proc_seam_darkness": surface.proc_seam_darkness,
		&"disc_proc_lip_width_px": surface.proc_lip_width_px,
		&"disc_proc_lip_strength": surface.proc_lip_strength,
		&"disc_proc_lip_highlight": surface.proc_lip_highlight,
		&"disc_proc_seam_reflection_occlusion": surface.proc_seam_reflection_occlusion,
		&"disc_proc_rivet_radius_m": surface.proc_rivet_radius_m,
		&"disc_proc_rivet_spacing_m": surface.proc_rivet_spacing_m,
		&"disc_proc_rivet_inset_m": surface.proc_rivet_inset_m,
		&"disc_proc_rivet_row_spacing_m": surface.proc_rivet_row_spacing_m,
		&"disc_proc_rivet_weights": Vector4(
			surface.proc_rivet_weight_none, surface.proc_rivet_weight_pairs,
			surface.proc_rivet_weight_clusters, surface.proc_rivet_weight_rows
		),
		&"disc_proc_rivet_tone": surface.proc_rivet_tone,
		&"disc_proc_rivet_highlight": surface.proc_rivet_highlight,
		&"disc_proc_rivet_shadow": surface.proc_rivet_shadow,
		&"disc_proc_rivet_shade": surface.proc_rivet_shade,
		&"disc_proc_rivet_shadow_offset": surface.proc_rivet_shadow_offset,
		&"disc_proc_highlight_color": surface.proc_highlight_color,
		&"disc_proc_plate_tilt": surface.proc_plate_tilt,
		&"disc_proc_sheen_strength": surface.proc_sheen_strength,
		&"disc_proc_sky_sheen_power": surface.proc_sky_sheen_power,
		&"disc_proc_sky_sheen_weight": surface.proc_sky_sheen_weight,
		&"disc_proc_sheen_exponent": surface.proc_sheen_exponent,
		&"disc_proc_sheen_bands": surface.proc_sheen_bands,
		&"disc_proc_sheen_band_softness": surface.proc_sheen_band_softness,
		&"disc_proc_brush_strength": surface.proc_brush_strength,
		&"disc_proc_brush_scale_m": surface.proc_brush_scale_m,
		&"disc_proc_roughness": surface.proc_roughness,
		&"disc_proc_roughness_variation": surface.proc_roughness_variation,
		&"disc_proc_rivet_fade_height_start_m": surface.proc_rivet_fade_height_start_m,
		&"disc_proc_rivet_fade_height_end_m": surface.proc_rivet_fade_height_end_m,
		&"disc_proc_seam_fade_height_start_m": surface.proc_seam_fade_height_start_m,
		&"disc_proc_seam_fade_height_end_m": surface.proc_seam_fade_height_end_m,
		&"disc_proc_aa_rivet_min_px": surface.proc_aa_rivet_min_px,
		&"disc_proc_aa_plate_min_px": surface.proc_aa_plate_min_px,
		&"disc_proc_brush_fade_px": surface.proc_brush_fade_px,
	}
	for key: StringName in params:
		_material.set_shader_parameter(key, params[key])


## Weather wetness (Bontago-22y.5): `amount` 0..1 adds `sheen_add` to the disc's
## sheen strength and scales its roughness by `roughness_scale` at amount 1.
## Amount 0 is exactly TerritoryVisuals' own values.
func set_wet(amount: float, sheen_add: float, roughness_scale: float, darken: float = 0.0) -> void:
	_wet_amount = clampf(amount, 0.0, 1.0)
	# Dry is one baseline: at amount 0 the stored wet params match a never-wetted overlay
	# (every term is multiplied by the amount, so rendering is identical).
	var dry: bool = _wet_amount <= 0.0
	_wet_sheen_add = 0.0 if dry else sheen_add
	_wet_roughness_scale = 1.0 if dry else roughness_scale
	_wet_darken = 0.0 if dry else darken
	_apply_wet()


## Bontago-mp0.127: the cloud shadow layers on the disc (vfx/CloudShadows.gd). `to_unit_*` map
## world to the layer's unit box, `alpha_*` is its strength; both 0 turns the term off.
func set_cloud_shadows(texture_a: Texture2D, texture_b: Texture2D, to_unit_a: Transform3D, to_unit_b: Transform3D,
		alpha_a: float, alpha_b: float, color: Color) -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"cshadow_tex_a", texture_a)
	_material.set_shader_parameter(&"cshadow_tex_b", texture_b)
	_material.set_shader_parameter(&"cshadow_a_m", to_unit_a)
	_material.set_shader_parameter(&"cshadow_b_m", to_unit_b)
	_material.set_shader_parameter(&"cshadow_a_alpha", alpha_a)
	_material.set_shader_parameter(&"cshadow_b_alpha", alpha_b)
	_material.set_shader_parameter(&"cshadow_color", Vector3(color.r, color.g, color.b))


## Weather fog (Bontago-470.3): the disc shader is `fog_disabled` (the warm
## theme fog once browned the graphite), so it applies the SAME distance fog as
## the Environment itself -- nothing within `begin_m`, `max_strength` at `end_m`,
## toward `color` -- to match the blocks. Amount 0 turns it off exactly.
func set_weather_fog(amount: float, max_strength: float, begin_m: float, end_m: float, color: Color) -> void:
	if _material == null:
		return
	_material.set_shader_parameter(&"wfog_strength", clampf(max_strength * amount, 0.0, 1.0))
	_material.set_shader_parameter(&"wfog_begin", begin_m)
	_material.set_shader_parameter(&"wfog_end", end_m)
	_material.set_shader_parameter(&"wfog_color", color)


func _apply_wet() -> void:
	if _material == null or _visuals == null:
		return
	var add: float = _wet_sheen_add * _wet_amount
	var rough: float = lerpf(1.0, _wet_roughness_scale, _wet_amount)
	_material.set_shader_parameter(&"wet_darken", _wet_darken * _wet_amount)
	_material.set_shader_parameter(&"disk_sheen_strength", _visuals.disk_sheen_strength + add)
	_material.set_shader_parameter(&"base_roughness", clampf(_visuals.disk_roughness * rough, 0.0, 1.0))
	var surface: DiscSurfaceDef = _visuals.disc_surface
	if surface != null:
		_material.set_shader_parameter(&"disc_proc_sheen_strength", surface.proc_sheen_strength + add)
		_material.set_shader_parameter(&"disc_proc_roughness", clampf(surface.proc_roughness * rough, 0.0, 1.0))
		_material.set_shader_parameter(&"disc_roughness_min", clampf(surface.roughness_min * rough, 0.0, 1.0))
		_material.set_shader_parameter(&"disc_roughness_max", clampf(surface.roughness_max * rough, 0.0, 1.0))
