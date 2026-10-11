class_name UiSpatialFocus
extends RefCounted
## Pure spatial focus wiring from on-screen rects (Bontago-1pi.159.15, N1).
##
## [method wire] gives every control left / right / up / down neighbours chosen by where the
## controls are drawn, so a screen needs no hand-authored chain. The result never leaves the
## given set: with no control in a direction the press wraps ([param loop]) or stays put.

## Off-axis distance counts this many times the on-axis distance, so "right" prefers the control
## level with this one over a nearer one that is far above or below.
const CROSS_AXIS_WEIGHT: float = 2.0


static func wire(controls: Array[Control], loop: bool) -> void:
	for control: Control in controls:
		if control == null:
			continue
		for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			var target: Control = _pick(control, controls, side, loop)
			control.set_focus_neighbor(side, control.get_path_to(target))


## The control whose rect intersects [param rect] and whose centre is nearest [param from]
## (global coordinates), or null.
static func nearest_in_rect(controls: Array[Control], rect: Rect2, from: Vector2) -> Control:
	var best: Control = null
	var best_distance: float = INF
	for control: Control in controls:
		if control == null or not rect.intersects(control.get_global_rect()):
			continue
		var distance: float = _center(control).distance_squared_to(from)
		if distance < best_distance:
			best_distance = distance
			best = control
	return best


static func _pick(from: Control, controls: Array[Control], side: Side, loop: bool) -> Control:
	var axis: Vector2 = _axis(side)
	var origin: Vector2 = _center(from)
	var best: Control = null
	var best_score: float = INF
	var wrap: Control = null
	var wrap_score: float = INF
	for other: Control in controls:
		if other == null or other == from:
			continue
		var delta: Vector2 = _center(other) - origin
		var along: float = delta.dot(axis)
		var across: float = absf(delta.cross(axis))
		if along > 0.0:
			var score: float = along + across * CROSS_AXIS_WEIGHT
			if score < best_score:
				best_score = score
				best = other
		else:
			# Wrap target: furthest along the opposite direction, level with this control.
			var wrap_rank: float = across * CROSS_AXIS_WEIGHT + along
			if wrap_rank < wrap_score:
				wrap_score = wrap_rank
				wrap = other
	if best != null:
		return best
	if loop and wrap != null:
		return wrap
	return from


static func _axis(side: Side) -> Vector2:
	match side:
		SIDE_LEFT:
			return Vector2.LEFT
		SIDE_RIGHT:
			return Vector2.RIGHT
		SIDE_TOP:
			return Vector2.UP
	return Vector2.DOWN


static func _center(control: Control) -> Vector2:
	return control.get_global_rect().get_center()
