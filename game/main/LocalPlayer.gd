class_name LocalPlayer
extends Node
## The local player: controller, ghost, HUD, tuning panel; extras attach to it.
## One self-contained subtree dropped into Main as a single instance. It decides
## no rules of its own: every placement still goes through Match.request_place().

@onready var _controller: PlayerController = $PlayerController
@onready var _ghost: GhostPreview = $GhostPreview
@onready var _hud: HUD = $HUDLayer
## The in-game tuning panel (F4). Lives here rather than in Main so it exists on
## every path that builds a LocalPlayer (sandbox, tutorial and the match) with one
## wiring point.
@onready var _tuning_panel: TuningPanel = $TuningPanel
## HUD.gd self-wires to Events in its own _ready(), and PlayerController's
## ghost_path is set inside this scene. Only the camera rig and Field, owned by
## Main outside this subtree, need set_camera_rig()/set_field() below.


## spec 1.5: the mouse only positions the held block, so a real play session
## captures the OS cursor (PlayerController.enable_mouse_capture()). Safe to call
## unconditionally: it is a silent no-op headless.
func _ready() -> void:
	_controller.bind_session(SessionPort.new(Net))
	_controller.enable_mouse_capture()
	_tuning_panel.set_controller(_controller)


## Called once by Main after it builds the shared CameraRig. It can't be wired by
## NodePath in the scene because CameraRig lives outside this subtree.
func set_camera_rig(rig: CameraRig) -> void:
	_controller.set_camera_rig(rig)
	_tuning_panel.set_camera_rig(rig)


## Same hand-off as set_camera_rig(), for the tuning panel's Territory tab and its
## refresh_territory_visuals_live() push (Field also lives outside this subtree).
func set_field(field: Field) -> void:
	_tuning_panel.set_field(field)


## Online there is no turn to take: every slot plays at once and this instance
## drives exactly one of them. PlayerController already resolves its own slot from
## Net when a session is running, so this only pins it explicitly. Offline it is
## never called and Events.turn_changed still decides.
func bind_local_slot(slot_id: int) -> void:
	_controller.set_acting_slot(slot_id)
	# default_ghost_origin() converts PlayerSlot.home_position (disk-local) to
	# a world point: this slot's home flag in world space.
	_controller.set_home_position(_controller.match_context.default_ghost_origin(slot_id))
	# The HUD's per-slot widgets (HELD/NEXT cards, timer ring) follow the local slot
	# from here, not from the first PLAYING-time turn_changed, so the first block
	# issued at countdown start lands in the cards.
	_hud.set_local_slot(slot_id)
	_controller.pull_current_held()


func controller() -> PlayerController:
	return _controller


func ghost() -> GhostPreview:
	return _ghost


func hud() -> HUD:
	return _hud

