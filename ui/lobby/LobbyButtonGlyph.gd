class_name LobbyButtonGlyph
extends RefCounted
## Puts the key / pad glyph of an Input Map action on a lobby button (Bontago-1pi.159.27): the
## hint is an InputPromptFlow (so it follows the active device and rebinds) sitting right before the
## label (and the button's icon), the glyph + icon + label group centred in the button
## (Bontago-1pi.159.39). The block styleboxes reserve the glyph's room on the left, so the button's
## minimum width grows to hold the group and the label stays centred in the rest; a glyph taller than
## the button's face is scaled down to fit. Look only; the shortcut itself is handled by ui/Lobby.gd.

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
		button.draw.connect(_sync.bind(button, flow))
		button.resized.connect(_place.bind(button, flow))
	flow.set_template(TEMPLATE_FORMAT % String(action))
	_place(button, flow)  # the button's draw / resize and the flow's size change keep it placed


static func flow_of(button: Button) -> InputPromptFlow:
	return button.get_node_or_null(NODE_NAME) as InputPromptFlow


static func _sync(button: Button, flow: InputPromptFlow) -> void:
	flow.modulate.a = DISABLED_ALPHA if button.disabled else 1.0
	_place(button, flow)  # cheap, and catches a changed label / re-styled boxes


static func _place(button: Button, flow: InputPromptFlow) -> void:
	if not is_instance_valid(button) or not is_instance_valid(flow):
		return
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var gap: float = float(arcade.space_2_px)
	var natural: Vector2 = flow.get_combined_minimum_size()
	var face_height: float = button.size.y - float(arcade.space_1_px * 2)
	var fit: float = 1.0
	if face_height > 0.0 and natural.y > face_height:
		fit = face_height / natural.y
	var glyph_width: float = natural.x * fit
	var reserve: float = glyph_width + gap
	for state: String in UiBlockButton.STATES:
		var box: StyleBox = button.get_theme_stylebox(state)
		if box != null:
			var delta: float = reserve - _reserved(box)
			if absf(delta) > 0.0:
				# The meta first: changing the margin can re-enter this function synchronously.
				box.set_meta(&"hint_reserve", reserve)
				box.content_margin_left = maxf(box.content_margin_left, 0.0) + delta
	# The group is glyph, gap, [icon, gap,] label; the label (+ icon) is centred in what the margin
	# leaves, so the group's left edge is (button width - group width) / 2.
	var group: float = reserve + content_width(button)
	flow.set_anchors_preset(Control.PRESET_TOP_LEFT)
	flow.size = natural
	flow.pivot_offset = Vector2(0.0, natural.y * 0.5)
	flow.scale = Vector2(fit, fit)
	flow.position = Vector2(maxf((button.size.x - group) * 0.5, 0.0), (button.size.y - natural.y) * 0.5)


## The width of the button's own content (icon, gap, label): its minimum width less the stylebox margins.
static func content_width(button: Button) -> float:
	var box: StyleBox = button.get_theme_stylebox(&"normal")
	var margins: float = 0.0 if box == null else maxf(box.content_margin_left, 0.0) + maxf(box.content_margin_right, 0.0)
	return maxf(button.get_minimum_size().x - margins, 0.0)


static func _reserved(box: StyleBox) -> float:
	return float(box.get_meta(&"hint_reserve", 0.0))
