class_name GraphicsApplier
extends Node
## Applies a GraphicsPreset (viewport, sun, sky, frame cap). Child of Main; sun and skybox are
## set before add_child. Listens to Settings itself: a preset change re-applies, a window-mode
## change re-resolves the frame cap next frame.
##
## The in-match frame cap is decided here (default = display refresh, see
## GraphicsPreset.FrameCap); ui/menus/MenuBackdrop.gd arbitrates it against the menu cap.
## Headless and agent-probe runs keep the engine default. The cap also follows the window: a
## low-frequency check (GraphicsPreset.screen_check_interval_s) re-applies it when the window
## moved to another screen or the screen's refresh rate changed.

var sun: DirectionalLight3D = null
var skybox: Skybox = null
## Test seams: no display headless.
var frame_cap_in_headless: bool = false
var refresh_rate_provider: Callable = Callable()
## Receives the DisplayServer vsync mode int.
var vsync_applier: Callable = Callable()

var _cap_display_key: Vector2 = Vector2.INF
var _screen_check_timer: Timer = null


func _ready() -> void:
	Settings.graphics_preset_changed.connect(apply)
	Settings.window_mode_changed.connect(_on_window_mode_changed)


## Applies every field GraphicsPreset (config/graphics/GraphicsPreset.gd) declares.
func apply(preset: GraphicsPreset) -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.msaa_3d = preset.msaa_3d
		# only written on change; 1.0 on every shipped preset.
		if not is_equal_approx(viewport.scaling_3d_scale, preset.render_scale_3d):
			viewport.scaling_3d_scale = preset.render_scale_3d
		# DECISION: the upscaler is a preset field (Low: FSR 1.0).
		var mode: Viewport.Scaling3DMode = preset.render_scale_3d_mode as Viewport.Scaling3DMode
		if viewport.scaling_3d_mode != mode:
			viewport.scaling_3d_mode = mode

	# DECISION: Godot 4 has no per-Viewport directional-shadow-atlas size;
	# RenderingServer.directional_shadow_atlas_set_size() is the only API and it is
	# global (applies to every DirectionalLight3D; Main.tscn has exactly one).
	# `is_16bits = true` is the engine default, not a preset tunable.
	RenderingServer.directional_shadow_atlas_set_size(preset.shadow_atlas_size, true)

	_apply_frame_cap(preset)

	# cascade count / range of the sun's shadow pass.
	if sun != null:
		sun.directional_shadow_mode = preset.sun_shadow_mode as DirectionalLight3D.ShadowMode
		sun.directional_shadow_max_distance = preset.sun_shadow_max_distance

	# The Skybox owns SSR/SSAO, glow, volumetric fog, the cloud deck and the probe.
	if skybox != null:
		skybox.apply_graphics_preset(preset)


func _frame_cap_skipped() -> bool:
	return not frame_cap_in_headless and (DisplayServer.get_name() == "headless" or AgentProbe.is_active())


func _current_refresh_hz() -> float:
	if refresh_rate_provider.is_valid():
		return float(refresh_rate_provider.call())
	return DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen())


func _apply_frame_cap(preset: GraphicsPreset) -> void:
	if _frame_cap_skipped():
		return
	# DECISION: vsync is set explicitly either way; Engine.max_fps still applies
	# alongside it, so the frame cap is resolved as before.
	var vsync_mode: int = DisplayServer.VSYNC_ENABLED if preset.vsync_enabled else DisplayServer.VSYNC_DISABLED
	if vsync_applier.is_valid():
		vsync_applier.call(vsync_mode)
	else:
		DisplayServer.window_set_vsync_mode(vsync_mode as DisplayServer.VSyncMode)
	var refresh_hz: float = _current_refresh_hz()
	_cap_display_key = Vector2(float(DisplayServer.window_get_current_screen()), refresh_hz)
	MenuBackdrop.set_match_cap(FrameCapRule.resolve_for_preset(preset, refresh_hz))
	if _screen_check_timer == null and DisplayServer.get_name() != "headless":
		_screen_check_timer = Timer.new()
		_screen_check_timer.wait_time = preset.screen_check_interval_s
		_screen_check_timer.timeout.connect(_recheck_frame_cap)
		add_child(_screen_check_timer)
		_screen_check_timer.start()


## Re-applies the cap only when the window's screen or that screen's refresh changed.
func _recheck_frame_cap() -> void:
	if _frame_cap_skipped():
		return
	var key: Vector2 = Vector2(float(DisplayServer.window_get_current_screen()), _current_refresh_hz())
	if key != _cap_display_key:
		_apply_frame_cap(Settings.current_graphics_preset())


func _on_window_mode_changed(_id: StringName) -> void:
	# The OS moves/resizes the window after apply_window_mode(); read the screen next frame.
	_apply_frame_cap.call_deferred(Settings.current_graphics_preset())
