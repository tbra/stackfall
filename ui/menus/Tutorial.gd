class_name Tutorial
extends Node
## Spec 1.2 "Tutorial": an extra over the one real one-player match the mode launcher builds
## (config.player_count = 1, normal rules, the scripted-gifts gate). This node holds no world of its
## own: attach() takes the local player's controller, ghost and HUD, and the five-step scripted
## sequence (config/match/TutorialConfig.gd) teaches placing, rotating, territory, specials/throwing
## and the camera in order.
##
## It is attached while the match is still LOADING, so nothing starts, shows or counts until
## Events.match_state_changed reports PLAYING (`_started`); the match reaching END ends it.
##
## Does not know about game/main/Main.gd: it only emits `finished`, once, when the last step
## completes, the player cancels (pause_menu) or the match ends.
##
## Each step's completion condition is checked only while that step is the *current* one
## (`_current_step()`), because Events.block_placed/special_consumed/territory_share_changed are
## global bus signals not scoped to the listening step; an event that would complete a later step
## can then never skip or repeat a step.

signal finished

@export var tutorial_config: TutorialConfig = preload("res://config/match/tutorial_config.tres")

var _controller: PlayerController
var _ghost: GhostPreview
var _hud: HUD
@onready var _prompt_label: InputPromptFlow = %PromptLabel
@onready var _prompt_panel: PanelContainer = %PromptLabel.get_parent().get_parent() as PanelContainer
@onready var _step_label: Label = %StepLabel
## The tip banner's look comes from these tokens.
@export var hud_visual_tuning: HUDVisualTuning = preload("res://config/ui/hud_visual_tuning.tres")

## -1 before the first _begin_step() call; otherwise an index into tutorial_config.steps.
var _step_index: int = -1
## True from the moment _end_tutorial() has run once (step 5 completing, or pause_menu): guards
## _process()/every Events handler below so a second trigger can never call Match.abort_match() or
## emit `finished` twice.
var _finished: bool = false
## True once the match is PLAYING: before that no step is current, no prompt shows and no
## completion handler counts.
var _started: bool = false

## Step "rotating"'s poll baseline: GhostPreview.orientation_index at the moment that step began
## (no Events signal exists for a purely local ghost manipulation: rotation never reaches the host
## until release).
var _rotation_baseline: int = 0

## Step "camera"'s cumulative hold, seconds of camera_orbit/camera_pan_* observed while that step
## is active. Never decays on release, so a tester need not hold one single continuous input.
var _camera_hold_elapsed_s: float = 0.0

## tools/bootstrap_project.gd's camera actions (already bound on keyboard and gamepad).
const CAMERA_ACTIONS: Array[StringName] = [
	&"camera_orbit", &"camera_pan_left", &"camera_pan_right", &"camera_pan_forward", &"camera_pan_back",
]

## config/match/TutorialConfig.gd's Step.completion_signal values this class understands. Kept as
## constants here (not on TutorialConfig, which is pure data) so a step's .tres entry and the code
## path that answers it cannot drift under a typo; an unrecognized completion_signal never matches,
## so that step never completes rather than silently counting as "always complete".
const SIGNAL_BLOCK_PLACED: StringName = &"block_placed"
const SIGNAL_ORIENTATION_CHANGED: StringName = &"orientation_changed"
const SIGNAL_TERRITORY_CLAIMED: StringName = &"territory_claimed"
const SIGNAL_SPECIAL_CONSUMED: StringName = &"special_consumed"
const SIGNAL_CAMERA_MOVED: StringName = &"camera_moved"

## The mode launcher always builds the tutorial match with config.player_count = 1, so there is
## only ever one tutorial participant and every Match call below that needs a slot id uses this.
const TUTORIAL_SLOT: int = 0


func _ready() -> void:
	Events.match_state_changed.connect(_on_match_state_changed)
	Events.block_placed.connect(_on_block_placed)
	Events.territory_share_changed.connect(_on_territory_share_changed)
	Events.special_consumed.connect(_on_special_consumed)
	_style_tip_banner()
	_prompt_panel.visible = false
	Settings.hud_scale_changed.connect(_on_hud_scale_changed)
	Settings.ui_scale_changed.connect(_on_hud_scale_changed)


## Wires the tutorial onto the local player's world the one builder made; call before the match
## is PLAYING.
func attach(player: HotSeat) -> void:
	_controller = player.controller()
	_ghost = player.ghost()
	_hud = player.hud()
	_place_tip_banner()


## A HUD plate with a rim step block ("1/5") and the sentence in cream, centred directly under the
## timer ring and never over it, at most tip_max_width_px wide.
func _style_tip_banner() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var theme: Theme = preload("res://ui/theme/stackfall_theme.tres")
	_prompt_panel.theme = theme
	var plate: StyleBoxFlat = StyleBoxFlat.new()
	plate.bg_color = hud_visual_tuning.surface_color
	plate.border_color = hud_visual_tuning.surface_border_color
	plate.set_border_width_all(int(hud_visual_tuning.panel_border_width_px))
	plate.set_corner_radius_all(arcade.radius_block_px)
	plate.shadow_color = arcade.disc_950_color
	plate.shadow_size = 1
	plate.shadow_offset = Vector2(0.0, float(arcade.drop_sm_px))
	plate.set_content_margin_all(float(arcade.space_5_px))
	_prompt_panel.add_theme_stylebox_override("panel", plate)
	var block: StyleBoxFlat = StyleBoxFlat.new()
	block.bg_color = arcade.rim_color
	block.border_color = arcade.rim_lip_color
	block.border_width_bottom = arcade.lip_sm_px
	block.set_corner_radius_all(arcade.radius_chip_px)
	block.content_margin_left = float(arcade.space_2_px)
	block.content_margin_right = float(arcade.space_2_px)
	_step_label.add_theme_stylebox_override("normal", block)
	_step_label.add_theme_font_override("font", theme.get_font(&"font", &"DisplayLabel"))
	_step_label.add_theme_font_size_override("font_size", arcade.font_size_button_px)
	_step_label.add_theme_color_override("font_color", arcade.ink_color)
	_prompt_label.set_text_color(arcade.cream_color)
	(_prompt_label.get_parent() as BoxContainer).add_theme_constant_override("separation", arcade.space_4_px)
	var half_width: float = hud_visual_tuning.tip_max_width_px * 0.5
	_prompt_panel.offset_left = -half_width
	_prompt_panel.offset_right = half_width


## DECISION: the banner lives in its own CanvasLayer, outside the HUD's scale root, so it
## follows the HUD scale by scaling the panel itself (same factor as the scale root) around its top-centre
## pivot; the ring gap scales too, so the banner stays centred directly under the (scaled) timer ring.
func _place_tip_banner() -> void:
	if _hud == null:
		return
	var factor: float = UiScaleTuning.hud_relative_factor()
	var height: float = _prompt_panel.offset_bottom - _prompt_panel.offset_top
	var top: float = _hud.timer_ring_bottom_px() + hud_visual_tuning.tip_ring_gap_px * factor
	_prompt_panel.offset_top = top
	_prompt_panel.offset_bottom = top + height
	_prompt_panel.pivot_offset = Vector2((_prompt_panel.offset_right - _prompt_panel.offset_left) * 0.5, 0.0)
	_prompt_panel.scale = Vector2(factor, factor)


func _on_hud_scale_changed(_value: float) -> void:
	_place_tip_banner()


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


## pause_menu (Escape / gamepad Start) is the quit gesture, not ui_cancel: gamepad B is also
## rotate_snap (and camera_snap_goal)'s button during gameplay (tools/bootstrap_project.gd), so
## reading ui_cancel would end the tutorial whenever a gamepad player snap-rotates. pause_menu is
## bound on both devices, collides with no gameplay action, and the real PauseMenu never opens
## while Tutorial owns the scene (see its `suppressed`), so the input is otherwise unclaimed.
func _unhandled_input(event: InputEvent) -> void:
	if _started and event.is_action_pressed(&"pause_menu"):
		_end_tutorial()
		get_viewport().set_input_as_handled()


func _any_camera_action_held() -> bool:
	for action: StringName in CAMERA_ACTIONS:
		if Input.is_action_pressed(action):
			return true
	return false


func _current_step() -> TutorialStep:
	if _finished or not _started or _step_index < 0 or _step_index >= tutorial_config.steps.size():
		return null
	return tutorial_config.steps[_step_index]


func _begin_step(index: int) -> void:
	_step_index = index
	var step: TutorialStep = tutorial_config.steps[index]
	_prompt_label.set_template(step.prompt_text)
	_step_label.text = "%d/%d" % [index + 1, tutorial_config.steps.size()]
	if step.completion_signal == SIGNAL_ORIENTATION_CHANGED:
		_rotation_baseline = _ghost.orientation_index
	elif step.completion_signal == SIGNAL_CAMERA_MOVED:
		_camera_hold_elapsed_s = 0.0
	elif step.completion_signal == SIGNAL_SPECIAL_CONSUMED:
		# config.scripted_gifts (game/main/MatchLaunch.gd's tutorial_config()) is
		# what lets this through MatchGifts.debug_queue_special()'s own gate --
		# see game/sandbox/Sandbox.gd's matching F9 seam for the same contract.
		Match.debug_queue_special(TUTORIAL_SLOT, tutorial_config.demo_special_id)


## Every completion handler below funnels here: advances exactly once per call, and step 5
## completing ends the tutorial the same way pause_menu does.
func _advance() -> void:
	if _step_index + 1 >= tutorial_config.steps.size():
		_end_tutorial()
		return
	_begin_step(_step_index + 1)


## The one place this class ends the match: step 5 completing (_advance()) and pause_menu
## (_unhandled_input()) and the match reaching END all reach this, so Match.abort_match() and
## `finished` can never be skipped for one path or double-fired for another. The mode launcher's
## owner is connected to `finished` and tears the match down.
func _end_tutorial() -> void:
	if _finished:
		return
	_finished = true
	Match.abort_match()
	finished.emit()


func _on_match_state_changed(_from_state: int, to_state: int) -> void:
	if to_state == Match.State.PLAYING and not _started and not _finished:
		_started = true
		_prompt_panel.visible = true
		_begin_step(0)
	elif to_state == Match.State.END:
		_end_tutorial()


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
