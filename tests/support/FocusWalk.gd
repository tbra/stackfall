class_name FocusWalk
extends RefCounted
## Gamepad and keyboard reachability for a built Control tree. Follows the engine's own focus
## resolution (Control.find_valid_focus_neighbor, what ui_down and friends use) so a test asserts
## "the loop closes, every stop is live, every live control is a stop" without naming a row, an
## order or a neighbour.

const DEFAULT_CAP: int = 200


## The stops visited from `start` (included, first) by repeatedly moving `side`, until the walk
## returns to `start`, revisits a stop, finds no neighbour, or visits `cap` stops.
static func loop(start: Control, side: Side = SIDE_BOTTOM, cap: int = DEFAULT_CAP) -> Array[Control]:
	var stops: Array[Control] = [start]
	var current: Control = start
	while stops.size() < cap:
		var next: Control = current.find_valid_focus_neighbor(side)
		if next == null or stops.has(next):
			break
		stops.append(next)
		current = next
	return stops


## True when stepping `side` from the last stop of `stops` lands back on `start`.
static func is_closed(stops: Array[Control], start: Control, side: Side = SIDE_BOTTOM) -> bool:
	if stops.is_empty() or stops[0] != start:
		return false
	return stops[stops.size() - 1].find_valid_focus_neighbor(side) == start


## Shown in the tree and not a disabled button: a player can act on it.
static func is_live(control: Control) -> bool:
	return control.is_visible_in_tree() and not (control is BaseButton and (control as BaseButton).disabled)


## Every live control under `root` (root excluded) that takes focus with FOCUS_ALL.
static func live_focusable(root: Control) -> Array[Control]:
	var found: Array[Control] = []
	_collect(root, found)
	return found


static func _collect(node: Node, found: Array[Control]) -> void:
	for child: Node in node.get_children():
		var control: Control = child as Control
		if control != null and control.focus_mode == Control.FOCUS_ALL and is_live(control):
			found.append(control)
		_collect(child, found)
