extends GutTest
## menu/lobby screens cap the frame rate, skip the hidden
## match world's 3D pass, and no hidden SubViewport keeps rendering.

const TUNING: MenuVisualTuning = preload("res://config/ui/menu_visual_tuning.tres")


func test_backdrop_caps_fps_and_disables_world_3d_then_restores() -> void:
	var before_fps: int = Engine.max_fps
	var before_3d: bool = get_viewport().disable_3d
	var backdrop: MenuBackdrop = MenuBackdrop.new()
	add_child(backdrop)
	assert_eq(Engine.max_fps, TUNING.menu_max_fps if before_fps <= 0 else mini(TUNING.menu_max_fps, before_fps))
	assert_gt(Engine.max_fps, 0)
	assert_true(get_viewport().disable_3d)
	backdrop.free()
	assert_eq(Engine.max_fps, before_fps)
	assert_eq(get_viewport().disable_3d, before_3d)
	assert_eq(MenuBackdrop.budget_holders(), 0)


func test_overlapping_menu_and_lobby_keep_budget_until_last_exit() -> void:
	var before_fps: int = Engine.max_fps
	var a: MenuBackdrop = MenuBackdrop.new()
	var b: MenuBackdrop = MenuBackdrop.new()
	add_child(a)
	add_child(b)
	a.free()
	assert_true(get_viewport().disable_3d)
	b.free()
	assert_eq(Engine.max_fps, before_fps)


func test_live_world_is_never_frozen_by_a_menu_backdrop_that_outlives_the_world_start() -> void:
	var main: Node = (load("res://game/main/Main.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	MenuBackdrop._refresh_dormancy()
	var skybox: Node = main.get_node("Skybox")
	assert_eq(skybox.process_mode, Node.PROCESS_MODE_DISABLED, "menu up, no world: dormant")
	main.set("_world_built", true)
	MenuBackdrop._refresh_dormancy()
	assert_eq(skybox.process_mode, Node.PROCESS_MODE_INHERIT, "world live (CLI sandbox path): never frozen")
	main.set("_world_built", false)
	MenuBackdrop._refresh_dormancy()
	assert_eq(skybox.process_mode, Node.PROCESS_MODE_DISABLED)
