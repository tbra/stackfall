class_name UiRowItem
extends RefCounted
## The shared base of every row-capable component. Godot cannot
## multi-inherit Button and Container, so the base is a contract every component applies to itself
## in _init: one row height (ComponentMetrics.row_height_px), centred vertically, sized to its
## content horizontally (every kind hugs by default; only an explicit `fill` expands), and tagged with the group [constant GROUP].

enum Kind { BUTTON_SM, ICON, TOGGLE, STEPPER, DROPDOWN, BADGE, METER }

const GROUP: StringName = &"ui_row_item"
const METRICS_PATH: String = "res://config/ui/component_metrics.tres"


static var _metrics: ComponentMetrics = null


## The shared metrics resource, loaded once (load() per call cost ~0.3 ms per row item).
static func metrics() -> ComponentMetrics:
	if _metrics == null:
		_metrics = load(METRICS_PATH) as ComponentMetrics
		if _metrics != null and not _metrics.changed.is_connected(invalidate_metrics_cache):
			_metrics.changed.connect(invalidate_metrics_cache)
	return _metrics


## Drops the cached resource so the next call reloads it (a `changed` emission, tests, tooling).
static func invalidate_metrics_cache() -> void:
	_metrics = null


## Applies the row-item contract to [param control]. [param fill] lets a meter / field / dropdown
## expand to the column; no kind does by default.
static func apply(control: Control, kind: Kind, fill: bool = false) -> void:
	var m: ComponentMetrics = metrics()
	var min_size: Vector2 = control.custom_minimum_size
	min_size.y = float(m.row_height_px)
	min_size.x = maxf(min_size.x, min_width_for(kind, m))
	control.custom_minimum_size = min_size
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL if fill else Control.SIZE_SHRINK_BEGIN
	control.add_to_group(GROUP)


## The width of the visible block of a square row-item button: the row height less the ledge.
static func square_face_px(m: ComponentMetrics = null) -> float:
	var metric: ComponentMetrics = m if m != null else metrics()
	return float(metric.row_height_px - MenuStyleFactory.arcade_tuning().drop_sm_px)


## The minimum width of a row item of [param kind] (0 = size to content).
static func min_width_for(kind: Kind, m: ComponentMetrics = null) -> float:
	var metric: ComponentMetrics = m if m != null else metrics()
	match kind:
		Kind.BUTTON_SM:
			return float(metric.button_sm_min_width_px)
		Kind.ICON:
			return float(metric.row_height_px)
		Kind.TOGGLE:
			return float(metric.toggle_min_width_px)
		Kind.STEPPER:
			return float(metric.stepper_width_units * metric.row_height_px)
		Kind.DROPDOWN:
			return 0.0  # hugs its widest item
		Kind.BADGE:
			return float(metric.badge_min_width_px)
		Kind.METER:
			return float(metric.meter_min_width_px)
	return 0.0


## The plain cream display-font value label shared by UiStepper and UiCycler.
static func make_value_label() -> Label:
	var label: Label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", MenuStyleFactory.arcade_tuning().cream_color)
	label.add_theme_font_size_override("font_size", metrics().stepper_value_font_px)
	var display: Font = (load("res://ui/theme/stackfall_theme.tres") as Theme).get_font(&"font", &"DisplayLabel")
	if display != null:
		label.add_theme_font_override("font", display)
	return label
