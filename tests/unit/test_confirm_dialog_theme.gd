extends GutTest
## Bontago-1pi.66: confirmation prompts must show the shared cream card behind
## the shared dark ink Label colour (owner playtest: dark text on dark panel).

const THEME_PATH: String = "res://ui/theme/stackfall_theme.tres"
const MIN_CONTRAST: float = 4.5


func _theme() -> Theme:
	return load(THEME_PATH) as Theme


func _assert_readable(dialog: AcceptDialog, label_text: String) -> void:
	dialog.theme = _theme()
	dialog.dialog_text = "Leave the match?"
	add_child_autofree(dialog)
	var panel: StyleBox = dialog.get_theme_stylebox("panel", dialog.get_class())
	assert_true(panel is StyleBoxFlat, "%s: panel is a StyleBoxFlat" % label_text)
	var bg: Color = (panel as StyleBoxFlat).bg_color
	bg.a = 1.0
	var ink: Color = dialog.get_label().get_theme_color("font_color", "Label")
	var ratio: float = MenuStyleFactory.contrast_ratio(ink, bg)
	assert_gte(ratio, MIN_CONTRAST, "%s: label/panel contrast %.2f" % [label_text, ratio])


func test_confirmation_dialog_contrast() -> void:
	_assert_readable(ConfirmationDialog.new(), "ConfirmationDialog")


func test_accept_dialog_contrast() -> void:
	_assert_readable(AcceptDialog.new(), "AcceptDialog")


func test_pause_menu_dialog_uses_shared_theme() -> void:
	var scene: PackedScene = load("res://ui/PauseMenu.tscn") as PackedScene
	var menu: Node = scene.instantiate()
	var dialog: ConfirmationDialog = menu.get_node("ConfirmDialog") as ConfirmationDialog
	assert_eq(dialog.theme.resource_path, THEME_PATH)
	menu.free()
