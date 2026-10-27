class_name SandboxHintBar
extends CanvasLayer
## the bottom-centre sandbox hint listing every debug F-key and its function.
## The keys are InputPromptFlow glyphs, the prompt control the Options footer uses: they come from the
## Input Map for the player's active device (keyboard names or gamepad buttons, swapped on
## Events.input_device_changed), never hard-coded. Debug-mode only (game/debug/DebugMode.gd).

const HINT_BOTTOM_MARGIN_PX: float = 6.0
const HINT_PLATE_ALPHA: float = 0.82
const HINT_THEME: Theme = preload("res://ui/theme/stackfall_theme.tres")
const LAYER_INDEX: int = 10
const ENTRY_SEPARATOR: String = "   "
const TOKEN_FORMAT: String = "{%s} %s"
## Action id and the function it performs, in display order.
const ENTRIES: Array[Dictionary] = [
	{"action": &"perf_overlay_toggle", "label": "perf"},
	{"action": &"pose_overlay_toggle", "label": "pose"},
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
	{"action": &"bot_cost_overlay_toggle", "label": "bot cost"},
	{"action": &"sandbox_next_slot", "label": "slot"},
]

var _plate: PanelContainer = null
var _hint: InputPromptFlow = null


func _ready() -> void:
	layer = LAYER_INDEX
	_hint = InputPromptFlow.new()
	_hint.single_row = true
	_hint.set_template(hint_template())
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
	_hint.text_color = arcade.sand_color
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(_hint)
	add_child(_plate)
	refresh()


func _process(_delta: float) -> void:
	_plate.visible = DebugMode.is_enabled()


## Rebuilds the glyphs from the current Input Map.
func refresh() -> void:
	_hint.refresh()
	_plate.visible = DebugMode.is_enabled()


## The InputPromptFlow template: one `{action} label` token per entry.
static func hint_template() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for entry: Dictionary in ENTRIES:
		parts.append(TOKEN_FORMAT % [entry["action"], entry["label"]])
	return ENTRY_SEPARATOR.join(parts)
