class_name UiPanel
extends PanelContainer
## The design system's Panel (docs/ui_reskin/components.md "Panel"): the disc-800 slab every menu
## sits in (radius-panel, space-5 padding, a solid ledge) with an uppercase heading led by the flare
## voxel bullet and a content column the screen adds its rows to. No nesting: groups inside a
## panel are [UiSection]s or a rule header, never another panel. The header is a [UiTitleRow]
## ([member header]) so a screen can add a trailing badge / Back button with
## `panel.header.add_trailing(...)`.

@export var heading: String = "":
	set(value):
		heading = value
		header.title = value
		header.visible = value != ""
## Where screens add the panel's rows.
var content: VBoxContainer = null
var header: UiTitleRow = null


func _init() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	add_theme_stylebox_override("panel", MenuStyleFactory.make_plate())
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", arcade.space_3_px)
	add_child(column)
	header = UiTitleRow.new()
	header.visible = false
	column.add_child(header)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", arcade.space_3_px)
	column.add_child(content)
