extends GutTest
## Bontago-1pi.11.53: game/Boot.tscn is the main scene and hands over to Main. Headless
## (this suite) takes the synchronous path, so Main exists right after Boot's _ready.

const MAIN_SCENE_SETTING: String = "application/run/main_scene"


func test_project_main_scene_is_boot() -> void:
	assert_eq(ProjectSettings.get_setting(MAIN_SCENE_SETTING), "res://game/Boot.tscn")
	assert_eq(Boot.MAIN_SCENE_PATH, "res://game/Main.tscn")


func test_headless_boot_adds_main_to_root_and_frees_itself() -> void:
	var boot: Boot = Boot.new()
	add_child(boot)
	# The hand-over is deferred one idle step (never add to the root inside _ready).
	await get_tree().process_frame
	var main: Node = get_tree().root.get_node_or_null(NodePath(Boot.MAIN_NODE_NAME))
	assert_not_null(main, "Main is added to the root after the deferred hand-over when headless")
	assert_true(not is_instance_valid(boot) or boot.is_queued_for_deletion(), "Boot removes itself after the hand-over")
	assert_eq(get_tree().current_scene, main)
	if main != null:
		main.queue_free()
	get_tree().current_scene = null
	await get_tree().process_frame
	await get_tree().process_frame


## Review of 1pi.11.53: a scene that cannot load must fail loudly (error + quit in the real
## game), never leave a black window waiting forever.
func test_missing_main_scene_fails_instead_of_hanging() -> void:
	var boot: Boot = Boot.new()
	boot.main_scene_path = "res://game/__missing_main_for_test__.tscn"
	boot.quit_on_failure = false
	add_child(boot)
	await get_tree().process_frame
	assert_true(boot.load_failed, "the failed load is reported")
	assert_push_error_count(1, "Boot reports the failure once")
	assert_engine_error("found", "the engine reports the missing resource")
	boot.queue_free()
