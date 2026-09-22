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
## Bontago-mv0.18: the in-game tuning panel (F4). Self-contained here (like
## _hud above) rather than instanced separately by game/Main.gd, so it exists
## on every path that builds a HotSeat -- the local --hot-seat entry point
## AND the real networked match (game/Main.gd's _build_match_world() uses
## this same scene) -- with one wiring point, instead of two.
@onready var _tuning_panel: TuningPanel = $TuningPanel
## HUD.gd self-wires to Events in its own _ready() ("connects to Events only
## — no node paths out of ui/", docs/M2_PLAN.md), and PlayerController's
## ghost_path is set inside this scene since both are HotSeat's own children.
## Only the camera rig and Field — owned by Main, outside this subtree — need
## the integrator's help; see set_camera_rig()/set_field() below.


## Bontago-mv0.14 (spec 1.5): the original's mouse only ever positions the
## held block, so a real play session hides/captures the OS cursor
## (PlayerController.enable_mouse_capture()) instead of leaving a free system
## cursor with nothing to point at. Safe to call unconditionally: it is a
## silent no-op headless (no window to capture; see godot's own DisplayServer
## behaviour), which is why every unit test that builds a HotSeat this way
## keeps working without a display.
func _ready() -> void:
	_controller.enable_mouse_capture()
	_tuning_panel.set_controller(_controller)


## Called once by the integrator after Main builds the shared CameraRig
## (docs/M2_PLAN.md: "the integrator wires Main.gd/tscn ... instance Field,
## HotSeat.tscn, BlocksContainer, BlockRegistry"). HotSeat can't wire this by
## NodePath at scene-author time because CameraRig lives outside this
## subtree.
func set_camera_rig(rig: CameraRig) -> void:
	_controller.set_camera_rig(rig)
	_tuning_panel.set_camera_rig(rig)


## Bontago-mv0.18: called once by game/Main.gd, the same hand-off as
## set_camera_rig() above, for the tuning panel's Territory tab and its
## refresh_territory_visuals_live() push (Field lives outside this subtree,
## same reason CameraRig does).
func set_field(field: Field) -> void:
	_tuning_panel.set_field(field)


## M3a: online there is no turn to take — every slot plays at once and this
## instance drives exactly one of them (docs/M3a_PLAN.md question 3, and the
## integrator's step 4). PlayerController already resolves its own slot from
## Net when a session is running, so this only exists for the case where the
## integrator wants to pin it explicitly. Offline it is never called and
## Events.turn_changed still decides, so hot-seat is byte-identical to M2.
func bind_local_slot(slot_id: int) -> void:
	_controller.set_acting_slot(slot_id)
	# Bontago-mv0.17 item 4: this is "the controller binds the local slot" the
	# item calls for -- Match.default_ghost_origin() is the existing read-only
	# API that already converts PlayerSlot.home_position (disk-local) to a
	# world point (autoload/Match.gd; named for its other caller, a peer whose
	# timer expired with no cursor ever reported, but it is exactly "this
	# slot's home flag in world space" with no fallback logic of its own).
	_controller.set_home_position(Match.default_ghost_origin(slot_id))


func controller() -> PlayerController:
	return _controller


func ghost() -> GhostPreview:
	return _ghost


func hud() -> HUD:
	return _hud
