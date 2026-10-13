class_name UiChatPanel
extends PanelContainer
## The design system's chat panel (docs/CHAT_PLAN.md section 3, docs/ui_reskin/components.md): one
## component, two skins. LOBBY is a CHAT title row, a scrolling log and an always-visible input line; HUD shows the last
## [member ChatConfig.hud_lines] lines, fades out after [member ChatConfig.line_visible_s] and shows the
## input line only while typing. Neither skin has a box, border or background (Bontago-1pi.159.45):
## the chat sits directly in its window, the HUD log kept readable by a text outline. The log is a plain-text RichTextLabel (bbcode off; the sender name is
## tinted with push_color / add_text, user text is never parsed). The panel never touches Net or Events:
## screens connect [signal submit_requested], [signal input_opened] / [signal input_closed] and feed
## [method append_line] / [method replace_history].
## Input: keyboard only to type (chat_open is bound by the screen). Enter submits, ui_cancel discards,
## and any gamepad press while typing closes the field and keeps the draft, so a pad player never gets stuck.

enum Mode { LOBBY, HUD }

## Typed text (already trimmed, never empty); the screen forwards it to Events.chat_send_requested.
signal submit_requested(text: String)
signal input_opened
signal input_closed

const CONFIG_PATH: String = "res://config/chat_config.tres"
const PLACEHOLDER_LOBBY: String = "Click or press T to chat"
const PLACEHOLDER_HUD: String = "Type a message"
const TITLE: String = "Chat"
const NAME_SEPARATOR: String = ": "
## Lobby log height in rows of the shared row height, and the minimum width (both skins) in space-7 steps.
const LOBBY_MIN_ROWS: int = 4
const WIDTH_STEPS: int = 8
## A stick counts as a pad press beyond this deflection.
## Floor for the fade length so a zero fade_s never divides by zero.
const FADE_MIN_S: float = 0.001
const PAD_AXIS_THRESHOLD: float = 0.5

@export var mode: Mode = Mode.LOBBY:
	set(value):
		mode = value
		if log != null:
			_apply_skin()

var config: ChatConfig = null
var log: RichTextLabel = null
var edit: LineEdit = null
## True while the screen holds show_scores: the HUD panel stays fully visible.
var hold_visible: bool = false:
	set(value):
		hold_visible = value
		if value:
			_restore()

var _lines: Array[Dictionary] = []
var _typing: bool = false
var _draft: String = ""
var _idle_s: float = 0.0
var _title_row: UiTitleRow = null
var _column: VBoxContainer = null


func _init() -> void:
	config = load(CONFIG_PATH) as ChatConfig
	config.sanitize()
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", arcade.space_2_px)
	add_child(_column)
	_title_row = UiTitleRow.new()
	_title_row.title = TITLE
	_column.add_child(_title_row)
	log = RichTextLabel.new()
	log.bbcode_enabled = false
	log.selection_enabled = false
	log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log.add_theme_font_size_override("normal_font_size", arcade.font_size_body_px)
	log.add_theme_color_override("default_color", arcade.sand_color)
	log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit = LineEdit.new()
	edit.max_length = config.max_chars
	edit.custom_minimum_size.y = float(UiRowItem.metrics().row_height_px)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiField._style_edit(edit, arcade)
	edit.text_submitted.connect(_on_text_submitted)
	edit.gui_input.connect(_on_edit_gui_input)
	edit.focus_entered.connect(_on_edit_focus_entered)
	edit.focus_exited.connect(_on_edit_focus_exited)
	_column.add_child(edit)
	_apply_skin()
	_idle_s = config.line_visible_s + config.fade_s


## True while the input line holds the keyboard.
func is_typing() -> bool:
	return _typing


## Lines currently drawn (HUD: at most hud_lines).
func shown_line_count() -> int:
	return _shown().size()


## Adds one wire line (ChatRules.make_line shape), wakes the HUD panel and scrolls the lobby log down.
func append_line(line: Dictionary) -> void:
	_lines.append(line)
	while _lines.size() > config.history_lines:
		_lines.pop_front()
	_render()
	_restore()


## Replaces the whole log (late-joiner history); does not wake a hidden HUD panel.
func replace_history(lines: Array) -> void:
	_lines.clear()
	for entry: Variant in lines:
		if entry is Dictionary:
			_lines.append(entry as Dictionary)
	while _lines.size() > config.history_lines:
		_lines.pop_front()
	_render()


## Shows the input line and takes focus (HUD: reveals the field; always restores the fade).
func open_input() -> void:
	if _typing:
		return
	_typing = true
	edit.text = _draft
	_draft = ""
	_restore()
	edit.visible = true
	if is_inside_tree():
		edit.grab_focus()
	edit.caret_column = edit.text.length()
	input_opened.emit()


## Ends typing. [param send] emits the trimmed text when it is not empty; either way the field clears.
func close_input(send: bool) -> void:
	if not _typing:
		return
	var typed: String = edit.text.strip_edges()
	_end_typing("")
	if send and typed != "":
		submit_requested.emit(typed)
	input_closed.emit()


## Advances the HUD fade by [param delta] seconds: visible, then fading over fade_s, then hidden.
func apply_fade(delta: float) -> void:
	if mode != Mode.HUD:
		return
	if _typing or hold_visible:
		_restore()
		return
	_idle_s += delta
	var fade_start: float = config.line_visible_s
	var fade_len: float = maxf(config.fade_s, FADE_MIN_S)
	if _idle_s <= fade_start:
		modulate.a = 1.0
	elif _idle_s < fade_start + fade_len:
		modulate.a = 1.0 - (_idle_s - fade_start) / fade_len
	else:
		modulate.a = 0.0
		visible = false


## The plain colour of a line's sender: its palette slot colour.
static func name_color(line: Dictionary) -> Color:
	var color_index: int = line.get(ChatRules.KEY_COLOR, 0) as int
	return Match.slot_color(color_index)


func _shown() -> Array[Dictionary]:
	if mode == Mode.HUD and _lines.size() > config.hud_lines:
		return _lines.slice(_lines.size() - config.hud_lines)
	return _lines


func _render() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	log.clear()
	var first: bool = true
	for line: Dictionary in _shown():
		if not first:
			log.newline()
		first = false
		var is_system: bool = (line.get(ChatRules.KEY_KIND, ChatRules.KIND_TEXT) as int) == ChatRules.KIND_SYSTEM
		if is_system:
			log.push_color(arcade.dust_color)
			log.add_text(line.get(ChatRules.KEY_TEXT, "") as String)
			log.pop()
			continue
		log.push_color(name_color(line))
		log.add_text((line.get(ChatRules.KEY_NAME, "") as String) + NAME_SEPARATOR)
		log.pop()
		log.push_color(arcade.cream_color)
		log.add_text(line.get(ChatRules.KEY_TEXT, "") as String)
		log.pop()
	if mode == Mode.LOBBY:
		log.scroll_to_line(maxi(log.get_line_count() - 1, 0))


## Fully visible again: any new line, opened input or held scores.
func _restore() -> void:
	_idle_s = 0.0
	if mode == Mode.HUD:
		modulate.a = 1.0
		visible = true


func _apply_skin() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var hud: bool = mode == Mode.HUD
	if log.get_parent() != null:
		log.get_parent().remove_child(log)
	if hud:
		# Bontago-1pi.159.45: no box, border or background; outlined text sits straight on the scene.
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		log.add_theme_color_override("font_outline_color", arcade.ink_color)
		log.add_theme_constant_override("outline_size", config.hud_outline_px)
		_column.add_child(log)
		_column.move_child(log, _title_row.get_index() + 1)
		custom_minimum_size = Vector2(float(arcade.space_7_px * WIDTH_STEPS), 0.0)
		log.fit_content = true
		log.scroll_active = false
		log.mouse_filter = Control.MOUSE_FILTER_IGNORE
		log.focus_mode = Control.FOCUS_NONE
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		edit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		edit.focus_mode = Control.FOCUS_CLICK
		edit.placeholder_text = PLACEHOLDER_HUD
		edit.visible = _typing
		_idle_s = config.line_visible_s + config.fade_s
		visible = false
		modulate.a = 0.0
	else:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		log.remove_theme_color_override("font_outline_color")
		log.remove_theme_constant_override("outline_size")
		_column.add_child(log)
		_column.move_child(log, _title_row.get_index() + 1)
		custom_minimum_size = Vector2(float(arcade.space_7_px * WIDTH_STEPS), 0.0)
		log.custom_minimum_size.y = float(UiRowItem.metrics().row_height_px * LOBBY_MIN_ROWS)
		log.fit_content = false
		log.scroll_active = true
		log.scroll_following = true
		log.mouse_filter = Control.MOUSE_FILTER_STOP
		log.focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_PASS
		edit.mouse_filter = Control.MOUSE_FILTER_STOP
		edit.focus_mode = Control.FOCUS_CLICK
		edit.placeholder_text = PLACEHOLDER_LOBBY
		edit.visible = true
		visible = true
		modulate.a = 1.0
	_title_row.visible = not hud
	_render()


## Clears typing state; [param draft] is kept for the next open (a pad close keeps the text).
func _end_typing(draft: String) -> void:
	_typing = false
	_draft = draft
	edit.text = ""
	edit.release_focus()
	if mode == Mode.HUD:
		edit.visible = false


func _on_text_submitted(_text: String) -> void:
	close_input(true)


func _on_edit_gui_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not _is_pad_event(event):
		close_input(false)
		edit.accept_event()


## Clicking the lobby field starts typing without open_input.
func _on_edit_focus_entered() -> void:
	if _typing:
		return
	_typing = true
	_restore()
	input_opened.emit()


## Losing focus (click elsewhere) ends typing and keeps the draft.
func _on_edit_focus_exited() -> void:
	if not _typing:
		return
	_end_typing(edit.text)
	input_closed.emit()


func _input(event: InputEvent) -> void:
	if _typing and _is_pad_event(event):
		var draft: String = edit.text
		_end_typing(draft)
		input_closed.emit()


func _is_pad_event(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	if event is InputEventJoypadMotion:
		return absf((event as InputEventJoypadMotion).axis_value) >= PAD_AXIS_THRESHOLD
	return false
