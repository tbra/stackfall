class_name GhostPreview
extends Node3D
## The non-physics held block (spec 1.4): floats at the height PlayerController
## reports (the disk surface plus hover_height plus the wheel's manual offset,
## never whatever is directly under the cursor), with a projected footprint
## showing what it would land on.
##
## Body: the material is CULL_BACK. With alpha blending and no depth write, back
## faces would let the far shell's coplanar per-cell seams bleed through the near
## face as visible dividers.
##
## Footprint: one polygon for the whole rotated shape (the union of every
## rendered triangle projected to XZ), shown flat on the disc at the height of a
## disk-only raycast that skips placed blocks (matching PlayerController's own
## surface probe), never a tower's top.
##
## Projection prism: the shaft under the shape, from the landing surface up to
## the shape's own underside, not a box around it. Its walls follow the
## silhouette outline and hug the underside piece by piece
## (_build_underside_walls()); where the underside touches the landing surface no
## wall is drawn. The material blends additively and emits light so a surface
## seen through the column brightens. projection_span_y() stays the whole shape's
## top-to-disc span, which PlayerController's spawn clearance reads.
##
## Block decal: _block_projection_decal projects the footprint mask from the
## ghost's underside down to the disc, so a placed block in that gap reads pale.
## Its cull_mask drops TerritoryOverlay.DISC_LAYER_BIT and both fades stay above
## zero: Godot's decal fade is pow(1 - |uv.y|, fade), so a fade of 0 makes a
## surface exactly on the box plane evaluate pow(0, 0) = NaN on the GPU, drawn
## black as a per-pixel speckle.
##
## DECISION (game/player/GhostPreview.gd): _rotated_top_offset() uses the visual mesh's full cube_size (as BlockMeshBuilder.build_mesh() does), not _rotated_bottom_offset()'s cube_margin-shrunk collision half_size, so it matches the rendered extent rather than the slightly smaller physics box.
## DECISION (game/player/GhostPreview.gd): the prism walls come from the rendered silhouette's outline, so yaw-only and pitched or rolled shapes share one algorithm with no per-orientation branch and no cell-grid seams to double-blend.
## DECISION (game/player/GhostPreview.gd): the shaft's top follows the shape's underside piece by piece rather than one whole-shape top, so an S or T piece never shows a shaft rising above its lower cells; the ghost body itself closes the shaft's top, so there is no cap polygon.
## DECISION (game/player/GhostPreview.gd): _accumulate_union() grows one candidate polygon per added triangle rather than a full pairwise fixed point. Every shipped shape's mesh is one connected shell, so a disconnected outline can only come from an enclosed hole, which winds the other way (Geometry2D.is_polygon_clockwise); no shipped shape has one, so that path is untested.
##
## Rotation is stored as an integer index over the 24 axis-aligned cube
## orientations (core/blocks/BlockOrientations.gd) plus a separate free-
## rotation quaternion layered on top. Resetting clears the quaternion and
## sets the index back to 0, so — unlike the original — rotation can never
## drift (spec 1.7, 1.4).
##
## The placement-validity tint (spec 1.5, 1.4):
## player-colour when Match.preview_placement says VALID, red when it says
## OUTSIDE_TERRITORY/CONTESTED/OFF_DISK/EMPTY, and a hatched pattern over a
## HOLE. It also owns the visual side of a rejected placement (spec 1.5's
## "thrown off the map with a visible reject animation") and the auto-drop
## flash — both purely cosmetic; PlayerController decides *when* to play them.
##
## A goal flag's no-build zone (Result.GOAL_ZONE) reads the same as HOLE —
## hatched, hole_tint_color — reusing the existing "can't build here" visual
## language rather than adding a fourth tint state or a new GhostTuning field.
##
## DECISION (game/player/GhostPreview.gd): this node's origin (0, 0, 0) is BlockShape.bottom_center() of the *unrotated* shape (matching BlockFactory's cell offsets) and rotation happens about that fixed origin, so after a 90-degree pitch/roll it is no longer the rotated shape's lowest point. update_placement() corrects for this every frame (_rotated_bottom_offset()), so the shape resting on the cursor's reported height is always the *rotated* one's lowest point.
##
## update_placement() also re-centres this node's XZ so the *rotated* shape's own
## geometric centre (rotated_center_offset()), not the fixed origin, sits over the
## cursor. PlayerController's camera follow tracks rotated_center_world(), so a
## pitch or roll spins the block in place instead of swinging the camera's
## framing. The Y correction is independent: bottom_offset still measures from
## the fixed origin.

const STATE_VALID: StringName = &"valid"
const STATE_INVALID: StringName = &"invalid"
const STATE_HOLE: StringName = &"hole"
const STATE_LOCKED: StringName = &"locked"

const HATCH_TEXTURE_SIZE: int = 32

## Ghost variant of game/blocks/BlockFactory.gd's CELL_GRID_SHADER:
## shaders/blocks/ghost_cell_grid.gdshader, not block_cell_grid.gdshader itself,
## because the ghost needs ALPHA (translucency) and a hatch overlay the shared
## block shader must not gain (see that file's header). It has no `contributing`
## uniform, so the settled/sleeping glow can never reach the ghost.
const GHOST_CELL_GRID_SHADER: Shader = preload("res://shaders/blocks/ghost_cell_grid.gdshader")
## The same BlockVisualTuning resource BlockFactory's VISUAL_TUNING reads, so a
## real block and its ghost always draw identical grid_line_color/grid_line_width_px.
# a static var, not a const: GDScript folds `CONST.prop` reads of a const Resource
# at compile time, which left every F4 edit of this tuning dead.
static var VISUAL_TUNING: BlockVisualTuning = preload("res://config/blocks/tuning/block_visual_tuning.tres")

## The smallest decal fade exponent _update_block_projection_decal() ever
## applies. Not a look tunable (ghost_tuning.block_projection_edge_fade is): a
## structural floor, because a fade of exactly 0.0 makes Godot's
## pow(1 - |uv.y|, fade) evaluate pow(0, 0) (NaN, drawn black) on any surface
## lying exactly on the decal box's top or bottom plane.
const _MIN_DECAL_FADE: float = 0.0001

## The smallest projected (XZ) triangle area, in square meters,
## _collect_rotated_triangles() still unions rather than drops as degenerate -- a
## triangle of the rendered shell that is edge-on to straight-down (an unrotated
## shape's vertical side faces, or any face rotated exactly vertical) projects to
## a zero-width sliver that would feed a near-empty/self-intersecting polygon
## into Geometry2D.merge_polygons.
const _MIN_SILHOUETTE_TRIANGLE_AREA: float = 1e-6

## Geometric tolerances for the underside-hugging prism walls, in meters.
## Structural float tolerances, not look tunables (file consts rather than
## GhostTuning fields, like _MIN_DECAL_FADE): no value in these ranges changes
## how the prism looks, only whether rounding (Geometry2D.merge_polygons'
## fixed-point output, ~1e-5 m) is absorbed.
## How far a split point may sit from an outline edge and still split it, and
## the shortest outline piece kept (a T-junction vertex ending exactly on the
## outline, _edge_split_params()).
const _SILHOUETTE_SPLIT_EPSILON: float = 1e-4
## How far _underside_heights() nudges its probe point off the outline, toward
## the silhouette's interior, so point-in-triangle tests never land exactly on
## the outline (which every neighbouring triangle "contains"). Two orders of
## magnitude above merge_polygons' own rounding, two below a cube.
const _SILHOUETTE_PROBE_INSET: float = 1e-3
## How close the underside may come to the wall bottom before that stretch of
## wall is treated as "the shape sits on the ground here" and not drawn
## (_append_underside_wall()).
## How far below the disc-level wall bottom the per-piece floor probe ray
## reaches, so a hit exactly on the disc still registers.
const _PIECE_FLOOR_RAY_MARGIN: float = 0.05
const _FLOOR_RAY_MAX_SKIPS: int = 3
const _FLOORS_NEVER: int = -1000000
const _FLOOR_RECAST_FRAMES: int = 12
const MASK_CACHE_MAX_ENTRIES: int = 64
const _MASK_KEY_SCALE: float = 1000.0
## Resolution of the block-projection decal's footprint mask.
const FOOTPRINT_MASK_PIXELS_PER_METER: float = 8.0
const FOOTPRINT_MASK_MAX_PIXELS: int = 96
const _MIN_POLYGON_POINTS: int = 3
## Indices of the probe point in _underside_heights()'s result.
const _HEIGHTS_PROBE_X: int = 2
const _HEIGHTS_PROBE_Y: int = 3
const _UNDERSIDE_CONTACT_EPSILON: float = 1e-4

## The group game/player/PlayerController.gd puts its own (local, player-driven)
## ghost in, so ui/hud/HUD.gd can show that block's height
## (height_above_surface()) without a node path. Remote peers' ghosts
## (game/player/RemoteCursors.gd) are never in it.
const LOCAL_HELD_GROUP: StringName = &"local_held_ghost"

## The 8 corner signs of a unit box centred on its own local position, used by
## _rotated_bottom_offset() to find a rotated shape's true lowest point.
const _CORNER_SIGNS: Array[Vector3] = BlockShape.CORNER_SIGNS

@export var tuning: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
@export var ghost_tuning: GhostTuning = preload("res://config/blocks/tuning/ghost_tuning.tres")

var orientation_index: int = 0
var free_quaternion: Quaternion = Quaternion.IDENTITY
## Extra manual raise/lower on top of tuning.hover_height (hover_raise/lower).
var manual_hover_offset: float = 0.0

var _shape: BlockShape = null
var _shape_visual: Node3D = null
## At most one entry: the whole rotated shape's footprint polygon, not one per
## bottom cell. An Array (not a single nullable MeshInstance3D) so
## _set_footprint_quad_count() handles 0 or 1 uniformly.
var _footprint_quads: Array[MeshInstance3D] = []
## Shared by every footprint quad (like _material is shared by every mesh of
## the held shape's own visual) so updating validity/lock state once repaints
## all of them.
var _footprint_material: StandardMaterial3D
## The vertical prism between the held shape's underside and the footprint on
## the disc: a single persistent node whose mesh is rebuilt in place every frame.
var _projection_mesh: MeshInstance3D
var _projection_material: StandardMaterial3D
## The world-space Y span _projection_mesh currently covers (top,
## bottom) -- Vector2.ZERO (and no visible mesh) when nothing is held or the
## prism collapsed (top <= bottom; see _update_footprint()'s own guard).
var _projection_span_y: Vector2 = Vector2.ZERO
## The ghost-local (not world-translated) XZ outline loop(s)
## _shape_silhouette_loops() built the prism walls from last time, plus the exact
## (shape, basis) pair that produced them: a frame that changes neither (the
## player is only moving the cursor) skips re-walking every triangle of the
## rendered mesh and re-running Geometry2D.merge_polygons. Every other input
## _update_projection_mesh() reads each frame (global_position.y, landing_y) only
## changes how high the cached walls are extruded, never their XZ shape, so
## caching on (shape, basis) alone is exact.
var _cached_silhouette_shape: BlockShape = null
var _cached_silhouette_basis: Basis = Basis.IDENTITY
var _cached_silhouette_loops: Array[PackedVector2Array] = []
var _cached_silhouette_valid: bool = false
## The underside-hugging wall list built alongside _cached_silhouette_loops,
## same (shape, basis) cache key. _cached_wall_segments holds consecutive (a, b)
## ghost-local XZ pairs -- every outline edge split wherever a projected mesh
## triangle edge crosses or touches it, so each piece lies under one fixed set of
## triangles -- and _cached_wall_heights holds, per piece, the shape's own
## underside Y at a and at b, *relative to the ghost origin*
## (global_position.y), so a frame that only moves the ghost re-emits these
## quads at a new offset and never re-walks the mesh.
var _cached_wall_segments: PackedVector2Array = PackedVector2Array()
var _cached_wall_heights: PackedVector2Array = PackedVector2Array()
## One ghost-local XZ point per cached wall piece, nudged just inside the
## silhouette, where _update_projection_mesh() casts its straight-down probe so
## each wall stops on whatever (tower top or disc) lies under that piece instead
## of running through placed blocks.
var _cached_wall_probes: PackedVector2Array = PackedVector2Array()
var _floors: PackedFloat64Array = PackedFloat64Array()
var _floors_shape: BlockShape = null
var _floors_position: Vector3 = Vector3.ZERO
var _floors_basis: Basis = Basis.IDENTITY
var _floors_bottom: float = 0.0
var _floors_frame: int = _FLOORS_NEVER
## The last disk-surface point update_placement() received: the fallback landing
## height for _update_footprint() when nothing is under the hull centre (a wide
## shape overhanging the disk's edge). sync_remote_position() never updates it,
## since a remote ghost has no local surface point.
var _last_surface_point: Vector3 = Vector3.ZERO

var _material: ShaderMaterial
var _hatch_texture: ImageTexture
var _player_color: Color = Color.WHITE
var _last_result: PlacementRules.Result = PlacementRules.Result.VALID
## spec 1.4: whether this slot's held piece was released early this interval
## and is now only being aimed/prepared -- see Match.is_release_locked().
## Overrides the validity tint below whenever true, since the lock is about
## *when* the piece may drop, not *where* the ghost sits.
var _locked: bool = false

## Projects ghost_tuning.block_projection_color downward over the footprint
## hull, from the ghost's own current underside down to the disc, so a placed
## block sitting in that gap reads pale/whitish like the disc's footprint marker.
## top_level (like _footprint_quads/_projection_mesh) so it never tilts with the
## ghost's rotation. Persistent: _update_block_projection_decal() rebuilds its
## size/position every frame.
var _block_projection_decal: Decal

var _flash_tween: Tween
var _reject_tween: Tween
## A world-space offset added on top of update_placement()/
## sync_remote_position()'s computed position every frame, animated by
## play_reject_animation()'s kick tween. World-space (not a rotated local offset)
## so the kick direction never depends on the held block's rotation.
var _reject_offset: Vector3 = Vector3.ZERO


## ribbon bands on the generic held crate sit 3% proud of the
## box so they never z-fight with its faces (a draw constant, not a tunable).
const HELD_GIFT_RIBBON_OVERHANG: float = 1.03

func _ready() -> void:
	# A ShaderMaterial (ghost_cell_grid.gdshader) draws the same thin cell-grid
	# lines placed blocks show (BlockFactory's CELL_GRID_SHADER). Its own
	# `render_mode cull_back;` gives the front-faces-only translucency (see the
	# class header).
	_material = ShaderMaterial.new()
	_material.shader = GHOST_CELL_GRID_SHADER
	_material.set_shader_parameter(&"grid_line_width_px", VISUAL_TUNING.grid_line_width_px)
	_material.set_shader_parameter(&"grid_line_color", VISUAL_TUNING.grid_line_color)
	_material.set_shader_parameter(&"cell_ao_strength", VISUAL_TUNING.cell_ao_strength)
	_material.set_shader_parameter(&"cell_ao_height", VISUAL_TUNING.cell_ao_height)

	_footprint_material = StandardMaterial3D.new()
	_footprint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_footprint_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_footprint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# The footprint quad is a near-ground-parallel decal seen at a shallow
	# grazing angle; anisotropic filtering, on top of _build_hatch_texture()'s
	# mipmaps, keeps the HOLE/GOAL_ZONE hatch stripes from re-aliasing. Other
	# states never assign albedo_texture (_apply_footprint_material()).
	_footprint_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	# The flat footprint is CULL_DISABLED (a flat quad viewed from above). The
	# prism walls are too: their outline has no internal face seams to bleed
	# through, and the far wall reading faintly through the near one is intended.
	_projection_material = StandardMaterial3D.new()
	_projection_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_projection_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_projection_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Additive blending sums the prism's colour onto whatever already rendered
	# behind it, so a surface seen through the column reads brighter, not just
	# tinted. _apply_projection_material() drives the emission colour and
	# ghost_tuning.projection_emission_energy every refresh.
	_projection_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_projection_material.emission_enabled = true

	_projection_mesh = MeshInstance3D.new()
	_projection_mesh.material_override = _projection_material
	_projection_mesh.top_level = true
	_projection_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_projection_mesh)

	# A plain opaque white texture: Decal has no flat-colour mode, so `modulate`
	# tints and fades it (see _update_block_projection_decal()). A tiny 2x2 image
	# is enough, since it is only stretched across size.x/size.z.
	_block_projection_decal = Decal.new()
	_block_projection_decal.texture_albedo = _build_white_decal_texture()
	_block_projection_decal.upper_fade = _decal_fade()
	_block_projection_decal.lower_fade = _decal_fade()
	# Never paint the disc: TerritoryOverlay keeps it on DISC_LAYER_BIT alone and
	# it has its own footprint quad, so dropping that bit from Decal's default
	# cull_mask leaves placed blocks (layer 1) painted.
	_block_projection_decal.cull_mask = _block_projection_decal.cull_mask & ~TerritoryOverlay.DISC_LAYER_BIT
	_block_projection_decal.top_level = true
	_block_projection_decal.visible = false
	add_child(_block_projection_decal)

	_hatch_texture = _build_hatch_texture()
	_material.set_shader_parameter(&"hatch_texture", _hatch_texture)
	_refresh_materials()


func set_shape(shape: BlockShape) -> void:
	_shape = shape
	if _shape_visual != null:
		_shape_visual.queue_free()
		_shape_visual = null
	# A new shape invalidates the cached silhouette outline; a stale
	# _shape_visual would leave _collect_rotated_triangles() reading freed nodes.
	_cached_silhouette_valid = false
	if shape == null:
		return
	_shape_visual = BlockFactory.build_visual_only(shape, tuning)
	add_child(_shape_visual)
	_apply_material_to_visual()
	_rebuild_gift_visual()


## while the current piece is a gift the ghost shows a gift
## presentation (SpecialDef.held_scene, else a generic crate) INSTEAD of the
## plain block mesh. The block meshes stay in _shape_visual (hidden) because
## the footprint/projection silhouette is built from them; only visibility
## changes. Pass &"" to return to the plain block ghost.
const GIFT_VISUAL_NAME: StringName = &"HeldGift"
var _held_gift_id: StringName = &""
var _gift_visual: Node3D = null


func set_held_gift(special_id: StringName) -> void:
	_held_gift_id = special_id
	if special_id != &"":
		# gifts always show and spawn upright.
		reset_rotation()
	_rebuild_gift_visual()
	_apply_projection_visibility()


## DECISION: a held gift is not a drop-and-stack block, so the
## placement projection (landing footprint, light-shaft prism, block decal) is
## hidden entirely -- no landing marker stays. Only visibility changes; the
## footprint/span bookkeeping PlayerController reads is untouched.
func _apply_projection_visibility() -> void:
	var show_projection: bool = _held_gift_id == &""
	for quad: MeshInstance3D in _footprint_quads:
		quad.visible = show_projection
	if _projection_mesh != null:
		_projection_mesh.visible = show_projection
	if _block_projection_decal != null and not show_projection:
		_block_projection_decal.visible = false


func _rebuild_gift_visual() -> void:
	_stop_held_facing()
	if _gift_visual != null:
		_gift_visual.queue_free()
		_gift_visual.get_parent().remove_child(_gift_visual)
		_gift_visual = null
	var show_gift: bool = _held_gift_id != &"" and _shape != null
	if _shape_visual != null:
		for child: Node in _shape_visual.get_children():
			var mesh_instance: MeshInstance3D = child as MeshInstance3D
			if mesh_instance != null:
				mesh_instance.visible = not show_gift
	if not show_gift:
		return
	# Codex GLB first, then the older held scene.
	_gift_visual = GiftModelTable.shared().build_gift_visual(_held_gift_id)
	var def: SpecialDef = SpecialDef.find_by_id(_held_gift_id)
	if _gift_visual == null and def != null and def.held_scene != null:
		_gift_visual = def.held_scene.instantiate() as Node3D
	if _gift_visual == null:
		_gift_visual = build_fallback_gift_visual(tuning.cube_size)
	_gift_visual.name = GIFT_VISUAL_NAME
	# Centre on the shape's bounds, in the ghost's unrotated frame (the ghost
	# basis rotates it together with the block).
	_gift_visual.position = BlockFactory.gift_cell_center(_shape, tuning)
	add_child(_gift_visual)
	_apply_gift_tint()
	_setup_held_facing()


## a gift whose table row has a held_nose_axis (Rocket, Magnet) is shown with
## that axis pointing along the aim/launch direction, not standing upright. PlayerController
## pushes the real direction via set_held_aim(); with none (remote ghosts) the horizontal
## camera forward is used, refreshed every frame. The turn is applied to the gift visual only.
## Shortest aim vector treated as a direction (a blend guard, not a tunable).
const MIN_AIM_LENGTH: float = 0.0001
var _held_nose_axis: Vector3 = Vector3.ZERO
var _held_keep_upright: bool = false
var _held_aim: Vector3 = Vector3.ZERO


func set_held_aim(direction: Vector3) -> void:
	_held_aim = direction.normalized() if direction.length() > MIN_AIM_LENGTH else Vector3.ZERO
	_refresh_held_facing()


## World AABB of the held gift model's meshes (zero-size AABB when no gift visual is shown):
## the arc preview starts at its centre.
func gift_visual_world_aabb() -> AABB:
	var merged: AABB = AABB()
	if _gift_visual == null or not _gift_visual.is_inside_tree():
		return merged
	var first: bool = true
	for node: Node in _gift_visual.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		merged = box if first else merged.merge(box)
		first = false
	if first:
		merged = AABB(_gift_visual.global_position, Vector3.ZERO)
	return merged


func _setup_held_facing() -> void:
	var entry: GiftModelEntry = GiftModelTable.shared().entry_for(_held_gift_id)
	_held_nose_axis = entry.held_nose_axis if entry != null else Vector3.ZERO
	_held_keep_upright = entry != null and entry.held_keep_upright
	if _held_nose_axis == Vector3.ZERO:
		return
	var tree: SceneTree = get_tree()
	if tree != null and not tree.process_frame.is_connected(_refresh_held_facing):
		tree.process_frame.connect(_refresh_held_facing)
	_refresh_held_facing()


func _stop_held_facing() -> void:
	_held_nose_axis = Vector3.ZERO
	var tree: SceneTree = get_tree()
	if tree != null and tree.process_frame.is_connected(_refresh_held_facing):
		tree.process_frame.disconnect(_refresh_held_facing)


func _refresh_held_facing() -> void:
	if _gift_visual == null or _held_nose_axis == Vector3.ZERO or not is_inside_tree():
		return
	var direction: Vector3 = _held_aim
	if direction == Vector3.ZERO:
		var camera: Camera3D = get_viewport().get_camera_3d() if get_viewport() != null else null
		if camera == null:
			return
		var flat: Vector3 = -camera.global_transform.basis.z
		flat.y = 0.0
		if flat.length() < MIN_AIM_LENGTH:
			return
		direction = flat.normalized()
	var facing: Basis = FlightFacing.nose_basis(_held_nose_axis, direction)
	if _held_keep_upright:
		facing = FlightFacing.upright_nose_basis(_held_nose_axis, direction)
	_gift_visual.basis = global_basis.inverse() * facing


## A held gift is shown exactly as authored in every ghost state: no tint
## overlay and no glow rim, which read as a white tint. Validity/lock state still
## shows in the footprint and the HUD, not by recolouring.
func _apply_gift_tint() -> void:
	if _gift_visual == null:
		return
	for node: Node in _gift_visual.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_overlay = null


## Generic gift look (GiftCrate's crate + ribbon colours), one cell in size.
static func build_fallback_gift_visual(cell_size: float) -> Node3D:
	var root: Node3D = Node3D.new()
	var box_size: Vector3 = Vector3.ONE * cell_size
	var body: MeshInstance3D = _fallback_box(box_size, GiftCrate.LID_COLOR)
	body.name = &"Body"
	root.add_child(body)
	var ribbon_x: MeshInstance3D = _fallback_box(
		Vector3(box_size.x * HELD_GIFT_RIBBON_OVERHANG, box_size.y * HELD_GIFT_RIBBON_OVERHANG, box_size.z * GiftCrate.RIBBON_WIDTH / GiftCrate.CRATE_SIZE.z), GiftCrate.RIBBON_COLOR)
	ribbon_x.name = &"RibbonX"
	root.add_child(ribbon_x)
	var ribbon_z: MeshInstance3D = _fallback_box(
		Vector3(box_size.x * GiftCrate.RIBBON_WIDTH / GiftCrate.CRATE_SIZE.x, box_size.y * HELD_GIFT_RIBBON_OVERHANG, box_size.z * HELD_GIFT_RIBBON_OVERHANG), GiftCrate.RIBBON_COLOR)
	ribbon_z.name = &"RibbonZ"
	root.add_child(ribbon_z)
	return root


static func _fallback_box(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh_instance


func get_shape() -> BlockShape:
	return _shape


func set_orientation_index(index: int) -> void:
	# a held gift is never rotated by its owner.
	if _held_gift_id != &"":
		return
	orientation_index = ((index % BlockOrientations.ORIENTATION_COUNT) + BlockOrientations.ORIENTATION_COUNT) % BlockOrientations.ORIENTATION_COUNT
	_apply_rotation()


func reset_rotation() -> void:
	orientation_index = 0
	free_quaternion = Quaternion.IDENTITY
	_apply_rotation()


## Spins the block while rotate_drag (MMB) is held: `yaw` about world up,
## `pitch` about `pitch_axis` (PlayerController passes the camera's world-space
## right axis, so pushing the mouse forward tips the block away from the player
## whichever way the camera faces). Each axis composes onto free_quaternion
## independently (`Quaternion(axis, angle) * free_quaternion`, normalised), so a
## frame with only one axis of motion never nudges the other. free_quaternion is
## the field submit_cursor/submit_place already send unmodified.
func apply_free_rotation_delta(yaw: float, pitch: float, pitch_axis: Vector3 = Vector3.RIGHT) -> void:
	if _held_gift_id != &"":
		return
	if yaw != 0.0:
		free_quaternion = (Quaternion(Vector3.UP, yaw) * free_quaternion).normalized()
	if pitch != 0.0:
		free_quaternion = (Quaternion(pitch_axis, pitch) * free_quaternion).normalized()
	_apply_rotation()


func _apply_rotation() -> void:
	var base_basis: Basis = BlockOrientations.get_basis(orientation_index)
	basis = Basis(free_quaternion) * base_basis


## Called every frame by PlayerController with the disk surface point/normal
## straight under the cursor (a raycast that skips placed blocks, so this is
## always the bare disk). Positions the ghost so the *rotated* held shape's
## lowest point sits at hover height above that surface (Y only), and so the
## *rotated* shape's own geometric centre column sits over the cursor's XZ (see
## rotated_center_offset()), then refreshes the footprint projection.
func update_placement(surface_point: Vector3, surface_normal: Vector3) -> void:
	var hover: float = tuning.hover_height + manual_hover_offset
	var anchor: Vector3 = surface_point + surface_normal * hover
	var bottom_offset: float = _rotated_bottom_offset()
	var center_offset: Vector3 = rotated_center_offset()
	global_position = Vector3(
		anchor.x - center_offset.x, anchor.y - bottom_offset, anchor.z - center_offset.z
	) + _reject_offset
	_last_surface_point = surface_point
	_update_footprint()


## How high the held shape's own lowest point hovers above the disk surface
## under it (the point update_placement() last received), in meters -- what the
## player adjusts with the wheel. The HUD shows this next to the tower height,
## which alone never moves while the block is raised.
func height_above_surface() -> float:
	return global_position.y - _reject_offset.y + _rotated_bottom_offset() - _last_surface_point.y


## Positions this ghost at an already-fully-resolved world point, with no
## further hover/rotation-pivot math -- used by game/player/RemoteCursors.gd for a
## synced remote peer's ghost, whose `origin` is that peer's own already-adjusted
## GhostPreview.global_position (spec 2.6's update_cursor carries a resolved pose,
## not a surface to re-derive one from). Going through update_placement() would
## apply the hover/rotated-bottom correction a second time.
func sync_remote_position(origin: Vector3) -> void:
	global_position = origin + _reject_offset
	_update_footprint()


# --- Rotated-bottom pivot correction ------

## How far below this node's own local origin (BlockShape.bottom_center() of
## the *unrotated* shape) the current, rotated shape's lowest point sits.
## Zero for an unrotated shape (the origin already is its lowest point); a
## 90-degree pitch/roll can put the true lowest point below (or, for a
## symmetric shape, level with) the origin, never above it, since the origin
## itself is always a point on the shape's own surface. Always <= 0.
func _rotated_bottom_offset() -> float:
	if _shape == null:
		return 0.0
	return _shape.rotated_bottom_offset(basis, tuning.cube_size, tuning.cube_margin)


## The mirror image of _rotated_bottom_offset(): how far *above* this node's own
## local origin the rotated shape's *highest* point sits, the prism's top for
## projection_span_y(). Always >= 0 for the same reason
## _rotated_bottom_offset() is always <= 0: the origin itself is always a point
## on the shape's own surface.
## DECISION (game/player/GhostPreview.gd): uses the *visual* mesh's own full cube_size (`half_size = tuning.cube_size * 0.5`, matching BlockMeshBuilder.build_mesh()), not _rotated_bottom_offset()'s cube_margin-shrunk collision half_size, so the top matches the rendered shape's true extent, not the slightly smaller physics box.
func _rotated_top_offset() -> float:
	if _shape == null or _shape.cells.is_empty():
		return 0.0
	var half_size: float = tuning.cube_size * 0.5
	var max_y: float = -INF
	for local: Vector3 in _shape.cell_centres(tuning.cube_size):
		for corner_sign: Vector3 in _CORNER_SIGNS:
			var corner: Vector3 = local + corner_sign * half_size
			var rotated_y: float = (basis * corner).y
			max_y = maxf(max_y, rotated_y)
	return 0.0 if max_y == -INF else max_y


## How far this node's own local origin (still BlockShape.bottom_center() of the
## *unrotated* shape) sits from the *rotated* held shape's own geometric centre,
## in world space. The unrotated centre-to-origin vector is purely vertical (the
## AABB centre of `cells` shares bottom_center()'s X/Z), so a yaw-only rotation
## never moves this in XZ, while a pitch/roll tips that vertical offset sideways
## exactly as update_placement() needs to keep the *rotated* shape's centre under
## the cursor. Zero for a shape with no cells and when nothing is held.
func rotated_center_offset() -> Vector3:
	if _shape == null or _shape.cells.is_empty():
		return Vector3.ZERO
	return _shape.rotated_center_offset(basis, tuning.cube_size)


## The rotated held shape's own geometric centre, in world space -- what
## game/player/CameraRig.gd's follow target should track instead of this node's own
## origin (see rotated_center_offset()'s doc comment) so orbiting/pitching the
## block spins it in place instead of visibly swinging the camera's framing.
## Falls back to global_position itself (rotated_center_offset() is then
## Vector3.ZERO) when nothing is held, so callers never need a null check.
func rotated_center_world() -> Vector3:
	return global_position + rotated_center_offset()


# --- Footprint projection (spec 1.4) --

## The *whole* rotated held shape's own convex hull, projected onto the XZ
## plane, ghost-local (not yet world-translated): every cell's own 8 corners
## (BlockFactory's cube_size/cube_margin box, same pivot) go through the full
## rotation basis, get projected to (x, z), and the convex hull of *all* of them
## together is the one footprint polygon, not one hull per cell: a shape's
## silhouette from directly above is one shape, however many landing heights are
## underneath different parts of it.
func _rotated_shape_hull() -> PackedVector2Array:
	if _shape == null or _shape.cells.is_empty():
		return PackedVector2Array()
	var half_size: float = (tuning.cube_size - tuning.cube_margin) * 0.5
	var points: PackedVector2Array = PackedVector2Array()
	for local_center: Vector3 in _shape.cell_centres(tuning.cube_size):
		for corner_sign: Vector3 in _CORNER_SIGNS:
			var rotated_corner: Vector3 = basis * (local_center + corner_sign * half_size)
			points.append(Vector2(rotated_corner.x, rotated_corner.z))
	return Geometry2D.convex_hull(points)


## Rebuilds the footprint quad (0 or 1 -- see _rotated_shape_hull()) and the
## vertical projection prism to match the current shape/rotation. The landing
## height comes from a disk-only raycast (_raycast_disk_surface(), skipping any
## placed RigidBody3D, like PlayerController's own surface probe) straight down
## from the hull's centroid, so the marker lands on the bare disc even when part
## of the held shape hovers over a placed block, never that block's top face. If
## nothing is under the centroid (a wide shape overhanging the disk's edge), it
## falls back to _last_surface_point rather than leaving the marker with no
## floor.
func _update_footprint() -> void:
	var hull: PackedVector2Array = _rotated_shape_hull()
	if hull.size() < 3:
		_set_footprint_quad_count(0)
		_clear_projection_mesh()
		_hide_block_projection_decal()
		return

	_set_footprint_quad_count(1)

	var centroid: Vector2 = _polygon_centroid(hull)
	var world_x: float = global_position.x + centroid.x
	var world_z: float = global_position.z + centroid.y
	var probe_origin: Vector3 = Vector3(world_x, ghost_tuning.cursor_ray_height, world_z)
	var hit: Dictionary = _raycast_disk_surface(probe_origin)
	var landing_y: float
	var landing_normal: Vector3
	if hit.is_empty():
		landing_y = _last_surface_point.y
		landing_normal = Vector3.UP
	else:
		landing_y = (hit["position"] as Vector3).y
		landing_normal = hit["normal"] as Vector3

	_footprint_quads[0].global_position = Vector3(world_x, landing_y, world_z) + landing_normal * ghost_tuning.footprint_offset
	# The quad follows the rendered silhouette (the union of every cell's
	# footprint), so concave shapes (plus5, u5, corner4...) don't show their
	# convex hull. The hull stays the bounding/test polygon.
	var footprint_mesh: ArrayMesh = _build_loops_mesh(_shape_silhouette_loops(), centroid)
	_footprint_quads[0].mesh = footprint_mesh if footprint_mesh != null else _build_polygon_mesh(hull, centroid)
	var world_hull: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in hull:
		world_hull.append(Vector2(global_position.x + point.x, global_position.z + point.y))

	_update_projection_mesh(landing_y)
	_update_block_projection_decal(world_hull, landing_y)
	_apply_projection_visibility()


## `_projection_span_y` is the *whole* shape's bookkeeping (top =
## _rotated_top_offset(); PlayerController's spawn clearance reads this
## contract), while the mesh walls the merged rendered silhouette
## (_shape_silhouette_loops()) from a shared wall_bottom_y up to the shape's own
## underside along the outline (the cached pieces from _build_underside_walls(),
## re-emitted at this frame's height). The prism collapses when the whole shape's
## top is within ghost_tuning.footprint_offset of the disc, or below it; a shape
## resting on the ground draws no wall at all (no mesh, though
## projection_span_y() still reports the body).
func _update_projection_mesh(landing_y: float) -> void:
	if _shape == null or _shape.cells.is_empty():
		_clear_projection_mesh()
		return

	var whole_top_y: float = global_position.y + _rotated_top_offset()
	if whole_top_y - landing_y <= ghost_tuning.footprint_offset:
		# The whole shape's own top is at or below the ground -- nothing to
		# show; keeps projection_span_y()'s "Vector2.ZERO when collapsed"
		# contract.
		_clear_projection_mesh()
		return

	var loops: Array[PackedVector2Array] = _shape_silhouette_loops()
	if loops.is_empty():
		_clear_projection_mesh()
		return

	_projection_span_y = Vector2(whole_top_y, landing_y)
	_projection_mesh.global_position = Vector3(global_position.x, 0.0, global_position.z)

	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()

	# Every wall bottoms out ghost_tuning.footprint_offset above `landing_y`, the
	# same epsilon the footprint quad uses above the disc, so the wall's
	# ground-contact edge never Z-fights the disc's collision mesh at `landing_y`.
	var wall_bottom_y: float = landing_y + ghost_tuning.footprint_offset
	# Re-emit the cached underside walls at this frame's own height -- the only
	# per-frame work (see _cached_wall_heights' own doc comment).
	var origin_y: float = global_position.y
	var floors: PackedFloat64Array = _piece_floors(wall_bottom_y)
	for i: int in range(_cached_wall_heights.size()):
		var heights: Vector2 = _cached_wall_heights[i]
		# Stop each piece on whatever is under it (a placed tower's top face,
		# which the block-projection decal paints), not the disc, so the
		# additive wall never runs through placed blocks.
		var piece_bottom_y: float = floors[i]
		_append_underside_wall(
			_cached_wall_segments[i * 2], _cached_wall_segments[i * 2 + 1],
			origin_y + heights.x, origin_y + heights.y, piece_bottom_y,
			verts, normals, uvs, indices
		)

	if verts.is_empty():
		# The shape rests on the ground along its whole outline -- no shaft to
		# draw. _projection_span_y is kept (spawn clearance still needs the body's
		# own top).
		_projection_mesh.mesh = null
		return

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var built: ArrayMesh = ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_projection_mesh.mesh = built


## Per-piece wall floors (world Y). Re-cast only when the ghost pose, wall set or
## disc-level floor changed, or every _FLOOR_RECAST_FRAMES physics frames (a
## tower may have grown), so a held still ghost costs no rays.
func _piece_floors(wall_bottom_y: float) -> PackedFloat64Array:
	var frame: int = Engine.get_physics_frames()
	if _floors_shape == _shape and _floors_position.is_equal_approx(global_position) \
			and _floors_basis.is_equal_approx(basis) and is_equal_approx(_floors_bottom, wall_bottom_y) \
			and _floors.size() == _cached_wall_heights.size() and frame - _floors_frame < _FLOOR_RECAST_FRAMES:
		return _floors
	_floors_shape = _shape
	_floors_position = global_position
	_floors_basis = basis
	_floors_bottom = wall_bottom_y
	_floors_frame = frame
	_floors = PackedFloat64Array()
	for i: int in range(_cached_wall_heights.size()):
		var heights: Vector2 = _cached_wall_heights[i]
		_floors.append(_piece_floor_y(_cached_wall_probes[i], global_position.y + minf(heights.x, heights.y), wall_bottom_y))
	return _floors


## World Y the wall piece probed at ghost-local `probe` should stop at: the
## first settled collider (placed sleeping block or disc; loose/falling blocks
## are skipped so the bottom never flickers; gifts are Areas and never hit)
## straight below `from_y`, plus footprint_offset against z-fighting, never
## lower than `floor_y` (the disc-level wall bottom).
func _piece_floor_y(probe: Vector2, from_y: float, floor_y: float) -> float:
	if not is_inside_tree() or from_y <= floor_y:
		return floor_y
	var world: World3D = get_world_3d()
	if world == null:
		return floor_y
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	if space_state == null:
		return floor_y
	var origin: Vector3 = Vector3(global_position.x + probe.x, from_y, global_position.z + probe.y)
	var exclude: Array[RID] = []
	for _attempt: int in range(_FLOOR_RAY_MAX_SKIPS + 1):
		var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			origin, Vector3(origin.x, floor_y - _PIECE_FLOOR_RAY_MARGIN, origin.z)
		)
		params.collision_mask = Field.PLACEMENT_QUERY_MASK
		params.exclude = exclude
		var hit: Dictionary = space_state.intersect_ray(params)
		if hit.is_empty():
			return floor_y
		var body: RigidBody3D = hit["collider"] as RigidBody3D
		if body != null and not body.sleeping:
			exclude.append(hit["rid"] as RID)
			continue
		return maxf(floor_y, (hit["position"] as Vector3).y + ghost_tuning.footprint_offset)
	return floor_y


## Hides the projection prism (nothing held, or it collapsed -- see
## _update_projection_mesh()'s own guard) without freeing the persistent node.
func _clear_projection_mesh() -> void:
	_projection_span_y = Vector2.ZERO
	if _projection_mesh != null:
		_projection_mesh.mesh = null


# --- Block projection decal (spec 1.4) ----------------------

## Sizes and positions `_block_projection_decal` over `world_hull`'s bounding box
## (world-space X/Z, the same hull _update_footprint() built the flat footprint
## from), projecting straight down from the ghost's current underside
## (_rotated_bottom_offset() -- deliberately not any higher, so the decal's
## volume never overlaps the held ghost's rendered body) down to `landing_y`.
## The disc lives on TerritoryOverlay.DISC_LAYER_BIT and _ready() strips that bit
## from the decal's cull_mask: painting the disc speckled it.
func _update_block_projection_decal(world_hull: PackedVector2Array, landing_y: float) -> void:
	if _block_projection_decal == null:
		return
	var top_y: float = global_position.y + _rotated_bottom_offset()
	if top_y - landing_y <= 0.001:
		_hide_block_projection_decal()
		return

	var min_point: Vector2 = world_hull[0]
	var max_point: Vector2 = world_hull[0]
	for point: Vector2 in world_hull:
		min_point = Vector2(minf(min_point.x, point.x), minf(min_point.y, point.y))
		max_point = Vector2(maxf(max_point.x, point.x), maxf(max_point.y, point.y))
	var size_x: float = maxf(max_point.x - min_point.x, 0.01)
	var size_z: float = maxf(max_point.y - min_point.y, 0.01)
	var center_x: float = (min_point.x + max_point.x) * 0.5
	var center_z: float = (min_point.y + max_point.y) * 0.5

	_block_projection_decal.visible = true
	_apply_decal_footprint_mask(
		Vector2(min_point.x - global_position.x, min_point.y - global_position.z), Vector2(size_x, size_z)
	)
	_block_projection_decal.upper_fade = _decal_fade()
	_block_projection_decal.lower_fade = _decal_fade()
	_block_projection_decal.normal_fade = ghost_tuning.block_projection_normal_fade
	_block_projection_decal.size = Vector3(size_x, top_y - landing_y, size_z)
	_block_projection_decal.global_position = Vector3(center_x, (top_y + landing_y) * 0.5, center_z)
	_block_projection_decal.modulate = Color(
		ghost_tuning.block_projection_color.r, ghost_tuning.block_projection_color.g,
		ghost_tuning.block_projection_color.b, ghost_tuning.block_projection_alpha
	)


## ghost_tuning.block_projection_edge_fade, never below _MIN_DECAL_FADE (see that
## constant for why zero is unsafe).
func _decal_fade() -> float:
	return maxf(ghost_tuning.block_projection_edge_fade, _MIN_DECAL_FADE)


## Hides the block-projection decal (nothing held, or the gap collapsed --
## see _update_block_projection_decal()'s own guard) without freeing the
## persistent node -- same idea as _clear_projection_mesh() just above.
func _hide_block_projection_decal() -> void:
	if _block_projection_decal != null:
		_block_projection_decal.visible = false


## A plain, fully-opaque white 2x2 texture -- Decal.texture_albedo needs a
## real Texture2D, and this project has no flat-colour art asset to spend on
## something `modulate` (see _update_block_projection_decal()) already tints
## and fades on its own; same runtime-built-texture idea as _build_hatch_
## texture() below.
func _build_white_decal_texture() -> ImageTexture:
	if _white_texture == null:
		var image: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
		image.fill(Color(1.0, 1.0, 1.0, 1.0))
		_white_texture = ImageTexture.create_from_image(image)
	return _white_texture


## The projection prism's outline loop(s) in ghost-local XZ -- the *rendered*
## shape's true silhouette from directly above, at the current rotation. Cached
## on (`_shape`, `basis`); see _cached_silhouette_loops' own doc comment for why
## that is exact for every other input _update_projection_mesh() reads. The same
## cache fill also builds the underside wall list (_build_underside_walls()), so
## a cache hit covers both.
func _shape_silhouette_loops() -> Array[PackedVector2Array]:
	if _shape == null or _shape_visual == null:
		return []
	if _cached_silhouette_valid and _cached_silhouette_shape == _shape \
			and _cached_silhouette_basis.is_equal_approx(basis):
		return _cached_silhouette_loops
	var triangles_3d: Array[PackedVector3Array] = _collect_rotated_triangles()
	var triangles_2d: Array[PackedVector2Array] = []
	for triangle: PackedVector3Array in triangles_3d:
		triangles_2d.append(_flatten_triangle(triangle))
	var loops: Array[PackedVector2Array] = []
	for triangle: PackedVector2Array in triangles_2d:
		loops = _accumulate_union(loops, triangle)
	_build_underside_walls(loops, triangles_3d, triangles_2d)
	_cached_silhouette_shape = _shape
	_cached_silhouette_basis = basis
	_cached_silhouette_loops = loops
	_cached_silhouette_valid = true
	return loops


## Every triangle of every MeshInstance3D under _shape_visual (in the common
## case BlockFactory's single BlockMeshBuilder shell; the sloped-cell/custom-mesh
## fallback is walked the same way, one MeshInstance3D per cell with its own
## local `.position` offset), each vertex transformed by the ghost's current
## rotation `basis` (matching _rotated_bottom_offset()/_rotated_top_offset()'s
## corner math), in ghost-local 3D (each Y is a height relative to
## global_position.y). Triangles whose XZ projection is degenerate (near-zero
## area, e.g. a vertical face at identity rotation) are dropped -- see
## _MIN_SILHOUETTE_TRIANGLE_AREA; such a triangle also has no well-defined plane
## height over XZ for _underside_heights() to read.
func _collect_rotated_triangles() -> Array[PackedVector3Array]:
	var triangles: Array[PackedVector3Array] = []
	for child: Node in _shape_visual.get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var local_offset: Vector3 = mesh_instance.position
		var mesh: Mesh = mesh_instance.mesh
		for surface: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
			if indices.is_empty():
				indices = _sequential_indices(verts.size())
			for i: int in range(0, indices.size() - 2, 3):
				var triangle: PackedVector3Array = PackedVector3Array([
					basis * (local_offset + verts[indices[i]]),
					basis * (local_offset + verts[indices[i + 1]]),
					basis * (local_offset + verts[indices[i + 2]]),
				])
				if _triangle_area(_flatten_triangle(triangle)) >= _MIN_SILHOUETTE_TRIANGLE_AREA:
					triangles.append(triangle)
	return triangles


## A ghost-local 3D triangle dropped straight down onto XZ (x, z).
func _flatten_triangle(triangle: PackedVector3Array) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(triangle[0].x, triangle[0].z),
		Vector2(triangle[1].x, triangle[1].z),
		Vector2(triangle[2].x, triangle[2].z),
	])


## Fallback index buffer (0, 1, 2, 3, ...) for a surface with no ARRAY_INDEX at
## all; every real mesh this file walks (BlockMeshBuilder's combined shell,
## BoxMesh's primitive surface) always has one.
func _sequential_indices(vertex_count: int) -> PackedInt32Array:
	var indices: PackedInt32Array = PackedInt32Array()
	indices.resize(vertex_count)
	for i: int in range(vertex_count):
		indices[i] = i
	return indices


## Twice the signed area (shoelace formula), absolute value -- cheap enough to
## call once per candidate triangle without a second pass.
func _triangle_area(triangle: PackedVector2Array) -> float:
	var a: Vector2 = triangle[0]
	var b: Vector2 = triangle[1]
	var c: Vector2 = triangle[2]
	return absf((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) * 0.5


## Folds `addition` into `existing` (a list of already-mutually-disjoint
## outline loops) via Geometry2D.merge_polygons, growing one candidate polygon
## against every existing loop it touches in turn (so a single new triangle
## can bridge two previously separate loops into one in the same pass) --
## see this file's own header DECISION for why one growing candidate per
## addition is enough rather than a full pairwise fixed point over the whole
## pool. A pair that doesn't overlap/touch at all (merge_polygons returns the
## two polygons unchanged) is left as two separate loops -- correct for a
## shape whose current rotation genuinely splits its silhouette into disjoint
## pieces, which does not happen for any shipped BlockShape but costs nothing
## to leave correct for one that might.
func _accumulate_union(
	existing: Array[PackedVector2Array], addition: PackedVector2Array
) -> Array[PackedVector2Array]:
	var candidate: PackedVector2Array = addition
	var remainder: Array[PackedVector2Array] = []
	for polygon: PackedVector2Array in existing:
		var merge_result: Array = Geometry2D.merge_polygons(polygon, candidate)
		if merge_result.size() == 1:
			candidate = merge_result[0]
		else:
			remainder.append(polygon)
	remainder.append(candidate)
	return remainder


## Fills _cached_wall_segments/_cached_wall_heights from the silhouette `loops`
## and the rotated mesh triangles that produced them. Step 1: every outline edge
## a->b is split at every parameter where a projected triangle edge crosses it
## (Geometry2D.segment_intersects_segment) or where a projected triangle vertex
## lies on it (within _SILHOUETTE_SPLIT_EPSILON -- a T-junction, e.g.
## BlockMeshBuilder's per-cell bottom-face seams ending exactly on the outline,
## which a crossing test alone can miss by float rounding). Between two
## consecutive split parameters no triangle boundary crosses the edge, so the
## lowest triangle over the piece is one fixed triangle. Step 2
## (_underside_heights()): that triangle's own plane, evaluated at the piece's
## two endpoints, is the shape's underside there -- exact for a tilted underside
## (the wall's top edge slopes with it) and stepped wherever an overhang begins
## (a split lands exactly on the step). Pieces shorter than the split epsilon, or
## with no triangle on either side (an outline spike thinner than
## _SILHOUETTE_PROBE_INSET), are dropped.
func _build_underside_walls(
	loops: Array[PackedVector2Array],
	triangles_3d: Array[PackedVector3Array], triangles_2d: Array[PackedVector2Array]
) -> void:
	_cached_wall_segments = PackedVector2Array()
	_cached_wall_heights = PackedVector2Array()
	_cached_wall_probes = PackedVector2Array()
	for loop: PackedVector2Array in loops:
		var edge_count: int = loop.size()
		if edge_count < 3:
			continue
		for i: int in range(edge_count):
			var a: Vector2 = loop[i]
			var b: Vector2 = loop[(i + 1) % edge_count]
			var edge_length: float = a.distance_to(b)
			if edge_length <= _SILHOUETTE_SPLIT_EPSILON:
				continue
			var params: PackedFloat64Array = _edge_split_params(a, b, triangles_2d)
			var previous: float = params[0]
			# Index (into _cached_wall_heights) of the last piece kept on *this*
			# edge, or -1 -- lets a piece that just continues the previous one's
			# plane (same height at the shared point, same slope: e.g. a flat
			# bar's per-cell bottom-face seams) extend it instead of adding a
			# redundant quad.
			var last_piece: int = -1
			for k: int in range(1, params.size()):
				var current: float = params[k]
				if (current - previous) * edge_length <= _SILHOUETTE_SPLIT_EPSILON:
					continue
				var piece_a: Vector2 = a.lerp(b, previous)
				var piece_b: Vector2 = a.lerp(b, current)
				previous = current
				var heights: PackedFloat64Array = _underside_heights(piece_a, piece_b, triangles_3d, triangles_2d)
				if heights.is_empty():
					last_piece = -1
					continue
				if last_piece >= 0 and _continues_piece(last_piece, piece_a, piece_b, heights):
					_cached_wall_segments[last_piece * 2 + 1] = piece_b
					var extended: Vector2 = _cached_wall_heights[last_piece]
					_cached_wall_heights[last_piece] = Vector2(extended.x, heights[1])
					continue
				_cached_wall_segments.append(piece_a)
				_cached_wall_segments.append(piece_b)
				_cached_wall_heights.append(Vector2(heights[0], heights[1]))
				_cached_wall_probes.append(Vector2(heights[_HEIGHTS_PROBE_X], heights[_HEIGHTS_PROBE_Y]))
				last_piece = _cached_wall_heights.size() - 1


## Whether new piece piece_a->piece_b (underside `heights` at its ends) lies on
## the same straight underside line as cached piece `index` on the same
## outline edge: it starts where that one ends, at the same height, with the
## same slope -- so one quad can cover both exactly.
func _continues_piece(index: int, piece_a: Vector2, piece_b: Vector2, heights: PackedFloat64Array) -> bool:
	var prev_a: Vector2 = _cached_wall_segments[index * 2]
	var prev_b: Vector2 = _cached_wall_segments[index * 2 + 1]
	var prev_heights: Vector2 = _cached_wall_heights[index]
	if prev_b.distance_to(piece_a) > _SILHOUETTE_SPLIT_EPSILON:
		return false
	if absf(prev_heights.y - heights[0]) > _UNDERSIDE_CONTACT_EPSILON:
		return false
	var prev_slope: float = (prev_heights.y - prev_heights.x) / prev_a.distance_to(prev_b)
	var slope: float = (heights[1] - heights[0]) / piece_a.distance_to(piece_b)
	return absf(prev_slope - slope) <= _UNDERSIDE_CONTACT_EPSILON


## Sorted split parameters (always including 0.0 and 1.0) along outline edge
## a->b -- see _build_underside_walls()'s own step 1. Near-duplicates are left
## in; the caller skips any piece shorter than _SILHOUETTE_SPLIT_EPSILON.
func _edge_split_params(a: Vector2, b: Vector2, triangles_2d: Array[PackedVector2Array]) -> PackedFloat64Array:
	var params: PackedFloat64Array = PackedFloat64Array([0.0, 1.0])
	var edge: Vector2 = b - a
	var length_squared: float = edge.length_squared()
	for triangle: PackedVector2Array in triangles_2d:
		for k: int in range(3):
			var p: Vector2 = triangle[k]
			var q: Vector2 = triangle[(k + 1) % 3]
			var crossing: Variant = Geometry2D.segment_intersects_segment(a, b, p, q)
			if crossing != null:
				params.append(clampf(((crossing as Vector2) - a).dot(edge) / length_squared, 0.0, 1.0))
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p, a, b)
			if closest.distance_to(p) <= _SILHOUETTE_SPLIT_EPSILON:
				params.append(clampf((closest - a).dot(edge) / length_squared, 0.0, 1.0))
	params.sort()
	return params


## The shape's own underside height (relative to the ghost origin) at the two
## endpoints of outline piece a->b, as [height_at_a, height_at_b] -- or empty
## when neither side of the piece has any mesh triangle over it. Probes the
## piece's midpoint nudged _SILHOUETTE_PROBE_INSET off the outline (left side
## first, then right: which side is "inside" depends on the loop's winding,
## and a hole loop winds the other way, so both are tried rather than trusting
## Geometry2D.is_polygon_clockwise), picks the triangle with the *lowest*
## plane Y there (a closed shell's lowest surface over a point is its
## underside), and evaluates that one triangle's plane at the two real,
## un-nudged endpoints. No triangle boundary crosses the piece
## (_edge_split_params()), so that plane is the underside along its whole
## length.
func _underside_heights(
	a: Vector2, b: Vector2,
	triangles_3d: Array[PackedVector3Array], triangles_2d: Array[PackedVector2Array]
) -> PackedFloat64Array:
	var midpoint: Vector2 = (a + b) * 0.5
	var direction: Vector2 = (b - a).normalized()
	var left: Vector2 = Vector2(-direction.y, direction.x)
	for side: float in [1.0, -1.0]:
		var probe: Vector2 = midpoint + left * (side * _SILHOUETTE_PROBE_INSET)
		var best_index: int = -1
		var best_y: float = INF
		for j: int in range(triangles_2d.size()):
			var flat: PackedVector2Array = triangles_2d[j]
			if not Geometry2D.point_is_inside_triangle(probe, flat[0], flat[1], flat[2]):
				continue
			var y: float = _triangle_plane_y(triangles_3d[j], flat, probe)
			if y < best_y:
				best_y = y
				best_index = j
		if best_index >= 0:
			var triangle: PackedVector3Array = triangles_3d[best_index]
			var triangle_flat: PackedVector2Array = triangles_2d[best_index]
			return PackedFloat64Array([
				_triangle_plane_y(triangle, triangle_flat, a),
				_triangle_plane_y(triangle, triangle_flat, b),
				probe.x, probe.y,
			])
	return PackedFloat64Array()


## The Y of `triangle`'s own plane straight above/below XZ point `point`
## (barycentric weights from its XZ projection `flat`, extrapolated if
## `point` is outside it). `flat` is never degenerate here --
## _collect_rotated_triangles() already dropped every triangle under
## _MIN_SILHOUETTE_TRIANGLE_AREA.
func _triangle_plane_y(triangle: PackedVector3Array, flat: PackedVector2Array, point: Vector2) -> float:
	var e1: Vector2 = flat[1] - flat[0]
	var e2: Vector2 = flat[2] - flat[0]
	var d: Vector2 = point - flat[0]
	var denominator: float = e1.x * e2.y - e2.x * e1.y
	var weight_1: float = (d.x * e2.y - e2.x * d.y) / denominator
	var weight_2: float = (e1.x * d.y - d.x * e1.y) / denominator
	return triangle[0].y + weight_1 * (triangle[1].y - triangle[0].y) + weight_2 * (triangle[2].y - triangle[0].y)


## Appends one underside wall into the caller's shared mesh arrays: a vertical
## quad over ghost-local XZ segment a->b, from `bottom_y` up to the shape's own
## underside at each end (`top_a`/`top_b`, world Y -- the top edge may slope).
## Always exactly 4 vertices in (a_top, b_top, b_bottom, a_bottom) order, the
## layout tests/unit/blocks/test_ghost_preview.gd reconstructs walls from. Where the
## underside dips to within _UNDERSIDE_CONTACT_EPSILON of `bottom_y` (the shape
## sitting on the landing surface there) nothing is drawn; a piece crossing that
## level is clipped at the crossing point, so its low end collapses to a triangle
## (a_top == a_bottom) rather than dipping below the disc.
## DECISION (game/player/GhostPreview.gd): no extra
## vertical "step" face is emitted where two consecutive pieces meet at
## different heights -- both pieces lie on the same outline and each rises
## from the same bottom to its own top at the shared vertex, so they tile the
## wall with no gap (the height difference is a zero-area line). The vertical
## face an interior overhang step would need is the shape's own side face
## (e.g. S4's lower cell's inner side), already drawn by the ghost body.
## One winding is enough -- _projection_material's own CULL_DISABLED (see
## _ready()) draws both sides of every triangle regardless of winding.
func _append_underside_wall(
	a: Vector2, b: Vector2, top_a: float, top_b: float, bottom_y: float,
	verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array
) -> void:
	var limit: float = bottom_y + _UNDERSIDE_CONTACT_EPSILON
	if top_a <= limit and top_b <= limit:
		return
	var start: Vector2 = a
	var end: Vector2 = b
	var top_start: float = top_a
	var top_end: float = top_b
	if top_start < bottom_y:
		start = a.lerp(b, (bottom_y - top_a) / (top_b - top_a))
		top_start = bottom_y
	elif top_end < bottom_y:
		end = b.lerp(a, (bottom_y - top_b) / (top_a - top_b))
		top_end = bottom_y
	var edge_length: float = start.distance_to(end)
	if edge_length <= 0.0:
		return
	# Outward-ish normal for this edge (SHADING_MODE_UNSHADED means it has no
	# visible effect today, but a correct value costs nothing and keeps the
	# mesh sane if the material ever changes).
	var edge_dir: Vector2 = (end - start) / edge_length
	var normal: Vector3 = Vector3(edge_dir.y, 0.0, -edge_dir.x)
	var base_index: int = verts.size()
	verts.append(Vector3(start.x, top_start, start.y))
	verts.append(Vector3(end.x, top_end, end.y))
	verts.append(Vector3(end.x, bottom_y, end.y))
	verts.append(Vector3(start.x, bottom_y, start.y))
	for _k: int in range(4):
		normals.append(normal)
	uvs.append(Vector2(0.0, 0.0))
	uvs.append(Vector2(edge_length / tuning.cube_size, 0.0))
	uvs.append(Vector2(edge_length / tuning.cube_size, (top_end - bottom_y) / tuning.cube_size))
	uvs.append(Vector2(0.0, (top_start - bottom_y) / tuning.cube_size))
	indices.append(base_index)
	indices.append(base_index + 2)
	indices.append(base_index + 1)
	indices.append(base_index)
	indices.append(base_index + 3)
	indices.append(base_index + 2)


## Unweighted average of `hull`'s own vertices -- good enough as "roughly the
## middle of the shape" for the one straight-down probe _update_footprint()
## needs (a true polygon centroid would weight by edge geometry, which buys
## nothing here: the probe only has to land somewhere inside a convex shape
## the disc is expected to be under almost all of, with _last_surface_point
## as the fallback for the rare edge-of-disk overhang anyway).
func _polygon_centroid(hull: PackedVector2Array) -> Vector2:
	var sum: Vector2 = Vector2.ZERO
	for point: Vector2 in hull:
		sum += point
	return sum / float(hull.size())


## Builds a flat (Y = 0 in its own local space), upward-facing triangle-fan
## mesh from `hull` (a convex polygon, in ghost-local XZ) recentered on
## `center` -- the point the caller positions the MeshInstance3D itself at --
## so the mesh's own vertices are the polygon's true rotated shape, not a
## fixed unit square. UVs tile at roughly one cube_size per unit so the hole
## hatch texture (uv1_scale in ghost_tuning.hatch_scale) still reads sensibly.
func _build_polygon_mesh(hull: PackedVector2Array, center: Vector2) -> ArrayMesh:
	var vertex_count: int = hull.size()
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in hull:
		var local: Vector2 = point - center
		verts.append(Vector3(local.x, 0.0, local.y))
		normals.append(Vector3.UP)
		uvs.append(Vector2(local.x / tuning.cube_size + 0.5, local.y / tuning.cube_size + 0.5))
	var indices: PackedInt32Array = PackedInt32Array()
	for i: int in range(1, vertex_count - 1):
		indices.append(0)
		indices.append(i)
		indices.append(i + 1)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var built: ArrayMesh = ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return built


## Flat triangle mesh of every silhouette loop (hole loops wind opposite to the
## largest loop and are skipped; shipped shapes have none), recentred on
## `center`. Null when nothing triangulates, so the caller can fall back to the
## convex hull mesh.
func _build_loops_mesh(loops: Array[PackedVector2Array], center: Vector2) -> ArrayMesh:
	if loops.is_empty():
		return null
	var outer_clockwise: bool = Geometry2D.is_polygon_clockwise(_largest_loop(loops))
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for loop: PackedVector2Array in loops:
		if loop.size() < _MIN_POLYGON_POINTS or Geometry2D.is_polygon_clockwise(loop) != outer_clockwise:
			continue
		var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(loop)
		if triangles.is_empty():
			continue
		var base: int = verts.size()
		for point: Vector2 in loop:
			var local: Vector2 = point - center
			verts.append(Vector3(local.x, 0.0, local.y))
			normals.append(Vector3.UP)
			uvs.append(Vector2(local.x / tuning.cube_size + 0.5, local.y / tuning.cube_size + 0.5))
		for index: int in triangles:
			indices.append(base + index)
	if indices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var built: ArrayMesh = ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return built


func _largest_loop(loops: Array[PackedVector2Array]) -> PackedVector2Array:
	var best: PackedVector2Array = loops[0]
	var best_area: float = 0.0
	for loop: PackedVector2Array in loops:
		var area: float = 0.0
		for i: int in range(loop.size()):
			var next: Vector2 = loop[(i + 1) % loop.size()]
			area += loop[i].x * next.y - next.x * loop[i].y
		if absf(area) > best_area:
			best_area = absf(area)
			best = loop
	return best


## The decal's albedo is an alpha mask of the true footprint over
## [origin, origin + extent] (ghost-local XZ), so it doesn't paint a solid
## rectangle over every placed block below a concave piece. Rebuilt only when the
## shape/rotation/box changes.
var _mask_shape: BlockShape = null
var _mask_basis: Basis = Basis.IDENTITY
var _mask_origin: Vector2 = Vector2.ZERO
var _mask_extent: Vector2 = Vector2.ZERO
var _mask_cache: Dictionary = {}
static var _white_texture: ImageTexture = null


## Drops the static texture/material cache on exit (freed before the renderer shuts down).
static func release_statics() -> void:
	_white_texture = null


func _apply_decal_footprint_mask(origin: Vector2, extent: Vector2) -> void:
	if _mask_shape == _shape and _mask_basis.is_equal_approx(basis) \
			and _mask_origin.is_equal_approx(origin) and _mask_extent.is_equal_approx(extent):
		return
	var loops: Array[PackedVector2Array] = _shape_silhouette_loops()
	if loops.is_empty():
		_block_projection_decal.texture_albedo = _build_white_decal_texture()
		return
	_mask_shape = _shape
	_mask_basis = basis
	_mask_origin = origin
	_mask_extent = extent
	var key: int = [
		_shape.get_instance_id(), roundi(basis.x.x * _MASK_KEY_SCALE), roundi(basis.x.y * _MASK_KEY_SCALE),
		roundi(basis.x.z * _MASK_KEY_SCALE), roundi(basis.y.x * _MASK_KEY_SCALE), roundi(basis.y.y * _MASK_KEY_SCALE),
		roundi(basis.y.z * _MASK_KEY_SCALE), roundi(basis.z.x * _MASK_KEY_SCALE), roundi(basis.z.y * _MASK_KEY_SCALE),
		roundi(basis.z.z * _MASK_KEY_SCALE), roundi(origin.x * _MASK_KEY_SCALE), roundi(origin.y * _MASK_KEY_SCALE),
		roundi(extent.x * _MASK_KEY_SCALE), roundi(extent.y * _MASK_KEY_SCALE),
	].hash()
	if _mask_cache.has(key):
		_block_projection_decal.texture_albedo = _mask_cache[key] as ImageTexture
		return
	if _mask_cache.size() >= MASK_CACHE_MAX_ENTRIES:
		_mask_cache.clear()
	var texture: ImageTexture = ImageTexture.create_from_image(_rasterize_footprint_mask(loops, origin, extent))
	_mask_cache[key] = texture
	_block_projection_decal.texture_albedo = texture


## Scanline fill of the outer loops (even-odd, hole loops skipped like the
## mesh) into an alpha mask over [origin, origin + extent]; one fill_rect per
## covered span, no per-pixel polygon tests.
func _rasterize_footprint_mask(loops: Array[PackedVector2Array], origin: Vector2, extent: Vector2) -> Image:
	var width: int = clampi(ceili(extent.x * FOOTPRINT_MASK_PIXELS_PER_METER), 2, FOOTPRINT_MASK_MAX_PIXELS)
	var height: int = clampi(ceili(extent.y * FOOTPRINT_MASK_PIXELS_PER_METER), 2, FOOTPRINT_MASK_MAX_PIXELS)
	var image: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(Color.WHITE, 0.0))
	var outer_clockwise: bool = Geometry2D.is_polygon_clockwise(_largest_loop(loops))
	var edges: PackedVector2Array = PackedVector2Array()
	for loop: PackedVector2Array in loops:
		if Geometry2D.is_polygon_clockwise(loop) != outer_clockwise:
			continue
		for i: int in range(loop.size()):
			edges.append(loop[i])
			edges.append(loop[(i + 1) % loop.size()])
	var crossings: PackedFloat64Array = PackedFloat64Array()
	for row: int in range(height):
		var v: float = origin.y + (row + 0.5) / height * extent.y
		crossings.clear()
		for e: int in range(0, edges.size(), 2):
			var a: Vector2 = edges[e]
			var b: Vector2 = edges[e + 1]
			if (a.y <= v) != (b.y <= v):
				crossings.append(a.x + (v - a.y) / (b.y - a.y) * (b.x - a.x))
		crossings.sort()
		for k: int in range(0, crossings.size() - 1, 2):
			var x0: int = clampi(ceili((crossings[k] - origin.x) / extent.x * width - 0.5), 0, width)
			var x1: int = clampi(ceili((crossings[k + 1] - origin.x) / extent.x * width - 0.5), 0, width)
			if x1 > x0:
				image.fill_rect(Rect2i(x0, row, x1 - x0, 1), Color.WHITE)
	return image


## Straight down from `origin`, skipping any RigidBody3D (a placed block) so the
## first hit reported is the disk's own collision -- never a tower underneath the
## hull's centroid. Mirrors game/player/PlayerController.gd's own
## _raycast_disk_surface() (both call Field.raycast_disk_surface()), including
## its surface_probe_max_blocks bound against a very tall or adversarial stack.
func _raycast_disk_surface(origin: Vector3) -> Dictionary:
	if not is_inside_tree():
		return {}
	var world: World3D = get_world_3d()
	if world == null:
		return {}
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	if space_state == null:
		return {}
	return Field.raycast_disk_surface(
		space_state, origin, ghost_tuning.placement_ray_length, ghost_tuning.surface_probe_max_blocks
	)


func _set_footprint_quad_count(count: int) -> void:
	while _footprint_quads.size() < count:
		var quad: MeshInstance3D = _make_footprint_quad()
		add_child(quad)
		_footprint_quads.append(quad)
	while _footprint_quads.size() > count:
		var extra: MeshInstance3D = _footprint_quads.pop_back()
		extra.queue_free()


## The world-space Y span (top, bottom) of the held shape's whole
## bookkeeping -- Vector2.ZERO when nothing is held or the prism collapsed (see
## _update_projection_mesh()'s own guard). `top` is the held shape's current
## *highest* point (_rotated_top_offset()); `bottom` is the footprint's landing
## height. This is bookkeeping, not the mesh's extent: the walls stop at the
## shape's underside.
func projection_span_y() -> Vector2:
	return _projection_span_y


# --- Ghost-vs-placed-block collision (spec 1.4) -------------

## Local (unrotated), cell-local centers of the held shape's own collision
## boxes -- matching game/blocks/BlockFactory.gd's build() exactly (same
## cube_size/cube_margin and BlockShape.bottom_center() pivot) so the swept
## collision test lines up with the box the real spawned Block would occupy
## there. DECISION (game/player/GhostPreview.gd): duplicated rather than calling
## BlockFactory's private static _make_collision_shape(); it is the same few
## lines _rotated_bottom_offset() already computes for the same shape. Empty (not
## null) when nothing is held.
func collision_box_local_centers() -> Array[Vector3]:
	if _shape == null:
		return []
	return _shape.cell_centres(tuning.cube_size)


## Half-extent of one collision box, matching game/blocks/BlockFactory.gd's own
## `half_size`. A sloped cell (ConvexPolygonShape3D in BlockFactory) is
## approximated as a full box here -- no shipped shape sets sloped_cells today, so
## this never runs against a shape it would misrepresent.
func collision_half_size() -> float:
	return (tuning.cube_size - tuning.cube_margin) * 0.5


# --- Placement validity tint (spec 1.5, 1.4) --------------------------------

## The active slot's colour, used for the VALID tint. Setting it re-applies
## the material immediately if the ghost is currently showing VALID, so a
## turn change re-colours the ghost without waiting for the next
## preview_placement() poll.
func set_player_color(color: Color) -> void:
	_player_color = color
	if _last_result == PlacementRules.Result.VALID:
		_refresh_materials()


## Maps Match.preview_placement()'s advisory result onto the three tint
## states spec 1.4 calls for. Safe to call every frame.
func apply_validity(result: PlacementRules.Result) -> void:
	_last_result = result
	_refresh_materials()


## spec 1.4/1.4's "distinct timer-locked state": whether this
## slot's held piece may be released right now. Called every frame alongside
## apply_validity() by game/player/PlayerController.gd; the locked tint wins over
## whatever validity state was just applied.
func set_locked(locked: bool) -> void:
	_locked = locked
	_refresh_materials()


func _refresh_materials() -> void:
	_apply_validity_material()
	_apply_gift_tint()
	_apply_glow()
	_apply_footprint_material()
	_apply_projection_material()


## Which tint state the ghost is currently showing (STATE_*).
func current_state() -> StringName:
	if _locked:
		return STATE_LOCKED
	match _last_result:
		PlacementRules.Result.VALID:
			return STATE_VALID
		PlacementRules.Result.HOLE, PlacementRules.Result.GOAL_ZONE:
			return STATE_HOLE
		_:
			return STATE_INVALID


## Every branch below applies ghost_tuning.ghost_opacity as the material's alpha
## instead of the picked colour's own alpha, so one F4 slider controls every
## state's opacity together.
func _apply_validity_material() -> void:
	if _material == null:
		return
	if _locked:
		_material.set_shader_parameter(&"use_hatch", false)
		_material.set_shader_parameter(
			&"albedo_color", _with_alpha(ghost_tuning.locked_tint_color, ghost_tuning.ghost_opacity)
		)
		return
	match _last_result:
		PlacementRules.Result.VALID:
			_material.set_shader_parameter(&"use_hatch", false)
			_material.set_shader_parameter(&"albedo_color", _with_alpha(_player_color, ghost_tuning.ghost_opacity))
		PlacementRules.Result.HOLE, PlacementRules.Result.GOAL_ZONE:
			_material.set_shader_parameter(&"use_hatch", true)
			_material.set_shader_parameter(&"hatch_scale", ghost_tuning.hatch_scale)
			_material.set_shader_parameter(
				&"albedo_color", _with_alpha(ghost_tuning.hole_tint_color, ghost_tuning.ghost_opacity)
			)
		_:
			_material.set_shader_parameter(&"use_hatch", false)
			_material.set_shader_parameter(
				&"albedo_color", _with_alpha(ghost_tuning.invalid_tint_color, ghost_tuning.ghost_opacity)
			)


## The footprint quads get a validity/lock cue tied to the held shape's own body
## state (_apply_validity_material() above), at ghost_tuning.footprint_alpha --
## every footprint quad shares this one material. The cue is only a faint hue
## blended into a near-white base (_footprint_color_for_state()), not the full
## state colour the body shows; _state_hue_color() is the one shared lookup.
func _apply_footprint_material() -> void:
	if _footprint_material == null:
		return
	_footprint_material.albedo_color = _footprint_color_for_state()
	var hatched: bool = not _locked and (
		_last_result == PlacementRules.Result.HOLE or _last_result == PlacementRules.Result.GOAL_ZONE
	)
	if hatched:
		_footprint_material.albedo_texture = _hatch_texture
		_footprint_material.uv1_scale = Vector3(ghost_tuning.hatch_scale, ghost_tuning.hatch_scale, 1.0)
	else:
		_footprint_material.albedo_texture = null


## The raw, un-alpha'd, un-blended state colour -- valid/invalid/hole/locked,
## exactly what _apply_validity_material() picks for the held shape's body -- so
## the footprint (blended toward near-white) and the projection prism (the plain
## state colour, fainter and additive) share one lookup.
func _state_hue_color() -> Color:
	if _locked:
		return ghost_tuning.locked_tint_color
	match _last_result:
		PlacementRules.Result.VALID:
			return _player_color
		PlacementRules.Result.HOLE, PlacementRules.Result.GOAL_ZONE:
			return ghost_tuning.hole_tint_color
		_:
			return ghost_tuning.invalid_tint_color


## ghost_tuning.footprint_base_color (near-white) with only a faint amount of the
## current state's hue blended in (footprint_hue_strength): validity is still
## readable (a hint of red/grey/gold tints the near-white disc), just far more
## subtle than the held shape's body or the projection prism.
func _footprint_color_for_state() -> Color:
	var blended: Color = ghost_tuning.footprint_base_color.lerp(_state_hue_color(), ghost_tuning.footprint_hue_strength)
	return _with_alpha(blended, ghost_tuning.footprint_alpha)


## The projection prism's walls, at ghost_tuning.projection_alpha (fainter than
## the flat footprint decal it stands on). DECISION (game/player/GhostPreview.gd):
## reuses _state_hue_color() when ghost_tuning.projection_uses_state_tint is true
## (the default; the prism is tinted like everything else the ghost shows), and
## false is a tuning-panel escape hatch for a state-neutral prism (always the base
## tint_color). The material blends additively (BLEND_MODE_ADD, _ready()) and this
## drives its emission at ghost_tuning.projection_emission_energy, so the column
## brightens whatever is behind it. A per-block emission hook on
## BlockFactory/Block.gd was rejected in favour of this material-only change.
func _apply_projection_material() -> void:
	if _projection_material == null:
		return
	var state_color: Color = _state_hue_color() if ghost_tuning.projection_uses_state_tint else ghost_tuning.tint_color
	_projection_material.albedo_color = _with_alpha(state_color, ghost_tuning.projection_alpha)
	_projection_material.emission = Color(state_color.r, state_color.g, state_color.b)
	_projection_material.emission_energy_multiplier = ghost_tuning.projection_emission_energy


# --- Glow ----------------------------------------------------
# Presentation only: a fresnel rim in the ghost's tint colour. Steady at
# ghost_tuning.glow_strength; once the local block timer is within
# glow_warning_lead_seconds of the forced drop it pulses, the rate ramping from
# glow_pulse_start_hz to glow_pulse_end_hz. Nothing here touches timers or drops.
# DECISION: remote ghosts get the steady glow (same material, so
# it is free and consistent) but never the warning pulse -- only the ghost in
# LOCAL_HELD_GROUP polls the local slot's timer.

## Seconds left on the block timer, or a negative value when no timer applies.
var _drop_time_left: float = -1.0
var _pulse_phase: float = 0.0


func _process(delta: float) -> void:
	if is_in_group(LOCAL_HELD_GROUP):
		set_drop_time_left(_local_feed_time_left())
		set_glue_charges(_local_glue_charges())
	advance_glow(delta)


## Glue is a charge modifier, not a held piece. While the local slot has charges
## the ghost's shape meshes get the translucent jelly shell.
## DECISION: remote ghosts get the same shell: RemoteCursors mirrors
## Match.glue_drops_left() into set_glue_charges().
var _glue_charges: int = 0


func set_glue_charges(charges: int) -> void:
	var was_glued: bool = _glue_charges > 0
	_glue_charges = maxi(charges, 0)
	if was_glued != (_glue_charges > 0):
		_apply_glue_overlay()


func _apply_glue_overlay() -> void:
	if _shape_visual == null:
		return
	for child: Node in _shape_visual.get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance != null:
			# Loaded by path, not by class name: HoneyCoat reaches Block, which would grow the layer-lint SCC.
			var honey_coat: GDScript = LateScripts.script(LateScripts.HONEY_COAT)
			honey_coat.call(&"set_ghost_coated", mesh_instance, _shape.cell_centres(tuning.cube_size), _glue_charges > 0)


func _local_glue_charges() -> int:
	var ctx: MatchContext = MatchContext.current()
	var slot: int = ctx.active_slot() if ctx.net_is_offline() else ctx.net_local_slot()
	return ctx.glue_drops_left(slot)


func _local_feed_time_left() -> float:
	var ctx: MatchContext = MatchContext.current()
	if _shape == null or not ctx.feed_timer_enabled():
		return -1.0
	var slot: int = ctx.active_slot() if ctx.net_is_offline() else ctx.net_local_slot()
	return ctx.feed_time_left(slot)


## Feeds the block timer (seconds left before the forced drop; negative = none).
func set_drop_time_left(seconds: float) -> void:
	_drop_time_left = seconds
	if not is_pulse_active():
		_pulse_phase = 0.0


## True while the forced drop is within glow_warning_lead_seconds.
func is_pulse_active() -> bool:
	# a locked (greyed, interval-locked) piece is not force-dropped.
	return not _locked and _drop_time_left >= 0.0 and _drop_time_left <= ghost_tuning.glow_warning_lead_seconds


## Current warning pulse rate in Hz (0 while inactive); ramps start -> end.
func pulse_frequency_hz() -> float:
	if not is_pulse_active():
		return 0.0
	var lead: float = maxf(ghost_tuning.glow_warning_lead_seconds, 0.0001)
	var progress: float = clampf(1.0 - _drop_time_left / lead, 0.0, 1.0)
	return lerpf(ghost_tuning.glow_pulse_start_hz, ghost_tuning.glow_pulse_end_hz, progress)


## Effective glow multiplier right now (steady strength, or pulsing above it).
func glow_level() -> float:
	var level: float = ghost_tuning.glow_strength
	if is_pulse_active():
		var wave: float = 0.5 + 0.5 * sin(_pulse_phase)
		level *= lerpf(1.0, ghost_tuning.glow_pulse_peak_multiplier, wave)
	return level


func advance_glow(delta: float) -> void:
	if is_pulse_active():
		_pulse_phase = fmod(_pulse_phase + TAU * pulse_frequency_hz() * delta, TAU)
	else:
		_pulse_phase = 0.0
	_apply_glow()


func _apply_glow() -> void:
	var level: float = glow_level()
	if _material != null:
		_material.set_shader_parameter(&"glow_strength", level)
		_material.set_shader_parameter(&"glow_rim_power", ghost_tuning.glow_rim_power)


func _with_alpha(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)


func _apply_material_to_visual() -> void:
	if _shape_visual == null:
		return
	for child: Node in _shape_visual.get_children():
		if child is MeshInstance3D:
			var mesh_instance: MeshInstance3D = child as MeshInstance3D
			mesh_instance.material_override = _material
			# DECISION: the held block is a preview, so it casts no light shadow;
			# the projected footprint is its only ground marker.
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_glue_overlay()


# --- Reject / auto-drop animation (spec 1.5, 1.4) ---------------------------

## Spec 1.5: "released [in a contested area] ... is thrown off the map with a
## visible reject animation" (every invalid release burns the block, decided by
## Match.request_place -- this is just the ghost-side cue: a bright flash plus a
## small arc kick on _reject_offset, a world-space position offset applied on top
## of update_placement()'s/sync_remote_position()'s computed position every
## frame).
##
## The kick is a world-space vector added after rotation is applied, not an
## offset on _shape_visual's local position, which rides along with the rotation
## basis and would send a pitched or rolled block's kick the wrong way. The kick
## direction (world +X sideways, +Y up) never depends on the block's rotation and
## survives PlayerController re-homing the ghost's position every frame.
func play_reject_animation() -> void:
	_flash_material(ghost_tuning.reject_flash_color, ghost_tuning.reject_flash_duration)
	if _reject_tween != null and _reject_tween.is_valid():
		_reject_tween.kill()
	_reject_offset = Vector3.ZERO
	var kick: Vector3 = Vector3(ghost_tuning.reject_arc_sideways, ghost_tuning.reject_arc_height, 0.0)
	var half_duration: float = ghost_tuning.reject_arc_duration * 0.5
	_reject_tween = create_tween()
	_reject_tween.tween_property(self, ^"_reject_offset", kick, half_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_reject_tween.tween_property(self, ^"_reject_offset", Vector3.ZERO, half_duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Spec 1.4: "When the timer runs out, the held block drops from its current
## ghost position." A quick neutral flash tells the player the drop was
## automatic, not a click.
func play_auto_drop_flash() -> void:
	_flash_material(ghost_tuning.auto_drop_flash_color, ghost_tuning.auto_drop_flash_duration)


func _flash_material(color: Color, duration: float) -> void:
	if _material == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	var restore_color: Color = _material.get_shader_parameter(&"albedo_color") as Color
	_material.set_shader_parameter(&"albedo_color", color)
	_flash_tween = create_tween()
	# ShaderMaterial uniforms are reachable as a dynamic "shader_parameter/<name>"
	# property (Godot's documented idiom for animating a shader uniform with a
	# Tween).
	_flash_tween.tween_property(_material, ^"shader_parameter/albedo_color", restore_color, duration)


# --- Mesh / texture builders -------------------------------------------------

## One flat polygon for the footprint, tinted by the shared _footprint_material
## so every quad repaints together when validity/lock state changes. Starts
## meshless -- _update_footprint() assigns the real mesh (_build_polygon_mesh())
## every frame, since its shape depends on the held shape's current rotation.
func _make_footprint_quad() -> MeshInstance3D:
	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.material_override = _footprint_material
	mesh_instance.top_level = true
	return mesh_instance


## A small diagonal-stripe pattern (spec 1.4: "hatched pattern when over a
## hole"), generated once instead of shipped as an art asset. Tiled across the
## flat footprint quad via ghost_tuning.hatch_scale (StandardMaterial3D.uv1_scale)
## and across the held shape's body via the same hatch_scale as a
## shaders/blocks/ghost_cell_grid.gdshader uniform (hand-rolled triplanar
## sampling there, not uv1_scale -- the shape's mesh has 0..1 UVs per cell face,
## not per whole shape).
func _build_hatch_texture() -> ImageTexture:
	var image: Image = Image.create(HATCH_TEXTURE_SIZE, HATCH_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var period: float = float(HATCH_TEXTURE_SIZE) / 4.0
	for y: int in range(HATCH_TEXTURE_SIZE):
		for x: int in range(HATCH_TEXTURE_SIZE):
			var phase: float = fmod(float(x + y), period) / period
			var opaque: bool = phase < ghost_tuning.hatch_stripe_width
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0 if opaque else 0.0))
	# Mipmaps: without a mip chain the GPU has only this one full-resolution
	# level to minify from at distance or at an oblique ground-decal angle, and
	# linear-filtering a high-frequency diagonal stripe pattern that hard aliases
	# into speckled noise. generate_mipmaps() gives the renderer the downsampled
	# levels it needs to blend a proper grey average.
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
