class_name UiHelpLine
extends MarginContainer
## The design system's help line (Bontago-1pi.159.35; owner 2026-10-12 "explanation of options next to
## them when unclear ... instead of tooltips"): one body-text line per settings panel that explains
## the option the player is on. Rows are tagged with a key ([method tag]); the sentence lives in
## config/option_help_table.tres (OptionHelpTable). The line shows the hovered row's text, else the
## focused row's, so mouse hover, keyboard focus and gamepad focus all work; a row with no entry
## (self-explanatory) leaves the line empty. A cycler / dropdown row shows the per-item entry
## "<key>/<index>" of the item currently selected when the table has one.
##
## The line keeps its reserved height (OptionHelpTable.reserved_lines) even while empty, so showing
## or clearing a hint never moves the panel's rows. It only reacts to controls under [member scope].

const HELP_KEY_META: StringName = &"help_key"

## Only hovered / focused controls inside this node (the panel's settings) are explained.
var scope: Control = null
## Overrides the hovered-control lookup (tests; a synthetic hover).
var hover_source: Callable = Callable()
var table: OptionHelpTable = null
var label: UiText = null


## Tags [param node] (a row, or a lone control) with the help key it is explained under.
static func tag(node: Node, key: String) -> void:
	node.set_meta(HELP_KEY_META, key)


static func key_of(node: Node) -> String:
	return str(node.get_meta(HELP_KEY_META, ""))


func _init() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	# Separation from the rows above (Bontago-1pi.159.44): a top rule plus one space-2 step of air.
	add_theme_constant_override("margin_top", arcade.space_2_px + arcade.well_border_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	label = UiText.make(UiText.Role.BODY)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(label)


func _ready() -> void:
	if table == null:
		table = OptionHelpTable.shared()
	# DECISION (Bontago-1pi.159.35): reserve the height a full text of reserved_lines lines really takes
	# (line spacing included), measured once. N * get_line_height() was a few px short, so the first
	# hint grew the line after focus-follow had positioned the settings scroll and clipped the last row.
	var probe: PackedStringArray = PackedStringArray()
	for _i: int in table.reserved_lines:
		probe.append("Ag")
	label.text = "\n".join(probe)
	label.custom_minimum_size.y = maxf(float(table.reserved_lines) * label.get_line_height(), label.get_combined_minimum_size().y)
	label.text = ""


## The separating rule on the top edge (disc-400, the dividers colour).
func _draw() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	draw_rect(Rect2(0.0, 0.0, size.x, float(arcade.well_border_px)), arcade.disc_400_color)


## Explains controls under [param root] (default: this line's parent).
func bind(root: Control) -> void:
	scope = root
	refresh()


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		refresh()


## Recomputes the text from the current hover / focus.
func refresh() -> void:
	var shown: String = resolve_text()
	if label.text != shown:
		label.text = shown


## The hovered row's text, else the focused row's, else "".
func resolve_text() -> String:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return ""
	var hovered: Control = hover_source.call() as Control if hover_source.is_valid() else viewport.gui_get_hovered_control()
	var shown: String = text_for_control(hovered)
	if shown.is_empty():
		shown = text_for_control(viewport.gui_get_focus_owner())
	return shown


## The text of the nearest tagged ancestor-or-self of [param control] inside [member scope].
func text_for_control(control: Control) -> String:
	if control == null or scope == null or not is_instance_valid(control):
		return ""
	if control != scope and not scope.is_ancestor_of(control):
		return ""
	var tables: OptionHelpTable = table if table != null else OptionHelpTable.shared()
	var node: Node = control
	while node != null:
		var key: String = key_of(node)
		if not key.is_empty():
			var shown: String = tables.text_for(key, selected_item_of(node))
			if not shown.is_empty():
				return shown
		if node == scope:
			break
		node = node.get_parent()
	return ""


## The selected item of the first cycler / dropdown in [param node]'s subtree (or itself); -1 when none.
static func selected_item_of(node: Node) -> int:
	if node is UiCycler:
		return (node as UiCycler).selected()
	if node is UiDropdown:
		return (node as UiDropdown).selected
	for child: Node in node.get_children():
		var found: int = selected_item_of(child)
		if found >= 0:
			return found
	return -1
