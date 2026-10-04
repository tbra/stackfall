class_name InputPromptFlow
extends HFlowContainer
## Reusable "hint row"/prompt text control (Bontago-1pi.71): a template string where
## `{action}` (or `{a|b|c}` for a group that shares one slot) is replaced by the
## InputGlyph of the BOUND Input Map action for the player's ACTIVE device
## (Settings.active_input_device()), and plain text between tokens is drawn as
## words in Labels. It rebuilds itself on Events.input_device_changed, when it
## re-enters the tree or becomes visible (so a rebind made elsewhere shows up),
## and through refresh() for an explicit trigger.
##
## Example footer: "{ui_accept} Select   {ui_cancel} Back". Gamepad bindings
## resolve through KeyRebindRow.gamepad_events_for (own pad events, else the
## documented stand-ins); an action with no binding on the device falls back to
## its humanized action name so no prompt is ever blank or shows a wrong key.
## Identical glyphs inside one group are shown once (four stick directions ->
## one stick glyph).

## Glyphs shown per token (a second binding of the same device adds a glyph).
const MAX_GLYPHS_PER_TOKEN: int = 1
const TOKEN_OPEN: String = "{"
const TOKEN_CLOSE: String = "}"
const GROUP_SEPARATOR: String = "|"
const INPUT_GLYPH_SCENE: PackedScene = preload("res://ui/InputGlyph.tscn")

## Template text; set via set_template() or in the inspector.
@export_multiline var template: String = "":
	set(value):
		template = value
		if is_node_ready():
			refresh()

## Ink for the word labels (menus pass their palette ink; a transparent default
## leaves the theme colour alone).
var text_color: Color = Color(0.0, 0.0, 0.0, 0.0)


func _ready() -> void:
	if not Events.input_device_changed.is_connected(_on_input_device_changed):
		Events.input_device_changed.connect(_on_input_device_changed)
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)
	refresh()


func _enter_tree() -> void:
	if is_node_ready():
		refresh()


func set_template(value: String) -> void:
	template = value
	if is_node_ready():
		refresh()


func set_text_color(color: Color) -> void:
	text_color = color
	if is_node_ready():
		refresh()


## Rebuilds the children from the template for the active device.
func refresh() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	var rest: String = template
	while not rest.is_empty():
		var open: int = rest.find(TOKEN_OPEN)
		var close: int = rest.find(TOKEN_CLOSE, open + 1) if open >= 0 else -1
		if open < 0 or close < 0:
			_add_words(rest)
			break
		_add_words(rest.substr(0, open))
		_add_token(rest.substr(open + 1, close - open - 1))
		rest = rest.substr(close + 1)


## Test seam: the glyphs currently shown, in order.
func glyphs() -> Array[InputGlyph]:
	var found: Array[InputGlyph] = []
	for child: Node in get_children():
		if child is InputGlyph and not child.is_queued_for_deletion():
			found.append(child as InputGlyph)
	return found


## Test seam: the plain text currently shown (words joined by spaces; glyphs skipped).
func plain_text() -> String:
	var words: PackedStringArray = PackedStringArray()
	for child: Node in get_children():
		if child is Label and not child.is_queued_for_deletion():
			words.append((child as Label).text.strip_edges())
	return " ".join(words)


## The events of `action` for the active device (public so callers/tests can
## compare with what the control resolved).
static func events_for_active_device(action: StringName) -> Array[InputEvent]:
	if Settings.active_input_device() == Settings.DEVICE_GAMEPAD:
		return KeyRebindRow.gamepad_events_for(action)
	return KeyRebindRow.events_of_family(action, false)


func _on_input_device_changed(_device: StringName) -> void:
	refresh()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		refresh()


func _add_words(text: String) -> void:
	for word: String in text.split(" ", false):
		_add_label(word)


func _add_label(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if text_color.a > 0.0:
		label.add_theme_color_override("font_color", text_color)
	add_child(label)


func _add_token(token: String) -> void:
	var shown_texts: PackedStringArray = PackedStringArray()
	var unbound: Array[String] = []
	for action_name: String in token.split(GROUP_SEPARATOR, false):
		var action: StringName = StringName(action_name.strip_edges())
		var events: Array[InputEvent] = events_for_active_device(action)
		if events.is_empty():
			unbound.append(String(action).replace("_", " "))
			continue
		var shown: int = 0
		for event: InputEvent in events:
			if shown >= MAX_GLYPHS_PER_TOKEN:
				break
			var glyph: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
			add_child(glyph)
			glyph.set_event(event)
			if shown_texts.has(glyph.label_text()):
				remove_child(glyph)
				glyph.free()
				continue
			shown_texts.append(glyph.label_text())
			shown += 1
	if shown_texts.is_empty() and not unbound.is_empty():
		# DECISION: an action with no binding on this device reads as its own name
		# rather than a guessed key.
		_add_label(unbound[0])
