extends GutTest
## Bontago-1pi.11.48: menu/lobby screens cap the frame rate, skip the hidden
## match world's 3D pass, and no hidden SubViewport keeps rendering.

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


## Bontago-1pi.11.91: the menu is a picture, so registered world roots stop processing while a
## menu/lobby holds the budget and get their own mode back on the last release.
func test_world_roots_dormant_while_menu_holds_budget_then_restored() -> void:
	var world: Node3D = Node3D.new()
	var inherit_node: Node3D = Node3D.new()
	var always_node: Node3D = Node3D.new()
	always_node.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child_autofree(world)
	add_child_autofree(inherit_node)
	add_child_autofree(always_node)
	MenuBackdrop.set_dormant_world([world, inherit_node, always_node] as Array[Node])
	assert_false(MenuBackdrop.world_dormant())
	var a: MenuBackdrop = MenuBackdrop.new()
	var b: MenuBackdrop = MenuBackdrop.new()
	add_child(a)
	add_child(b)
	MenuBackdrop._refresh_dormancy()  # what the first _process frame does
	assert_true(MenuBackdrop.world_dormant())
	assert_eq(world.process_mode, Node.PROCESS_MODE_DISABLED)
	assert_false(world.can_process())
	assert_eq(always_node.process_mode, Node.PROCESS_MODE_DISABLED)
	a.free()
	assert_eq(world.process_mode, Node.PROCESS_MODE_DISABLED, "lobby still holds it")
	b.free()
	assert_false(MenuBackdrop.world_dormant())
	assert_eq(world.process_mode, Node.PROCESS_MODE_INHERIT, "match start restores the world")
	assert_eq(always_node.process_mode, Node.PROCESS_MODE_ALWAYS)
	MenuBackdrop.set_dormant_world([] as Array[Node])


func test_world_registered_while_menu_open_goes_dormant_and_replacing_restores() -> void:
	var world: Node3D = Node3D.new()
	add_child_autofree(world)
	var backdrop: MenuBackdrop = MenuBackdrop.new()
	add_child(backdrop)
	MenuBackdrop.set_dormant_world([world] as Array[Node])
	MenuBackdrop._refresh_dormancy()
	assert_eq(world.process_mode, Node.PROCESS_MODE_DISABLED)
	MenuBackdrop.set_dormant_world([] as Array[Node])
	assert_eq(world.process_mode, Node.PROCESS_MODE_INHERIT)
	backdrop.free()


func test_main_menu_stops_world_roots_and_leaving_it_restores_them() -> void:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	add_child_autofree(main)
	MenuBackdrop._refresh_dormancy()
	var menu: Node = main.get("_main_menu") as Node
	assert_not_null(menu, "Main shows the menu on boot")
	for node_name: String in ["Skybox", "CloudShadows", "HorizonIslands"]:
		assert_eq(main.get_node(node_name).process_mode, Node.PROCESS_MODE_DISABLED, node_name)
	main.remove_child(menu)
	menu.free()
	for node_name: String in ["Skybox", "CloudShadows", "HorizonIslands"]:
		assert_eq(main.get_node(node_name).process_mode, Node.PROCESS_MODE_INHERIT, node_name)


func test_live_world_is_never_frozen_by_a_menu_backdrop_that_outlives_the_world_start() -> void:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
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
