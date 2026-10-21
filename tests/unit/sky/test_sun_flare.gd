extends GutTest
## game/sky/SunFlare.gd (Graphics pass 2): the screen-space lens
## flare's pure-ish geometry/visibility helpers, driven directly without a
## real rendered frame (matching game/sky/Skybox.gd's/game/BlockEffectsManager.gd's
## own headless-test approach for their own visual systems).

## Saved/restored the same way tests/unit/sky/test_skybox.gd's own
## _original_preset_id does -- the real Settings autoload outlives this
## script.
var _original_preset_id: StringName


func before_each() -> void:
	_original_preset_id = Settings.current_graphics_preset().id


func after_each() -> void:
	Settings.set_graphics_preset(_original_preset_id)


func _make_flare() -> SunFlare:
	var flare: SunFlare = SunFlare.new()
	flare.config = load("res://config/sky/sun_flare.tres") as SunFlareConfig
	add_child_autofree(flare)
	return flare


## fix round: a freshly created, never-ticked Camera3D's
## rendering-side transform (what Camera3D.unproject_position() actually
## projects against) lags one physics tick behind a script's own
## global_position/look_at() write here, because "physics interpolation on"
## (CLAUDE.md's tech rules) holds the camera's visual transform at its old
## value until the next physics step syncs it -- reproduced while writing
## this test (an un-awaited unproject_position() call read back the
## camera's pre-look_at identity orientation instead). A real gameplay
## camera never hits this: it already moves every frame, so its visual
## transform is always caught up by the time game/sky/SunFlare.gd reads it the
## following frame. A test building a bare, one-shot camera has to wait for
## that same catch-up explicitly.
func _make_camera_facing(direction: Vector3) -> Camera3D:
	var camera: Camera3D = Camera3D.new()
	add_child_autofree(camera)
	camera.global_position = Vector3.ZERO
	camera.look_at(direction.normalized(), Vector3.UP if absf(direction.normalized().y) < 0.99 else Vector3.FORWARD)
	await wait_physics_frames(2)
	return camera


func test_visibility_is_zero_when_camera_faces_away_from_the_sun() -> void:
	var flare: SunFlare = _make_flare()
	var camera: Camera3D = await _make_camera_facing(-flare.config.sun_direction)
	flare._camera = camera

	var visibility: float = flare._compute_visibility()

	assert_eq(visibility, 0.0, "facing directly away from the sun must gate visibility to zero via min_facing_dot.")


const DISC_RADIUS_M: float = 6.0
const BELOW_DISC_M: float = 20.0
const CLOUD_DISTANCE_M: float = 300.0
const SIDEWAYS_M: float = 400.0


func _tiny_field() -> Field:
	var map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true) as MapDef
	map.field_radius = DISC_RADIUS_M
	var field: Field = Field.new()
	field.map_def = map
	add_child_autofree(field)
	return field


## The flare with its own copy of the config (the shared resource must not be edited) aimed along `sun`.
func _flare_aimed(sun: Vector3) -> SunFlare:
	var flare: SunFlare = SunFlare.new()
	flare.config = (load("res://config/sky/sun_flare.tres") as SunFlareConfig).duplicate() as SunFlareConfig
	flare.config.sun_direction = sun.normalized()
	add_child_autofree(flare)
	return flare


func _camera_at(position: Vector3, look: Vector3) -> Camera3D:
	var camera: Camera3D = Camera3D.new()
	add_child_autofree(camera)
	camera.global_position = position
	camera.look_at(position + look.normalized(), Vector3.UP if absf(look.normalized().y) < 0.99 else Vector3.FORWARD)
	await wait_physics_frames(2)
	return camera


func test_disc_blocks_the_flare_ray_seen_from_below() -> void:
	_tiny_field()
	var sun: Vector3 = Vector3(0.25, 1.0, 0.1).normalized()
	var flare: SunFlare = _flare_aimed(sun)
	# Aimed so the ray crosses the disc well inside the rim and off the 1 m grid lines (a ray through a
	# quad corner or the jagged rim cells is a coin toss for any trimesh query).
	var camera: Camera3D = await _camera_at(Vector3(-3.37, -BELOW_DISC_M, -1.21), sun)
	flare._camera = camera
	# The faulty path, reproduced: the single forward ray crosses the one-sided disc unhit.
	var forward: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position + sun * 100.0)
	assert_true(camera.get_world_3d().direct_space_state.intersect_ray(forward).is_empty(),
			"fixture: the forward ray from below passes through the single-sided disc without a hit")
	assert_eq(flare._occlusion_factor(sun), 0.0, "the reverse ray finds the disc, so the sun is hidden from below")
	assert_eq(flare._compute_visibility(), 0.0, "and the flare visibility follows")
	flare.config.reverse_ray_enabled = false
	assert_eq(flare._occlusion_factor(sun), 1.0, "with the reverse ray off, the old single ray lets the sun through")


func test_open_sky_beside_the_disc_is_not_occluded() -> void:
	_tiny_field()
	var sun: Vector3 = Vector3(0.25, 1.0, 0.1).normalized()
	var flare: SunFlare = _flare_aimed(sun)
	var camera: Camera3D = await _camera_at(Vector3(DISC_RADIUS_M * 4.0, -BELOW_DISC_M, 0.0), sun)
	flare._camera = camera
	assert_eq(flare._occlusion_factor(sun), 1.0, "a camera beside the disc has a clear line to the sun")
	var above: Camera3D = await _camera_at(Vector3(0.0, 10.0, 0.0), sun)
	flare._camera = above
	assert_eq(flare._occlusion_factor(sun), 1.0, "a camera above the disc looking at a sun above it is not blocked")


## A CloudSea holding one puff, built where tests can aim a camera at it; no drift, so the clock is irrelevant.
func _single_puff_sea() -> CloudSea:
	var def: SkyCycleDef = SkyTestKit.cycle()
	def.cloud_clump_count = 1
	def.cloud_bank_count = 0
	def.proc_far_count = 0
	def.cloud_puffs_per_clump = 1
	def.cloud_drift_speed_min_mps = 0.0
	def.cloud_drift_speed_max_mps = 0.0
	var sea: CloudSea = CloudSea.new()
	add_child_autofree(sea)
	sea.configure_cycle(def, null, 1.0, 1)
	return sea


## The visibility _process() last handed the flare shader, read off the rect's material.
func _shown_visibility(flare: SunFlare) -> float:
	var rect: ColorRect = flare.get_node("FlareRect") as ColorRect
	return (rect.material as ShaderMaterial).get_shader_parameter(&"visibility") as float


func test_flare_is_hidden_by_a_cloud_and_follows_the_cloud_strength() -> void:
	var sea: CloudSea = _single_puff_sea()
	var centre: Vector3 = SkyTestKit.puff_centre(sea)
	var sun: Vector3 = Vector3(1.0, 0.0, 0.0)
	var flare: SunFlare = _flare_aimed(sun)
	flare.config.cloud_occlusion_refresh_s = 0.0
	var camera: Camera3D = await _camera_at(centre - sun * CLOUD_DISTANCE_M, sun)
	flare._camera = camera
	assert_eq(flare._occlusion_factor(sun), 1.0, "fixture: no physics body anywhere (puffs are not bodies)")
	assert_lt(flare._compute_visibility(), 0.01, "the puff between the camera and the sun hides the flare")
	flare.config.cloud_occlusion_strength = 0.0
	assert_gt(flare._compute_visibility(), 0.5, "with clouds ignored the same view shows the flare")
	flare.config.cloud_occlusion_strength = 0.5
	var half: float = flare._compute_visibility()
	assert_almost_eq(half, 0.5 * flare._edge_fade(flare._sun_screen_uv()), 0.02, "strength scales how much of a fully hidden sun is dimmed")
	# Clear sky: the same camera shifted well sideways sees the sun.
	flare.config.cloud_occlusion_strength = 1.0
	var clear_camera: Camera3D = await _camera_at(centre - sun * CLOUD_DISTANCE_M + Vector3(0.0, 0.0, SIDEWAYS_M), sun)
	flare._camera = clear_camera
	assert_gt(flare._compute_visibility(), 0.5, "a clear line to the sun leaves the flare visible")


func test_cloud_occlusion_fades_in_over_time_instead_of_popping() -> void:
	var sea: CloudSea = _single_puff_sea()
	var centre: Vector3 = SkyTestKit.puff_centre(sea)
	var sun: Vector3 = Vector3(1.0, 0.0, 0.0)
	var flare: SunFlare = _flare_aimed(sun)
	flare.config.cloud_occlusion_refresh_s = 0.0
	var clear: Camera3D = await _camera_at(centre - sun * CLOUD_DISTANCE_M + Vector3(0.0, 0.0, SIDEWAYS_M), sun)
	flare._camera = clear
	flare._process(1.0)
	var open_sky: float = _shown_visibility(flare)
	assert_gt(open_sky, 0.5, "fixture: the flare settles visible in the clear")
	var blocked: Camera3D = await _camera_at(centre - sun * CLOUD_DISTANCE_M, sun)
	flare._camera = blocked
	flare._process(0.016)
	var after_one_frame: float = _shown_visibility(flare)
	assert_lt(after_one_frame, open_sky, "the cloud starts dimming the flare at once")
	assert_gt(after_one_frame, open_sky * 0.5, "but one frame does not slam it off")
	flare._process(2.0)
	assert_lt(_shown_visibility(flare), 0.01, "and given time it is gone behind the cloud")

