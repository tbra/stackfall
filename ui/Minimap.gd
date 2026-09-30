class_name Minimap
extends PanelContainer
## Top-down minimap for M7 P5 (docs/M7_PLAN.md "P5 -- HUD minimap + reskin"),
## rebuilt for Bontago-mp0.3.3 (owner feedback, feedback/graphics_feedback.md:
## "the minimap especially has a bunch of graphical problems where it's
## reflecting the sky depending on the camera angle").
##
## DECISION (ui/Minimap.gd, Bontago-mp0.3.3): the original M7 P5 design used a
## live orthographic SubViewport + Camera3D looking straight down at the
## shared World3D (docs/M7_ART_DIRECTION.md Q4, owner-selected option (a)).
## In practice that camera also framed game/DiscMirror.gd's planar-reflection
## quad -- a real 3D plane sitting on the disk -- and a top-down camera's own
## viewing angle relative to that mirror plane changes with match state (disk
## tilt, camera height reframing per MapDef), so the mirror sometimes bounced
## sky/cloud color into the minimap and sometimes didn't: exactly the "graphical
## problems ... reflecting the sky depending on the camera angle" report,
## which per-camera Environment overrides (Bontago-xtq.30's earlier fix, see
## this file's git history) could not solve because the mirror itself is a
## reflective 3D surface, not a post-process. This file paints the minimap
## directly from Match's own TerritoryRaster/MapDef/PlayerSlot state -- no
## Camera3D, no SubViewport, so there is no "camera angle" left for it to
## depend on, ever.
##
## DECISION (ui/Minimap.gd, Bontago-mp0.3.3, owner review 2026-09-26): drawn
## **camera-relative** ("up" on the minimap = the main gameplay camera's own
## forward direction, mockup 08's behaviour) rather than the earlier north-up
## choice -- the owner's review compared the overview capture's 3D framing
## (red home on the LEFT) against the minimap (blue on the left) and called
## that out as a mismatch: "the minimap must match what the player sees".
## set_camera_forward() below takes the horizontal (x, z) component of
## whichever Camera3D is `current` and rotates every world-space point into
## screen space around it every rebuild; the default (1, 0)/(0, 1) basis
## (identity, i.e. north-up) is unchanged when nothing ever calls it, which
## keeps tests/unit/test_hud.gd's existing fixtures deterministic. ui/HUD.gd
## is the caller (see its own DECISION on why it reads the camera through
## Viewport.get_camera_3d() rather than a node path/new Events signal).
##
## ui/HUD.gd owns one of these (instanced directly in ui/HUD.tscn, script-
## built rather than its own .tscn) and calls set_map_def() once per match
## (framing) plus set_match_state() every Events.territory_share_changed tick
## (cheap reference stores; the actual per-pixel image rebuild is throttled by
## tuning.minimap_refresh_hz's own Timer below, same cadence the old
## SubViewport had). Stays invisible until the first set_map_def() with a
## non-null MapDef -- a menu/no-match HUD instance renders nothing and costs
## nothing, per the original brief's acceptance check.

@export var tuning: HUDVisualTuning = preload("res://config/hud_visual_tuning.tres")

var _canvas: Control = null
var _refresh_timer: Timer = null

var _map_def: MapDef = null
## Half the meters-wide square the minimap frames, in disk-local space:
## MapDef.field_radius + tuning.minimap_zoom_margin_m. Replaces the old
## Camera3D.size as the thing tests assert framing against.
var _half_extent: float = 1.0
var _field_radius: float = 1.0

## Live match state, refreshed by HUD.gd every territory_share_changed tick
## (see set_match_state()); read back only by the throttled rebuild below.
var _raster: TerritoryRaster = null
var _slot_colors: PackedColorArray = PackedColorArray()
var _home_positions: PackedVector2Array = PackedVector2Array()
## Host and client both expose disk-local gift positions through Match.gift_states().
var _gift_states: Array[Dictionary] = []

## Orthonormal camera-relative basis for the world (x, z) -> minimap (u, v)
## rotation (see class doc DECISION). Defaults to the identity/north-up
## basis; set_camera_forward() below rotates both vectors together so they
## stay perpendicular and unit-length.
var _camera_right: Vector2 = Vector2(1.0, 0.0)
var _camera_forward: Vector2 = Vector2(0.0, 1.0)

## Basis the cached image was rasterized with. The image is rebuilt at
## minimap_refresh_hz, but the basis changes every frame while the camera
## orbits, so _on_canvas_draw() rotates the cached texture by the difference
## (Bontago-sen.5: territory used to lag behind the beacons and the camera).
var _image_right: Vector2 = Vector2(1.0, 0.0)
var _image_forward: Vector2 = Vector2(0.0, 1.0)

## Runs after game/CameraRig.gd (priority 1) and ui/HUD.gd (0), so the basis
## is read from this frame's final camera transform, not the previous one.
const _PROCESS_PRIORITY_AFTER_CAMERA: int = 2

var _image: Image = null
var _texture: ImageTexture = null
## Bontago-1pi.11.9: inputs of the last _rebuild_image(), so the refresh timer can skip an unchanged rebuild.
const NO_BUILD_HASH: int = -1
var _built_raster_hash: int = NO_BUILD_HASH
var _built_colors: PackedColorArray = PackedColorArray()


func _ready() -> void:
	process_priority = _PROCESS_PRIORITY_AFTER_CAMERA
	custom_minimum_size = Vector2(tuning.minimap_size_px, tuning.minimap_size_px)

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = tuning.minimap_backdrop_color
	style.border_color = tuning.minimap_frame_color
	style.set_border_width_all(int(tuning.minimap_frame_border_width_px))
	# A square panel whose corner radius is half its own size renders as a
	# circle -- the minimap's whole circular frame/backdrop, with no separate
	# clip node needed. _rebuild_image() below leaves every off-disk pixel of
	# the drawn image fully transparent, so this circular backdrop is what
	# shows through in the corners.
	style.set_corner_radius_all(int(tuning.minimap_size_px * 0.5))
	add_theme_stylebox_override("panel", style)

	_canvas = Control.new()
	_canvas.name = "MinimapCanvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_canvas_draw)
	add_child(_canvas)

	_image = Image.create(tuning.minimap_size_px, tuning.minimap_size_px, false, Image.FORMAT_RGBA8)
	_texture = ImageTexture.create_from_image(_image)

	_refresh_timer = Timer.new()
	_refresh_timer.name = "RefreshTimer"
	_refresh_timer.one_shot = false
	_refresh_timer.wait_time = _refresh_interval()
	_refresh_timer.timeout.connect(_on_refresh_timeout)
	add_child(_refresh_timer)

	visible = false


## Frames the minimap from `map_def`'s own radius plus tuning.
## minimap_zoom_margin_m, and (re)starts the refresh timer. Passing null
## disables the minimap entirely (no match loaded) -- the menu/no-match state
## the brief requires costs nothing.
func set_map_def(map_def: MapDef) -> void:
	_map_def = map_def
	if map_def == null:
		_raster = null
		_gift_states.clear()
		if _refresh_timer != null:
			_refresh_timer.stop()
		visible = false
		return

	_field_radius = map_def.field_radius
	_half_extent = map_def.field_radius + tuning.minimap_zoom_margin_m
	visible = true
	_refresh_timer.wait_time = _refresh_interval()
	_refresh_timer.start()
	# One immediate render so the minimap shows the new framing right away
	# instead of waiting up to one full refresh interval.
	render_now()


## The live TerritoryRaster/slot colors/home positions to draw, refreshed by
## ui/HUD.gd every Events.territory_share_changed tick. Cheap: stores
## references only (a TerritoryRaster is mutated in place by Match's own
## solve loop, the same live object every other territory reader -- e.g.
## game/TerritoryOverlay.gd -- re-reads each tick), so calling this often is
## exactly as costly as calling it once. `slot_colors`, indexed by team id,
## is `MatchConfig.player_colors` -- the identical array/convention
## game/Main.gd already hands TerritoryOverlay.set_source() and
## game/Field.gd's own shader upload use, so the minimap and the disk itself
## can never disagree about which color a team is.
func set_match_state(
	raster: TerritoryRaster, slot_colors: PackedColorArray, home_positions: PackedVector2Array
) -> void:
	_raster = raster
	_slot_colors = slot_colors
	_home_positions = home_positions


func set_gift_states(states: Array[Dictionary]) -> void:
	_gift_states = states.duplicate(true)
	if _canvas != null and _map_def != null:
		_canvas.queue_redraw()


## The main gameplay camera's own horizontal right/forward directions (world
## x, z of Camera3D.global_transform.basis.x / -basis.z), neither needing to
## be pre-normalized. ui/HUD.gd calls this every frame from whichever
## Camera3D Viewport.get_camera_3d() currently reports (see its own DECISION
## for why it reads the camera that way instead of a node path). Rotates the
## minimap so it always matches what that camera is showing on screen (owner
## review 2026-09-26: "the minimap must match what the player sees"): right
## reads as right, forward as up. DECISION: takes both vectors straight from
## the camera's own basis rather than deriving `right` from `forward` with an
## assumed perpendicular/no-roll rotation -- reading the real basis.x is
## exact for any camera (including the capture tool's own off-axis
## three-quarter framing, tools/capture_mockup08.gd's _frame_overview()) with
## no cross-product sign convention to get wrong. A near-zero vector (no
## camera, or one looking/rolled straight along an axis) is ignored, leaving
## whatever basis was last set.
func set_camera_basis(right_xz: Vector2, forward_xz: Vector2) -> void:
	if right_xz.length_squared() < 0.0001 or forward_xz.length_squared() < 0.0001:
		return
	var new_right: Vector2 = right_xz.normalized()
	var new_forward: Vector2 = forward_xz.normalized()
	if new_right.is_equal_approx(_camera_right) and new_forward.is_equal_approx(_camera_forward):
		return
	_camera_right = new_right
	_camera_forward = new_forward
	if _canvas != null and _map_def != null:
		_canvas.queue_redraw()


func _process(_delta: float) -> void:
	if _map_def == null or not is_inside_tree():
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var basis: Basis = camera.global_transform.basis
	set_camera_basis(Vector2(basis.x.x, basis.x.z), Vector2(-basis.z.x, -basis.z.z))


## Transform mapping a pixel of the cached image (rasterized with the image
## basis) to where it belongs under the current basis, about `center`.
func image_to_current_transform(center: Vector2) -> Transform2D:
	var a: float = _image_right.dot(_camera_right)
	var b: float = _image_forward.dot(_camera_right)
	var d: float = _image_right.dot(_camera_forward)
	var e: float = _image_forward.dot(_camera_forward)
	var rot: Transform2D = Transform2D(Vector2(a, -d), Vector2(-b, e), Vector2.ZERO)
	rot.origin = center - rot.basis_xform(center)
	return rot


## True once a non-null MapDef has been set (i.e. the minimap is actually
## drawing something), false in the menu/no-match state.
func is_active() -> bool:
	return _map_def != null


## Half the meters-wide square the minimap currently frames (MapDef.
## field_radius + tuning.minimap_zoom_margin_m). Exposed for tests so they
## can assert on framing without a 3D camera to read it from.
func half_extent() -> float:
	return _half_extent


## Rebuilds the raster image and redraws immediately. Used by set_map_def()
## (so a fresh framing shows right away) and the refresh Timer below; also a
## test seam (tests/unit/test_hud.gd) so a test can force one rebuild without
## waiting on the Timer.
func render_now() -> void:
	_rebuild_image()
	if _canvas != null:
		_canvas.queue_redraw()


func _refresh_interval() -> float:
	return 1.0 / maxf(tuning.minimap_refresh_hz, 0.001)


func _on_refresh_timeout() -> void:
	if _map_def == null:
		return
	# Bontago-1pi.11.9: the pixel loop in _rebuild_image() costs ~60 ms of
	# GDScript; at minimap_refresh_hz that was an 8 Hz frame hitch even with a
	# completely settled board. DECISION: rebuild only when the image inputs
	# changed. Camera rotation alone is covered by image_to_current_transform()
	# (the cached texture is rotated on draw), so it does not force a rebuild.
	if not _image_inputs_changed():
		return
	render_now()


## True when the raster's owner ids, the team colors or the image size differ
## from what the cached image was last built from.
func _image_inputs_changed() -> bool:
	if _raster == null:
		return _built_raster_hash != NO_BUILD_HASH
	return (
		_raster.ownership_hash() != _built_raster_hash
		or _slot_colors != _built_colors
		or _image == null or _image.get_width() != tuning.minimap_size_px
	)


## World-space (disk-local x, z) -> minimap pixel, through the current
## camera-relative basis (see class doc DECISION and set_camera_forward()).
## `forward` maps to "up" (decreasing py), `right` maps to "right"
## (increasing px), matching how a player reads their own on-screen view.
func _world_to_px(world: Vector2, px_per_m: float) -> Vector2:
	var u: float = world.x * _camera_right.x + world.y * _camera_right.y
	var v: float = world.x * _camera_forward.x + world.y * _camera_forward.y
	return Vector2((u + _half_extent) * px_per_m, (_half_extent - v) * px_per_m)


## Rasterizes the live TerritoryRaster into a small top-down RGBA image,
## camera-relative (see class doc DECISION), entirely in 2D -- no Camera3D/
## SubViewport, so nothing here can ever sample the sky or a 3D mirror. One
## output pixel is one grid-cell lookup (CellGrid.world_to_cell), so the cost
## is tuning.minimap_size_px^2 regardless of the raster's own (usually much
## higher) resolution. Off-disk pixels are left fully transparent so the
## panel's own circular backdrop (see _ready()) shows through and gives the
## minimap its circular silhouette with no separate clip/mask. Each pixel
## walks the *inverse* of _world_to_px() -- from screen (u, v) back to a
## world point -- since that is the direction the loop actually needs (one
## lookup per output pixel, not one per raster cell).
func _rebuild_image() -> void:
	_built_raster_hash = _raster.ownership_hash() if _raster != null else NO_BUILD_HASH
	_built_colors = _slot_colors
	_image_right = _camera_right
	_image_forward = _camera_forward
	var size_px: int = tuning.minimap_size_px
	if _image == null or _image.get_width() != size_px or _image.get_height() != size_px:
		_image = Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	_image.fill(Color(0.0, 0.0, 0.0, 0.0))

	if _raster != null and _half_extent > 0.0:
		var grid: CellGrid = _raster.grid()
		var meters_per_px: float = (_half_extent * 2.0) / float(size_px)
		var unowned: Color = tuning.minimap_backdrop_color
		var sat_boost: float = tuning.minimap_territory_saturation_boost
		var val_boost: float = tuning.minimap_territory_value_boost
		for py: int in range(size_px):
			var v: float = _half_extent - (float(py) + 0.5) * meters_per_px
			for px: int in range(size_px):
				var u: float = (float(px) + 0.5) * meters_per_px - _half_extent
				var world_x: float = u * _camera_right.x + v * _camera_forward.x
				var world_z: float = u * _camera_right.y + v * _camera_forward.y
				var cell: Vector2i = grid.world_to_cell(Vector2(world_x, world_z))
				if not grid.in_bounds(cell.x, cell.y) or not grid.is_in_disk(cell.x, cell.y):
					continue
				var team: int = _raster.team_at(cell.x, cell.y)
				var color: Color = unowned
				if team >= 0 and team < _slot_colors.size():
					var base: Color = _slot_colors[team]
					color = Color.from_hsv(
						base.h, clampf(base.s * sat_boost, 0.0, 1.0), clampf(base.v * val_boost, 0.0, 1.0), base.a
					)
				_image.set_pixel(px, py, color)

	if _texture == null:
		_texture = ImageTexture.create_from_image(_image)
	else:
		_texture.update(_image)


func _on_canvas_draw() -> void:
	if _texture == null or _canvas == null:
		return
	_canvas.draw_set_transform_matrix(image_to_current_transform(_canvas.size * 0.5))
	_canvas.draw_texture_rect(_texture, Rect2(Vector2.ZERO, _canvas.size), false)
	_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_disc_outline()
	_draw_beacons()
	_draw_gifts()


## A falling crate has a parachute-like ring; a landed crate is a filled
## square. Both share the same disk-local point and camera-relative transform.
func _draw_gifts() -> void:
	if _canvas == null or _map_def == null or _half_extent <= 0.0:
		return
	for marker: Dictionary in gift_marker_draw_data():
		var point: Vector2 = marker["pixel"]
		var radius: float = tuning.minimap_gift_radius_px
		if int(marker["phase"]) == MatchGifts.FALLING:
			_canvas.draw_circle(point, radius + 2.0, tuning.minimap_gift_outline_color)
			_canvas.draw_arc(point, radius, 0.0, TAU, 20, tuning.minimap_gift_falling_color, 2.0)
		else:
			var rect: Rect2 = Rect2(point - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
			_canvas.draw_rect(rect.grow(1.0), tuning.minimap_gift_outline_color)
			_canvas.draw_rect(rect, tuning.minimap_gift_landed_color)


## Also a deterministic seam for camera-bearing and lifecycle tests.
func gift_marker_draw_data() -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	if _canvas == null or _map_def == null or _half_extent <= 0.0:
		return markers
	var canvas_width: float = _canvas.size.x if _canvas.size.x > 0.0 else float(tuning.minimap_size_px)
	var px_per_m: float = canvas_width / (_half_extent * 2.0)
	for state: Dictionary in _gift_states:
		var position: Variant = state.get("position")
		var phase: int = int(state.get("phase", -1))
		if not position is Vector2 or not (position as Vector2).is_finite():
			continue
		if phase != MatchGifts.FALLING and phase != MatchGifts.LANDED:
			continue
		var disk_point: Vector2 = position
		if disk_point.length_squared() > _field_radius * _field_radius:
			continue
		markers.append({"id": int(state.get("id", -1)), "phase": phase,
			"pixel": _world_to_px(disk_point, px_per_m)})
	return markers


## Thin stroke at the disk's own field-radius edge (inside the zoom-margin
## padding), so the playable disc's true boundary reads against the darker
## unowned floor drawn around it (owner review 2026-09-26).
func _draw_disc_outline() -> void:
	if _canvas == null or _map_def == null or _half_extent <= 0.0:
		return
	var size_px: float = _canvas.size.x
	if size_px <= 0.0:
		return
	var px_per_m: float = size_px / (_half_extent * 2.0)
	var center: Vector2 = Vector2(size_px, size_px) * 0.5
	_canvas.draw_arc(
		center, _field_radius * px_per_m, 0.0, TAU, 48, tuning.minimap_disc_outline_color, 1.0
	)


## Small team-colored diamond at each slot's home-flag position, echoing
## mockup 08's beacon glyphs (owner review 2026-09-26: diamonds, not circles).
func _draw_beacons() -> void:
	if _canvas == null or _map_def == null or _half_extent <= 0.0:
		return
	var size_px: float = _canvas.size.x
	if size_px <= 0.0:
		return
	var px_per_m: float = size_px / (_half_extent * 2.0)
	var half: float = tuning.minimap_beacon_radius_px
	for i: int in range(_home_positions.size()):
		var point: Vector2 = _world_to_px(_home_positions[i], px_per_m)
		var color: Color = _slot_colors[i] if i < _slot_colors.size() else Color.WHITE
		var diamond: PackedVector2Array = PackedVector2Array([
			point + Vector2(0.0, -half),
			point + Vector2(half, 0.0),
			point + Vector2(0.0, half),
			point + Vector2(-half, 0.0),
		])
		_canvas.draw_colored_polygon(diamond, color)
		var outline: PackedVector2Array = diamond.duplicate()
		outline.append(diamond[0])
		_canvas.draw_polyline(outline, Color(0.0, 0.0, 0.0, 0.6), 1.0, true)


## Test seam (tests/unit/test_hud.gd): the last image render_now() built, so
## a test can assert on actual pixel colors without reaching into private
## state by name.
func debug_image() -> Image:
	return _image
