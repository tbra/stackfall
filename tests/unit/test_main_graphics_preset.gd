extends GutTest
## Bontago-xtq.26 (M7 P1): game/Main.gd's _apply_graphics_preset() consumer --
## Settings.set_graphics_preset() must reach the real Viewport and the real
## WorldEnvironment's Environment resource once Main is in the tree. Drives
## the real Main scene, the same fixture shape as tests/unit/test_sandbox.gd,
## because the point is Main's own signal wiring (Settings.graphics_preset_
## changed -> _apply_graphics_preset()), not config/GraphicsPreset.gd in
## isolation (already covered by tests/unit/test_settings.gd).

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")

## game/Main.gd has no class_name (a scene root, not a type other code names
## -- see tests/unit/test_sandbox.gd's matching comment), so the instance is
## held through a Variant-typed reference.
var _main: Variant = null

## Restored in after_each() so this test cannot leak a changed preset into
## whichever test file the runner happens to load next in the same process
## (the real "Settings" autoload outlives this script).
var _original_preset_id: StringName


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	assert_true(Net.is_offline(), "fixture: the real Net must start offline")
	_original_preset_id = Settings.current_graphics_preset().id
	_main = MAIN_SCENE.instantiate()
	add_child_autofree(_main)
	assert_not_null(_main._main_menu, "fixture: Main boots to the main menu with no command-line flags")


func after_each() -> void:
	Settings.set_graphics_preset(_original_preset_id)
	Match.abort_match()
	Match.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame
	MatchTestReset.clear_world()


func _world_environment() -> WorldEnvironment:
	return _main.get_node("WorldEnvironment") as WorldEnvironment


func test_low_preset_disables_msaa_and_ssr_and_volumetric_fog() -> void:
	Settings.set_graphics_preset(&"low")
	var low_preset: GraphicsPreset = Settings.current_graphics_preset()

	var viewport: Viewport = _main.get_viewport() as Viewport
	assert_eq(viewport.msaa_3d, low_preset.msaa_3d, "low preset must reach the active Viewport's msaa_3d")

	var environment: Environment = _world_environment().environment
	assert_eq(environment.ssr_enabled, low_preset.ssr_enabled, "low preset drops SSR")
	assert_eq(
		environment.volumetric_fog_enabled, low_preset.volumetric_fog_enabled, "low preset drops the cloud-deck fog"
	)


func test_high_preset_keeps_msaa_and_ssr_and_volumetric_fog() -> void:
	Settings.set_graphics_preset(&"low")
	Settings.set_graphics_preset(&"high")
	var high_preset: GraphicsPreset = Settings.current_graphics_preset()

	var viewport: Viewport = _main.get_viewport() as Viewport
	assert_eq(viewport.msaa_3d, high_preset.msaa_3d, "high preset must reach the active Viewport's msaa_3d")

	var environment: Environment = _world_environment().environment
	assert_eq(environment.ssr_enabled, high_preset.ssr_enabled, "high preset keeps SSR")
	assert_eq(
		environment.volumetric_fog_enabled, high_preset.volumetric_fog_enabled, "high preset keeps the cloud-deck fog"
	)


func test_low_preset_reduces_sun_shadow_cascades() -> void:
	Settings.set_graphics_preset(&"low")
	var low_preset: GraphicsPreset = Settings.current_graphics_preset()
	var sun: DirectionalLight3D = _main.get_node("DirectionalLight3D") as DirectionalLight3D
	assert_eq(int(sun.directional_shadow_mode), low_preset.sun_shadow_mode, "low preset sets cascade count")
	assert_eq(sun.directional_shadow_max_distance, low_preset.sun_shadow_max_distance)
	Settings.set_graphics_preset(&"high")
	assert_eq(int(sun.directional_shadow_mode), DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)


## Bontago-1pi.11.49: drops the main menu so no MenuBackdrop holds the menu budget.
func _leave_menu() -> void:
	var menu: Node = _main._main_menu
	if menu != null and menu.is_inside_tree():
		_main.remove_child(menu)
		menu.free()
		_main._main_menu = null
	assert_eq(MenuBackdrop.budget_holders(), 0, "fixture: no menu budget holder")


func _stub_refresh(hz: float) -> void:
	_main.frame_cap_in_headless = true
	_main.refresh_rate_provider = func() -> float: return hz


func test_frame_cap_defaults_to_display_refresh_on_every_preset() -> void:
	var before_fps: int = Engine.max_fps
	_leave_menu()
	_stub_refresh(144.0)
	for id: StringName in [&"low", &"medium", &"high"]:
		Settings.set_graphics_preset(id)
		assert_eq(Settings.current_graphics_preset().frame_cap_mode, GraphicsPreset.FrameCap.DISPLAY_REFRESH)
		assert_eq(Engine.max_fps, 144, "preset %s follows the display refresh" % id)
	_stub_refresh(0.0)
	Settings.set_graphics_preset(&"medium")
	assert_eq(Engine.max_fps, Settings.current_graphics_preset().fallback_fps, "fallback when the display reports <= 0")
	MenuBackdrop.clear_match_cap()
	Engine.max_fps = before_fps


func test_frame_cap_fixed_and_uncapped_modes() -> void:
	assert_eq(FrameCapRule.resolve(GraphicsPreset.FrameCap.FIXED, 90, 144.0, 60), 90)
	assert_eq(FrameCapRule.resolve(GraphicsPreset.FrameCap.UNCAPPED, 90, 144.0, 60), 0)
	assert_eq(FrameCapRule.resolve(GraphicsPreset.FrameCap.DISPLAY_REFRESH, 90, 143.98, 60), 144)
	assert_eq(FrameCapRule.resolve(GraphicsPreset.FrameCap.DISPLAY_REFRESH, 90, -1.0, 75), 75)


func test_menu_match_preset_change_menu_sequence_ends_with_right_caps() -> void:
	var before_fps: int = Engine.max_fps
	var menu_cap: int = load("res://config/menu_visual_tuning.tres").menu_max_fps
	_leave_menu()
	_stub_refresh(144.0)
	Settings.set_graphics_preset(&"high")
	assert_eq(Engine.max_fps, 144, "match")
	var backdrop: MenuBackdrop = MenuBackdrop.new()
	add_child(backdrop)
	assert_eq(Engine.max_fps, menu_cap, "menu cap in the menu")
	Settings.set_graphics_preset(&"low")
	assert_eq(Engine.max_fps, menu_cap, "preset change in the menu keeps the menu cap")
	_stub_refresh(60.0)
	Settings.set_graphics_preset(&"medium")
	backdrop.free()
	assert_eq(Engine.max_fps, 60, "match cap from the latest preset after the menu closes")
	var again: MenuBackdrop = MenuBackdrop.new()
	add_child(again)
	assert_eq(Engine.max_fps, menu_cap)
	again.free()
	assert_eq(Engine.max_fps, 60, "back in the match")
	MenuBackdrop.clear_match_cap()
	Engine.max_fps = before_fps


func test_headless_leaves_engine_cap_alone() -> void:
	var before_fps: int = Engine.max_fps
	Settings.set_graphics_preset(&"low")
	assert_eq(Engine.max_fps, before_fps)
