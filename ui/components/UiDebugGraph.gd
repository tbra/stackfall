class_name UiDebugGraph
extends Control
## Rolling graph of N series over a budget line (the top edge, drawn as a hairline). Look B: no plate of its own, the
## hairline in disc_500 and each series a thin polyline in the colour the caller passes. Redraws only while visible.

class Series:
	var values: PackedFloat32Array = PackedFloat32Array()
	var ceiling: float = 1.0
	var color: Color = Color.WHITE

var _series: Array[Series] = []


func _init() -> void:
	custom_minimum_size = Vector2(0.0, float(UiRowItem.metrics().debug_graph_height_px))
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Series `index`: samples, the value at the top edge, and its colour.
func set_series(index: int, values: PackedFloat32Array, ceiling: float, color: Color) -> void:
	while _series.size() <= index:
		_series.append(Series.new())
	var series: Series = _series[index]
	series.values = values
	series.ceiling = ceiling
	series.color = color
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	var metrics: ComponentMetrics = UiRowItem.metrics()
	var line: Color = Color(MenuStyleFactory.arcade_tuning().disc_500_color, metrics.debug_hairline_alpha)
	draw_rect(Rect2(0.0, 0.0, size.x, float(metrics.debug_hairline_px)), line)
	for series: Series in _series:
		var count: int = series.values.size()
		if count < 2 or series.ceiling <= 0.0:
			continue
		var points: PackedVector2Array = PackedVector2Array()
		for i: int in count:
			var level: float = clampf(series.values[i] / series.ceiling, 0.0, 1.0)
			points.append(Vector2(size.x * float(i) / float(count - 1), size.y - level * size.y))
		draw_polyline(points, series.color, metrics.debug_graph_line_px)
