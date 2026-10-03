class_name LobbySection
extends VBoxContainer
## One collapsible block of the lobby's settings column (Bontago-1pi.53, package
## S1a, docs/LOBBY_REWORK_PLAN.md section 2): a header (the section's caption, a
## chevron and a right-aligned one-line summary), a main body that is always
## shown while the section is expanded, and an optional Advanced block behind a
## flat toggle chip.
##
## **Scene convention** (the section builds only its own header and chip; every
## setting control stays an authored node of ui/Lobby.tscn so its `%UniqueName`
## keeps resolving, and nothing is reparented at runtime):
## - a child named `Body` (any Control) holds the main controls,
## - an optional child named `Advanced` (a MarginContainer) holds the Advanced
##   controls; it starts collapsed (plan D7: expanded state is not persisted).
##
## **Focus.** [member header_button] and [member advanced_button] are FOCUS_ALL
## Buttons, so `ui_accept` and a click both toggle; a mouse press and the keyboard
## fire the same `pressed` signal. Every toggle emits [signal expanded_changed] or
## [signal advanced_changed]; ui/Lobby.gd listens and rewires its focus loop, so a
## collapsed block can never leave an invisible focus stop behind.
##
## **Read-only clients.** The header and chip are not settings, so a client can
## still open a section to read it; only the setting controls inside are disabled
## by the Lobby.

## The section was expanded or collapsed (header press).
signal expanded_changed(expanded: bool)
## The Advanced block was opened or closed (chip press, or the header of a
## [member header_opens_advanced] section).
signal advanced_changed(open: bool)

## Chevron glyphs in front of the caption (collapsed / expanded).
const CHEVRON_COLLAPSED: int = 0x25B8
const CHEVRON_EXPANDED: int = 0x25BE
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
## A section with no main controls (the Experiments section): its header toggles
## the Advanced block and no separate chip is drawn.
@export var header_opens_advanced: bool = false
## Sizes and spacings; the Lobby overwrites it with its own export before styling.
@export var layout_tuning: LobbyLayoutTuning = preload("res://config/lobby_layout_tuning.tres")

## The focusable header Button (always present after _ready).
var header_button: Button = null
## The focusable Advanced chip; null when the section has no Advanced block or its
## header acts as the toggle.
var advanced_button: Button = null
## The authored main body / Advanced block (either may be null).
var body: Control = null
var advanced: Control = null

var _expanded: bool = true
var _advanced_open: bool = false
var _summary: String = ""
var _title_label: Label = null
var _chevron_label: Label = null
var _summary_label: Label = null


func _ready() -> void:
	body = get_node_or_null(NodePath(String(BODY_NAME))) as Control
	advanced = get_node_or_null(NodePath(String(ADVANCED_NAME))) as Control
	_build_header()
	if advanced != null and not header_opens_advanced:
		_build_advanced_chip()
	_apply_layout()
	_apply_state()


## Colours the header and the chip from the shared menu tunables and takes the
## Lobby's own layout resource (the Lobby calls this from _apply_visual_style(); no
## new colours are introduced).
func apply_style(tuning: MenuVisualTuning, layout: LobbyLayoutTuning) -> void:
	layout_tuning = layout
	_apply_layout()
	MenuStyleFactory.apply_flat_stepper_button(header_button, tuning)
	for label: Label in [_chevron_label, _title_label, _summary_label]:
		label.add_theme_color_override("font_color", tuning.label_muted_color)
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


func summary() -> String:
	return _summary


func is_expanded() -> bool:
	return _expanded


func is_advanced_open() -> bool:
	return _advanced_open


## Programmatic expand/collapse; emits [signal expanded_changed] only on a change.
func set_expanded(value: bool) -> void:
	if _expanded == value:
		return
	_expanded = value
	_apply_state()
	expanded_changed.emit(_expanded)


## Programmatic open/close of the Advanced block (a no-op without one); emits
## [signal advanced_changed] only on a change.
func set_advanced_open(value: bool) -> void:
	if advanced == null or _advanced_open == value:
		return
	_advanced_open = value
	_apply_state()
	advanced_changed.emit(_advanced_open)


func has_advanced() -> bool:
	return advanced != null


## Y on the pad (lobby_quick_advanced): toggles the Advanced block, expanding a
## collapsed section first so the block is actually shown.
func toggle_advanced() -> void:
	if advanced == null:
		return
	if not _expanded:
		set_expanded(true)
	set_advanced_open(not _advanced_open)


func _apply_layout() -> void:
	if advanced != null:
		advanced.add_theme_constant_override("margin_left", layout_tuning.advanced_indent_px)


func _build_header() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "HeaderPanel"
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	header_button = Button.new()
	header_button.name = "HeaderButton"
	header_button.focus_mode = Control.FOCUS_ALL
	header_button.pressed.connect(_on_header_pressed)
	panel.add_child(header_button)

	# The row sits over the button (PanelContainer stacks its children) and ignores the
	# mouse, so a click anywhere on the header reaches the button underneath.
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "HeaderRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	_chevron_label = Label.new()
	_chevron_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_chevron_label)
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
	add_child(panel)
	move_child(panel, 0)


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


func _on_header_pressed() -> void:
	if header_opens_advanced:
		set_advanced_open(not _advanced_open)
	else:
		set_expanded(not _expanded)


func _on_advanced_chip_toggled(pressed: bool) -> void:
	set_advanced_open(pressed)


func _apply_state() -> void:
	if body != null:
		body.visible = _expanded
	if advanced != null:
		advanced.visible = _advanced_open and (_expanded or header_opens_advanced)
	if advanced_button != null:
		advanced_button.visible = _expanded
		advanced_button.set_pressed_no_signal(_advanced_open)
	var open: bool = _advanced_open if header_opens_advanced else _expanded
	_chevron_label.text = char(CHEVRON_EXPANDED if open else CHEVRON_COLLAPSED)
