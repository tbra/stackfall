class_name LobbyButtonGlyph
extends RefCounted
## Puts the key / pad glyph of an Input Map action on a lobby button (Bontago-1pi.159.27): the
## hint is an InputPromptFlow (so it follows the active device and rebinds) laid over the button's
## right end, and the button's block styleboxes reserve its room so the label stays centred in the
## rest. Look only; the shortcut itself is handled by ui/Lobby.gd.

const NODE_NAME: String = "HintGlyph"
const TEMPLATE_FORMAT: String = "{%s}"
## The hint dims with a disabled button.
const DISABLED_ALPHA: float = 0.45


## Adds (or re-targets) the hint for [param action] on [param button].
static func attach(button: Button, action: StringName) -> void:
	var flow: InputPromptFlow = button.get_node_or_null(NODE_NAME) as InputPromptFlow
	if flow == null:
		flow = InputPromptFlow.new()
		flow.name = NODE_NAME
		flow.single_row = true
		flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(flow)
		flow.minimum_size_changed.connect(_place.bind(button, flow))
		button.draw.connect(_sync_alpha.bind(button, flow))
	flow.set_template(TEMPLATE_FORMAT % String(action))
	_place.call_deferred(button, flow)


static func flow_of(button: Button) -> InputPromptFlow:
	return button.get_node_or_null(NODE_NAME) as InputPromptFlow


static func _sync_alpha(button: Button, flow: InputPromptFlow) -> void:
	flow.modulate.a = DISABLED_ALPHA if button.disabled else 1.0


static func _place(button: Button, flow: InputPromptFlow) -> void:
	if not is_instance_valid(button) or not is_instance_valid(flow):
		return
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var pad: float = float(arcade.space_2_px)
	var glyph_size: Vector2 = flow.get_combined_minimum_size()
	flow.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	flow.offset_right = -pad
	flow.offset_left = -pad - glyph_size.x
	flow.offset_top = -glyph_size.y * 0.5
	flow.offset_bottom = glyph_size.y * 0.5
	var reserve: float = glyph_size.x + pad * 2.0
	for state: String in UiBlockButton.STATES:
		var box: StyleBox = button.get_theme_stylebox(state)
		if box != null:
			box.content_margin_right = maxf(box.content_margin_right, 0.0) + reserve - _reserved(box)
			box.set_meta(&"hint_reserve", reserve)


static func _reserved(box: StyleBox) -> float:
	return float(box.get_meta(&"hint_reserve", 0.0))
