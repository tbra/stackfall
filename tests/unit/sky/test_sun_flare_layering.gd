extends GutTest
## Bontago-mp0.33: the additive sun flare must render below every UI layer and
## hide while a full-screen panel (results, pause) is open.

const RESULTS_SCENE: PackedScene = preload("res://ui/menus/ResultsScreen.tscn")
func test_flare_hides_while_results_are_shown() -> void:
	var flare: SunFlare = SunFlare.new()
	add_child_autofree(flare)
	var camera: Camera3D = Camera3D.new()
	add_child_autofree(camera)
	flare._camera = camera
	flare._process(0.016)
	var rect: ColorRect = flare.get_node("FlareRect") as ColorRect
	assert_true(rect.visible, "fixture: flare visible with no UI open.")
	var screen: ResultsScreen = RESULTS_SCENE.instantiate() as ResultsScreen
	add_child_autofree(screen)
	screen.visible = true
	assert_true(flare.is_fullscreen_ui_open())
	flare._process(0.016)
	assert_false(rect.visible, "flare must hide while the results screen is up.")
	screen.visible = false
	flare._process(0.016)
	assert_true(rect.visible, "flare returns once results close.")
