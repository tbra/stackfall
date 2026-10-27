class_name PoseOverlay
extends CanvasLayer
## Debug-only pose panel. `pose_overlay_toggle` (F2, gamepad Back + D-pad left) shows or hides the
## world pose of the held block, the camera and the disc tilt, refreshed every frame while shown.
## Gated by game/debug/DebugMode.gd like F1; reads only, never writes game state.
## The parent hands in `camera` and `field` before add_child; the held block comes from the
## published MatchContext.current().local_held().

const NO_VALUE: String = "-"
const RAD_TO_DEG_FACTOR: float = 180.0 / PI
const HELD_LINE: String = "held   pos %s  rot %s deg"
const CAMERA_LINE: String = "camera pos %s  rot %s deg"
const TILT_LINE: String = "disc tilt %s deg about %s"

var config: DebugConfig = null
var camera: Camera3D = null
var field: Field = null

@onready var _panel: PanelContainer = %Panel
@onready var _held_label: Label = %HeldLabel
@onready var _camera_label: Label = %CameraLabel
@onready var _tilt_label: Label = %TiltLabel


func _ready() -> void:
	if config == null:
		config = DebugConfig.new()
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = config.overlay_background_color()
	style.set_content_margin_all(float(arcade.space_2_px))
	style.set_corner_radius_all(arcade.radius_chip_px)
	_panel.add_theme_stylebox_override(&"panel", style)
	# Left edge, mid-height: F1 owns the top-right, F9 the top-left, the hint bar the bottom.
	_panel.offset_left = config.overlay_margin.x
	for label: Label in [_held_label, _camera_label, _tilt_label]:
		label.add_theme_color_override(&"font_color", config.overlay_text_color())


func is_shown() -> bool:
	return _panel.visible


func set_shown(shown: bool) -> void:
	_panel.visible = shown
	if shown:
		refresh()


func _process(_delta: float) -> void:
	if not is_shown():
		return
	if not DebugMode.is_enabled():
		set_shown(false)
		return
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not DebugMode.is_enabled() or not event.is_action_pressed(&"pose_overlay_toggle"):
		return
	# tools/bootstrap_project.gd's DECISION: the pad half only counts while Back is held.
	if event is InputEventJoypadButton and not Input.is_action_pressed(&"camera_snap_home"):
		return
	set_shown(not is_shown())
	get_viewport().set_input_as_handled()


## Rewrites the three lines from the live nodes.
func refresh() -> void:
	var decimals: int = config.pose_decimals
	var held: LocalHeldView = MatchContext.current().local_held()
	_held_label.text = NO_VALUE if held.shape == null else HELD_LINE % [
		vec_text(held.origin, decimals), vec_text(held_basis(held).get_euler() * RAD_TO_DEG_FACTOR, decimals)]
	var cam: Node3D = camera if is_instance_valid(camera) else null
	_camera_label.text = NO_VALUE if cam == null else CAMERA_LINE % [
		vec_text(cam.global_position, decimals),
		vec_text(cam.global_basis.orthonormalized().get_euler() * RAD_TO_DEG_FACTOR, decimals)]
	_tilt_label.text = NO_VALUE if not is_instance_valid(field) else tilt_text(field.global_basis, decimals)


## Pure: the held block's world basis, composed the way GhostPreview does.
static func held_basis(held: LocalHeldView) -> Basis:
	return Basis(held.free_quat) * BlockOrientations.get_basis(held.orientation_index)


## Pure: angle and axis of a basis. An untilted disc has no axis, so it shows up.
static func tilt_text(basis: Basis, decimals: int) -> String:
	var tilt: Quaternion = basis.orthonormalized().get_rotation_quaternion()
	var angle_deg: float = rad_to_deg(tilt.get_angle())
	var axis: Vector3 = tilt.get_axis() if angle_deg > 0.0 else Vector3.UP
	return TILT_LINE % [number_text(angle_deg, decimals), vec_text(axis, decimals)]


## Fixed decimals; "+ 0.0" turns a negative zero into a plain one.
static func number_text(value: float, decimals: int) -> String:
	return "%.*f" % [decimals, value + 0.0]


static func vec_text(v: Vector3, decimals: int) -> String:
	return "(%s, %s, %s)" % [number_text(v.x, decimals), number_text(v.y, decimals), number_text(v.z, decimals)]
