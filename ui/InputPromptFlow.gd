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
## Theme type variation of the action words (13 px caption, stackfall_theme).
const ACTION_WORD_VARIATION: StringName = &"CaptionLabel"
## Fewer words than this in the final run are left unglued.
const MIN_WORDS_TO_GLUE: int = 2
const INPUT_GLYPH_SCENE: PackedScene = preload("res://ui/InputGlyph.tscn")

## Template text; set via set_template() or in the inspector.
@export_multiline var template: String = "":
	set(value):
		template = value
		if is_node_ready():
			refresh()

## Bontago-1pi.83: keep every token on one row. An HFlowContainer reports only its widest
## child as minimum width, so inside a shrink-wrapped pill it wraps; with this on, the
## summed child width is pinned as the minimum after each rebuild.
@export var single_row: bool = false

## Ink for the word labels (menus pass their palette ink; a transparent default
## leaves the theme colour alone).
var text_color: Color = Color(0.0, 0.0, 0.0, 0.0)
## True right after a token: the next word run is preceded by a glyph gap.
var _gap_pending: bool = false


func _ready() -> void:
	# Stackfall Arcade: a cap and its word read as one pair; pairs sit a peer-gap apart.
	# DECISION (Bontago-hfa.12): word Labels carry their own trailing space (h_separation 0) so words
	# sit a normal font space apart; only keycap glyphs get a space_2 gap (_add_gap). Wrapped lines a
	# space_1 apart, always start-aligned.
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	add_theme_constant_override(&"h_separation", 0)
	add_theme_constant_override(&"v_separation", arcade.space_1_px)
	alignment = FlowContainer.ALIGNMENT_BEGIN
	last_wrap_alignment = FlowContainer.LAST_WRAP_ALIGNMENT_BEGIN
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
	_gap_pending = false
	var rest: String = template
	while not rest.is_empty():
		var open: int = rest.find(TOKEN_OPEN)
		var close: int = rest.find(TOKEN_CLOSE, open + 1) if open >= 0 else -1
		if open < 0 or close < 0:
			_add_words(rest, true)
			break
		_add_words(rest.substr(0, open), false)
		_add_token(rest.substr(open + 1, close - open - 1))
		rest = rest.substr(close + 1)
	if single_row:
		_pin_single_row_width.call_deferred()


## Sets custom_minimum_size.x to the width of all live children laid out on one row.
func _pin_single_row_width() -> void:
	var total: float = 0.0
	var count: int = 0
	for child: Node in get_children():
		var control: Control = child as Control
		if control == null or control.is_queued_for_deletion() or not control.visible:
			continue
		total += control.get_combined_minimum_size().x
		count += 1
	if count > 1:
		total += float(count - 1) * float(get_theme_constant(&"h_separation"))
	custom_minimum_size.x = total


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


## Adds the words of one plain-text run. Each Label ends in a space except the run's last word
## (the space is the font's own advance, not a container gap). In the template's final run the last
## two words share one Label so a wrap can never leave a single short word alone on the last line.
func _add_words(text: String, is_final_run: bool) -> void:
	var words: PackedStringArray = text.split(" ", false)
	if is_final_run and words.size() >= MIN_WORDS_TO_GLUE:
		var glued: String = words[words.size() - 2] + " " + words[words.size() - 1]
		words = words.slice(0, words.size() - 2)
		words.append(glued)
	if _gap_pending and not words.is_empty():
		_add_gap()
		_gap_pending = false
	for index: int in words.size():
		var is_last: bool = index == words.size() - 1
		_add_label(words[index] if is_last else words[index] + " ")


func _add_gap() -> void:
	var gap: Control = Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.custom_minimum_size = Vector2(float(MenuStyleFactory.arcade_tuning().space_2_px), 0.0)
	add_child(gap)


func _add_label(text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Stackfall Arcade KeyPrompt: the action word is a sand caption-size label unless the host
	# menu passes its own ink.
	label.theme_type_variation = ACTION_WORD_VARIATION
	label.add_theme_color_override("font_color", text_color if text_color.a > 0.0 else MenuStyleFactory.arcade_tuning().sand_color)
	add_child(label)


func _add_token(token: String) -> void:
	if get_child_count() > 0:
		_add_gap()
	_gap_pending = true
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
