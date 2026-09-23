class_name DiscMirror
extends Node3D
## Planar mirror reflection for the disc (Bontago-xtq.12 step 2, owner: "the
## disc isn't very reflective, like at all?"). Step 1's ReflectionProbe and
## step 2's game/Skybox.gd configure_ssr() both fall short of a legible
## per-block mirror image from the follow camera's shallow angle: the probe
## only ever samples a blurred, periodically-snapshotted cubemap, and SSR can
## only reflect what the main camera's own depth buffer already has on
## screen, at whatever ray-march budget it affords.
##
## This node renders a second Camera3D, mirrored about the disk's own plane,
## into a SubViewport every frame; shaders/territory.gdshader (via
## game/TerritoryOverlay.gd's set_mirror_texture() and, for
## mirror_max_luminance below, its public material() accessor -- neither
## requires editing that file, which stays out of this package's ownership)
## samples that viewport's texture at SCREEN_UV (X flipped -- see
## mirror_transform()'s own DECISION comment below for why) -- the standard
## planar-reflection technique (e.g. Half-Life 2's water, many racing games'
## puddle/floor reflections): the mirror camera shares the main camera's
## exact projection (fov/near/far/aspect), so a given screen pixel's
## mirrored-camera color is the correct reflection for that same pixel's
## real-camera ray, once that one flip is undone. No other per-pixel offset
## math is needed; the two cameras' projections lining up is what makes
## SCREEN_UV (modulo the flip) the right sample coordinate.
##
## Wired in Main.tscn with camera_path/field_path pointing at the live
## CameraRig's Camera3D and the match Field -- both are read-only from here
## (this package's own ownership keeps game/Field.gd and camera code
## untouched; every read below is a plain external property/method read, the
## same category CameraRig.gd's own class doc uses for "no deep node paths"
## -- one hop to a sibling this node was directly wired to, not a
## get_node("../../...") chain).
##
## DECISION (game/DiscMirror.gd): the disc is pulled out of the mirror
## camera's own render by giving TerritoryOverlay a second render layer
## (DISC_LAYER_BIT, bit 19/layer 20) that only the mirror camera's cull_mask
## excludes -- every other camera (CameraRig, a screenshot tool) keeps its
## default all-layers cull_mask, so this is invisible to them. Without this,
## the mirror camera would render the disc's own shader material (which
## itself samples mirror_tex), producing a one-frame-stale nested reflection
## of a reflection instead of a clean image of the blocks/sky above it.

@export var camera_path: NodePath = NodePath("")
@export var field_path: NodePath = NodePath("")
@export var visuals: TerritoryVisuals = preload("res://config/territory_visuals.tres")

const DISC_LAYER_BIT: int = 1 << 19
## Camera3D.cull_mask default (all 20 render layers on), minus DISC_LAYER_BIT.
const MIRROR_CULL_MASK: int = 0xFFFFF & ~DISC_LAYER_BIT
## mirror_resolution_scale is clamped into this range: 0 would make an
## invalid (zero-area) SubViewport, and > 1.0 would only ever cost more than
## the main viewport itself for no sharpness the main camera's own screen
## could resolve.
const MIN_RESOLUTION_SCALE: float = 0.05
const MAX_RESOLUTION_SCALE: float = 1.0

var _viewport: SubViewport = null
var _camera: Camera3D = null
var _source_camera: Camera3D = null
var _field: Field = null
var _overlay: TerritoryOverlay = null


func _ready() -> void:
	_source_camera = get_node_or_null(camera_path) as Camera3D
	_field = get_node_or_null(field_path) as Field

	_viewport = SubViewport.new()
	_viewport.name = "MirrorViewport"
	# The main scene's own World3D, not a second physics/lighting copy --
	# the mirror camera must see the same blocks/sky the main camera does.
	_viewport.own_world_3d = false
	_viewport.transparent_bg = false
	add_child(_viewport)

	_camera = Camera3D.new()
	_camera.name = "MirrorCamera"
	_camera.cull_mask = MIRROR_CULL_MASK
	_viewport.add_child(_camera)

	if _field != null:
		var overlay: TerritoryOverlay = _field.overlay()
		if overlay != null:
			_overlay = overlay
			# DECISION: REPLACES layers (not `overlay.layers | DISC_LAYER_BIT`)
			# -- VisualInstance3D.layers/Camera3D.cull_mask visibility is an
			# OR test (an instance renders if ANY shared bit is set), so
			# adding DISC_LAYER_BIT on top of the disc's default layer 1
			# would have left it visible to the mirror camera anyway through
			# that shared bit 0 (found exactly this way: a debug print
			# showed cull_mask correctly excluding bit 19, and the disc's
			# own underside still rendering in the mirror -- because its
			# layers still included bit 0 too). Every OTHER camera in this
			# project (CameraRig, every screenshot tool) keeps Godot's
			# default cull_mask (all layers on, including this one), so
			# moving the disc off layer 1 entirely does not hide it from
			# any of them.
			overlay.layers = DISC_LAYER_BIT

	_resize_viewport()


func _process(_delta: float) -> void:
	if _source_camera == null or _viewport == null or _camera == null:
		return

	# visuals.mirror_enabled off (F4, or a screenshot tool's --mirror-mode=):
	# stop paying for the second scene render entirely, not just skip
	# blending its result in shaders/territory.gdshader -- UPDATE_DISABLED
	# is the actual GPU-cost knob; camera math below would otherwise still
	# run and the viewport would still re-render every frame for nothing.
	_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if visuals.mirror_enabled else SubViewport.UPDATE_DISABLED
	)
	if _overlay != null:
		_overlay.set_mirror_texture(
			_viewport.get_texture(), visuals.mirror_enabled, visuals.mirror_strength
		)
		# Bontago-xtq.20: mirror_max_luminance has no dedicated push method on
		# TerritoryOverlay (out of this package's ownership -- see the class
		# doc above) -- material() is the same public accessor
		# tests/unit/test_territory_overlay.gd already reads shader params
		# through, so this is not a new kind of touch on that file.
		# Review (xtq.20): material() is null until TerritoryOverlay.configure()
		# has run, the same guard set_mirror_texture() applies internally.
		var overlay_material: ShaderMaterial = _overlay.material()
		if overlay_material != null:
			overlay_material.set_shader_parameter(
				&"mirror_max_luminance", visuals.mirror_max_luminance
			)
	if not visuals.mirror_enabled:
		return

	_resize_viewport()
	_camera.global_transform = mirror_transform(_source_camera.global_transform, _mirror_plane())
	_camera.fov = _source_camera.fov
	_camera.near = _source_camera.near
	_camera.far = _source_camera.far
	_camera.projection = _source_camera.projection


## Sizes the SubViewport to the main viewport's own size, scaled by
## visuals.mirror_resolution_scale -- keeping the exact same aspect ratio is
## what lets the shader sample it at SCREEN_UV directly (see class doc).
## Re-checked every frame (cheap: SubViewport.size is a no-op write when
## already the right size) so a live F4 edit of mirror_resolution_scale or a
## window resize both take effect without extra wiring.
func _resize_viewport() -> void:
	var main_size: Vector2i = get_viewport().size
	var scale: float = clampf(
		visuals.mirror_resolution_scale, MIN_RESOLUTION_SCALE, MAX_RESOLUTION_SCALE
	)
	var size: Vector2i = Vector2i(
		maxi(int(float(main_size.x) * scale), 1), maxi(int(float(main_size.y) * scale), 1)
	)
	if _viewport.size != size:
		_viewport.size = size


## The disk-local plane (world-space origin/normal) blocks reflect across --
## Field's own transform, so an M4 tilt (spec 2.1/2.7) is honoured exactly
## the way Field.gd's own surface_y()/world_from_disk_local() already
## document: the disk's world Y is only ~0 while flat, so the mirror plane
## has to come from the live transform, not a hard-coded Plane(Vector3.UP,
## 0.0).
func _mirror_plane() -> Plane:
	if _field == null:
		return Plane(Vector3.UP, 0.0)
	var field_xf: Transform3D = _field.global_transform
	return Plane(field_xf.basis.y.normalized(), field_xf.origin)


## Pure math, no SubViewport/rendering involved: reflects `camera_xf` about
## `plane`, giving the transform a physical mirror would show the camera at
## -- almost. Static and public so tests/unit/test_territory_overlay.gd can
## check a couple of sample poses directly (see that file's own mirror
## section) without ever building a SubViewport in a headless test.
##
## DECISION (game/DiscMirror.gd): `right` is deliberately NOT the naive
## per-axis reflection of camera_xf.basis.x (found the hard way: an early
## build of this feature rendered blocks and flags as an invisible/torn mess
## in the mirror -- the single-sided StandardMaterial3D cull_mode every
## Block/flag uses assumes front faces wind counter-clockwise; reflecting
## all three basis axes makes the
## resulting basis improper (determinant -1, i.e. left-handed), which flips
## that winding for every triangle rendered through it, so the rasterizer's
## backface culling discards the wrong faces). Deriving `right` instead via
## Godot's own right-hand convention (right == up.cross(back), verified
## against Transform3D.IDENTITY: (0,1,0).cross(0,0,1) == (1,0,0)) keeps the
## basis proper -- correct culling, no glitches -- at the cost of the
## rendered image being the true mirror image flipped left-right (negating
## exactly one axis of an orthonormal frame always flips its handedness back
## to proper, and here that axis is `right`). shaders/territory.gdshader's
## mirror sampling corrects for that by flipping SCREEN_UV.x when it reads
## mirror_tex (see that shader's own comment beside the uniform), so the
## final on-disc image is the correct mirror, with no culling glitches.
static func mirror_transform(camera_xf: Transform3D, plane: Plane) -> Transform3D:
	var origin: Vector3 = _reflect_point(camera_xf.origin, plane)
	var up: Vector3 = _reflect_vector(camera_xf.basis.y, plane.normal)
	var back: Vector3 = _reflect_vector(camera_xf.basis.z, plane.normal)
	var right: Vector3 = up.cross(back)
	return Transform3D(Basis(right, up, back), origin)


## Reflects a WORLD POINT across `plane`: p' = p - 2 * distance(p) * normal,
## the standard point-reflection formula (Plane.distance_to() is the signed
## distance already, consistent with plane.normal's own sign, so no extra
## sign-handling is needed here).
static func _reflect_point(point: Vector3, plane: Plane) -> Vector3:
	return point - 2.0 * plane.distance_to(point) * plane.normal


## Reflects a DIRECTION (no translation component) across a plane whose
## normal is `normal` -- the same formula as _reflect_point() minus the
## offset, since a direction has no position to be "on" one side of the
## plane or the other. Applying this to all three of a camera's basis axes
## produces a valid orthonormal (but orientation-reversing, determinant -1)
## basis, which is exactly what a mirror image is.
static func _reflect_vector(vector: Vector3, normal: Vector3) -> Vector3:
	return vector - 2.0 * vector.dot(normal) * normal
