class_name GiftDemo
extends Node
## Manual gift test scene (Bontago-mp0.25).
## Launch: godot --path . res://tools/gift_demo.tscn
## Three offline seats stay idle while slot 0 uses normal sandbox placement.
## The arrow keys replace the current held gift; Glue intentionally receives
## ordinary block carriers for its charged follow-up drops.

const PLAYER_COUNT: int = 4
const HUMAN_SLOT: int = 0
const GLUE_ID: StringName = &"glue"
const SETUP_BLOCK_HEIGHT_M: float = 5.0

var _main: Node3D = null
var _sandbox: Sandbox = null
var _field: Field = null
var _roster: Array[SpecialDef] = []
var _selected_index: int = 0
var _generation: int = 0
var _demo_ready: bool = false
var _status: Label = null


func _ready() -> void:
	_build_panel()
	_roster = SpecialDef.load_all_specials()
	if _roster.is_empty():
		_status.text = "No gift definitions installed."
		return
	_main = (load("res://game/Main.tscn") as PackedScene).instantiate() as Node3D
	var sandbox_settings: SandboxConfig = (_main.get("sandbox_config") as SandboxConfig).duplicate(true) as SandboxConfig
	sandbox_settings.default_player_count = PLAYER_COUNT
	_main.set("sandbox_config", sandbox_settings)
	var match_settings: MatchConfig = (_main.get("match_config") as MatchConfig).duplicate(true) as MatchConfig
	match_settings.special_frequency = 0 # Demo selects gifts; no random crates.
	_main.set("match_config", match_settings)
	add_child(_main)
	# Bontago-1pi.34: the sandbox's pause menu "Leave match" goes back to the
	# real main menu scene (Main's own handler would only show a nested menu
	# under this demo's panel). Esc is that pause menu here.
	var pause: PauseMenu = _main.get("_pause_menu") as PauseMenu
	if pause != null:
		pause.leave_match_requested.connect(_on_leave_requested)
	_main.call("start_sandbox_from_menu")
	_sandbox = _main.get("_sandbox") as Sandbox
	_field = _main.get("_field") as Field
	_sandbox.controller().input_enabled = false
	_sandbox.ghost().visible = false
	Events.feed_block_issued.connect(_on_feed_block_issued)
	_start_population()


func _on_leave_requested() -> void:
	DemoReturn.return_to_menu(get_tree())


func _build_panel() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -430.0
	panel.offset_right = -16.0
	panel.offset_top = 16.0
	panel.offset_bottom = 132.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var layout: VBoxContainer = VBoxContainer.new()
	margin.add_child(layout)
	var title: Label = Label.new()
	title.text = "Gift demo ? 3 idle opponents"
	layout.add_child(title)
	_status = Label.new()
	_status.text = "Preparing arena?"
	layout.add_child(_status)
	var controls: HBoxContainer = HBoxContainer.new()
	layout.add_child(controls)
	var help: Label = Label.new()
	help.text = "? / ? gift   ?   F6 cursor   ?   R reset"
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(help)
	var reset_button: Button = Button.new()
	reset_button.name = &"ResetButton"
	reset_button.text = "Reset"
	reset_button.pressed.connect(reset_demo)
	controls.add_child(reset_button)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.is_action("gift_demo_cursor_toggle"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action("gift_demo_reset"):
		reset_demo()
		get_viewport().set_input_as_handled()
	elif _demo_ready and event.is_action("gift_demo_cycle_prev"):
		cycle_gift(-1)
		get_viewport().set_input_as_handled()
	elif _demo_ready and event.is_action("gift_demo_cycle_next"):
		cycle_gift(1)
		get_viewport().set_input_as_handled()


func cycle_gift(direction: int) -> void:
	if not _demo_ready or _roster.is_empty() or direction == 0:
		return
	_selected_index = posmod(_selected_index + direction, _roster.size())
	_install_selected_gift()


func reset_demo() -> void:
	if _sandbox == null or Match.config == null:
		return
	_generation += 1
	_demo_ready = false
	_status.text = "Resetting arena?"
	_sandbox.controller().input_enabled = false
	_sandbox.ghost().visible = false
	_sandbox._reset_field()
	_selected_index = 0
	_start_population()


func _start_population() -> void:
	var generation: int = _generation
	_populate_after_countdown(generation)


func _populate_after_countdown(generation: int) -> void:
	while Match.state() != Match.State.PLAYING:
		if generation != _generation or not is_inside_tree():
			return
		await get_tree().process_frame
	if generation != _generation:
		return
	# These are ordinary accepted placements by each idle opponent. Their
	# blocks are registered and can interact with thrown gifts normally.
	for slot_id: int in range(1, PLAYER_COUNT):
		var home: Vector2 = Match.slot(slot_id).home_position
		var origin: Vector3 = _field.to_global(Vector3(home.x, SETUP_BLOCK_HEIGHT_M, home.y))
		var result: StringName = Match.request_place(slot_id, origin, 0, Quaternion.IDENTITY, false)
		if result != PlacementRules.REASON_OK:
			push_warning("GiftDemo: pre-place for slot %d refused: %s" % [slot_id, result])
	_demo_ready = true
	_install_selected_gift()
	for _frame: int in 20:
		await get_tree().physics_frame
	if generation != _generation:
		return
	_sandbox.controller().input_enabled = true
	_sandbox.ghost().visible = true
	_update_status()
	print("GIFT_DEMO_READY players=%d preplaced=%d gift=%s" % [Match.slot_count(), Match.blocks_parent().get_child_count(), _roster[_selected_index].id])


func _clear_pending_gift() -> void:
	# Demo-only current-piece replacement; no gameplay API mutates held pieces.
	var queues: Array = Match._gifts._pending_queues
	if queues.size() > HUMAN_SLOT:
		(queues[HUMAN_SLOT] as Array).clear()
	Match._feed._next_gift_shapes.erase(HUMAN_SLOT)


func _clear_glue_charges() -> void:
	if Match.glue_drops_left(HUMAN_SLOT) <= 0:
		return
	Match._gifts._glue_drops.erase(HUMAN_SLOT)
	Match._gifts._publish_glue_charges(HUMAN_SLOT)


func _install_selected_gift() -> void:
	if not _demo_ready:
		return
	var special_id: StringName = _roster[_selected_index].id
	_clear_glue_charges()
	if special_id == GLUE_ID:
		_clear_pending_gift()
	if not Match.debug_queue_special(HUMAN_SLOT, special_id):
		push_warning("GiftDemo: could not queue %s" % special_id)
		return
	# The sandbox's initial ordinary piece is discarded. All later pieces
	# still flow through MatchFeed after a normal place or throw.
	Match._feed._issue_next_block(HUMAN_SLOT)
	_update_status()


func _on_feed_block_issued(slot_id: int, _shape_id: StringName, _next_shape_id: StringName) -> void:
	if not _demo_ready or slot_id != HUMAN_SLOT:
		return
	var special_id: StringName = _roster[_selected_index].id
	if special_id == GLUE_ID:
		if Match.glue_drops_left(HUMAN_SLOT) == 0:
			Match.debug_queue_special(HUMAN_SLOT, GLUE_ID)
	else:
		Match.debug_queue_special(HUMAN_SLOT, special_id)
	_update_status()


func _update_status() -> void:
	if not _demo_ready:
		return
	var id: String = String(_roster[_selected_index].id)
	var display: String = id.replace("_", " ").capitalize()
	var detail: String = "  ?  %d charged block drops" % Match.glue_drops_left(HUMAN_SLOT) if id == "glue" else ""
	_status.text = "%d / %d   %s%s" % [_selected_index + 1, _roster.size(), display, detail]
