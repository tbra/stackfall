extends GutTest
## Bontago-hfa.2 (UI reskin P0a): ui/theme/BlockStyleBox.gd draws the block recipe (face, lit top,
## lip, ledge; pressed and disabled variants) from ArcadeVisualTuning.

const CONTROL_RECT: Rect2 = Rect2(0.0, 0.0, 200.0, 60.0)

var _tuning: ArcadeVisualTuning = null


func before_each() -> void:
	_tuning = load("res://config/arcade_visual_tuning.tres") as ArcadeVisualTuning


func _layer(layers: Array[Dictionary], layer_name: String) -> Dictionary:
	for layer: Dictionary in layers:
		if String(layer["name"]) == layer_name:
			return layer
	return {}


func test_normal_block_stacks_ledge_lip_top_face() -> void:
	var box: BlockStyleBox = BlockStyleBox.make(_tuning.disc_600_color, _tuning)
	var layers: Array[Dictionary] = box.layers_for(CONTROL_RECT)
	assert_eq(layers.size(), 4, "ledge, lip, top, face")
	var ledge: Rect2 = _layer(layers, "ledge")["rect"] as Rect2
	var lip: Rect2 = _layer(layers, "lip")["rect"] as Rect2
	var face: Rect2 = _layer(layers, "face")["rect"] as Rect2
	assert_eq(ledge.position.y, float(_tuning.drop_px), "the ledge starts a drop below the top")
	assert_eq(ledge.end.y, CONTROL_RECT.end.y, "the ledge reaches the control bottom")
	assert_eq(lip.size.y, CONTROL_RECT.size.y - _tuning.drop_px, "the lip layer covers the block above the ledge")
	assert_eq(face.position.y, float(_tuning.top_px), "the lit top is top_px tall")
	assert_eq(face.end.y, lip.end.y - _tuning.lip_px, "the lip is lip_px tall")
	assert_eq(_layer(layers, "ledge")["color"], _tuning.disc_950_color)
	assert_eq(_layer(layers, "face")["color"], _tuning.disc_600_color)


func test_small_block_uses_the_compact_recipe() -> void:
	var box: BlockStyleBox = BlockStyleBox.make(_tuning.disc_600_color, _tuning, true)
	assert_eq(box.lip_px, _tuning.lip_sm_px)
	assert_eq(box.drop_px, _tuning.drop_sm_px)
	assert_eq(box.radius_px, _tuning.radius_block_px)


func test_derived_top_and_lip_follow_the_mix_tokens() -> void:
	var box: BlockStyleBox = BlockStyleBox.make(_tuning.disc_600_color, _tuning)
	assert_true(box.top_color.is_equal_approx(_tuning.disc_600_color.lerp(Color.WHITE, _tuning.block_top_light_mix)))
	assert_true(box.lip_color.is_equal_approx(_tuning.disc_600_color.lerp(Color.BLACK, _tuning.block_lip_dark_mix)))


func test_named_face_overrides_win() -> void:
	var box: BlockStyleBox = BlockStyleBox.make(_tuning.flare_color, _tuning, false, BlockStyleBox.STATE_NORMAL, _tuning.flare_lip_color, _tuning.flare_top_color)
	assert_eq(box.lip_color, _tuning.flare_lip_color)
	assert_eq(box.top_color, _tuning.flare_top_color)


func test_pressed_drops_the_face_onto_the_ledge_and_removes_it() -> void:
	var normal: BlockStyleBox = BlockStyleBox.make(_tuning.flare_color, _tuning, false, BlockStyleBox.STATE_NORMAL, _tuning.flare_lip_color)
	var pressed: BlockStyleBox = BlockStyleBox.make(_tuning.flare_color, _tuning, false, BlockStyleBox.STATE_PRESSED, _tuning.flare_lip_color)
	var layers: Array[Dictionary] = pressed.layers_for(CONTROL_RECT)
	assert_eq(layers.size(), 3, "no ledge when pressed")
	assert_true(_layer(layers, "ledge").is_empty())
	assert_eq((_layer(layers, "lip")["rect"] as Rect2).position.y, float(_tuning.drop_px), "face moved down by the drop")
	assert_eq(_layer(layers, "face")["color"], _tuning.flare_lip_color, "the pressed face is the lip colour (flare-lip)")
	assert_eq(pressed.get_minimum_size(), normal.get_minimum_size(), "pressing does not change the layout size")
	assert_eq(pressed.get_margin(SIDE_TOP) - normal.get_margin(SIDE_TOP), float(_tuning.drop_px), "label travels with the face")


func test_disabled_is_flat_translucent_without_a_ledge() -> void:
	var box: BlockStyleBox = BlockStyleBox.make(_tuning.disc_600_color, _tuning, false, BlockStyleBox.STATE_DISABLED)
	var layers: Array[Dictionary] = box.layers_for(CONTROL_RECT)
	assert_true(_layer(layers, "ledge").is_empty())
	for layer: Dictionary in layers:
		assert_almost_eq((layer["color"] as Color).a, _tuning.disabled_alpha, 0.0001, "%s at the disabled opacity" % layer["name"])


func test_hover_lightens_the_face() -> void:
	var box: BlockStyleBox = BlockStyleBox.make(_tuning.disc_600_color, _tuning, false, BlockStyleBox.STATE_HOVER)
	assert_gt(box.face_color.get_luminance(), _tuning.disc_600_color.get_luminance())


func test_content_margins_leave_room_for_top_lip_and_ledge() -> void:
	var box: BlockStyleBox = BlockStyleBox.make(_tuning.disc_600_color, _tuning)
	assert_eq(box.get_margin(SIDE_LEFT), float(_tuning.space_4_px))
	assert_eq(box.get_margin(SIDE_TOP), float(_tuning.button_pad_y_px + _tuning.top_px))
	assert_eq(box.get_margin(SIDE_BOTTOM), float(_tuning.button_pad_y_px + _tuning.lip_px + _tuning.drop_px))


func test_draw_runs_against_a_canvas_item() -> void:
	var canvas: RID = RenderingServer.canvas_item_create()
	for state: int in [BlockStyleBox.STATE_NORMAL, BlockStyleBox.STATE_PRESSED, BlockStyleBox.STATE_DISABLED]:
		BlockStyleBox.make(_tuning.mint_color, _tuning, false, state).draw(canvas, CONTROL_RECT)
	RenderingServer.free_rid(canvas)
	assert_true(true, "drawing all three states raised no error")


func test_a_button_with_a_block_stylebox_sizes_to_it() -> void:
	var button: Button = Button.new()
	button.text = "PLAY"
	add_child_autofree(button)
	MenuStyleFactory.apply_block(button, _tuning.flare_color, _tuning.ink_color)
	var box: StyleBox = button.get_theme_stylebox("normal")
	assert_true(box is BlockStyleBox)
	assert_gte(button.get_combined_minimum_size().y, box.get_minimum_size().y)
	assert_eq(button.get_theme_color("font_color"), _tuning.ink_color)
	assert_eq(button.get_theme_color("font_pressed_color"), _tuning.ink_color)
