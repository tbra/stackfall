extends GutTest
## Bontago-1pi.74: the main-menu build label has one source (BuildVersion),
## is never empty, and sits beside the Debug pill at every supported size.

const SIZES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(900, 1200),
]
const SETTLE_FRAMES: int = 4
const EDGE_EPS: float = 1.0


func after_each() -> void:
	DebugMode.clear_override_for_test()


func test_label_is_non_empty() -> void:
	assert_false(BuildVersion.label().is_empty())


func test_compose_rules() -> void:
	assert_eq(BuildVersion.compose("0.0.1", "abc123"), "0.0.1+abc123")
	assert_eq(BuildVersion.compose("0.0.1", ""), "0.0.1")
	assert_eq(BuildVersion.compose("", ""), BuildVersion.FALLBACK)
	assert_eq(BuildVersion.compose("  ", " "), BuildVersion.FALLBACK)


func test_label_shown_beside_debug_button_at_sizes() -> void:
	DebugMode.set_override_for_test(true)
	for window: Vector2i in SIZES:
		var vp: SubViewport = UiScale.make_viewport(window)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child_autofree(vp)
		var menu: MainMenu = load("res://ui/MainMenu.tscn").instantiate() as MainMenu
		vp.add_child(menu)
		Net.stop_discovery()
		for _i: int in SETTLE_FRAMES:
			await get_tree().process_frame
		var label: Label = menu.get_node("%BuildVersionLabel") as Label
		var debug_button: Control = menu.get_node("%DebugButton") as Control
		var logical: Rect2 = Rect2(Vector2.ZERO, Vector2(vp.get_visible_rect().size))
		assert_true(label.is_visible_in_tree(), "label visible at %s" % window)
		assert_eq(label.text, BuildVersion.label())
		var lr: Rect2 = label.get_global_rect()
		var dr: Rect2 = debug_button.get_global_rect()
		assert_true(logical.grow(EDGE_EPS).encloses(lr), "label on screen at %s" % window)
		assert_false(lr.intersects(dr), "label does not overlap Debug at %s" % window)
		assert_gte(lr.position.x, dr.end.x - EDGE_EPS, "label right of Debug at %s" % window)
		vp.queue_free()
		await get_tree().process_frame
