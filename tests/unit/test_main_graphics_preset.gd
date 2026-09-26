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
