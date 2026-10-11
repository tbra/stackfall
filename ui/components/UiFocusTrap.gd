class_name UiFocusTrap
extends RefCounted
## Keeps controller / keyboard focus inside one screen (Bontago-1pi.159.15, N1).
##
## Godot resolves an unset focus_neighbor_* by a spatial search over the WHOLE viewport, so a
## stick or arrow press on a control with no neighbour on that side (a dropdown's left / right)
## jumps into whatever screen is underneath the overlay. [method trap] closes every such gap and
## [method suspend_outside] takes the screens behind out of focus altogether while an overlay is up.


## Every focusable Control at or below [param root], in tree order.
static func focusables(root: Control) -> Array[Control]:
	var found: Array[Control] = []
	_collect(root, found)
	return found


## Makes every focusable at or below [param root] keep focus inside it: a neighbour (side, next,
## previous) that is unset or points outside [param root] is replaced by the control itself
## (sides) or the wrapped tree-order neighbour (next / previous). Neighbours that already point
## inside root are left alone. Call after the screen has wired its own chain.
static func trap(root: Control) -> void:
	var controls: Array[Control] = focusables(root)
	var count: int = controls.size()
	for i: int in range(count):
		var control: Control = controls[i]
		for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			if not _points_inside(control, control.get_focus_neighbor(side), root):
				control.set_focus_neighbor(side, control.get_path_to(control))
		var next: Control = controls[(i + 1) % count]
		var previous: Control = controls[(i - 1 + count) % count]
		if not _points_inside(control, control.focus_next, root):
			control.focus_next = control.get_path_to(next)
		if not _points_inside(control, control.focus_previous, root):
			control.focus_previous = control.get_path_to(previous)


## Sets every focusable under [param outside] that is not under [param root] to FOCUS_NONE (and
## releases focus held there). Returns a Callable that restores each one's previous focus mode.
static func suspend_outside(root: Control, outside: Node) -> Callable:
	var saved: Array = []
	var stack: Array[Node] = [outside]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node == root:
			continue
		var control: Control = node as Control
		if control != null and control.focus_mode != Control.FOCUS_NONE:
			saved.append([control, control.focus_mode])
			if control.has_focus():
				control.release_focus()
			control.focus_mode = Control.FOCUS_NONE
		stack.append_array(node.get_children())
	return _restore.bind(saved)


static func _restore(saved: Array) -> void:
	for entry: Array in saved:
		var control: Control = entry[0] as Control
		if is_instance_valid(control):
			control.focus_mode = entry[1] as Control.FocusMode


static func _collect(node: Node, found: Array[Control]) -> void:
	var control: Control = node as Control
	if control != null and control.focus_mode != Control.FOCUS_NONE:
		found.append(control)
	for child: Node in node.get_children():
		_collect(child, found)


static func _points_inside(control: Control, path: NodePath, root: Control) -> bool:
	if path.is_empty():
		return false
	var target: Node = control.get_node_or_null(path)
	return target != null and (target == root or root.is_ancestor_of(target))
