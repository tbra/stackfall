extends GutTest
## Bontago-mp0.33: the additive sun flare must render below every UI layer and
## hide while a full-screen panel (results, pause) is open.

const RESULTS_SCENE: PackedScene = preload("res://ui/ResultsScreen.tscn")
const UI_SCENES: Array[String] = [
	"res://ui/HUD.tscn",
	"res://ui/PauseMenu.tscn",
	"res://ui/TuningPanel.tscn",
	"res://ui/NetDebugOverlay.tscn",
	"res://ui/SandboxPanel.tscn",
]


func test_flare_layer_is_below_default_canvas_and_every_ui_layer() -> void:
	var flare: SunFlare = SunFlare.new()
	add_child_autofree(flare)
	assert_lt(flare.layer, 0, "flare must sit under layer 0 (ResultsScreen lives on the default canvas).")
	for path: String in UI_SCENES:
		var ui: CanvasLayer = (load(path) as PackedScene).instantiate() as CanvasLayer
		assert_not_null(ui, path)
		if ui == null:
			continue
		assert_lt(flare.layer, maxi(ui.layer, 0), "flare must be below %s" % path)
		ui.free()


func test_main_scene_flare_uses_default_layer_overridden_in_ready() -> void:
	var main: PackedScene = load("res://game/Main.tscn") as PackedScene
	var state: SceneState = main.get_state()
	for i: int in state.get_node_count():
		if state.get_node_name(i) == &"SunFlare":
			for p: int in state.get_node_property_count(i):
				assert_ne(state.get_node_property_name(i, p), &"layer", "layer is owned by SunFlare.FLARE_LAYER, not the scene.")
			return
	fail_test("Main.tscn has no SunFlare node")


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
