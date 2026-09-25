class_name Tutorial
extends Node
## docs/M6_PLAN.md package B3 (spec 2.7 "Tutorial"): a single-player, offline
## match built the same way game/Sandbox.gd/game/HotSeat.gd already are (one
## PlayerController + GhostPreview + HUD subtree, wired the same way, driving
## the one slot config.player_count = 1 gives it -- game/Main.gd's own
## start_tutorial_from_menu()), plus a five-step scripted sequence
## (config/TutorialConfig.gd) that teaches placing, rotating, territory,
## specials/throwing and the camera in order.
##
## Does not know about game/Main.gd (the same "no deep node paths"/decoupling
## convention ui/MainMenu.gd's own header describes for sandbox_requested):
## it only ever emits `finished`, once, when the last step completes or the
## player cancels (ui_cancel) -- game/Main.gd's start_tutorial_from_menu() is
## the one thing that adds this node, connects to that signal, and frees it
## again.
##
## Each step's own completion condition is checked only while that step is
## the *current* one (`_current_step()`), so an event that would complete a
## later step firing early (nothing does this today, but Events.block_placed/
## special_consumed/territory_share_changed are global bus signals, not
## scoped to "the step that is listening") can never skip or repeat a step --
## see docs/M6_PLAN.md package B3's own test list.

signal finished

@export var tutorial_config: TutorialConfig = preload("res://config/tutorial_config.tres")

@onready var _controller: PlayerController = $PlayerController
@onready var _ghost: GhostPreview = $GhostPreview
@onready var _hud: HUD = $HUDLayer
@onready var _prompt_label: Label = %PromptLabel

## -1 before the first _begin_step() call (never observed once _ready() has
## run); otherwise an index into tutorial_config.steps.
var _step_index: int = -1
## True from the moment _end_tutorial() has run once (step 5 completing, or
## ui_cancel) -- guards _process()/every Events handler below so a second
## trigger (there should never be one, but see this class's own doc comment
## on why each handler is defensive) can never call Match.abort_match() or
## emit `finished` twice.
var _finished: bool = false

## Step "rotating"'s poll baseline: GhostPreview.orientation_index at the
## moment that step began (config/TutorialConfig.gd's own plan doc: "no
## Events signal exists for a purely local ghost manipulation -- rotation
## never reaches the host until release").
var _rotation_baseline: int = 0

## Step "camera"'s cumulative hold, seconds of camera_orbit/camera_pan_*
## observed while that step is active. Never decays on release (this class's
## own DECISION below) -- a tester need not hold one single continuous input.
var _camera_hold_elapsed_s: float = 0.0

## tools/bootstrap_project.gd's own camera actions (both keyboard and
## gamepad-bound there already -- CLAUDE.md's "every action needs both" is
## satisfied at the Input Map, not by anything in this file).
const CAMERA_ACTIONS: Array[StringName] = [
	&"camera_orbit", &"camera_pan_left", &"camera_pan_right", &"camera_pan_forward", &"camera_pan_back",
]

## config/TutorialConfig.gd's own Step.completion_signal values this class
## understands. Kept as constants here (not on TutorialConfig, which is pure
## data) so a step's .tres entry and the code path that answers it can never
## drift under a typo -- an unrecognized completion_signal simply never
## matches any of these and that step never completes, rather than silently
## treating a typo as "always complete".
const SIGNAL_BLOCK_PLACED: StringName = &"block_placed"
const SIGNAL_ORIENTATION_CHANGED: StringName = &"orientation_changed"
const SIGNAL_TERRITORY_CLAIMED: StringName = &"territory_claimed"
const SIGNAL_SPECIAL_CONSUMED: StringName = &"special_consumed"
const SIGNAL_CAMERA_MOVED: StringName = &"camera_moved"

## game/Main.gd's own _build_tutorial_config() always sets
## config.player_count = 1 -- there is only ever one tutorial participant, so
## every Match call below that needs a slot id uses this rather than a second
## "which slot is this" field to drift out of step with it.
const TUTORIAL_SLOT: int = 0


func _ready() -> void:
	Events.turn_changed.connect(_on_turn_changed)
	Events.block_placed.connect(_on_block_placed)
	Events.territory_share_changed.connect(_on_territory_share_changed)
	Events.special_consumed.connect(_on_special_consumed)
	# Bontago-mv0.14 (spec 1.5): same reasoning as HotSeat.gd/Sandbox.gd's own
	# _ready() -- a silent no-op headless, so every test that builds this
	# scene without a display keeps working.
	_controller.enable_mouse_capture()
	_begin_step(0)


## Called once by game/Main.gd, the same hand-off as HotSeat.set_camera_rig()/
## Sandbox.set_camera_rig() -- CameraRig lives outside this subtree.
func set_camera_rig(rig: CameraRig) -> void:
	_controller.set_camera_rig(rig)


func controller() -> PlayerController:
	return _controller


func ghost() -> GhostPreview:
	return _ghost


func hud() -> HUD:
	return _hud


## The step currently shown/checked, for a test to assert against without
## reaching into `tutorial_config.steps` and `_step_index` separately.
func current_step_id() -> StringName:
	var step: TutorialStep = _current_step()
	return step.id if step != null else &""


func _process(delta: float) -> void:
	var step: TutorialStep = _current_step()
	if step == null:
		return
	if step.completion_signal == SIGNAL_ORIENTATION_CHANGED:
		if _ghost.orientation_index != _rotation_baseline:
			_advance()
	elif step.completion_signal == SIGNAL_CAMERA_MOVED:
		if _any_camera_action_held():
			_camera_hold_elapsed_s += delta
			if _camera_hold_elapsed_s >= tutorial_config.camera_hold_seconds:
				_advance()


## ui_cancel (Escape / gamepad B -- Godot's own built-in UI action, already
## bound on both devices by default; CLAUDE.md's "never raw keycodes" is why
## this is the one action this file reads directly, rather than adding a new
## project-specific one for a single Esc-to-quit case).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_end_tutorial()
		get_viewport().set_input_as_handled()


func _any_camera_action_held() -> bool:
	for action: StringName in CAMERA_ACTIONS:
		if Input.is_action_pressed(action):
			return true
	return false


func _current_step() -> TutorialStep:
	if _finished or _step_index < 0 or _step_index >= tutorial_config.steps.size():
		return null
	return tutorial_config.steps[_step_index]


func _begin_step(index: int) -> void:
	_step_index = index
	var step: TutorialStep = tutorial_config.steps[index]
	_prompt_label.text = step.prompt_text
	if step.completion_signal == SIGNAL_ORIENTATION_CHANGED:
		_rotation_baseline = _ghost.orientation_index
	elif step.completion_signal == SIGNAL_CAMERA_MOVED:
		_camera_hold_elapsed_s = 0.0
	elif step.completion_signal == SIGNAL_SPECIAL_CONSUMED:
		# config.sandbox = true (game/Main.gd's _build_tutorial_config()) is
		# what lets this through MatchGifts.debug_queue_special()'s own gate --
		# see game/Sandbox.gd's matching F9 seam for the same contract.
		Match.debug_queue_special(TUTORIAL_SLOT, tutorial_config.demo_special_id)


## Every completion handler below funnels here: advances exactly once per
## call, and step 5 completing ends the tutorial the same way ui_cancel does
## (docs/M6_PLAN.md package B3: "step 5 completion ends the tutorial").
func _advance() -> void:
	if _step_index + 1 >= tutorial_config.steps.size():
		_end_tutorial()
		return
	_begin_step(_step_index + 1)


## The one place this class ends the match: step 5 completing (_advance()
## above) and ui_cancel (_unhandled_input() above) both reach this, so
## Match.abort_match() and `finished` can never be skipped for one path or
## double-fired for the other. game/Main.gd's start_tutorial_from_menu() is
## the one thing connected to `finished`; it frees this node and shows the
## Main Menu again once this returns.
func _end_tutorial() -> void:
	if _finished:
		return
	_finished = true
	Match.abort_match()
	finished.emit()


func _on_turn_changed(slot_id: int) -> void:
	# Bontago-mv0.17 item 4 / game/Sandbox.gd's own matching _on_turn_changed()
	# doc comment: the one-time "a controller is now bound to a real slot"
	# moment, so the first frame looks from the tutorial slot's home flag
	# toward the disk centre instead of the generic yaw = 0 default.
	_controller.set_home_position(Match.default_ghost_origin(slot_id))


func _on_block_placed(_block: RigidBody3D, _shape_id: StringName) -> void:
	var step: TutorialStep = _current_step()
	if step != null and step.completion_signal == SIGNAL_BLOCK_PLACED:
		_advance()


func _on_territory_share_changed(shares: PackedFloat32Array) -> void:
	var step: TutorialStep = _current_step()
	if step == null or step.completion_signal != SIGNAL_TERRITORY_CLAIMED:
		return
	var team_id: int = Match.team_of(TUTORIAL_SLOT)
	if team_id >= 0 and team_id < shares.size() and shares[team_id] > 0.0:
		_advance()


func _on_special_consumed(slot_id: int, _special_id: StringName) -> void:
	if slot_id != TUTORIAL_SLOT:
		return
	var step: TutorialStep = _current_step()
	if step != null and step.completion_signal == SIGNAL_SPECIAL_CONSUMED:
		_advance()
