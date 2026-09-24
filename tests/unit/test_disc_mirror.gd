extends GutTest
## game/DiscMirror.gd (Bontago-xtq.20, owner 2026-09-23 20:12: "the main
## light source is glaringly visible in the disc reflection") pushes
## mirror_max_luminance onto the shared TerritoryOverlay's material every
## frame, through that overlay's own public material() accessor -- not a
## dedicated push method on game/TerritoryOverlay.gd, which stays out of this
## package's file ownership (see DiscMirror.gd's own class doc). This is the
## one place that push is exercised end to end, through a real DiscMirror
## node's _process(); tests/unit/test_territory_overlay.gd separately pins
## the shader's own compiled-in default and its luminance-clamp math.

## Same shared-tiny-map trick test_field.gd already documents: a plain
## Field.new() against the full-size round_medium.tres map pays an ~11 s
## collision build for nothing here, since nothing below depends on the
## map's actual scale.
var _tiny_map: MapDef


func before_each() -> void:
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 6.0


## Builds a minimal live scene DiscMirror actually needs: a sibling Camera3D
## (camera_path) and a sibling Field (field_path), added to the tree in that
## order so both are already ready by the time the DiscMirror node itself is
## added (and runs its own _ready(), which resolves both paths and reads
## field.overlay()).
func _make_wired_mirror(visuals: TerritoryVisuals) -> Dictionary:
	var world: Node3D = Node3D.new()
	add_child_autofree(world)

	var camera: Camera3D = Camera3D.new()
	camera.name = "Cam"
	world.add_child(camera)

	var field: Field = Field.new()
	field.name = "F"
	field.map_def = _tiny_map
	field.visuals = visuals
	world.add_child(field)

	var mirror: DiscMirror = DiscMirror.new()
	mirror.camera_path = NodePath("../Cam")
	mirror.field_path = NodePath("../F")
	mirror.visuals = visuals
	world.add_child(mirror)

	return {"mirror": mirror, "field": field, "camera": camera}


func test_process_pushes_mirror_max_luminance_onto_the_overlay_material() -> void:
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	visuals.mirror_enabled = true
	visuals.mirror_max_luminance = 2.5
	var wired: Dictionary = _make_wired_mirror(visuals)
	var mirror: DiscMirror = wired["mirror"] as DiscMirror
	var field: Field = wired["field"] as Field

	mirror._process(0.016)

	assert_almost_eq(
		float(field.overlay().material().get_shader_parameter(&"mirror_max_luminance")),
		2.5, 0.0001,
		"DiscMirror._process() must push the current visuals.mirror_max_luminance every frame.",
	)


func test_process_pushes_an_updated_mirror_max_luminance_on_a_later_frame() -> void:
	# A live F4 edit (ui/TuningPanel.gd) changes visuals in place; the next
	# _process() tick must reflect it, not just the value at _ready() time.
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	visuals.mirror_enabled = true
	visuals.mirror_max_luminance = 1.0
	var wired: Dictionary = _make_wired_mirror(visuals)
	var mirror: DiscMirror = wired["mirror"] as DiscMirror
	var field: Field = wired["field"] as Field
	mirror._process(0.016)

	visuals.mirror_max_luminance = 3.75
	mirror._process(0.016)

	assert_almost_eq(
		float(field.overlay().material().get_shader_parameter(&"mirror_max_luminance")),
		3.75, 0.0001,
	)


# --- Bontago-xtq.21 (owner 2026-09-24: "there's a clear delay between the
# reflection and the ghost block while moving ... they don't align at all")
# -- process-order regression, same idea as tests/unit/test_camera_rig.gd's
# own Bontago-mv0.26 section: lets the real SceneTree dispatch _process()
# itself (process_priority, not call order in this test file) across
# several frames, so a fix that only reordered two direct calls in a test
# wouldn't be enough to pass it. -----------------------------------------

## Stand-in for whatever moves the source camera each frame in the real
## scene (game/CameraRig.gd, out of this package's ownership) -- moves
## `camera` a fixed step on X every _process() at a caller-chosen
## process_priority, so this test can put it at exactly CameraRig's own
## priority (1, DiscMirror.gd's class doc) without importing that file's
## private constant.
class CameraMoverStub extends Node3D:
	var camera: Camera3D
	var step_x: float = 0.1

	func _process(_delta: float) -> void:
		camera.global_position += Vector3(step_x, 0.0, 0.0)


func test_mirror_camera_tracks_the_sources_transform_the_same_frame_it_moves() -> void:
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	visuals.mirror_enabled = true
	var wired: Dictionary = _make_wired_mirror(visuals)
	var mirror: DiscMirror = wired["mirror"] as DiscMirror
	var camera: Camera3D = wired["camera"] as Camera3D

	var mover: CameraMoverStub = CameraMoverStub.new()
	mover.camera = camera
	# CameraRig.gd's own _PROCESS_PRIORITY_AFTER_GHOST -- DiscMirror must
	# still run after a mover at this exact priority (or higher) to see this
	# frame's camera pose, not last frame's.
	mover.process_priority = 1
	add_child_autofree(mover)

	# A newly add_child()'d node's first _process() call can land one
	# process_frame signal later than the frame it was actually added on
	# (Godot's own scheduling, nothing to do with this bug, same warm-up
	# test_camera_rig.gd's own Bontago-mv0.26 section documents) -- let that
	# one-time startup transient pass before the constant-motion loop below.
	await get_tree().process_frame
	await get_tree().process_frame

	for i: int in range(10):
		await get_tree().process_frame
		var expected: Transform3D = DiscMirror.mirror_transform(
			camera.global_transform, Plane(Vector3.UP, 0.0)
		)
		assert_almost_eq(
			mirror._camera.global_transform.origin.x, expected.origin.x, 0.0001,
			"frame %d: the mirror camera must reflect THIS frame's source pose, not one frame stale." % i
		)


func test_mirror_camera_has_physics_interpolation_off() -> void:
	# Bontago-xtq.21: the owner's own log showed `WARNING: [Physics
	# interpolation] Interpolated Camera3D triggered from outside physics
	# process ... MirrorCamera` -- this node's transform is fully re-derived
	# every _process() frame (never through _physics_process), so server-side
	# interpolation between physics ticks can only ever add lag on top of
	# that, never something correct to show.
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	visuals.mirror_enabled = true
	var wired: Dictionary = _make_wired_mirror(visuals)
	var mirror: DiscMirror = wired["mirror"] as DiscMirror

	assert_eq(mirror._camera.physics_interpolation_mode, Node.PHYSICS_INTERPOLATION_MODE_OFF)


func test_discmirror_process_priority_runs_after_a_priority_one_camera_mover() -> void:
	# Direct pin on the fix itself (see the class doc's own ROOT CAUSE
	# paragraph): whatever the exact margin, it must clear CameraRig.gd's own
	# priority (1) -- this is the numeric fact the process-order test above
	# exercises end to end through the real SceneTree.
	var visuals: TerritoryVisuals = TerritoryVisuals.new()
	var wired: Dictionary = _make_wired_mirror(visuals)
	var mirror: DiscMirror = wired["mirror"] as DiscMirror

	assert_gt(mirror.process_priority, 1)
