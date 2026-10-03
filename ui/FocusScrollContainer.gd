class_name FocusScrollContainer
extends ScrollContainer
## Bontago-1pi.47 (owner playtest: "In menus that have scrolling, for example
## controller remapping, navigating with gamepad/arrow keys doesn't update the
## scroll position"). A ScrollContainer that keeps whichever descendant just
## took keyboard/gamepad focus visible -- the shared approach for every menu
## list that can outgrow its panel (ui/OptionsMenu.tscn's Settings page and
## Controls rebind list use it; ui/Lobby.tscn's settings column gets the same
## behaviour from the plain engine property `follow_focus = true`).
##
## DECISION (Bontago-1pi.47): the engine's own `follow_focus` (set here, and
## explicitly in the scene) does the actual scrolling -- its handler listens to
## the viewport's `gui_focus_changed` and calls ensure_control_visible() for any
## descendant, however deeply nested, and works with the custom focus_neighbor
## wiring because it reacts to the focus change, not to how focus got there.
## Plain follow_focus scrolls the *minimum* distance, so walking UP a list
## leaves the focused control flush against the top edge with the section
## caption above it (e.g. "Rotation" over "Rotate left") clipped away. This
## subclass additionally reveals the caption Label(s) that directly precede the
## focused control (or one of its ancestors) in their parent, so a section's
## heading is never hidden while its first row is selected. Mouse-wheel and
## scrollbar scrolling are untouched.


func _init() -> void:
	follow_focus = true


func _enter_tree() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null and not viewport.gui_focus_changed.is_connected(_on_gui_focus_changed):
		viewport.gui_focus_changed.connect(_on_gui_focus_changed)


func _exit_tree() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null and viewport.gui_focus_changed.is_connected(_on_gui_focus_changed):
		viewport.gui_focus_changed.disconnect(_on_gui_focus_changed)


func _on_gui_focus_changed(control: Control) -> void:
	if not follow_focus or control == null or not is_ancestor_of(control):
		return
	if not control.is_visible_in_tree():
		return
	for caption: Control in leading_captions(control):
		ensure_control_visible(caption)
	ensure_control_visible(control)


## The visible Labels that sit immediately before `control`, or before any of its
## ancestors inside this container, in their parents' child order -- the section
## captions a row's own focus should not scroll out of view. Public so tests can
## assert the resolution without driving focus.
func leading_captions(control: Control) -> Array[Control]:
	var captions: Array[Control] = []
	var node: Node = control
	while node != null and node != self:
		var parent: Node = node.get_parent()
		if parent == null:
			break
		var index: int = node.get_index()
		if index > 0:
			var previous: Label = parent.get_child(index - 1) as Label
			if previous != null and previous.is_visible_in_tree():
				captions.append(previous)
		node = parent
	return captions
