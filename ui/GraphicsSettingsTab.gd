class_name GraphicsSettingsTab
extends FocusScrollContainer
## Bontago-1pi.11.86 / 1pi.153: the Options "Graphics" page, built from design-system components
## (UiSection / UiRow / UiDropdown / UiToggle / UiSegmentMeter).
##
## DECISION (owner 2026-10-10 "limit it to the options games usually include", research delegated to
## the orchestrator): the page shows the common PC-game set only -- Graphics preset, Anti-aliasing,
## Render scale, Upscaler, Shadows, Reflections, Bloom, Volumetric fog, Environment detail, Block
## outlines, Frame cap (+ Fixed fps while the cap is Fixed). Shadows, Reflections and Environment
## detail are COMBINED rows: one tier writes several GraphicsPreset fields at once (tables in
## GraphicsPreset). The preset fields, settings keys and preset .tres files are unchanged, so saved
## per-field overrides still load; a combined row shows the tier whose values all match, else "Custom".
## There is no Ultra tier because no Ultra preset exists (Low / Medium / High only).
##
## Editing any control stores per-field overrides through Settings.set_graphics_override(), after
## which the preset picker shows "Custom"; Settings re-emits graphics_preset_changed with the
## effective preset so live consumers re-apply.

enum Kind { TOGGLE, DROPDOWN, METER, COMBO }

const PRESET_IDS: Array[StringName] = [&"low", &"medium", &"high"]
const PRESET_LABELS: Array[String] = ["Low", "Medium", "High"]
const CUSTOM_LABEL: String = "Custom"
const PERCENT_SCALE: float = 100.0
const NODE_PRESET_OPTION: String = "PresetOption"
const FIXED_FPS_FIELD: StringName = &"fixed_fps"
const FRAME_CAP_FIELD: StringName = &"frame_cap_mode"
const TIER_LABELS: Array[String] = ["Low", "Medium", "High"]
const REFLECTION_LABELS: Array[String] = ["Off", "Low", "High"]

const SECTION_PRESET: String = "Preset"
const SECTION_QUALITY: String = "Quality"
const SECTION_EFFECTS: String = "Effects"
const SECTION_FRAME_RATE: String = "Frame rate"

## Combined-row ids (control_for() keys; they are not GraphicsPreset fields).
const COMBO_SHADOWS: StringName = &"shadows"
const COMBO_REFLECTIONS: StringName = &"reflections"
const COMBO_ENVIRONMENT: StringName = &"environment_detail"

## Display order top to bottom; "section" entries start a UiSection. kind TOGGLE | DROPDOWN (field
## values + labels) | METER (field, fmt: "percent" | "fps") | COMBO (id + tiers + labels).
const ROW_MSAA_3D: Dictionary = {"field": &"msaa_3d", "label": "Anti-aliasing", "kind": Kind.DROPDOWN, "labels": ["Off", "MSAA 2x", "MSAA 4x"]}
const ROW_RENDER_SCALE_3D: Dictionary = {"field": &"render_scale_3d", "label": "Render scale", "kind": Kind.METER, "fmt": "percent"}
const ROW_RENDER_SCALE_3D_MODE: Dictionary = {"field": &"render_scale_3d_mode", "label": "Upscaler", "kind": Kind.DROPDOWN, "labels": ["Bilinear", "FSR 1.0", "FSR 2.2"]}
const ROW_SHADOWS: Dictionary = {"field": COMBO_SHADOWS, "label": "Shadows", "kind": Kind.COMBO, "labels": TIER_LABELS}
const ROW_REFLECTIONS: Dictionary = {"field": COMBO_REFLECTIONS, "label": "Reflections", "kind": Kind.COMBO, "labels": REFLECTION_LABELS}
const ROW_GLOW_ENABLED: Dictionary = {"field": &"glow_enabled", "label": "Bloom", "kind": Kind.TOGGLE}
const ROW_VOLUMETRIC_FOG_ENABLED: Dictionary = {"field": &"volumetric_fog_enabled", "label": "Volumetric fog", "kind": Kind.TOGGLE}
const ROW_ENVIRONMENT: Dictionary = {"field": COMBO_ENVIRONMENT, "label": "Environment detail", "kind": Kind.COMBO, "labels": TIER_LABELS}
const ROW_BLOCK_OUTLINE_ENABLED: Dictionary = {"field": &"block_outline_enabled", "label": "Block outlines", "kind": Kind.TOGGLE}
const ROW_FRAME_CAP_MODE: Dictionary = {"field": &"frame_cap_mode", "label": "Frame cap", "kind": Kind.DROPDOWN, "labels": ["Display refresh", "Fixed", "Uncapped"]}
const ROW_FIXED_FPS: Dictionary = {"field": &"fixed_fps", "label": "Fixed fps", "kind": Kind.METER, "fmt": "fps"}

const SECTIONS: Array[Dictionary] = [
	{"title": SECTION_QUALITY, "items": [ROW_MSAA_3D, ROW_RENDER_SCALE_3D, ROW_RENDER_SCALE_3D_MODE, ROW_SHADOWS, ROW_REFLECTIONS]},
	{"title": SECTION_EFFECTS, "items": [ROW_GLOW_ENABLED, ROW_VOLUMETRIC_FOG_ENABLED, ROW_ENVIRONMENT, ROW_BLOCK_OUTLINE_ENABLED]},
	{"title": SECTION_FRAME_RATE, "items": [ROW_FRAME_CAP_MODE, ROW_FIXED_FPS]},
]

## Returns the Settings provider (the real autoload, or a test's own Settings.new() assigned to
## OptionsMenu.settings_provider after the menu entered the tree, hence a getter, not a value).
var _provider_getter: Callable = Callable()
var preset_option: UiDropdown = null
var _fields: VBoxContainer = null
var _controls: Array[Control] = []
## field / combo id -> {"kind", "control", "row"(dict), "tiers"(combo only)}
var _by_field: Dictionary = {}
var _refreshing: bool = false


## Builds the page. Call once, after the node is in the tree (so `owner` can be set).
func build(provider_getter: Callable, menu_owner: Node) -> void:
	_provider_getter = provider_getter
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	_fields = VBoxContainer.new()
	_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fields.add_theme_constant_override("separation", arcade.space_4_px)
	_fields.theme = _spacing_theme(arcade)
	add_child(_fields)
	_build_preset_section(menu_owner)
	for section: Dictionary in SECTIONS:
		var body: VBoxContainer = _add_section(section["title"] as String)
		for row: Dictionary in (section["items"] as Array):
			_build_row(body, row)
	refresh_from_settings()


func _provider() -> Variant:
	return _provider_getter.call()


## Every focusable control top to bottom, preset picker first.
func focus_controls() -> Array[Control]:
	return _controls


## The control that edits `field` (a GraphicsPreset field or a combined-row id; test/inspection
## seam), or null.
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
		var row: Dictionary = entry["row"]
		match row["kind"]:
			Kind.TOGGLE:
				(entry["control"] as UiToggle).set_on_silent(bool(_provider().graphics_field_value(field)))
			Kind.DROPDOWN:
				var values: Array = GraphicsPreset.limits_for(field)["values"]
				(entry["control"] as UiDropdown).select(values.find(int(_provider().graphics_field_value(field))))
			Kind.METER:
				var meter: UiSegmentMeter = entry["control"] as UiSegmentMeter
				meter.set_value_silent(_cells_for(field, float(_provider().graphics_field_value(field)), meter))
				meter.queue_redraw()
			Kind.COMBO:
				var tiers: Array[Dictionary] = entry["tiers"] as Array[Dictionary]
				var tier: int = GraphicsPreset.matching_tier(tiers, func(f: StringName) -> Variant: return _provider().graphics_field_value(f))
				(entry["control"] as UiDropdown).select(tier if tier >= 0 else tiers.size())
	_refresh_fixed_fps_enabled()
	_refreshing = false


## The page's own Theme: every column inside (a section's caption/body, a body's rows) is spaced
## `space-3` apart; only the gap between sections is wider (the page column's own separation).
static func _spacing_theme(arcade: ArcadeVisualTuning) -> Theme:
	var page_theme: Theme = Theme.new()
	page_theme.set_constant("separation", "VBoxContainer", arcade.space_3_px)
	return page_theme


## One UiSection (caption header + Body column); returns its Body.
func _add_section(title: String) -> VBoxContainer:
	var section: UiSection = UiSection.new()
	section.title = title
	var body: VBoxContainer = VBoxContainer.new()
	body.name = UiSection.BODY_NAME
	section.add_child(body)
	_fields.add_child(section)
	return body


func _add_row(body: VBoxContainer, label_text: String, control: Control) -> void:
	body.add_child(UiRow.new().setup(label_text, control))
	_controls.append(control)
	# FocusScrollContainer only reveals caption Labels that are siblings of the focused control; a
	# UiSection's caption is in its own header row, so a section's first control reveals it.
	if body.get_child_count() == 1:
		control.focus_entered.connect(_reveal_section.bind(body.get_parent() as UiSection))


func _reveal_section(section: UiSection) -> void:
	ensure_control_visible.call_deferred(section.get_child(0) as Control)


func _build_preset_section(menu_owner: Node) -> void:
	var body: VBoxContainer = _add_section(SECTION_PRESET)
	preset_option = UiDropdown.new()
	preset_option.name = NODE_PRESET_OPTION
	preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for label: String in PRESET_LABELS:
		preset_option.add_item(label)
	preset_option.add_item(CUSTOM_LABEL)
	# Custom is only ever a state (set by editing a control), never something to pick.
	preset_option.set_item_disabled(PRESET_IDS.size(), true)
	_add_row(body, "Graphics preset", preset_option)
	# Keep the %PresetOption lookup the menu and its tests use.
	preset_option.unique_name_in_owner = true
	preset_option.owner = menu_owner
	preset_option.item_selected.connect(pick_preset)


func _build_row(body: VBoxContainer, row: Dictionary) -> void:
	var field: StringName = row["field"] as StringName
	match row["kind"]:
		Kind.TOGGLE:
			var toggle: UiToggle = UiToggle.new()
			toggle.toggled.connect(_on_toggle.bind(field))
			_add_row(body, row["label"] as String, toggle)
			_by_field[field] = {"kind": Kind.TOGGLE, "control": toggle, "row": row}
		Kind.DROPDOWN:
			var dropdown: UiDropdown = _make_dropdown(row["labels"] as Array)
			dropdown.item_selected.connect(_on_dropdown_selected.bind(field))
			_add_row(body, row["label"] as String, dropdown)
			_by_field[field] = {"kind": Kind.DROPDOWN, "control": dropdown, "row": row}
		Kind.METER:
			var meter: UiSegmentMeter = UiSegmentMeter.new()
			var limits: Dictionary = GraphicsPreset.limits_for(field)
			meter.step_count = roundi((float(limits["max"]) - float(limits["min"])) / float(limits["step"]))
			meter.formatter = func(cells: int) -> String: return _format_value(_value_for_cells(field, cells), row["fmt"] as String)
			meter.value_changed.connect(_on_meter_changed.bind(field))
			_add_row(body, row["label"] as String, meter)
			_by_field[field] = {"kind": Kind.METER, "control": meter, "row": row}
		Kind.COMBO:
			var tiers: Array[Dictionary] = _tiers_for(field)
			var combo: UiDropdown = _make_dropdown(row["labels"] as Array)
			combo.add_item(CUSTOM_LABEL)
			# Custom is only ever a state (no tier matches), never something to pick.
			combo.set_item_disabled(tiers.size(), true)
			combo.item_selected.connect(_on_combo_selected.bind(field))
			_add_row(body, row["label"] as String, combo)
			_by_field[field] = {"kind": Kind.COMBO, "control": combo, "row": row, "tiers": tiers}


func _make_dropdown(labels: Array) -> UiDropdown:
	var dropdown: UiDropdown = UiDropdown.new()
	dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for text: String in labels:
		dropdown.add_item(text)
	return dropdown


func _tiers_for(combo: StringName) -> Array[Dictionary]:
	match combo:
		COMBO_SHADOWS:
			return GraphicsPreset.preset_tiers(GraphicsPreset.SHADOW_FIELDS)
		COMBO_ENVIRONMENT:
			return GraphicsPreset.preset_tiers(GraphicsPreset.ENVIRONMENT_FIELDS)
		_:
			return GraphicsPreset.REFLECTION_TIERS


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


func _on_dropdown_selected(index: int, field: StringName) -> void:
	var values: Array = GraphicsPreset.limits_for(field)["values"]
	if index >= 0 and index < values.size():
		_edit(field, values[index])


## A combined row picked tier `index`: every field of that tier is written, then one refresh.
func _on_combo_selected(index: int, combo: StringName) -> void:
	if _refreshing:
		return
	var tiers: Array[Dictionary] = _by_field[combo]["tiers"] as Array[Dictionary]
	if index >= 0 and index < tiers.size():
		var tier: Dictionary = tiers[index]
		for field: StringName in tier:
			_provider().set_graphics_override(field, tier[field])
	refresh_from_settings()


func _on_meter_changed(cells: int, field: StringName) -> void:
	_edit(field, _value_for_cells(field, cells))


func _edit(field: StringName, value: Variant) -> void:
	if _refreshing:
		return
	_provider().set_graphics_override(field, value)
	refresh_from_settings()


## The meter's value for `cells` filled cells of `field`'s min..max range.
static func _value_for_cells(field: StringName, cells: int) -> float:
	var limits: Dictionary = GraphicsPreset.limits_for(field)
	return float(limits["min"]) + float(cells) * float(limits["step"])


static func _cells_for(field: StringName, value: float, meter: UiSegmentMeter) -> int:
	var limits: Dictionary = GraphicsPreset.limits_for(field)
	return clampi(roundi((value - float(limits["min"])) / float(limits["step"])), 0, meter.step_count)


## The fixed-fps meter only matters while the frame cap is "Fixed".
func _refresh_fixed_fps_enabled() -> void:
	if not _by_field.has(FIXED_FPS_FIELD) or not _by_field.has(FRAME_CAP_FIELD):
		return
	var fixed: bool = int(_provider().graphics_field_value(FRAME_CAP_FIELD)) == GraphicsPreset.FrameCap.FIXED
	(_by_field[FIXED_FPS_FIELD]["control"] as UiSegmentMeter).editable = fixed


static func _format_value(value: float, fmt: String) -> String:
	match fmt:
		"fps":
			return "%d" % roundi(value)
		_:
			return "%d%%" % roundi(value * PERCENT_SCALE)
