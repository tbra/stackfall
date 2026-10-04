class_name LobbySection
extends VBoxContainer
## One block of the lobby's settings column (Bontago-1pi.53, package S1a,
## docs/LOBBY_REWORK_PLAN.md section 2; Bontago-1pi.61 made the headers static): a
## header (the section's caption and a right-aligned one-line summary, never
## collapsible), a main body that is always shown, and an optional Advanced block
## behind a flat toggle chip. Only the Advanced block collapses.
##
## **Scene convention** (the section builds only its own header and chip; every
## setting control stays an authored node of ui/Lobby.tscn so its `%UniqueName`
## keeps resolving, and nothing is reparented at runtime):
## - a child named `Body` (any Control) holds the main controls,
## - an optional child named `Advanced` (a MarginContainer) holds the Advanced
##   controls; it starts collapsed (plan D7: expanded state is not persisted).
##
## **Focus.** [member advanced_button] is a FOCUS_ALL toggle Button, so `ui_accept` and a
## click both toggle; the header is a plain label row and is not a focus stop. Every
## toggle emits [signal advanced_changed]; ui/Lobby.gd listens and rewires its focus loop,
## so a collapsed block can never leave an invisible focus stop behind.
##
## **Focus never gets lost.** Hiding the Advanced block (chip, or Y on the pad) while focus
## is inside it hands focus to the section's chip, so the gamepad loop keeps its place.
##
## **Read-only clients.** The chip is not a setting, so a client can still open the
## Advanced block to read it; only the setting controls inside are disabled by the Lobby.

## The Advanced block was opened or closed (chip press).
signal advanced_changed(open: bool)

## Text of the Advanced toggle chip.
const ADVANCED_CHIP_TEXT: String = "Advanced"
const BODY_NAME: StringName = &"Body"
const ADVANCED_NAME: StringName = &"Advanced"

## The caption shown in the header ("GAME", "ROUND", "GIFTS", ...).
@export var title: String = "":
	set(value):
		title = value
		if _title_label != null:
			_title_label.text = value
## Sizes and spacings; the Lobby overwrites it with its own export before styling.
@export var layout_tuning: LobbyLayoutTuning = preload("res://config/lobby_layout_tuning.tres")

## The focusable Advanced chip; null when the section has no Advanced block.
var advanced_button: Button = null
## The authored main body / Advanced block (either may be null).
var body: Control = null
var advanced: Control = null

var _advanced_open: bool = false
var _summary: String = ""
var _title_label: Label = null
var _summary_label: Label = null
## Bontago-mp0.124: the header's section icon (white source, tinted like the caption).
var _icon_rect: TextureRect = null
var _icon_texture: Texture2D = null


func _ready() -> void:
	body = get_node_or_null(NodePath(String(BODY_NAME))) as Control
	advanced = get_node_or_null(NodePath(String(ADVANCED_NAME))) as Control
	_build_header()
	if advanced != null:
		_build_advanced_chip()
	_apply_layout()
	_apply_state()


## Colours the header and the chip from the shared menu tunables and takes the
## Lobby's own layout resource (the Lobby calls this from _apply_visual_style(); no
## new colours are introduced).
func apply_style(tuning: MenuVisualTuning, layout: LobbyLayoutTuning) -> void:
	layout_tuning = layout
	_apply_layout()
	for label: Label in [_title_label, _summary_label]:
		label.add_theme_color_override("font_color", tuning.label_muted_color)
	_icon_rect.modulate = tuning.label_muted_color
	if advanced_button != null:
		MenuStyleFactory.apply_toggle_chip(
			advanced_button, tuning.pill_cream_color, tuning.pill_cream_hover_color,
			tuning.pill_mint_color, tuning.pill_mint_hover_color, tuning.ink_color, tuning
		)


## The one-line summary on the header's right ("Classic · Round · Medium · Cycle").
func set_summary(text: String) -> void:
	_summary = text
	if _summary_label != null:
		_summary_label.text = text


## Bontago-mp0.124: the section symbol drawn left of the caption (UiArtTable lobby icon).
func set_header_icon(texture: Texture2D) -> void:
	_icon_texture = texture
	if _icon_rect != null:
		_icon_rect.texture = texture
		_icon_rect.visible = texture != null


## The texture currently shown in the header (null when none).
func header_icon() -> Texture2D:
	return _icon_rect.texture if _icon_rect != null else null


func summary() -> String:
	return _summary


func is_advanced_open() -> bool:
	return _advanced_open


## Programmatic open/close of the Advanced block (a no-op without one); emits
## [signal advanced_changed] only on a change.
func set_advanced_open(value: bool) -> void:
	if advanced == null or _advanced_open == value:
		return
	var keep_focus: bool = not value and _focus_in(advanced)
	_advanced_open = value
	_apply_state()
	if keep_focus:
		advanced_button.grab_focus()
	advanced_changed.emit(_advanced_open)


func has_advanced() -> bool:
	return advanced != null


## True while the viewport's focus owner is this section's chip or any control inside
## it (the Lobby's Y shortcut picks the section to toggle with it).
func has_focus_inside() -> bool:
	var focus_owner: Control = _focus_owner()
	return focus_owner != null and (focus_owner == self or is_ancestor_of(focus_owner))


## True while the focus owner sits inside [param node] (itself or a descendant).
func _focus_in(node: Control) -> bool:
	var focus_owner: Control = _focus_owner()
	return node != null and focus_owner != null and (focus_owner == node or node.is_ancestor_of(focus_owner))


func _focus_owner() -> Control:
	return get_viewport().gui_get_focus_owner() if is_inside_tree() else null


## Y on the pad (lobby_quick_advanced): toggles the Advanced block.
func toggle_advanced() -> void:
	if advanced == null:
		return
	set_advanced_open(not _advanced_open)


func _apply_layout() -> void:
	if advanced != null:
		advanced.add_theme_constant_override("margin_left", layout_tuning.advanced_indent_px)


func _build_header() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "HeaderRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_rect = TextureRect.new()
	_icon_rect.name = "HeaderIcon"
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon_rect.custom_minimum_size = Vector2.ONE * float(UiArtTable.shared().lobby_icon_px)
	_icon_rect.texture = _icon_texture
	_icon_rect.visible = _icon_texture != null
	row.add_child(_icon_rect)
	_title_label = Label.new()
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.theme_type_variation = &"CaptionLabel"
	_title_label.text = title
	row.add_child(_title_label)
	var spacer: Control = Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_summary_label = Label.new()
	_summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary_label.theme_type_variation = &"CaptionLabel"
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_summary_label.text = _summary
	row.add_child(_summary_label)
	add_child(row)
	move_child(row, 0)


func _build_advanced_chip() -> void:
	advanced_button = Button.new()
	advanced_button.name = "AdvancedButton"
	advanced_button.toggle_mode = true
	advanced_button.focus_mode = Control.FOCUS_ALL
	advanced_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	advanced_button.text = ADVANCED_CHIP_TEXT
	advanced_button.toggled.connect(_on_advanced_chip_toggled)
	add_child(advanced_button)
	move_child(advanced_button, advanced.get_index())


func _on_advanced_chip_toggled(pressed: bool) -> void:
	set_advanced_open(pressed)


func _apply_state() -> void:
	if advanced != null:
		advanced.visible = _advanced_open
	if advanced_button != null:
		advanced_button.set_pressed_no_signal(_advanced_open)
		var chevron_key: StringName = UiArtTable.KEY_ADVANCED_OPEN if _advanced_open else UiArtTable.KEY_ADVANCED_CLOSED
		UiArtTable.shared().apply_button_icon(advanced_button, UiArtTable.shared().lobby_icon(chevron_key))
