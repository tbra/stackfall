extends Node
## Bontago-1pi.66 probe: captures a themed ConfirmationDialog off-screen.

func _ready() -> void:
	var host: Control = Control.new()
	host.theme = load("res://ui/theme/stackfall_theme.tres") as Theme
	add_child(host)
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = "Leave match"
	dialog.dialog_text = "Leave the match and return to the main menu?"
	host.add_child(dialog)
	dialog.popup_centered(Vector2i(300, 140))
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png("C:/Users/tonyf/AppData/Local/Temp/claude/M--Bontago/8aff5b2c-a113-4b13-acde-6336cb007585/scratchpad/confirm_dialog.png")
	get_tree().quit()
