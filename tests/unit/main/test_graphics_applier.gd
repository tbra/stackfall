extends GutTest
## GraphicsApplier contract (P7 plan section 2.1): apply(preset) writes every GraphicsPreset field
## to the viewport, the sun and the skybox, and resolves the frame cap through the injected seams
## (skipped headless unless frame_cap_in_headless). The applier also listens to Settings itself.
## Built standalone: sun and skybox are set before add_child, no Main scene.

var _applier: GraphicsApplier = null
var _sun: DirectionalLight3D = null
var _before_fps: int = 0
var _before_msaa: Viewport.MSAA = Viewport.MSAA_DISABLED
var _before_scale: float = 1.0
var _before_mode: Viewport.Scaling3DMode = Viewport.SCALING_3D_MODE_BILINEAR
var _original_preset_id: StringName
var _modes: Array[int] = []


func before_each() -> void:
	_before_fps = Engine.max_fps
	var viewport: Viewport = get_viewport()
	_before_msaa = viewport.msaa_3d
	_before_scale = viewport.scaling_3d_scale
	_before_mode = viewport.scaling_3d_mode
	_original_preset_id = Settings.current_graphics_preset().id
	_modes.clear()
	_sun = DirectionalLight3D.new()
	_applier = GraphicsApplier.new()
	_applier.sun = _sun
	add_child_autofree(_sun)
	add_child_autofree(_applier)


func after_each() -> void:
	Settings.set_graphics_preset(_original_preset_id)
	var viewport: Viewport = get_viewport()
	viewport.msaa_3d = _before_msaa
	viewport.scaling_3d_scale = _before_scale
	viewport.scaling_3d_mode = _before_mode
	MenuBackdrop._match_cap = -1
	Engine.max_fps = _before_fps


## Frame-cap tests: the seams are what the applier is documented to read (no display headless).
func _cap_seams(hz: float) -> void:
	_applier.frame_cap_in_headless = true
	_applier.refresh_rate_provider = func() -> float: return hz
	_applier.vsync_applier = func(mode: int) -> void: _modes.append(mode)


## A fresh preset with the given GraphicsPreset fields set (name -> value).
func _preset(fields: Dictionary = {}) -> GraphicsPreset:
	var preset: GraphicsPreset = GraphicsPreset.new()
	preset.id = &"contract"
	for field: StringName in fields:
		preset.set(field, fields[field])
	return preset


func test_apply_writes_msaa_and_render_scale_to_the_viewport() -> void:
	var preset: GraphicsPreset = _preset({&"msaa_3d": Viewport.MSAA_4X, &"render_scale_3d": 0.75, &"render_scale_3d_mode": 1})
	_applier.apply(preset)
	var viewport: Viewport = get_viewport()
	assert_eq(viewport.msaa_3d, Viewport.MSAA_4X)
	assert_almost_eq(viewport.scaling_3d_scale, 0.75, 0.0001)
	assert_eq(viewport.scaling_3d_mode, Viewport.SCALING_3D_MODE_FSR)


func test_apply_again_follows_the_latest_preset() -> void:
	_applier.apply(_preset({&"msaa_3d": Viewport.MSAA_8X}))
	assert_eq(get_viewport().msaa_3d, Viewport.MSAA_8X)
	_applier.apply(_preset({&"msaa_3d": Viewport.MSAA_DISABLED}))
	assert_eq(get_viewport().msaa_3d, Viewport.MSAA_DISABLED)


func test_apply_writes_the_sun_shadow_mode_and_distance() -> void:
	_applier.apply(
		_preset({&"sun_shadow_mode": 1, &"sun_shadow_max_distance": 42.0})
	)
	assert_eq(_sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS)
	assert_almost_eq(_sun.directional_shadow_max_distance, 42.0, 0.0001)


func test_apply_without_sun_or_skybox_is_harmless() -> void:
	var bare: GraphicsApplier = GraphicsApplier.new()
	add_child_autofree(bare)
	bare.apply(_preset({&"msaa_3d": Viewport.MSAA_2X}))
	assert_eq(get_viewport().msaa_3d, Viewport.MSAA_2X, "the viewport is still written")


func test_apply_reaches_the_skybox() -> void:
	var environment: Environment = Environment.new()
	environment.sky = Sky.new()
	var skybox: Skybox = Skybox.new()
	skybox.config = SkyboxConfig.new()
	skybox.sky_def = SkyTestKit.cycle()
	skybox.environment = environment
	add_child_autofree(skybox)
	var bare: GraphicsApplier = GraphicsApplier.new()
	bare.skybox = skybox
	add_child_autofree(bare)
	bare.apply(_preset({&"ssr_enabled": false}))
	assert_false(skybox.environment.ssr_enabled, "SSR off in the preset reaches the skybox's environment")
	bare.apply(_preset({&"ssr_enabled": true}))
	assert_true(skybox.environment.ssr_enabled, "and back on")


func test_settings_preset_change_is_applied_without_a_manual_apply() -> void:
	Settings.set_graphics_preset(&"low")
	var low: GraphicsPreset = Settings.current_graphics_preset()
	assert_eq(get_viewport().msaa_3d, low.msaa_3d)
	assert_eq(_sun.directional_shadow_mode, low.sun_shadow_mode as DirectionalLight3D.ShadowMode)
	Settings.set_graphics_preset(&"high")
	var high: GraphicsPreset = Settings.current_graphics_preset()
	assert_eq(get_viewport().msaa_3d, high.msaa_3d)
	assert_almost_eq(_sun.directional_shadow_max_distance, high.sun_shadow_max_distance, 0.0001)


func test_frame_cap_is_skipped_headless_unless_opted_in() -> void:
	_applier.refresh_rate_provider = func() -> float: return 144.0
	_applier.vsync_applier = func(mode: int) -> void: _modes.append(mode)
	_applier.apply(_preset())
	assert_eq(Engine.max_fps, _before_fps, "engine cap untouched headless")
	assert_eq(_modes.size(), 0, "vsync untouched headless")


func test_frame_cap_defaults_to_display_refresh_with_fallback() -> void:
	_cap_seams(144.0)
	_applier.apply(_preset())
	assert_eq(Engine.max_fps, 144)
	_applier.refresh_rate_provider = func() -> float: return 0.0
	var preset: GraphicsPreset = _preset({&"fallback_fps": 75})
	_applier.apply(preset)
	assert_eq(Engine.max_fps, 75, "fallback when the display reports <= 0")


func test_frame_cap_fixed_and_uncapped_modes() -> void:
	_cap_seams(144.0)
	_applier.apply(
		_preset({&"frame_cap_mode": GraphicsPreset.FrameCap.FIXED, &"fixed_fps": 90})
	)
	assert_eq(Engine.max_fps, 90)
	_applier.apply(_preset({&"frame_cap_mode": GraphicsPreset.FrameCap.UNCAPPED}))
	assert_eq(Engine.max_fps, 0)


func test_vsync_follows_the_preset_and_leaves_the_cap_alone() -> void:
	_cap_seams(144.0)
	_applier.apply(_preset())
	if _modes.is_empty():
		fail_test("vsync applied")
		return
	assert_eq(_modes.back(), DisplayServer.VSYNC_ENABLED)
	_applier.apply(_preset({&"vsync_enabled": false}))
	assert_gt(_modes.size(), 1, "vsync applied again")
	assert_eq(_modes.back(), DisplayServer.VSYNC_DISABLED)
	assert_eq(Engine.max_fps, 144, "cap unchanged by vsync")


func test_window_mode_change_reapplies_the_cap_next_frame() -> void:
	_cap_seams(144.0)
	_applier.apply(_preset())
	assert_eq(Engine.max_fps, 144)
	_applier.refresh_rate_provider = func() -> float: return 60.0
	Settings.window_mode_changed.emit(&"windowed")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(Engine.max_fps, 60, "the cap follows the display after a window-mode change")


func test_menu_match_preset_change_menu_sequence_ends_with_right_caps() -> void:
	var menu_cap: int = load("res://config/ui/menu_visual_tuning.tres").menu_max_fps
	_cap_seams(144.0)
	_applier.apply(_preset())
	assert_eq(Engine.max_fps, 144, "match")
	var backdrop: MenuBackdrop = MenuBackdrop.new()
	add_child(backdrop)
	assert_eq(Engine.max_fps, menu_cap, "menu cap in the menu")
	_applier.apply(_preset({&"vsync_enabled": false}))
	assert_eq(Engine.max_fps, menu_cap, "preset change in the menu keeps the menu cap")
	_applier.refresh_rate_provider = func() -> float: return 60.0
	_applier.apply(_preset())
	backdrop.free()
	assert_eq(Engine.max_fps, 60, "match cap from the latest preset after the menu closes")
	var again: MenuBackdrop = MenuBackdrop.new()
	add_child(again)
	assert_eq(Engine.max_fps, menu_cap)
	again.free()
	assert_eq(Engine.max_fps, 60, "back in the match")
