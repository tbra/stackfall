extends GutTest
## vfx/SunFlare.gd (Bontago-mp0.3.4, Graphics pass 2): the screen-space lens
## flare's pure-ish geometry/visibility helpers, driven directly without a
## real rendered frame (matching game/Skybox.gd's/game/BlockEffectsManager.gd's
## own headless-test approach for their own visual systems).

## Saved/restored the same way tests/unit/test_skybox.gd's own
## _original_preset_id does -- the real Settings autoload outlives this
## script.
var _original_preset_id: StringName


func before_each() -> void:
	_original_preset_id = Settings.current_graphics_preset().id


func after_each() -> void:
	Settings.set_graphics_preset(_original_preset_id)


func _make_flare() -> SunFlare:
	var flare: SunFlare = SunFlare.new()
	flare.config = load("res://config/sun_flare.tres") as SunFlareConfig
	add_child_autofree(flare)
	return flare


## Bontago-mp0.3.4 fix round: a freshly created, never-ticked Camera3D's
## rendering-side transform (what Camera3D.unproject_position() actually
## projects against) lags one physics tick behind a script's own
## global_position/look_at() write here, because "physics interpolation on"
## (CLAUDE.md's tech rules) holds the camera's visual transform at its old
## value until the next physics step syncs it -- reproduced while writing
## this test (an un-awaited unproject_position() call read back the
## camera's pre-look_at identity orientation instead). A real gameplay
## camera never hits this: it already moves every frame, so its visual
## transform is always caught up by the time vfx/SunFlare.gd reads it the
## following frame. A test building a bare, one-shot camera has to wait for
## that same catch-up explicitly.
func _make_camera_facing(direction: Vector3) -> Camera3D:
	var camera: Camera3D = Camera3D.new()
	add_child_autofree(camera)
	camera.global_position = Vector3.ZERO
	camera.look_at(direction.normalized(), Vector3.UP if absf(direction.normalized().y) < 0.99 else Vector3.FORWARD)
	await wait_physics_frames(2)
	return camera


func test_sun_screen_uv_lands_near_screen_center_when_camera_faces_the_sun() -> void:
	var flare: SunFlare = _make_flare()
	var camera: Camera3D = await _make_camera_facing(flare.config.sun_direction)
	flare._camera = camera

	var uv: Vector2 = flare._sun_screen_uv()

	assert_almost_eq(uv.x, 0.5, 0.05, "a camera looking straight at the sun direction must project it near screen-center X.")
	assert_almost_eq(uv.y, 0.5, 0.05, "a camera looking straight at the sun direction must project it near screen-center Y.")


func test_visibility_is_zero_when_camera_faces_away_from_the_sun() -> void:
	var flare: SunFlare = _make_flare()
	var camera: Camera3D = await _make_camera_facing(-flare.config.sun_direction)
	flare._camera = camera

	var visibility: float = flare._compute_visibility()

	assert_eq(visibility, 0.0, "facing directly away from the sun must gate visibility to zero via min_facing_dot.")


func test_visibility_is_positive_when_camera_faces_the_sun_with_no_occluder() -> void:
	var flare: SunFlare = _make_flare()
	var camera: Camera3D = await _make_camera_facing(flare.config.sun_direction)
	flare._camera = camera

	var visibility: float = flare._compute_visibility()

	assert_gt(visibility, 0.0, "facing the sun with nothing between the camera and it must not be gated to zero.")


func test_edge_fade_is_full_at_center_and_zero_far_outside() -> void:
	var flare: SunFlare = _make_flare()

	assert_almost_eq(flare._edge_fade(Vector2(0.5, 0.5)), 1.0, 0.001, "screen center must be fully visible.")
	assert_eq(flare._edge_fade(Vector2(-2.0, 0.5)), 0.0, "far outside the edge_fade_margin must be fully faded.")


func test_low_graphics_preset_disables_the_flare() -> void:
	var flare: SunFlare = _make_flare()
	assert_true(flare.is_flare_enabled(), "fixture: the flare must start enabled on the current (non-Low) preset.")

	Settings.set_graphics_preset(&"low")

	assert_false(flare.is_flare_enabled(), "the Low graphics preset must disable the full-viewport flare pass.")
