extends Node
## Controller rumble via Godot's own Input singleton
## (Input.start_joy_vibration/stop_joy_vibration -- SDL joypads, also reached
## by a pad GodotSteam virtualises through Steam Input). This file never
## touches the Steam API directly (CLAUDE.md: never write Steam or
## SteamMultiplayerPeer as a bare identifier); rumble goes through Input only.
##
## Listens on Events, the same pattern as game/player/CameraRig.gd's
## Events.block_impacted -> camera shake reaction. Only ever rumbles the joypad that most recently sent a real
## button/axis event (see _input()); a session driven entirely by mouse and
## keyboard never buzzes a pad sitting idle nearby, and this is a total no-op
## headless or with no pad connected -- there is simply never a
## InputEventJoypadButton/Motion to track a device id from in that case.
##
## No class_name: this is the Rumble autoload singleton (see autoload/Net.gd's header).

@export var config: RumbleConfig = preload("res://config/player/rumble_config.tres")

const DEVICE_NONE: int = -1
const LocalFeedback := preload("res://autoload/match/LocalFeedback.gd")

## Which joypad most recently sent a real InputEventJoypadButton/Motion (past
## Settings.JOYPAD_MOTION_DEVICE_THRESHOLD for motion, reusing that deadzone
## constant rather than duplicating it; DECISION). DEVICE_NONE until the first such event ever arrives.
var _last_device_id: int = DEVICE_NONE

## Which device FAMILY (Settings.DEVICE_GAMEPAD/DEVICE_KEYBOARD_MOUSE) most
## recently sent real input, tracked independently of autoload/Settings.gd's
## own _active_device (both react to the same _input() dispatch; there is no
## ordering dependency between the two).
var _last_family: StringName = &""

## Swappable vibration calls (tests record them instead of touching hardware).
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
	# A world build/teardown never leaves a pad buzzing into the next match.
	Events.match_scope_reset.connect(stop_all)


## Only classifies the raw event into "which pad last spoke" /
## "keyboard-mouse last spoke", never acts on it directly.
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


## Stops whatever the last-tracked pad is currently doing. Called on
## pause_menu_opened and by the match-end handler, so a mid-decay rumble never
## keeps buzzing into a menu or the results screen.
func stop_all() -> void:
	if _last_device_id != DEVICE_NONE:
		stop_vibration_fn.call(_last_device_id)


func _on_pause_menu_opened() -> void:
	stop_all()


func _on_block_impacted(speed: float) -> void:
	# No slot on this signal (game/blocks/Block.gd never passes one), so this
	# reacts for every instance unconditionally, like game/player/CameraRig.gd's
	# camera-shake reaction to the same signal.
	if speed < config.impact_speed_threshold:
		return
	var span: float = maxf(config.impact_speed_max - config.impact_speed_threshold, 0.0001)
	var t: float = clampf((speed - config.impact_speed_threshold) / span, 0.0, 1.0)
	_trigger(config.impact_weak_magnitude * t, config.impact_strong_magnitude * t, config.impact_duration_s)


## Silent for a bot seat: offline, Net.is_local_slot() is true for every slot,
## bots included (autoload/match/LocalFeedback.gd).
func _on_placement_rejected(slot_id: int, _reason: StringName) -> void:
	if not LocalFeedback.is_own_human_slot(slot_id):
		return
	_trigger(
		config.placement_refused_weak_magnitude,
		config.placement_refused_strong_magnitude,
		config.placement_refused_duration_s,
	)


## DECISION (autoload/Rumble.gd): there is no "you just placed a block" signal
## carrying a slot id (block_placed has no slot; placement_relocated only fires
## for auto-drop relocation). feed_block_issued(slot_id, ...) is the closest
## per-slot signal: MatchFeed.gd emits it the instant a slot's held block is
## consumed and the next one is handed over, so it doubles as "your last drop
## landed". It also fires once at match start, so the first block issued to a
## slot ticks too, which reads fine as a "new block ready" tick.
##
## Personal feedback, so only a human seat driven from this machine
## (autoload/match/LocalFeedback.gd); offline Net.is_local_slot() is true for
## every slot, so without the bot check each bot's feed buzzed the pad.
func _on_feed_block_issued(slot_id: int, _shape_id: StringName, _next_shape_id: StringName) -> void:
	if not LocalFeedback.is_own_human_slot(slot_id):
		return
	_trigger(
		config.block_placed_weak_magnitude,
		config.block_placed_strong_magnitude,
		config.block_placed_duration_s,
	)


## No slot on this signal; treated like block_impacted above, a global world
## event every instance reacts to regardless of locality.
func _on_special_triggered(_net_id: int, _def_id: StringName, _position: Vector3, _chain_depth: int) -> void:
	_trigger(
		config.special_triggered_weak_magnitude,
		config.special_triggered_strong_magnitude,
		config.special_triggered_duration_s,
	)


## Only the eliminated player's own pad (a human seat on this
## machine), never a bot's or another peer's elimination.
func _on_player_eliminated(slot_id: int, _team_id: int) -> void:
	if not LocalFeedback.is_own_human_slot(slot_id):
		return
	_trigger(
		config.player_eliminated_weak_magnitude,
		config.player_eliminated_strong_magnitude,
		config.player_eliminated_duration_s,
	)


## DECISION (autoload/Rumble.gd): the only match-end signal is
## match_won(team_id); there is no "you lost" signal, so win/lose is derived per
## local slot by comparing team_of_slot() the way autoload/Sfx.gd does for a
## null Match.config (offline/hot-seat: every slot is its own team). Stops any
## lingering rumble first, then plays the appropriate pulse.
func _on_match_won(team_id: int) -> void:
	stop_all()
	var slot_count: int = maxi(Match.slot_count(), team_id + 1)
	for slot_id: int in range(slot_count):
		# The first HUMAN seat on this machine decides win or
		# loss; a bot seat (every slot is local offline) never does.
		if not LocalFeedback.is_own_human_slot(slot_id):
			continue
		if _team_of_slot(slot_id) == team_id:
			_trigger(config.match_won_weak_magnitude, config.match_won_strong_magnitude, config.match_won_duration_s)
		else:
			_trigger(config.match_lost_weak_magnitude, config.match_lost_strong_magnitude, config.match_lost_duration_s)
		return


## Null-safe mirror of config/match/MatchConfig.gd's team_of_slot(): Match.config
## is null before a match starts.
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


## A short "test" pulse ui/menus/OptionsMenu.gd's rumble intensity slider
## nudges (when the slider is released or the rumble toggle is turned on) so
## the player can feel the current intensity without a real match event.
## DECISION (autoload/Rumble.gd): reuses config.impact_weak_magnitude/
## impact_strong_magnitude/impact_duration_s (the "moderate hit" pulse of
## _on_block_impacted() at full speed) rather than a new RumbleConfig field.
## Goes through the same _trigger() gating as every other reaction, so it is
## silent unless rumble is enabled and a gamepad is the last-active device.
func trigger_test_pulse() -> void:
	_trigger(config.impact_weak_magnitude, config.impact_strong_magnitude, config.impact_duration_s)


func _start_vibration_real(device: int, weak_magnitude: float, strong_magnitude: float, duration_s: float) -> void:
	Input.start_joy_vibration(device, weak_magnitude, strong_magnitude, duration_s)


func _stop_vibration_real(device: int) -> void:
	Input.stop_joy_vibration(device)
