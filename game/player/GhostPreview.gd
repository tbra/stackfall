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
## (GhostSilhouette.build()); where the underside touches the landing surface no
## wall is drawn. The material blends additively and emits light so a surface
## seen through the column brightens.
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
## A hit normal flatter than this (a block's side face or edge, never the disc) is treated as level,
## so the shear never divides by ~0.
const _MIN_PLANE_NORMAL_Y: float = 0.1
const _UNDERSIDE_CONTACT_EPSILON: float = 1e-4

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
## The ghost-local (not world-translated) silhouette (outline loops, underside
## walls and their probes) GhostSilhouette built last time, plus the exact
## (shape, basis) pair that produced it: a frame that changes neither (the player
## is only moving the cursor) skips re-walking every triangle of the rendered
## mesh. Every other input _update_projection_mesh() reads each frame
## (global_position.y, landing_y) only changes how high the cached walls are
## extruded, never their XZ shape, so caching on (shape, basis) alone is exact.
## wall_heights are relative to the ghost origin, so a frame that only moves the
## ghost re-emits the quads at a new offset.
var _cached_silhouette_shape: BlockShape = null
var _cached_silhouette_basis: Basis = Basis.IDENTITY
var _cached_silhouette_valid: bool = false
var _silhouette: GhostSilhouette.Result = GhostSilhouette.Result.new()
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
## The live disc plane under the hull centroid (point + normal), from the last
## _update_footprint(); level at the _last_surface_point fallback on a miss.
var _plane_point: Vector3 = Vector3.ZERO
var _plane_normal: Vector3 = Vector3.UP

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
	# _shape_visual would leave _shape_silhouette_loops() reading freed nodes.
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
## footprint bookkeeping is untouched.
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


## Called every frame by PlayerController with the disk surface point
## straight under the cursor (a raycast that skips placed blocks, so this is
## always the bare disk). Positions the ghost so the *rotated* held shape's
## lowest point sits at hover height straight above (world up) that point, and so the
## *rotated* shape's own geometric centre column sits over the cursor's XZ (see
## rotated_center_offset()), then refreshes the footprint projection.
func update_placement(surface_point: Vector3) -> void:
	var hover: float = tuning.hover_height + manual_hover_offset
	var anchor: Vector3 = surface_point + Vector3.UP * hover
	var bottom_offset: float = _rotated_bottom_offset()
	var center_offset: Vector3 = rotated_center_offset()
	global_position = Vector3(
		anchor.x - center_offset.x, anchor.y - bottom_offset, anchor.z - center_offset.z
	) + _reject_offset
	_last_surface_point = surface_point
	_update_footprint()


## World Y of the live disc plane (_plane_point/_plane_normal) at world (x, z).
func _disc_y_at(x: float, z: float) -> float:
	return _plane_point.y - (_plane_normal.x * (x - _plane_point.x) + _plane_normal.z * (z - _plane_point.z)) / _plane_normal.y


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
## local origin the rotated shape's *highest* point sits, the prism's top. Always >= 0 for the same reason
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
## height comes from a disk-only raycast (raycast_disk_surface(), skipping any
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
	var hit: Dictionary = raycast_disk_surface(probe_origin)
	var landing_y: float
	var landing_normal: Vector3
	if hit.is_empty():
		landing_y = _last_surface_point.y
		landing_normal = Vector3.UP
	else:
		landing_y = (hit["position"] as Vector3).y
		landing_normal = hit["normal"] as Vector3
	_plane_point = Vector3(world_x, landing_y, world_z)
	_plane_normal = landing_normal if landing_normal.y > _MIN_PLANE_NORMAL_Y else Vector3.UP

	# The flat world-XZ mesh is sheared onto the tilted plane so it follows the
	# vertical drop the block will make; the offset is along world up.
	var shear: Basis = Basis(
		Vector3(1.0, -_plane_normal.x / _plane_normal.y, 0.0), Vector3.UP,
		Vector3(0.0, -_plane_normal.z / _plane_normal.y, 1.0)
	)
	_footprint_quads[0].global_transform = Transform3D(
		shear, _plane_point + Vector3.UP * ghost_tuning.footprint_offset
	)
	# The quad follows the rendered silhouette (the union of every cell's
	# footprint), so concave shapes (plus5, u5, corner4...) don't show their
	# convex hull. The hull stays the bounding/test polygon.
	var footprint_mesh: ArrayMesh = _build_loops_mesh(_shape_silhouette_loops(), centroid)
	_footprint_quads[0].mesh = footprint_mesh if footprint_mesh != null else _build_polygon_mesh(hull, centroid)
	var world_hull: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in hull:
		world_hull.append(Vector2(global_position.x + point.x, global_position.z + point.y))
	var lowest_y: float = INF
	for world_point: Vector2 in world_hull:
		lowest_y = minf(lowest_y, _disc_y_at(world_point.x, world_point.y))

	_update_projection_mesh(lowest_y)
	_update_block_projection_decal(world_hull, lowest_y)
	_apply_projection_visibility()


## The mesh walls the merged rendered silhouette (_shape_silhouette_loops())
## from the live disc under each piece up to the shape's own underside along the outline
## (the cached pieces from GhostSilhouette.build(), re-emitted at this frame's
## height). The prism collapses when the whole shape's top (_rotated_top_offset())
## is within ghost_tuning.footprint_offset of the disc, or below it; a shape
## resting on the ground draws no wall at all (no mesh).
func _update_projection_mesh(lowest_y: float) -> void:
	if _shape == null or _shape.cells.is_empty():
		_clear_projection_mesh()
		return

	var whole_top_y: float = global_position.y + _rotated_top_offset()
	if whole_top_y - lowest_y <= ghost_tuning.footprint_offset:
		# The whole shape's own top is at or below the ground -- nothing to show.
		_clear_projection_mesh()
		return

	var loops: Array[PackedVector2Array] = _shape_silhouette_loops()
	if loops.is_empty():
		_clear_projection_mesh()
		return

	_projection_mesh.global_position = Vector3(global_position.x, 0.0, global_position.z)

	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()

	# Every wall bottoms out ghost_tuning.footprint_offset above the live disc under
	# its piece, the same epsilon the footprint quad uses, so the ground-contact
	# edge never Z-fights the disc's collision mesh.
	# Re-emit the cached underside walls at this frame's own height -- the only
	# per-frame work (see _silhouette's own doc comment).
	var origin_y: float = global_position.y
	var floors: PackedFloat64Array = _piece_floors(lowest_y)
	for i: int in range(_silhouette.wall_heights.size()):
		var heights: Vector2 = _silhouette.wall_heights[i]
		# Stop each piece on whatever is under it (a placed tower's top face,
		# which the block-projection decal paints), not the disc, so the
		# additive wall never runs through placed blocks.
		var piece_bottom_y: float = floors[i]
		_append_underside_wall(
			_silhouette.wall_segments[i * 2], _silhouette.wall_segments[i * 2 + 1],
			origin_y + heights.x, origin_y + heights.y, piece_bottom_y,
			verts, normals, uvs, indices
		)

	if verts.is_empty():
		# The shape rests on the ground along its whole outline -- no shaft to
		# draw.
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
func _piece_floors(lowest_y: float) -> PackedFloat64Array:
	var frame: int = Engine.get_physics_frames()
	if _floors_shape == _shape and _floors_position.is_equal_approx(global_position) \
			and _floors_basis.is_equal_approx(basis) and is_equal_approx(_floors_bottom, lowest_y) \
			and _floors.size() == _silhouette.wall_heights.size() and frame - _floors_frame < _FLOOR_RECAST_FRAMES:
		return _floors
	_floors_shape = _shape
	_floors_position = global_position
	_floors_basis = basis
	_floors_bottom = lowest_y
	_floors_frame = frame
	_floors = PackedFloat64Array()
	for i: int in range(_silhouette.wall_heights.size()):
		var heights: Vector2 = _silhouette.wall_heights[i]
		var probe: Vector2 = _silhouette.probes[i]
		var disc_floor_y: float = _disc_y_at(global_position.x + probe.x, global_position.z + probe.y) + ghost_tuning.footprint_offset
		_floors.append(_piece_floor_y(probe, global_position.y + minf(heights.x, heights.y), disc_floor_y))
	return _floors


## World Y the wall piece probed at ghost-local `probe` should stop at: the
## first settled collider (placed sleeping block or disc; loose/falling blocks
## are skipped so the bottom never flickers; gifts are Areas and never hit)
## straight below `from_y`, plus footprint_offset against z-fighting, never
## lower than `floor_y` (the live disc under the piece, plus footprint_offset).
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
		params.collision_mask = FieldBody.PLACEMENT_QUERY_MASK
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
	if _projection_mesh != null:
		_projection_mesh.mesh = null


# --- Block projection decal (spec 1.4) ----------------------

## Sizes and positions `_block_projection_decal` over `world_hull`'s bounding box
## (world-space X/Z, the same hull _update_footprint() built the flat footprint
## from), projecting straight down from the ghost's current underside
## (_rotated_bottom_offset() -- deliberately not any higher, so the decal's
## volume never overlaps the held ghost's rendered body) down to `lowest_y`, the
## lowest live-disc point under the hull.
## The disc lives on TerritoryOverlay.DISC_LAYER_BIT and _ready() strips that bit
## from the decal's cull_mask: painting the disc speckled it.
func _update_block_projection_decal(world_hull: PackedVector2Array, lowest_y: float) -> void:
	if _block_projection_decal == null:
		return
	var top_y: float = global_position.y + _rotated_bottom_offset()
	if top_y - lowest_y <= 0.001:
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
	_block_projection_decal.size = Vector3(size_x, top_y - lowest_y, size_z)
	_block_projection_decal.global_position = Vector3(center_x, (top_y + lowest_y) * 0.5, center_z)
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
## on (`_shape`, `basis`); see _cached_silhouette_shape's own doc comment for why
## that is exact for every other input _update_projection_mesh() reads. The same
## cache fill also builds the underside wall list (GhostSilhouette.build()), so
## a cache hit covers both.
func _shape_silhouette_loops() -> Array[PackedVector2Array]:
	if _shape == null or _shape_visual == null:
		return []
	if _cached_silhouette_valid and _cached_silhouette_shape == _shape \
			and _cached_silhouette_basis.is_equal_approx(basis):
		return _silhouette.loops
	var meshes: Array[Mesh] = []
	var offsets: PackedVector3Array = PackedVector3Array()
	for child: Node in _shape_visual.get_children():
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		meshes.append(mesh_instance.mesh)
		offsets.append(mesh_instance.position)
	_silhouette = GhostSilhouette.build(meshes, offsets, basis)
	_cached_silhouette_shape = _shape
	_cached_silhouette_basis = basis
	_cached_silhouette_valid = true
	return _silhouette.loops


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
	var outer_clockwise: bool = Geometry2D.is_polygon_clockwise(GhostSilhouette.largest_loop(loops))
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
	var texture: ImageTexture = ImageTexture.create_from_image(GhostSilhouette.rasterize_mask(
		loops, origin, extent, FOOTPRINT_MASK_PIXELS_PER_METER, FOOTPRINT_MASK_MAX_PIXELS
	))
	_mask_cache[key] = texture
	_block_projection_decal.texture_albedo = texture


## Straight down from `origin`, skipping any RigidBody3D (a placed block) so the
## first hit reported is the disk's own collision -- never a tower underneath the
## hull's centroid. Also the controller's cursor ray (null-checked);
## bounded by surface_probe_max_blocks against a very tall or adversarial stack.
func raycast_disk_surface(origin: Vector3) -> Dictionary:
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
# it is free and consistent) but never the warning pulse -- only the local
# slot's ghost gets the local slot's timer pushed by its controller.

## Seconds left on the block timer (pushed by the owner), or a negative value when no timer applies.
var _drop_time_left: float = -1.0
var _pulse_phase: float = 0.0


func _process(delta: float) -> void:
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
