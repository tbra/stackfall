class_name Minimap
extends PanelContainer
## Top-down live minimap for M7 P5 (docs/M7_PLAN.md "P5 -- HUD minimap +
## reskin"). Owns a SubViewport with an orthographic Camera3D that shares the
## main scene's own World3D, so the disk/blocks/territory the minimap shows
## are the live scene, not a second independently-maintained renderer
## (docs/M7_ART_DIRECTION.md's HUD styling section, option (a), owner-
## selected: "live orthographic SubViewport camera ... recommended").
##
## ui/HUD.gd owns one of these (instanced directly in ui/HUD.tscn, script-
## built rather than its own .tscn -- game/DiscMirror.gd is the precedent for
## a SubViewport+Camera3D node built entirely in _ready() with no child scene
## of its own) and calls set_map_def() whenever it learns a match's MapDef
## (_on_territory_share_changed(), the plan's chosen hook: "no new signal
## needed"). Stays invisible and its SubViewport disabled
## (UPDATE_DISABLED) until the first set_map_def(with a non-null MapDef) --
## a menu/no-match HUD instance renders nothing and costs nothing, per the
## brief's acceptance check.

@export var tuning: HUDVisualTuning = preload("res://config/hud_visual_tuning.tres")

var _viewport: SubViewport = null
var _camera: Camera3D = null
var _texture_rect: TextureRect = null
var _refresh_timer: Timer = null
var _map_def: MapDef = null


func _ready() -> void:
	custom_minimum_size = Vector2(tuning.minimap_size_px, tuning.minimap_size_px)

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = tuning.minimap_backdrop_color
	style.border_color = tuning.minimap_frame_color
	style.set_border_width_all(int(tuning.panel_border_width_px))
	style.set_corner_radius_all(int(tuning.panel_corner_radius_px))
	add_theme_stylebox_override("panel", style)

	_viewport = SubViewport.new()
	_viewport.name = "MinimapViewport"
	# DECISION (ui/Minimap.gd): own_world_3d = false (the default) instead of
	# the brief's literal `SubViewport.world_3d = get_viewport().world_3d` --
	# both make this SubViewport share the main Viewport's own World3D so the
	# same disk/blocks/territory render here, but own_world_3d = false is the
	# pattern game/DiscMirror.gd already uses in this codebase for exactly
	# the same "second camera into the same live World3D" need, and sidesteps
	# get_viewport() being self-referential once called from a script
	# attached to a node that is itself inside the SubViewport it would be
	# trying to read from.
	_viewport.own_world_3d = false
	_viewport.transparent_bg = false
	_viewport.size = Vector2i(tuning.minimap_size_px, tuning.minimap_size_px)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	_camera = Camera3D.new()
	_camera.name = "MinimapCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.near = tuning.minimap_near_clip_m
	_camera.far = tuning.minimap_camera_height_m + tuning.minimap_far_clip_m
	_camera.current = true
	# Bontago-xtq.30 (see minimap_camera_height_m's own DECISION comment in
	# config/HUDVisualTuning.gd for the full root cause): own_world_3d = false
	# above shares the main scene's live World3D (so the disk/blocks render
	# here at all) but a Camera3D's WORLD ENVIRONMENT still falls back to
	# whatever WorldEnvironment node is in that shared World3D unless this
	# camera carries its own -- Camera3D.environment always wins over a
	# WorldEnvironment node for the camera it's set on (Godot's own resolution
	# order), so this is a clean per-camera override with no change to the
	# main scene's own Environment/WorldEnvironment. Built once here (not
	# reread every frame): every field is a fixed "flatten this to a legible
	# top-down readout" choice, none of them need to react to a live F4 edit
	# the way the main scene's own preset-driven fields do.
	_camera.environment = _build_environment()
	_viewport.add_child(_camera)

	_texture_rect = TextureRect.new()
	_texture_rect.name = "MinimapTexture"
	_texture_rect.texture = _viewport.get_texture()
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(_texture_rect)

	_refresh_timer = Timer.new()
	_refresh_timer.name = "RefreshTimer"
	_refresh_timer.one_shot = false
	_refresh_timer.wait_time = _refresh_interval()
	_refresh_timer.timeout.connect(_on_refresh_timeout)
	add_child(_refresh_timer)

	visible = false


## Positions/frames the minimap's camera from `map_def`'s own radius plus
## tuning.minimap_zoom_margin_m, and (re)starts the refresh timer. Passing
## null disables the viewport entirely (no match loaded) -- the menu/no-match
## state the brief requires costs nothing.
func set_map_def(map_def: MapDef) -> void:
	_map_def = map_def
	if _viewport == null or _camera == null:
		return
	if map_def == null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if _refresh_timer != null:
			_refresh_timer.stop()
		visible = false
		return

	var half_extent: float = map_def.field_radius + tuning.minimap_zoom_margin_m
	_camera.size = half_extent * 2.0
	_camera.position = Vector3(0.0, tuning.minimap_camera_height_m, 0.0)
	_camera.rotation = Vector3(-PI / 2.0, 0.0, 0.0)
	visible = true
	_refresh_timer.wait_time = _refresh_interval()
	_refresh_timer.start()
	# One immediate render so the minimap shows the new framing right away
	# instead of waiting up to one full refresh interval.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Bontago-xtq.30: a flat, solid-color, no-post-processing Environment for the
## minimap camera alone -- deliberately opaque to whatever the shared World3D's
## own WorldEnvironment (game/Main.tscn) is doing (procedural sky, SSR,
## preset-driven volumetric fog: game/Main.gd's _apply_graphics_preset()).
## BG_COLOR (not BG_SKY/BG_CLEAR_COLOR) means this camera never samples the
## sky material either, so a menu/no-match state (before set_map_def() ever
## runs, camera parented under a disabled viewport) still has a defined,
## on-brand background the moment it turns on.
func _build_environment() -> Environment:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = tuning.minimap_backdrop_color
	environment.fog_enabled = false
	environment.volumetric_fog_enabled = false
	environment.glow_enabled = false
	environment.ssr_enabled = false
	environment.ssao_enabled = false
	environment.ssil_enabled = false
	environment.sdfgi_enabled = false
	return environment


func _refresh_interval() -> float:
	return 1.0 / maxf(tuning.minimap_refresh_hz, 0.001)


func _on_refresh_timeout() -> void:
	if _viewport == null or _map_def == null:
		return
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Exposed for tests (tests/unit/test_hud.gd) so they can assert on the live
## SubViewport/Camera3D without reaching into the node tree by internal name.
func viewport() -> SubViewport:
	return _viewport


func camera() -> Camera3D:
	return _camera


## True once a non-null MapDef has been set (i.e. the minimap is actually
## rendering something), false in the menu/no-match state.
func is_active() -> bool:
	return _map_def != null
