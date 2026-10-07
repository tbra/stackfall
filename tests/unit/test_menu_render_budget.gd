extends GutTest
## Bontago-1pi.11.48: menu/lobby screens cap the frame rate, skip the hidden
## match world's 3D pass, and no hidden SubViewport keeps rendering.

const MAIN_MENU_SCENE: PackedScene = preload("res://ui/MainMenu.tscn")
const TUNING: MenuVisualTuning = preload("res://config/menu_visual_tuning.tres")


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


func test_hidden_diorama_does_not_render() -> void:
	var menu: MainMenu = MAIN_MENU_SCENE.instantiate() as MainMenu
	add_child_autofree(menu)
	await get_tree().process_frame
	var diorama: MenuDiorama = menu.find_child("Diorama", true, false) as MenuDiorama
	assert_not_null(diorama)
	var vp: SubViewport = diorama.get_node("DioramaViewport") as SubViewport
	var expected: SubViewport.UpdateMode = SubViewport.UPDATE_ONCE if TUNING.diorama_update_fps > 0 else SubViewport.UPDATE_ALWAYS
	assert_eq(vp.render_target_update_mode, expected)
	menu.hide()
	assert_eq(vp.render_target_update_mode, SubViewport.UPDATE_DISABLED)


func test_match_cap_set_while_menu_open_applies_on_last_exit() -> void:
	var before_fps: int = Engine.max_fps
	var backdrop: MenuBackdrop = MenuBackdrop.new()
	add_child(backdrop)
	MenuBackdrop.set_match_cap(144)
	assert_eq(Engine.max_fps, TUNING.menu_max_fps, "menu cap stays in force")
	backdrop.free()
	assert_eq(Engine.max_fps, 144)
	MenuBackdrop.clear_match_cap()
	Engine.max_fps = before_fps


func test_diorama_renders_only_at_its_update_rate() -> void:
	var diorama: MenuDiorama = MenuDiorama.new()
	var tuning: MenuVisualTuning = TUNING.duplicate() as MenuVisualTuning
	tuning.diorama_update_fps = 10
	diorama.tuning = tuning
	add_child_autofree(diorama)
	var vp: SubViewport = diorama._viewport
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var camera_before: Vector3 = diorama._camera.position
	diorama._process(0.04)
	assert_eq(vp.render_target_update_mode, SubViewport.UPDATE_DISABLED, "below the interval: no render")
	assert_eq(diorama._camera.position, camera_before, "below the interval: camera untouched")
	diorama._process(0.07)
	assert_eq(vp.render_target_update_mode, SubViewport.UPDATE_ONCE, "interval reached: one render")
	assert_ne(diorama._camera.position, camera_before)
	assert_almost_eq(diorama._elapsed_s, 0.11, 0.0001, "banked time is not lost")
	tuning.diorama_update_fps = 0
	diorama.hide()
	diorama.show()
	assert_eq(vp.render_target_update_mode, SubViewport.UPDATE_ALWAYS, "0 = every frame")
