class_name UiSection
extends VBoxContainer
## The design system's Section (docs/ui_reskin/components.md "Section"): a group header inside a
## panel (the section's caption with an optional icon on the left, a dust one-line summary of the
## current values on the right, never collapsible) over a main body that is always shown, and an
## optional Advanced block behind a disclosure bar (rim caret + "ADVANCED"). Only the Advanced
## block collapses. Moved here from the old lobby section block (Bontago-1pi.53 / .61 / .83 / mp0.124).
##
## **Scene convention** (the section builds only its own header and bar; every setting control
## stays an authored node so its `%UniqueName` keeps resolving, and nothing is reparented at
## runtime):
## - a child named `Body` (any Control) holds the main controls,
## - an optional child named `Advanced` (a MarginContainer) holds the Advanced controls; it
##   starts collapsed (plan D7: the expanded state is not persisted).
## Chip grids ([UiChipToggle]) and rows ([UiRow]) go inside Body / Advanced like any control.
##
## **Focus.** [member advanced_button] is a FOCUS_ALL toggle Button, so `ui_accept` (A on a pad) and
## a click both toggle; the header is a plain label row and is not a focus stop. Every toggle emits
## [signal advanced_changed]; the screen listens and rewires its focus loop, so a collapsed block
## can never leave an invisible focus stop behind. Hiding the block while focus is inside it hands
## focus to the bar. **Read-only clients** can still open the block to read it; only the setting
## controls inside are disabled by the screen.

## The Advanced block was opened or closed (bar press).
signal advanced_changed(open: bool)

## Text of the Advanced disclosure bar.
const ADVANCED_CHIP_TEXT: String = "ADVANCED"
## The disclosure triangle drawn before the text (right = collapsed, down = open).
const DISCLOSURE_CLOSED: String = "►"
const DISCLOSURE_OPEN: String = "▼"
const BODY_NAME: StringName = &"Body"
const ADVANCED_NAME: StringName = &"Advanced"

## The caption shown in the header ("GAME", "ROUND", "GIFTS", ...).
@export var title: String = "":
	set(value):
		title = value
		if _title_label != null:
			_title_label.text = value
## Indent of the Advanced block and padding of the bar; token defaults, a legacy layer may override.
var advanced_indent_px: int = 0
var bar_padding_px: int = 0

## The focusable Advanced bar; null when the section has no Advanced block.
var advanced_button: Button = null
## The authored main body / Advanced block (either may be null).
var body: Control = null
var advanced: Control = null

var _advanced_open: bool = false
var _summary: String = ""
var _title_label: Label = null
var _summary_label: Label = null
## The header's section icon (white source, tinted like the caption).
var _icon_rect: TextureRect = null
var _icon_texture: Texture2D = null


func _init() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	advanced_indent_px = arcade.space_4_px
	bar_padding_px = arcade.space_3_px


func _ready() -> void:
	body = get_node_or_null(NodePath(String(BODY_NAME))) as Control
	advanced = get_node_or_null(NodePath(String(ADVANCED_NAME))) as Control
	_build_header()
	if advanced != null:
		_build_advanced_bar()
	_apply_layout()
	_apply_state()
	_style_header()
	_style_disclosure()


## The header colours: dust caption and summary (the design's label / caption styles).
func _style_header() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	for label: Label in [_title_label, _summary_label]:
		label.add_theme_color_override("font_color", arcade.dust_color)
	_icon_rect.modulate = arcade.dust_color


## Advanced is a full-width disc-700 bar (rim caret + word; the value summary stays in the header
## above it) that lightens on hover; the shared theme's cream focus outline stays so keyboard and
## gamepad users see where they are.
func _style_disclosure() -> void:
	if advanced_button == null:
		return
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var faces: Dictionary = {
		"normal": arcade.disc_700_color, "pressed": arcade.disc_700_color,
		"disabled": arcade.disc_700_color, "hover": arcade.disc_600_color, "hover_pressed": arcade.disc_600_color,
	}
	for state: String in faces:
		var bar: StyleBoxFlat = StyleBoxFlat.new()
		bar.bg_color = faces[state]
		bar.set_corner_radius_all(arcade.radius_block_px)
		bar.content_margin_left = float(bar_padding_px)
		bar.content_margin_right = float(bar_padding_px)
		bar.content_margin_top = float(arcade.space_2_px)
		bar.content_margin_bottom = float(arcade.space_2_px)
		advanced_button.add_theme_stylebox_override(state, bar)
	advanced_button.flat = false
	advanced_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item: String in ["font_color", "font_pressed_color", "font_disabled_color"]:
		advanced_button.add_theme_color_override(item, arcade.rim_color)
	for item: String in ["font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
		advanced_button.add_theme_color_override(item, arcade.cream_color)


## The one-line summary on the header's right ("Classic - Round - Medium - Cycle").
func set_summary(text: String) -> void:
	_summary = text
	if _summary_label != null:
		_summary_label.text = text


func get_summary() -> String:
	return _summary


## The section symbol drawn left of the caption (UiArtTable lobby icon).
func set_header_icon(texture: Texture2D) -> void:
	_icon_texture = texture
	if _icon_rect != null:
		_icon_rect.texture = texture
		_icon_rect.visible = texture != null


## The texture currently shown in the header (null when none).
func header_icon() -> Texture2D:
	return _icon_rect.texture if _icon_rect != null else null


func is_advanced_open() -> bool:
	return _advanced_open


## Programmatic open/close of the Advanced block (a no-op without one); emits
## [signal advanced_changed] only on a change.
func set_advanced_open(open: bool) -> void:
	if advanced == null or _advanced_open == open:
		return
	var keep_focus: bool = not open and _focus_in(advanced)
	_advanced_open = open
	_apply_state()
	if keep_focus:
		advanced_button.grab_focus()
	advanced_changed.emit(_advanced_open)


func has_advanced() -> bool:
	return advanced != null


## True while the viewport's focus owner is this section's bar or any control inside it.
func has_focus_inside() -> bool:
	var focus_owner: Control = _focus_owner()
	return focus_owner != null and (focus_owner == self or is_ancestor_of(focus_owner))


## True while the focus owner sits inside [param node] (itself or a descendant).
func _focus_in(node: Control) -> bool:
	var focus_owner: Control = _focus_owner()
	return node != null and focus_owner != null and (focus_owner == node or node.is_ancestor_of(focus_owner))


func _focus_owner() -> Control:
	return get_viewport().gui_get_focus_owner() if is_inside_tree() else null


## Toggles the Advanced block (the lobby's Y shortcut).
func toggle_advanced() -> void:
	if advanced == null:
		return
	set_advanced_open(not _advanced_open)


func _apply_layout() -> void:
	if advanced != null:
		advanced.add_theme_constant_override("margin_left", advanced_indent_px)


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


func _build_advanced_bar() -> void:
	advanced_button = Button.new()
	advanced_button.name = "AdvancedButton"
	advanced_button.toggle_mode = true
	advanced_button.focus_mode = Control.FOCUS_ALL
	advanced_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	advanced_button.flat = true
	advanced_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	advanced_button.text = _disclosure_text()
	advanced_button.toggled.connect(_on_advanced_bar_toggled)
	add_child(advanced_button)
	move_child(advanced_button, advanced.get_index())


func _on_advanced_bar_toggled(pressed: bool) -> void:
	set_advanced_open(pressed)


func _apply_state() -> void:
	if advanced != null:
		advanced.visible = _advanced_open
	if advanced_button != null:
		advanced_button.set_pressed_no_signal(_advanced_open)
		advanced_button.text = _disclosure_text()


func _disclosure_text() -> String:
	return "%s %s" % [DISCLOSURE_OPEN if _advanced_open else DISCLOSURE_CLOSED, ADVANCED_CHIP_TEXT]
