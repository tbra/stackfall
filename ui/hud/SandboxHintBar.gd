class_name SandboxHintBar
extends CanvasLayer
## the bottom-centre sandbox hint listing every debug F-key and its function.
## Key names are read from the Input Map (InputGlyph.events_of_family), never hard-coded, so a
## rebind or a regenerated map shows up here. Debug-mode only (game/debug/DebugMode.gd).

const HINT_BOTTOM_MARGIN_PX: float = 6.0
const HINT_PLATE_ALPHA: float = 0.82
const HINT_THEME: Theme = preload("res://ui/theme/stackfall_theme.tres")
const LAYER_INDEX: int = 10
const ENTRY_SEPARATOR: String = "   "
const KEY_FORMAT: String = "%s %s"
const NO_KEY_TEXT: String = "?"
## Action id and the function it performs, in display order.
const ENTRIES: Array[Dictionary] = [
	{"action": &"perf_overlay_toggle", "label": "perf"},
	{"action": &"net_debug_toggle", "label": "net"},
	{"action": &"tuning_panel_toggle", "label": "tuning"},
	{"action": &"sandbox_reset_field", "label": "reset"},
	{"action": &"sandbox_toggle_timer", "label": "timer"},
	{"action": &"sandbox_spawn_tower", "label": "tower"},
	{"action": &"hud_toggle", "label": "HUD"},
	{"action": &"sandbox_force_special", "label": "special"},
	{"action": &"sandbox_slow_motion", "label": "slow-mo"},
	{"action": &"sandbox_pause_physics", "label": "pause"},
	{"action": &"screenshot_capture", "label": "screenshot"},
	{"action": &"sandbox_next_slot", "label": "slot"},
]

var _plate: PanelContainer = null
var _hint: Label = null


func _ready() -> void:
	layer = LAYER_INDEX
	_hint = Label.new()
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	_plate = PanelContainer.new()
	_plate.theme = HINT_THEME
	_plate.anchor_left = 0.5
	_plate.anchor_right = 0.5
	_plate.anchor_top = 1.0
	_plate.anchor_bottom = 1.0
	_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_plate.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_plate.offset_bottom = -HINT_BOTTOM_MARGIN_PX
	var backing: StyleBoxFlat = MenuStyleFactory.make_plate(Color(arcade.disc_900_color, HINT_PLATE_ALPHA))
	backing.set_corner_radius_all(arcade.radius_block_px)
	backing.shadow_size = 0
	backing.content_margin_left = float(arcade.space_4_px)
	backing.content_margin_right = float(arcade.space_4_px)
	backing.content_margin_top = float(arcade.space_1_px)
	backing.content_margin_bottom = float(arcade.space_1_px)
	_plate.add_theme_stylebox_override("panel", backing)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.theme_type_variation = &"CaptionLabel"
	_hint.add_theme_color_override("font_color", arcade.sand_color)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(_hint)
	add_child(_plate)
	refresh()


func _process(_delta: float) -> void:
	_plate.visible = DebugMode.is_enabled()


## Rebuilds the text from the current Input Map.
func refresh() -> void:
	_hint.text = hint_text()
	_plate.visible = DebugMode.is_enabled()


static func hint_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for entry: Dictionary in ENTRIES:
		parts.append(KEY_FORMAT % [key_text(entry["action"] as StringName), entry["label"]])
	return ENTRY_SEPARATOR.join(parts)


static func key_text(action: StringName) -> String:
	for event: InputEvent in InputGlyph.events_of_family(action, false):
		var key_event: InputEventKey = event as InputEventKey
		if key_event != null:
			return key_event.as_text_keycode() if key_event.keycode != KEY_NONE else key_event.as_text_physical_keycode()
	return NO_KEY_TEXT
