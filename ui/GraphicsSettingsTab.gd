class_name GraphicsSettingsTab
extends FocusScrollContainer
## Bontago-1pi.11.86 (owner 2026-10-10): the Options "Graphics" page. A preset picker at the top
## (Low / Medium / High set every control below to that preset's values) and one control per
## GPU-relevant GraphicsPreset field. Editing any control stores a per-field override through
## Settings.set_graphics_override(), after which the picker shows "Custom"; Settings re-emits
## graphics_preset_changed with the effective preset so live consumers re-apply.
##
## Built in code from ROWS so a new field is one table entry. ui/OptionsMenu.gd owns the Arcade
## styling: it reads headers()/sliders()/value_labels()/checks() after build() and applies its
## existing section-header, SegmentMeter, value-label and ON/OFF-word styling to them.

## The state of the controls changed (preset pick or an edit): the menu refreshes its ON/OFF words.
signal refreshed

enum Kind { TOGGLE, CYCLE, SLIDER }

const PRESET_IDS: Array[StringName] = [&"low", &"medium", &"high"]
const PRESET_LABELS: Array[String] = ["Low", "Medium", "High"]
const CUSTOM_LABEL: String = "Custom"
const LABEL_MIN_WIDTH_PX: float = 180.0
const VALUE_LABEL_MIN_WIDTH_PX: float = 70.0
const ROW_SEPARATION_PX: int = 16
const DISABLED_ALPHA: float = 0.5
const PERCENT_SCALE: float = 100.0
const NODE_PRESET_OPTION: String = "PresetOption"
const FIXED_FPS_FIELD: StringName = &"fixed_fps"
const FRAME_CAP_FIELD: StringName = &"frame_cap_mode"

## DECISION (ui/GraphicsSettingsTab.gd): slider bounds/steps are widget configuration, not game
## tuning (the same reasoning as ui/OptionsMenu.gd's volume slider consts).
const SECTION_PRESET: String = "Preset"
const SECTION_QUALITY: String = "Quality"
const SECTION_EFFECTS: String = "Effects"
const SECTION_FRAME_RATE: String = "Frame rate"

## Display order top to bottom. kind TOGGLE | CYCLE (values + labels) | SLIDER (min, max, step,
## fmt: "percent" | "meters" | "fps").
const ROW_SECTION_QUALITY: Dictionary = {"section": SECTION_QUALITY}
const ROW_MSAA_3D: Dictionary = {"field": &"msaa_3d", "label": "Anti-aliasing", "kind": Kind.CYCLE, "values": [0, 1, 2], "labels": ["Off", "MSAA 2x", "MSAA 4x"]}
const ROW_RENDER_SCALE_3D: Dictionary = {"field": &"render_scale_3d", "label": "Render scale", "kind": Kind.SLIDER, "min": 0.5, "max": 1.0, "step": 0.05, "fmt": "percent"}
const ROW_RENDER_SCALE_3D_MODE: Dictionary = {"field": &"render_scale_3d_mode", "label": "Upscaler", "kind": Kind.CYCLE, "values": [0, 1, 2], "labels": ["Bilinear", "FSR 1.0", "FSR 2.2"]}
const ROW_SHADOW_ATLAS_SIZE: Dictionary = {"field": &"shadow_atlas_size", "label": "Shadow detail", "kind": Kind.CYCLE, "values": [1024, 2048, 4096, 8192], "labels": ["1K", "2K", "4K", "8K"]}
const ROW_SUN_SHADOW_MODE: Dictionary = {"field": &"sun_shadow_mode", "label": "Shadow cascades", "kind": Kind.CYCLE, "values": [0, 1, 2], "labels": ["1 split", "2 splits", "4 splits"]}
const ROW_SUN_SHADOW_MAX_DISTANCE: Dictionary = {"field": &"sun_shadow_max_distance", "label": "Shadow range", "kind": Kind.SLIDER, "min": 30.0, "max": 150.0, "step": 10.0, "fmt": "meters"}
const ROW_REFLECTION_PROBE_MODE: Dictionary = {"field": &"reflection_probe_mode", "label": "Reflections", "kind": Kind.CYCLE, "values": [0, 1, 2, 3], "labels": ["Off", "Once", "Interval", "Always"]}
const ROW_SSR_ENABLED: Dictionary = {"field": &"ssr_enabled", "label": "Screen reflections", "kind": Kind.TOGGLE}
const ROW_GLOW_ENABLED: Dictionary = {"field": &"glow_enabled", "label": "Glow", "kind": Kind.TOGGLE}
const ROW_VOLUMETRIC_FOG_ENABLED: Dictionary = {"field": &"volumetric_fog_enabled", "label": "Volumetric fog", "kind": Kind.TOGGLE}
const ROW_CLOUD_PUFF_DENSITY: Dictionary = {"field": &"cloud_puff_density", "label": "Cloud density", "kind": Kind.SLIDER, "min": 0.0, "max": 1.0, "step": 0.05, "fmt": "percent"}
const ROW_SECTION_EFFECTS: Dictionary = {"section": SECTION_EFFECTS}
const ROW_CLOUD_SHADOWS_ENABLED: Dictionary = {"field": &"cloud_shadows_enabled", "label": "Cloud shadows", "kind": Kind.TOGGLE}
const ROW_AURORA_ENABLED: Dictionary = {"field": &"aurora_enabled", "label": "Aurora", "kind": Kind.TOGGLE}
const ROW_BIRDS_ENABLED: Dictionary = {"field": &"birds_enabled", "label": "Distant birds", "kind": Kind.TOGGLE}
const ROW_AMBIENT_LIFE_ENABLED: Dictionary = {"field": &"ambient_life_enabled", "label": "Ambient life", "kind": Kind.TOGGLE}
const ROW_BLOCK_OUTLINE_ENABLED: Dictionary = {"field": &"block_outline_enabled", "label": "Block outlines", "kind": Kind.TOGGLE}
const ROW_BLOCK_DISSOLVE_EFFECT_ENABLED: Dictionary = {"field": &"block_dissolve_effect_enabled", "label": "Dissolve effect", "kind": Kind.TOGGLE}
const ROW_DISC_FINE_DETAIL_ENABLED: Dictionary = {"field": &"disc_fine_detail_enabled", "label": "Disc detail", "kind": Kind.TOGGLE}
const ROW_HOLE_VOID_ANIMATED: Dictionary = {"field": &"hole_void_animated", "label": "Animated void", "kind": Kind.TOGGLE}
const ROW_GIFT_IDLE_GLOW_ENABLED: Dictionary = {"field": &"gift_idle_glow_enabled", "label": "Crate glow", "kind": Kind.TOGGLE}
const ROW_SECTION_FRAME_RATE: Dictionary = {"section": SECTION_FRAME_RATE}
const ROW_FRAME_CAP_MODE: Dictionary = {"field": &"frame_cap_mode", "label": "Frame cap", "kind": Kind.CYCLE, "values": [0, 1, 2], "labels": ["Display refresh", "Fixed", "Uncapped"]}
const ROW_FIXED_FPS: Dictionary = {"field": &"fixed_fps", "label": "Fixed fps", "kind": Kind.SLIDER, "min": 30.0, "max": 360.0, "step": 10.0, "fmt": "fps"}

const ROWS: Array[Dictionary] = [
	ROW_SECTION_QUALITY,
	ROW_MSAA_3D,
	ROW_RENDER_SCALE_3D,
	ROW_RENDER_SCALE_3D_MODE,
	ROW_SHADOW_ATLAS_SIZE,
	ROW_SUN_SHADOW_MODE,
	ROW_SUN_SHADOW_MAX_DISTANCE,
	ROW_REFLECTION_PROBE_MODE,
	ROW_SSR_ENABLED,
	ROW_GLOW_ENABLED,
	ROW_VOLUMETRIC_FOG_ENABLED,
	ROW_CLOUD_PUFF_DENSITY,
	ROW_SECTION_EFFECTS,
	ROW_CLOUD_SHADOWS_ENABLED,
	ROW_AURORA_ENABLED,
	ROW_BIRDS_ENABLED,
	ROW_AMBIENT_LIFE_ENABLED,
	ROW_BLOCK_OUTLINE_ENABLED,
	ROW_BLOCK_DISSOLVE_EFFECT_ENABLED,
	ROW_DISC_FINE_DETAIL_ENABLED,
	ROW_HOLE_VOID_ANIMATED,
	ROW_GIFT_IDLE_GLOW_ENABLED,
	ROW_SECTION_FRAME_RATE,
	ROW_FRAME_CAP_MODE,
	ROW_FIXED_FPS,
]

## Returns the Settings provider (the real autoload, or a test's own Settings.new() assigned to
## OptionsMenu.settings_provider after the menu entered the tree, hence a getter, not a value).
var _provider_getter: Callable = Callable()
var preset_option: OptionButton = null
var _fields: VBoxContainer = null
var _headers: Array[Label] = []
var _sliders: Array[HSlider] = []
var _value_labels: Array[Label] = []
var _checks: Array[CheckButton] = []
var _controls: Array[Control] = []
## field -> {"kind", "control", "row"(dict), "value_label"}
var _by_field: Dictionary = {}
var _refreshing: bool = false


## Builds the page. Call once, after the node is in the tree (so `owner` can be set).
func build(provider_getter: Callable, menu_owner: Node) -> void:
	_provider_getter = provider_getter
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_fields = VBoxContainer.new()
	_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fields.add_theme_constant_override("separation", ROW_SEPARATION_PX)
	add_child(_fields)
	_add_header(SECTION_PRESET)
	_build_preset_row(menu_owner)
	for row: Dictionary in ROWS:
		if row.has("section"):
			_add_header(row["section"] as String)
			continue
		match row["kind"]:
			Kind.TOGGLE:
				_build_toggle_row(row)
			Kind.CYCLE:
				_build_cycle_row(row)
			Kind.SLIDER:
				_build_slider_row(row)
	refresh_from_settings()


func _provider() -> Variant:
	return _provider_getter.call()


func headers() -> Array[Label]:
	return _headers


func sliders() -> Array[HSlider]:
	return _sliders


func value_labels() -> Array[Label]:
	return _value_labels


func checks() -> Array[CheckButton]:
	return _checks


## Every focusable control top to bottom, preset picker first.
func focus_controls() -> Array[Control]:
	return _controls


## The control that edits `field` (test/inspection seam), or null.
func control_for(field: StringName) -> Control:
	return (_by_field[field]["control"] as Control) if _by_field.has(field) else null


## Re-reads every control from the Settings provider without emitting edits.
func refresh_from_settings() -> void:
	_refreshing = true
	if _provider().graphics_preset_is_custom():
		preset_option.select(PRESET_IDS.size())
	else:
		var index: int = PRESET_IDS.find(_provider().graphics_base_preset_id())
		preset_option.select(index if index >= 0 else PRESET_IDS.find(Settings.DEFAULT_PRESET_ID))
	for field: StringName in _by_field:
		var entry: Dictionary = _by_field[field]
		var value: Variant = _provider().graphics_field_value(field)
		var row: Dictionary = entry["row"]
		match row["kind"]:
			Kind.TOGGLE:
				(entry["control"] as CheckButton).set_pressed_no_signal(bool(value))
			Kind.CYCLE:
				(entry["control"] as CycleSelector).select((row["values"] as Array).find(int(value)))
			Kind.SLIDER:
				var slider: HSlider = entry["control"] as HSlider
				slider.set_value_no_signal(float(value))
				(entry["value_label"] as Label).text = _format_value(float(value), row["fmt"] as String)
	_refresh_fixed_fps_enabled()
	_refreshing = false
	refreshed.emit()


func _add_header(text: String) -> void:
	var header: Label = Label.new()
	header.text = text
	_fields.add_child(header)
	_headers.append(header)


func _make_row(label_text: String) -> HBoxContainer:
	var box: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = LABEL_MIN_WIDTH_PX
	box.add_child(label)
	_fields.add_child(box)
	return box


func _build_preset_row(menu_owner: Node) -> void:
	var box: HBoxContainer = _make_row("Graphics preset")
	preset_option = OptionButton.new()
	preset_option.name = NODE_PRESET_OPTION
	preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for label: String in PRESET_LABELS:
		preset_option.add_item(label)
	preset_option.add_item(CUSTOM_LABEL)
	# Custom is only ever a state (set by editing a control), never something to pick.
	preset_option.set_item_disabled(PRESET_IDS.size(), true)
	box.add_child(preset_option)
	# Keep the %PresetOption lookup the menu and its tests use.
	preset_option.unique_name_in_owner = true
	preset_option.owner = menu_owner
	preset_option.item_selected.connect(pick_preset)
	_controls.append(preset_option)


func _build_toggle_row(row: Dictionary) -> void:
	var box: HBoxContainer = _make_row(row["label"] as String)
	var check: CheckButton = CheckButton.new()
	box.add_child(check)
	check.toggled.connect(_on_toggle.bind(row["field"] as StringName))
	_checks.append(check)
	_controls.append(check)
	_by_field[row["field"]] = {"kind": Kind.TOGGLE, "control": check, "row": row}


func _build_cycle_row(row: Dictionary) -> void:
	var box: HBoxContainer = _make_row(row["label"] as String)
	var cycle: CycleSelector = CycleSelector.new()
	cycle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for text: String in (row["labels"] as Array):
		cycle.add_item(text)
	box.add_child(cycle)
	cycle.item_selected.connect(_on_cycle_selected.bind(row["field"] as StringName))
	_controls.append(cycle)
	_by_field[row["field"]] = {"kind": Kind.CYCLE, "control": cycle, "row": row}


func _build_slider_row(row: Dictionary) -> void:
	var box: HBoxContainer = _make_row(row["label"] as String)
	var slider: HSlider = HSlider.new()
	slider.min_value = float(row["min"])
	slider.max_value = float(row["max"])
	slider.step = float(row["step"])
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(slider)
	SliderNav.apply(slider)
	var value_label: Label = Label.new()
	value_label.custom_minimum_size.x = VALUE_LABEL_MIN_WIDTH_PX
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(value_label)
	slider.value_changed.connect(_on_slider_changed.bind(row["field"] as StringName))
	_sliders.append(slider)
	_value_labels.append(value_label)
	_controls.append(slider)
	_by_field[row["field"]] = {"kind": Kind.SLIDER, "control": slider, "row": row, "value_label": value_label}


## The user picked preset `index` (Low/Medium/High): every control takes that preset's values.
## Custom (or an out-of-range index) is ignored and the picker snaps back to the real state.
func pick_preset(index: int) -> void:
	if _refreshing:
		return
	if index < 0 or index >= PRESET_IDS.size():
		refresh_from_settings()
		return
	_provider().set_graphics_preset(PRESET_IDS[index])
	refresh_from_settings()


func _on_toggle(pressed: bool, field: StringName) -> void:
	_edit(field, pressed)


func _on_cycle_selected(index: int, field: StringName) -> void:
	var values: Array = _by_field[field]["row"]["values"]
	if index >= 0 and index < values.size():
		_edit(field, values[index])


func _on_slider_changed(value: float, field: StringName) -> void:
	_edit(field, value)


func _edit(field: StringName, value: Variant) -> void:
	if _refreshing:
		return
	_provider().set_graphics_override(field, value)
	refresh_from_settings()


## The fixed-fps slider only matters while the frame cap is "Fixed".
func _refresh_fixed_fps_enabled() -> void:
	if not _by_field.has(FIXED_FPS_FIELD) or not _by_field.has(FRAME_CAP_FIELD):
		return
	var fixed: bool = int(_provider().graphics_field_value(FRAME_CAP_FIELD)) == GraphicsPreset.FrameCap.FIXED
	var slider: HSlider = _by_field[FIXED_FPS_FIELD]["control"] as HSlider
	slider.editable = fixed
	slider.modulate.a = 1.0 if fixed else DISABLED_ALPHA


static func _format_value(value: float, fmt: String) -> String:
	match fmt:
		"meters":
			return "%d m" % roundi(value)
		"fps":
			return "%d" % roundi(value)
		_:
			return "%d%%" % roundi(value * PERCENT_SCALE)
