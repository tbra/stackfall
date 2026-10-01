class_name SunFlare
extends CanvasLayer
## Bontago-mp0.3.4 (Graphics pass 2, owner feedback feedback/graphics_
## feedback.md: "lens flare from the sun"): a screen-space lens flare -- a
## tight starburst sparkle at the sun's own screen position, plus ghost
## discs sampled along the axis from the sun to the screen center -- drawn
## via a full-viewport ColorRect using vfx/sun_flare.gdshader
## (render_mode blend_add: additive, so it only ever brightens, never
## darkens, whatever scene geometry is already on screen). Every visual
## number lives in config/SunFlareConfig.gd (`config`, see its own class doc
## for why it is not yet reachable from the in-game F4 panel).
##
## Fix round (owner: "move god rays into the sky, they're painting dark
## spokes over the disc"): the big warm sun halo and long god-ray beams are
## NOT drawn here anymore -- they moved into shaders/sunset_clouds.gdshader
## (part of the sky render pass, so they sit behind every opaque object for
## free, unlike this screen-space layer which draws on top of everything).
## This script only ever renders the true camera-lens artifacts.
##
## config.sun_direction is a fixed world-space direction (see that field's
## own DECISION for why it is measured from the painted sunset panorama, not
## Main.tscn's DirectionalLight3D rotation), so this script's only per-frame
## job is: project that direction from the live camera into screen UV
## (_sun_screen_uv()), decide how visible the flare should be right now
## (_compute_visibility(): facing the camera, not off past the screen edge,
## not occluded by scene geometry), and smooth that visibility over time
## (config.visibility_lerp_speed) so a single occluding frame does not pop
## the flare fully on/off.
##
## Host and client both run this identically -- it reads only the live
## Camera3D and the physics world for its one occlusion raycast, never
## Net/MultiplayerAPI, matching this package's visual-only, no-gameplay-
## change contract.

@export var config: SunFlareConfig = preload("res://config/sun_flare.tres")
## Wired in Main.tscn to the live gameplay camera (game/CameraRig.tscn's own
## Camera3D), the same NodePath convention game/DiscMirror.gd's own
## camera_path/field_path already use for a sibling-node reference resolved
## once at _ready() rather than a deep get_node("../..") chain.
@export var camera_path: NodePath = NodePath("")

const FLARE_SHADER: Shader = preload("res://vfx/sun_flare.gdshader")

## # DECISION (vfx/SunFlare.gd): a fixed local constant, not a
## config/SunFlareConfig.gd field -- this is an implementation detail of how
## "which screen pixel is the sun's direction" is computed (a point far
## enough along sun_direction that Camera3D.unproject_position() treats it as
## effectively at infinity, the same trick a real directional light's flare
## would use), not a tunable a playtester would ever want to move; matches
## game/Block.gd's own IMPACT_EMIT_INTERVAL_MS DECISION for the same
## distinction. _sun_projection_distance() below additionally clamps this
## against the live camera's own `far` clip plane (Camera3D's engine default
## is 4000 m, less than this constant) as a defensive measure so a future
## camera/preset with a much shorter far plane can never end up projecting a
## point past it.
##
## While debugging this file's own tests/unit/test_sun_flare.gd, an
## unproject_position() call right after a freshly created, never-ticked
## Camera3D's own look_at() read back a wildly wrong screen position
## (~3727px in a 1280px-wide viewport for a camera looking directly at the
## projected point) -- NOT a far-plane issue (unproject_position()'s x/y
## math does not depend on the far plane at all), but "physics interpolation
## on" (CLAUDE.md's tech rules): the camera's rendering-side transform lags
## one physics tick behind a script's own global_position/look_at() write
## until a physics step syncs it. See that test file's own
## _make_camera_facing() doc for the fix (await wait_physics_frames()) --
## a real gameplay camera never hits this, since it is already moving every
## frame by the time this script reads it.
const SUN_PROJECTION_DISTANCE_M: float = 5000.0

var _rect: ColorRect = null
var _material: ShaderMaterial = null
var _camera: Camera3D = null
var _current_visibility: float = 0.0
var _enabled: bool = true
## Bontago-adt: the active SkyThemeDef's sun_flare_enabled (Skybox.apply_theme()
## pushes it through set_theme_enabled(); night turns the sunset-aimed flare off).
var _theme_enabled: bool = true

const GROUP: StringName = &"sun_flare"


func _ready() -> void:
	add_to_group(GROUP)
	_rect = ColorRect.new()
	_rect.name = &"FlareRect"
	_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	_material = ShaderMaterial.new()
	_material.shader = FLARE_SHADER
	_rect.material = _material
	_camera = get_node_or_null(camera_path) as Camera3D
	var preset: GraphicsPreset = Settings.current_graphics_preset()
	_enabled = preset == null or preset.volumetric_fog_enabled
	Settings.graphics_preset_changed.connect(_on_graphics_preset_changed)


func _exit_tree() -> void:
	if Settings.graphics_preset_changed.is_connected(_on_graphics_preset_changed):
		Settings.graphics_preset_changed.disconnect(_on_graphics_preset_changed)


## Reuses the same volumetric_fog_enabled flag game/Skybox.gd and this
## package's own game/BlockEffectsManager.gd already gate their own Low-
## preset-disabled heavy bits on (docs/M7_ART_DIRECTION.md's performance
## budget) -- a full-viewport shader pass is exactly that kind of "heavy
## bit" on Low.
func _on_graphics_preset_changed(preset: GraphicsPreset) -> void:
	_enabled = preset == null or preset.volumetric_fog_enabled


## Bontago-adt: theme gate (see _theme_enabled). Fades out via the hidden rect
## immediately; the smoothed visibility restarts from 0 on re-enable.
func set_theme_enabled(value: bool) -> void:
	_theme_enabled = value
	if not value:
		_current_visibility = 0.0


func is_theme_enabled() -> bool:
	return _theme_enabled


func _process(delta: float) -> void:
	if _rect == null or _material == null:
		return
	if not _enabled or not _theme_enabled or _camera == null or config == null or not is_instance_valid(_camera):
		_rect.visible = false
		return
	_rect.visible = true

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / maxf(viewport_size.y, 1.0)

	var target_visibility: float = _compute_visibility()
	var lerp_amount: float = clampf(config.visibility_lerp_speed * delta, 0.0, 1.0)
	_current_visibility = lerpf(_current_visibility, target_visibility, lerp_amount)

	_material.set_shader_parameter(&"sun_uv", _sun_screen_uv())
	_material.set_shader_parameter(&"visibility", _current_visibility)
	_material.set_shader_parameter(&"sun_color", config.sun_color)
	_material.set_shader_parameter(&"core_radius", config.core_radius)
	_material.set_shader_parameter(&"core_softness", config.core_softness)
	_material.set_shader_parameter(&"core_intensity", config.core_intensity)
	_material.set_shader_parameter(&"ray_count", float(config.ray_count))
	_material.set_shader_parameter(&"ray_length", config.ray_length)
	_material.set_shader_parameter(&"ray_sharpness", config.ray_sharpness)
	_material.set_shader_parameter(&"ray_intensity", config.ray_intensity)
	_material.set_shader_parameter(&"ghost_count", float(config.ghost_count))
	_material.set_shader_parameter(&"ghost_positions", _ghost_positions_vector4())
	_material.set_shader_parameter(&"ghost_base_size", config.ghost_base_size)
	_material.set_shader_parameter(&"ghost_size_falloff", config.ghost_size_falloff)
	_material.set_shader_parameter(&"ghost_alpha", config.ghost_alpha)
	_material.set_shader_parameter(&"ghost_ring_width", config.ghost_ring_width)
	_material.set_shader_parameter(&"ghost_color_b", config.ghost_color_b)
	_material.set_shader_parameter(&"aspect_ratio", aspect)
	_material.set_shader_parameter(&"max_intensity", config.max_intensity)


## config.ghost_positions is a PackedFloat32Array (an easy list to hand-tune
## in the Resource inspector); the shader only accepts a fixed vec4 uniform
## (GLSL has no dynamic-length uniform arrays without a much heavier UBO
## setup this one small effect does not need) -- padded with -1.0 (the
## shader's own "skip this slot" sentinel) for any of the 4 slots past
## config's own array length.
func _ghost_positions_vector4() -> Vector4:
	var values: PackedFloat32Array = config.ghost_positions
	var result: Vector4 = Vector4(-1.0, -1.0, -1.0, -1.0)
	if values.size() > 0:
		result.x = values[0]
	if values.size() > 1:
		result.y = values[1]
	if values.size() > 2:
		result.z = values[2]
	if values.size() > 3:
		result.w = values[3]
	return result


## 0 (fully hidden) to 1 (fully shown): the sun must be roughly ahead of the
## camera (min_facing_dot), inside the screen rect plus a fade margin
## (_edge_fade()), and not blocked by scene geometry (_occlusion_factor()).
## The caller smooths the result over time; this function itself is a plain
## per-frame snapshot with no memory of its own.
func _compute_visibility() -> float:
	var direction: Vector3 = config.sun_direction.normalized()
	var camera_forward: Vector3 = -_camera.global_transform.basis.z
	var facing_dot: float = camera_forward.dot(direction)
	if facing_dot < config.min_facing_dot:
		return 0.0
	var uv: Vector2 = _sun_screen_uv()
	var edge_fade: float = _edge_fade(uv)
	if edge_fade <= 0.0:
		return 0.0
	return edge_fade * _occlusion_factor(direction)


## Projects a point far along config.sun_direction from the camera into
## normalized screen UV (0..1 x 0..1), the same coordinate space
## vfx/sun_flare.gdshader's SCREEN_UV/UV already uses. Only meaningful once
## _compute_visibility() has already confirmed the sun is roughly ahead of
## the camera -- Camera3D.unproject_position() on a point behind the camera
## can still land inside the 0..1 rect, which is exactly why that check runs
## first and gates the result down to 0 rather than trusting this UV alone.
func _sun_screen_uv() -> Vector2:
	# DECISION (vfx/SunFlare.gd): reads get_viewport().get_visible_rect().size
	# itself rather than accepting it as a parameter -- Camera3D.
	# unproject_position() always resolves screen pixels against the
	# camera's own associated Viewport internally, so normalizing by any
	# other size here would silently disagree with it.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Vector2(0.5, 0.5)
	var far_point: Vector3 = _camera.global_position + config.sun_direction.normalized() * _sun_projection_distance()
	var screen_pos: Vector2 = _camera.unproject_position(far_point)
	return screen_pos / viewport_size


## See SUN_PROJECTION_DISTANCE_M's own DECISION above for why this must never
## exceed the live camera's own far clip plane.
func _sun_projection_distance() -> float:
	return minf(SUN_PROJECTION_DISTANCE_M, _camera.far * 0.9)


func _edge_fade(uv: Vector2) -> float:
	var offset: Vector2 = (uv - Vector2(0.5, 0.5)).abs()
	var max_extent: float = 0.5 + config.edge_fade_margin
	var fade_x: float = 1.0 - smoothstep(0.5, max_extent, offset.x)
	var fade_y: float = 1.0 - smoothstep(0.5, max_extent, offset.y)
	return clampf(fade_x, 0.0, 1.0) * clampf(fade_y, 0.0, 1.0)


## One raycast from the camera toward the sun direction -- cheap (a single
## PhysicsDirectSpaceState3D.intersect_ray() call per frame), matching this
## package's brief ("check with a raycast or depth, cheap"). Any hit at all
## fades the flare fully out for this frame; _compute_visibility()'s caller
## (_process()) is what actually smooths that binary result over
## config.visibility_lerp_speed so a single frame's occlusion does not pop
## the flare off instantly.
func _occlusion_factor(direction: Vector3) -> float:
	var world: World3D = _camera.get_world_3d()
	if world == null:
		return 1.0
	var space_state: PhysicsDirectSpaceState3D = world.direct_space_state
	if space_state == null:
		return 1.0
	var from: Vector3 = _camera.global_position
	var to: Vector3 = from + direction * _sun_projection_distance()
	var params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	var result: Dictionary = space_state.intersect_ray(params)
	return 0.0 if not result.is_empty() else 1.0


## Test/inspection seam: the visibility _process() last smoothed toward, so a
## test can drive _compute_visibility()/the lerp directly without a real
## rendered frame.
func current_visibility() -> float:
	return _current_visibility


## Test/inspection seam for _on_graphics_preset_changed()'s own Low-preset
## gate, the same style as game/BlockEffectsManager.gd's own
## active_effect_count().
func is_flare_enabled() -> bool:
	return _enabled
