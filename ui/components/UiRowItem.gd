class_name UiRowItem
extends RefCounted
## The shared base of every row-capable component (docs/UI_COMPONENTS_PLAN.md section 3.1; owner
## 2026-10-10: "every one of those items should use the same base component"). Godot cannot
## multi-inherit Button and Container, so the base is a contract every component applies to itself
## in _init: one row height (ComponentMetrics.row_height_px), centred vertically, sized to its
## content horizontally unless it is marked `fill`, and tagged with the group [constant GROUP].

enum Kind { BUTTON_SM, ICON, TOGGLE, STEPPER, DROPDOWN, BADGE, METER }

const GROUP: StringName = &"ui_row_item"
const METRICS_PATH: String = "res://config/component_metrics.tres"


static func metrics() -> ComponentMetrics:
	return load(METRICS_PATH) as ComponentMetrics


## Applies the row-item contract to [param control]. [param fill] lets a meter / field / dropdown
## expand to the column; everything else never does.
static func apply(control: Control, kind: Kind, fill: bool = false) -> void:
	var m: ComponentMetrics = metrics()
	var min_size: Vector2 = control.custom_minimum_size
	min_size.y = float(m.row_height_px)
	min_size.x = maxf(min_size.x, min_width_for(kind, m))
	control.custom_minimum_size = min_size
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL if fill else Control.SIZE_SHRINK_BEGIN
	control.add_to_group(GROUP)


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
			return float(metric.dropdown_min_width_px)
		Kind.BADGE:
			return float(metric.badge_min_width_px)
		Kind.METER:
			return float(metric.meter_min_width_px)
	return 0.0
