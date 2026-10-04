class_name GiftDemoStrip
extends CanvasLayer
## Bontago-1pi.70: the gift demo's on-screen hint: which gift the next piece is
## forced to, plus the bound prev/next glyphs (shared InputGlyph, active device).

const INPUT_GLYPH_SCENE: PackedScene = preload("res://ui/InputGlyph.tscn")
const ACTION_PREV: StringName = &"gift_demo_cycle_prev"
const ACTION_NEXT: StringName = &"gift_demo_cycle_next"
const STRIP_LAYER: int = 30
const MARGIN_PX: float = 16.0

var _label: Label = null
var _row: HBoxContainer = null


func _ready() -> void:
	layer = STRIP_LAYER
	_row = HBoxContainer.new()
	_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_row.offset_top = MARGIN_PX
	_row.offset_right = -MARGIN_PX
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	_label = Label.new()
	_label.text = "Gift: off"
	_row.add_child(_label)
	Events.input_device_changed.connect(_on_device_changed)
	_rebuild_glyphs()


func set_gift(special_id: StringName) -> void:
	_label.text = "Gift: %s" % (String(special_id).replace("_", " ") if special_id != &"" else "off")


## Test seam: labels of the shown glyphs.
func glyph_texts() -> PackedStringArray:
	var texts: PackedStringArray = PackedStringArray()
	for child: Node in _row.get_children():
		if child is InputGlyph:
			texts.append((child as InputGlyph).label_text())
	return texts


func _on_device_changed(_device: StringName) -> void:
	_rebuild_glyphs()


func _rebuild_glyphs() -> void:
	for child: Node in _row.get_children():
		if child is InputGlyph:
			_row.remove_child(child)
			child.free()
	var want_gamepad: bool = Settings.active_input_device() == Settings.DEVICE_GAMEPAD
	for action: StringName in [ACTION_PREV, ACTION_NEXT]:
		for event: InputEvent in InputMap.action_get_events(action):
			var is_gamepad: bool = event is InputEventJoypadButton or event is InputEventJoypadMotion
			if is_gamepad != want_gamepad:
				continue
			var glyph: InputGlyph = INPUT_GLYPH_SCENE.instantiate() as InputGlyph
			_row.add_child(glyph)
			glyph.set_event(event)
			break
