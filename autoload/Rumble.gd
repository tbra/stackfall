extends Node
## Controller rumble via Godot's own Input singleton
## (Input.start_joy_vibration/stop_joy_vibration -- SDL joypads, also reached
## by a pad GodotSteam virtualises through Steam Input). This file never
## touches the Steam API directly (CLAUDE.md: never write Steam or
## SteamMultiplayerPeer as a bare identifier); rumble goes through Input only.
##
## Listens on Events (CLAUDE.md's global signal bus), the same pattern
## game/CameraRig.gd's Events.block_impacted -> camera shake reaction already
## uses (config/CameraShakeConfig.gd is this file's config/RumbleConfig.gd
## precedent). Only ever rumbles the joypad that most recently sent a real
## button/axis event (see _input()); a session driven entirely by mouse and
## keyboard never buzzes a pad sitting idle nearby, and this is a total no-op
## headless or with no pad connected -- there is simply never a
## InputEventJoypadButton/Motion to track a device id from in that case.
##
## No class_name: this is the Rumble autoload singleton, the same convention
## Events/Settings/Net/Match/Sfx already use (see autoload/Net.gd's header).

@export var config: RumbleConfig = preload("res://config/rumble_config.tres")

const DEVICE_NONE: int = -1

## Which joypad most recently sent a real InputEventJoypadButton/Motion (past
## Settings.JOYPAD_MOTION_DEVICE_THRESHOLD for motion, reusing that same
## deadzone constant rather than duplicating it here -- DECISION,
## autoload/Rumble.gd). DEVICE_NONE until the first such event ever arrives.
var _last_device_id: int = DEVICE_NONE

## Which device FAMILY (Settings.DEVICE_GAMEPAD/DEVICE_KEYBOARD_MOUSE) most
## recently sent real input, tracked independently of autoload/Settings.gd's
## own _active_device (both are plain Nodes reacting to the same _input()
## dispatch; there is no ordering dependency between the two, only a shared
## pair of StringName constants reused for DRY).
var _last_family: StringName = &""

## Test seam (tests/unit/test_rumble.gd): swaps the real Input calls for a
## Callable that records what was asked for instead of touching hardware --
## the same Variant/Callable seam idea autoload/Sfx.gd's set_root_dir_for_test()
## uses for a value GUT can't otherwise inject into the real singleton, except
## here the seam is a whole function rather than a value.
var start_vibration_fn: Callable = Callable(self, "_start_vibration_real")
var stop_vibration_fn: Callable = Callable(self, "_stop_vibration_real")


func _ready() -> void:
	Events.block_impacted.connect(_on_block_impacted)
	Events.placement_rejected.connect(_on_placement_rejected)
	Events.feed_block_issued.connect(_on_feed_block_issued)
	Events.special_triggered.connect(_on_special_triggered)
	Events.player_eliminated.connect(_on_player_eliminated)
	Events.match_won.connect(_on_match_won)
	Events.pause_menu_opened.connect(_on_pause_menu_opened)


## Runs for every node in the tree (plain autoload Node, same as
## autoload/Settings.gd's own _input()) -- only ever classifies the raw event
## into "which pad last spoke" / "keyboard-mouse last spoke", never acts on it
## directly.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		_last_device_id = (event as InputEventJoypadButton).device
		_last_family = Settings.DEVICE_GAMEPAD
	elif event is InputEventJoypadMotion:
		var motion: InputEventJoypadMotion = event
		if absf(motion.axis_value) >= Settings.JOYPAD_MOTION_DEVICE_THRESHOLD:
			_last_device_id = motion.device
			_last_family = Settings.DEVICE_GAMEPAD
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		_last_family = Settings.DEVICE_KEYBOARD_MOUSE


## Stops whatever the last-tracked pad is currently doing. Called by
## ui/PauseMenu.gd's own pause_menu_opened (via _on_pause_menu_opened below)
## and by this file's own match-end handler, so a mid-decay rumble never
## keeps buzzing into a menu or the results screen.
func stop_all() -> void:
	if _last_device_id != DEVICE_NONE:
		stop_vibration_fn.call(_last_device_id)


func _on_pause_menu_opened() -> void:
	stop_all()


func _on_block_impacted(speed: float) -> void:
	# Bontago (rumble package): no slot on this signal at all (game/Block.gd
	# never passes one -- confirmed by reading Block.gd), so this reacts for
	# every instance unconditionally, exactly like game/CameraRig.gd's own
	# camera-shake reaction to the same signal.
	if speed < config.impact_speed_threshold:
		return
	var span: float = maxf(config.impact_speed_max - config.impact_speed_threshold, 0.0001)
	var t: float = clampf((speed - config.impact_speed_threshold) / span, 0.0, 1.0)
	_trigger(config.impact_weak_magnitude * t, config.impact_strong_magnitude * t, config.impact_duration_s)


func _on_placement_rejected(slot_id: int, _reason: StringName) -> void:
	if not Net.is_local_slot(slot_id):
		return
	_trigger(
		config.placement_refused_weak_magnitude,
		config.placement_refused_strong_magnitude,
		config.placement_refused_duration_s,
	)


## DECISION (autoload/Rumble.gd): Events.gd has no "you just placed a block"
## signal carrying a slot id -- block_placed(block, shape_id) is global with
## no slot at all (confirmed by reading Events.gd/MatchPlacement.gd
## directly), and placement_relocated only fires for the rarer auto-drop
## relocation case. feed_block_issued(slot_id, ...) is the closest available
## per-slot signal: MatchFeed.gd emits it the instant a slot's held block is
## consumed and the next one is handed over, so it doubles as "your last drop
## landed, here's your next piece" for every placement after the first. It
## also fires once at match start before any placement has happened, so the
## very first block issued to a slot ticks too -- accepted as the simplest
## reasonable option per CLAUDE.md's minor-ambiguity rule (a "new block
## ready" light tick reads fine even at match start).
func _on_feed_block_issued(slot_id: int, _shape_id: StringName, _next_shape_id: StringName) -> void:
	if not Net.is_local_slot(slot_id):
		return
	_trigger(
		config.block_placed_weak_magnitude,
		config.block_placed_strong_magnitude,
		config.block_placed_duration_s,
	)


## No slot on this signal (Events.gd's own doc comment: only net_id/def_id/
## position/chain_depth) -- treated the same as block_impacted above, a
## global world event every instance reacts to regardless of locality.
func _on_special_triggered(_net_id: int, _def_id: StringName, _position: Vector3, _chain_depth: int) -> void:
	_trigger(
		config.special_triggered_weak_magnitude,
		config.special_triggered_strong_magnitude,
		config.special_triggered_duration_s,
	)


func _on_player_eliminated(slot_id: int, _team_id: int) -> void:
	if not Net.is_local_slot(slot_id):
		return
	_trigger(
		config.player_eliminated_weak_magnitude,
		config.player_eliminated_strong_magnitude,
		config.player_eliminated_duration_s,
	)


## DECISION (autoload/Rumble.gd): Events.gd has one match-end signal,
## match_won(team_id) -- there is no separate "you lost" signal, so this
## derives win/lose per local slot by comparing team_of_slot() the same way
## autoload/Sfx.gd's _on_gift_claimed()/_team_of_slot() already does for a
## null Match.config (offline/hot-seat: every slot is its own team, so a
## match_won team_id that matches a local slot's own id reads as a win for
## that slot). Stops any lingering rumble first (this doubles as "the match
## ends" stop point the brief asks for) before playing the appropriate pulse.
func _on_match_won(team_id: int) -> void:
	stop_all()
	var slot_count: int = maxi(Match.slot_count(), team_id + 1)
	for slot_id: int in range(slot_count):
		if not Net.is_local_slot(slot_id):
			continue
		if _team_of_slot(slot_id) == team_id:
			_trigger(config.match_won_weak_magnitude, config.match_won_strong_magnitude, config.match_won_duration_s)
		else:
			_trigger(config.match_lost_weak_magnitude, config.match_lost_strong_magnitude, config.match_lost_duration_s)
		return


## Null-safe mirror of config/MatchConfig.gd's team_of_slot() -- Match.config
## is null before a match starts, matching autoload/Sfx.gd's own
## _team_of_slot() helper.
func _team_of_slot(slot_id: int) -> int:
	if Match.config == null:
		return slot_id
	return Match.config.team_of_slot(slot_id)


func _trigger(weak_magnitude: float, strong_magnitude: float, duration_s: float) -> void:
	if not Settings.rumble_enabled():
		return
	if _last_family != Settings.DEVICE_GAMEPAD or _last_device_id == DEVICE_NONE:
		return
	var strength: float = clampf(Settings.rumble_strength(), 0.0, 1.0)
	var scaled_weak: float = clampf(weak_magnitude * strength, 0.0, 1.0)
	var scaled_strong: float = clampf(strong_magnitude * strength, 0.0, 1.0)
	if scaled_weak <= 0.0 and scaled_strong <= 0.0:
		return
	start_vibration_fn.call(_last_device_id, scaled_weak, scaled_strong, duration_s)


## Bontago (options package): a short "test" pulse ui/OptionsMenu.gd's rumble
## intensity slider nudges (when the slider is released or the rumble toggle
## is turned on) so the player can feel the current intensity without
## needing to trigger a real match event first. Reuses config.impact_weak_
## magnitude/impact_strong_magnitude/impact_duration_s -- the same "moderate
## hit" pulse _on_block_impacted() already produces at full impact speed --
## rather than inventing a new RumbleConfig field for a UI-only nudge
## (config/RumbleConfig.gd sits outside this package's owned files).
## DECISION (autoload/Rumble.gd). Goes through the same _trigger() gating as
## every other rumble reaction, so it is silent unless rumble is enabled and
## a gamepad is the last-active device.
func trigger_test_pulse() -> void:
	_trigger(config.impact_weak_magnitude, config.impact_strong_magnitude, config.impact_duration_s)


func _start_vibration_real(device: int, weak_magnitude: float, strong_magnitude: float, duration_s: float) -> void:
	Input.start_joy_vibration(device, weak_magnitude, strong_magnitude, duration_s)


func _stop_vibration_real(device: int) -> void:
	Input.stop_joy_vibration(device)


# --- Test seam -----------------------------------------------------------

## tests/unit/test_rumble.gd injects the last-seen device/family directly,
## the same "inject state GUT can't otherwise reach" role
## Settings.set_active_input_device_for_test() plays for its own tracker --
## real hardware never delivers a synthetic InputEventJoypadButton/Motion to
## a headless test run's window.
func set_last_device_for_test(device_id: int, family: StringName) -> void:
	_last_device_id = device_id
	_last_family = family
