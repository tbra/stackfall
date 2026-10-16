class_name UiButtonHint
extends RefCounted
## The optional trailing input hint of a block button ("an optional trailing input hint"). One component path for every glyph
## button: UiBlockButton.hint_action calls [method attach]; screens never place a glyph themselves.
##
## Layout (all values from ArcadeVisualTuning): the group [icon, label, gap(space_2), glyph] is
## centred horizontally in the button; the glyph is scaled down so its cap fits inside the block
## face with a space_3 total margin, and its cap is centred vertically on the label's own line (the
## stylebox content box of the CURRENT state, so it follows the press travel exactly like the
## text). State: a disabled button dims it (disabled_alpha), a pressed one darkens it
## (pressed_top_dark_mix). The hint is an InputPromptFlow, so it follows the active device and
## rebinds. The block styleboxes reserve the glyph's room in their right margin, so the label
## stays centred in what is left and the button's minimum width grows to hold the group.

const NODE_NAME: String = "HintGlyph"
const TEMPLATE_FORMAT: String = "{%s}"
const STATE_NAMES: Dictionary[int, String] = {
	BaseButton.DRAW_NORMAL: "normal",
	BaseButton.DRAW_HOVER: "hover",
	BaseButton.DRAW_PRESSED: "pressed",
	BaseButton.DRAW_HOVER_PRESSED: "hover_pressed",
	BaseButton.DRAW_DISABLED: "disabled",
}
const META_RESERVE: StringName = &"hint_reserve"
## Marks a stylebox this button owns (a private copy of the shared block): only those are mutated.
const META_OWN: StringName = &"hint_own"


## Adds (or re-targets) the hint for [param action] on [param button]; an empty action removes it.
static func attach(button: Button, action: StringName) -> void:
	var flow: InputPromptFlow = flow_of(button)
	if action == &"":
		if flow != null:
			_release_reserve(button)
			flow.queue_free()
			button.remove_child(flow)
		return
	if flow == null:
		flow = InputPromptFlow.new()
		flow.name = NODE_NAME
		flow.single_row = true
		flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(flow)
		flow.minimum_size_changed.connect(_place.bind(button, flow))
		button.draw.connect(_place.bind(button, flow))
		button.resized.connect(_place.bind(button, flow))
	flow.set_template(TEMPLATE_FORMAT % String(action))
	_place(button, flow)


static func flow_of(button: Button) -> InputPromptFlow:
	return button.get_node_or_null(NODE_NAME) as InputPromptFlow


## The width of the button's own content (icon, gap, label): its minimum width less the stylebox
## margins and the glyph's reserved room.
static func content_width(button: Button) -> float:
	var box: StyleBox = button.get_theme_stylebox(&"normal")
	var margins: float = 0.0 if box == null else maxf(box.content_margin_left, 0.0) + maxf(box.content_margin_right, 0.0)
	return maxf(button.get_minimum_size().x - margins, 0.0)


## The glyph's tint for a button draw state (pure; tests and the gallery assert it).
static func tint_for(draw_mode: int, arcade: ArcadeVisualTuning) -> Color:
	match draw_mode:
		BaseButton.DRAW_DISABLED:
			return Color(1.0, 1.0, 1.0, arcade.disabled_alpha)
		BaseButton.DRAW_PRESSED, BaseButton.DRAW_HOVER_PRESSED:
			return Color.WHITE.darkened(arcade.pressed_top_dark_mix)
	return Color.WHITE


static func _place(button: Button, flow: InputPromptFlow) -> void:
	if not is_instance_valid(button) or not is_instance_valid(flow) or not flow.is_inside_tree():
		return
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var gap: float = float(arcade.space_2_px)
	var natural: Vector2 = flow.get_combined_minimum_size()
	if natural.y <= 0.0:
		return
	var cap_drop: float = float(arcade.drop_sm_px)
	var body: float = maxf(natural.y - cap_drop, 1.0)
	var face_room: float = button.size.y - float(arcade.drop_sm_px) - float(arcade.space_3_px)  # space-3 total breathing room above/below the cap
	var fit: float = 1.0
	if face_room > 0.0 and body > face_room:
		fit = face_room / body
	var reserve: float = natural.x * fit + gap
	for state: String in UiBlockButton.STATES:
		var box: StyleBox = button.get_theme_stylebox(state)
		if box != null:
			var delta: float = reserve - float(box.get_meta(META_RESERVE, 0.0))
			if absf(delta) > 0.0:
				if not box.has_meta(META_OWN):
					# Block styleboxes are shared across buttons: reserve room on a private copy.
					box = box.duplicate() as StyleBox
					box.set_meta(META_OWN, true)
					button.add_theme_stylebox_override(state, box)
				# The meta first: changing the margin can re-enter this function synchronously.
				box.set_meta(META_RESERVE, reserve)
				box.content_margin_right = maxf(box.content_margin_right, 0.0) + delta
	var mode: int = button.get_draw_mode()
	flow.modulate = tint_for(mode, arcade)
	var current: StyleBox = button.get_theme_stylebox(STATE_NAMES.get(mode, "normal"))
	var line_top: float = 0.0 if current == null else maxf(current.content_margin_top, 0.0)
	var line_bottom: float = 0.0 if current == null else maxf(current.content_margin_bottom, 0.0)
	var line_centre: float = (line_top + button.size.y - line_bottom) * 0.5
	var group: float = content_width(button) + reserve
	var left: float = (button.size.x - group) * 0.5 + content_width(button) + gap
	flow.set_anchors_preset(Control.PRESET_TOP_LEFT)
	flow.size = natural
	flow.pivot_offset = Vector2.ZERO
	flow.scale = Vector2(fit, fit)
	flow.position = Vector2(roundf(maxf(left, 0.0)), roundf(line_centre - body * fit * 0.5))


static func _release_reserve(button: Button) -> void:
	for state: String in UiBlockButton.STATES:
		var box: StyleBox = button.get_theme_stylebox(state)
		if box != null and box.has_meta(META_RESERVE):
			box.content_margin_right = maxf(box.content_margin_right - float(box.get_meta(META_RESERVE)), 0.0)
			box.remove_meta(META_RESERVE)
