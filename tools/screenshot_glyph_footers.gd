extends Node
## Bontago-1pi.71 probe: main-menu footer for keyboard and gamepad on one contact sheet.

const OUT: String = "C:/Users/tonyf/AppData/Local/Temp/claude/M--Bontago/8aff5b2c-a113-4b13-acde-6336cb007585/scratchpad/glyph_footers.png"
const VIEW_SIZE: Vector2i = Vector2i(1280, 720)
const CROP: Rect2i = Rect2i(780, 600, 500, 120)


func _ready() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = VIEW_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var menu: Control = (load("res://ui/MainMenu.tscn") as PackedScene).instantiate() as Control
	viewport.add_child(menu)
	var sheet: Image = Image.create(CROP.size.x, CROP.size.y * 2, false, Image.FORMAT_RGBA8)
	var row: int = 0
	for device: StringName in [Settings.DEVICE_KEYBOARD_MOUSE, Settings.DEVICE_GAMEPAD]:
		Settings.set_active_input_device_for_test(device)
		await get_tree().create_timer(0.5).timeout
		var shot: Image = viewport.get_texture().get_image()
		shot.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(shot, CROP, Vector2i(0, row * CROP.size.y))
		row += 1
	sheet.save_png(OUT)
	get_tree().quit()
