class_name PoseOverlay
extends CanvasLayer
## Pose panel, in every build. `pose_overlay_toggle` (F2, gamepad Back + D-pad left) shows or hides the
## world pose of the held block, the camera and the disc tilt, refreshed every frame while shown.
## Reads only, never writes game state. The parent hands in `camera`, `field` and `match_context`
## before add_child; the held block comes from `match_context.local_held()`, read only while shown.
## Built on UiDebugPanel.

const NO_VALUE: String = "-"
const RAD_TO_DEG_FACTOR: float = 180.0 / PI
const HEADING: String = "POSE"
const SECTION_ID: StringName = &"pose"
const SECTION_TITLE: String = "World pose"
const TILT_LINE: String = "disc tilt %s deg about %s"

var config: DebugConfig = null
var camera: Camera3D = null
var field: Field = null
var match_context: MatchContext = null

var _panel: UiDebugPanel = null


func _ready() -> void:
	if config == null:
		config = DebugConfig.new()
	_panel = UiDebugPanel.new()
	_panel.heading = HEADING
	_panel.toggle_action = &"pose_overlay_toggle"
	_panel.modifier_action = &"camera_snap_home"
	_panel.visible = false
	add_child(_panel)
	_place()


func is_shown() -> bool:
	return _panel.visible


func set_shown(shown: bool) -> void:
	_panel.visible = shown
	if shown:
		refresh()
		_place()
	else:
		DebugOverlayLayout.report_stack_height(DebugOverlayLayout.Stack.POSE, 0.0)


func _exit_tree() -> void:
	DebugOverlayLayout.report_stack_height(DebugOverlayLayout.Stack.POSE, 0.0)


func _process(_delta: float) -> void:
	if not is_shown():
		return
	refresh()
	_place()


## Bottom-right stack, right above the minimap (ui/debug/DebugOverlayLayout.gd); follows the HUD scale.
func _place() -> void:
	DebugOverlayLayout.report_stack_height(DebugOverlayLayout.Stack.POSE, _panel.size.y)
	DebugOverlayLayout.place_stack(_panel, DebugOverlayLayout.Stack.POSE, config)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pose_overlay_toggle"):
		return
	# tools/bootstrap_project.gd's DECISION: the pad half only counts while Back is held.
	if event is InputEventJoypadButton and not Input.is_action_pressed(&"camera_snap_home"):
		return
	set_shown(not is_shown())
	get_viewport().set_input_as_handled()


## Rewrites the rows from the live nodes. Does nothing while hidden (no match-context read).
func refresh() -> void:
	if not is_shown():
		return
	var decimals: int = config.pose_decimals
	var rows: Array[DebugRow] = []
	var held: LocalHeldView = match_context.local_held() if match_context != null else null
	if held == null or held.shape == null:
		rows.append(DebugRow.pair("held", NO_VALUE))
	else:
		rows.append(DebugRow.pair("held pos", _vec_text(held.origin, decimals)))
		rows.append(DebugRow.pair("held rot deg", _vec_text(_held_basis(held).get_euler() * RAD_TO_DEG_FACTOR, decimals)))
	if is_instance_valid(camera):
		rows.append(DebugRow.pair("camera pos", _vec_text(camera.global_position, decimals)))
		rows.append(DebugRow.pair("camera rot deg",
			_vec_text(camera.global_basis.orthonormalized().get_euler() * RAD_TO_DEG_FACTOR, decimals)))
	else:
		rows.append(DebugRow.pair("camera", NO_VALUE))
	rows.append(DebugRow.pair("disc", NO_VALUE) if not is_instance_valid(field) else _single(tilt_text(field.global_basis, decimals)))
	_panel.set_section(SECTION_ID, SECTION_TITLE, rows)


static func _single(text: String) -> DebugRow:
	var row: DebugRow = DebugRow.new()
	row.cells = PackedStringArray([text])
	return row


## Pure: the held block's world basis, composed the way GhostPreview does.
static func _held_basis(held: LocalHeldView) -> Basis:
	return Basis(held.free_quat) * BlockOrientations.get_basis(held.orientation_index)


## Pure: angle and axis of a basis. An untilted disc has no axis, so it shows up.
static func tilt_text(basis: Basis, decimals: int) -> String:
	var tilt: Quaternion = basis.orthonormalized().get_rotation_quaternion()
	var angle_deg: float = rad_to_deg(tilt.get_angle())
	var axis: Vector3 = tilt.get_axis() if angle_deg > 0.0 else Vector3.UP
	return TILT_LINE % [_number_text(angle_deg, decimals), _vec_text(axis, decimals)]


## Fixed decimals; "+ 0.0" turns a negative zero into a plain one.
static func _number_text(value: float, decimals: int) -> String:
	return "%.*f" % [decimals, value + 0.0]


static func _vec_text(v: Vector3, decimals: int) -> String:
	return "(%s, %s, %s)" % [_number_text(v.x, decimals), _number_text(v.y, decimals), _number_text(v.z, decimals)]
