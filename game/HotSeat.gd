class_name HotSeat
extends Node
## Self-contained hot-seat subtree (docs/M2_PLAN.md P4, owner decision 1):
## one PlayerController + GhostPreview + HUD, meant to be dropped into
## Main.tscn as a single instance. It decides no rules of its own — every
## placement still goes through Match.request_place() even though every slot
## is local (spec 3.4). This is the debug/test scaffold for M2's "two
## players take turns on one PC" acceptance criterion, not a shipped menu
## mode: real hot-seat vs. real-time play is MatchConfig.hot_seat, decided at
## the lobby, and M3 replaces one-mouse hot-seat with one controller per peer.

@onready var _controller: PlayerController = $PlayerController
@onready var _ghost: GhostPreview = $GhostPreview
@onready var _hud: HUD = $HUDLayer
## HUD.gd self-wires to Events in its own _ready() ("connects to Events only
## — no node paths out of ui/", docs/M2_PLAN.md), and PlayerController's
## ghost_path is set inside this scene since both are HotSeat's own children.
## Only the camera rig — owned by Main, outside this subtree — needs the
## integrator's help; see set_camera_rig() below.


## Called once by the integrator after Main builds the shared CameraRig
## (docs/M2_PLAN.md: "the integrator wires Main.gd/tscn ... instance Field,
## HotSeat.tscn, BlocksContainer, BlockRegistry"). HotSeat can't wire this by
## NodePath at scene-author time because CameraRig lives outside this
## subtree.
func set_camera_rig(rig: CameraRig) -> void:
	_controller.set_camera_rig(rig)


## M3a: online there is no turn to take — every slot plays at once and this
## instance drives exactly one of them (docs/M3a_PLAN.md question 3, and the
## integrator's step 4). PlayerController already resolves its own slot from
## Net when a session is running, so this only exists for the case where the
## integrator wants to pin it explicitly. Offline it is never called and
## Events.turn_changed still decides, so hot-seat is byte-identical to M2.
func bind_local_slot(slot_id: int) -> void:
	_controller.set_acting_slot(slot_id)


func controller() -> PlayerController:
	return _controller


func ghost() -> GhostPreview:
	return _ghost


func hud() -> HUD:
	return _hud
