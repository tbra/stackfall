extends Node
## User settings: graphics preset, audio levels, control bindings, music folder.
##
## Persisted to a single user://settings.cfg ConfigFile and saved on every
## setter (small, infrequent writes, no debouncing needed).
##
## Settings only stores the user's choices and emits signals; it never
## touches a Viewport/Environment or plays audio itself. Consumers apply
## graphics_preset_changed/audio_settings_changed to the actual render/audio
## state.

signal graphics_preset_changed(preset: GraphicsPreset)
signal audio_settings_changed()
## The "Adaptive quality" option flipped.
signal adaptive_quality_setting_changed(enabled: bool)
signal camera_shake_setting_changed(enabled: bool)
## The player-chosen field of view changed (degrees; 0.0 = cleared, use CameraTuning.fov_deg).
signal fov_override_changed(degrees: float)
signal window_mode_changed(id: StringName)
## The relative UI scale changed (already sanitized and applied).
signal ui_scale_changed(scale: float)
signal hud_scale_changed(scale: float)
signal minimap_size_changed(preset: int)

## autoload/Rumble.gd reads rumble_enabled()/rumble_strength() directly (like
## camera_shake_enabled()); this fires so an ui/menus/OptionsMenu.gd row can
## live-update without polling.
signal rumble_setting_changed(enabled: bool, strength: float)
## The local player's typed name changed (already cleaned).
signal player_name_changed(player_name: String)

const DEFAULT_PRESET_ID: StringName = &"medium"
const PRESETS_DIR: String = "res://config/graphics/presets/"

## The last-used input device family: defaults to keyboard/mouse, switches to
## gamepad on gamepad input and back on mouse/keyboard input.
## ui/menus/OptionsMenu.gd's Controls page and ui/menus/KeyRebindRow.gd
## read active_input_device() to decide which device's binding glyphs to
## show; Events.input_device_changed lets both live-swap without reopening
## the menu.
const DEVICE_KEYBOARD_MOUSE: StringName = &"keyboard_mouse"
const DEVICE_GAMEPAD: StringName = &"gamepad"
const DEFAULT_ACTIVE_DEVICE: StringName = DEVICE_KEYBOARD_MOUSE

## DECISION: a UI-feel/detection threshold, not gameplay or physics tuning,
## so a plain script const instead of a config/*.tres Resource (like
## ui/menus/OptionsMenu.gd's MIN_VOLUME_DB/MAX_VOLUME_DB, see its DECISION).
## Filters incidental mouse jitter (a resting hand, OS pointer noise) from
## counting as "the player just used the mouse".
const MOUSE_MOTION_DEVICE_THRESHOLD_PX: float = 4.0

## Joypad axis deadzone for *device detection* only -- deliberately coarser
## than InputMap's own per-action deadzone (an analog stick's own resting
## drift must never flip the active device to gamepad on its own).
const JOYPAD_MOTION_DEVICE_THRESHOLD: float = 0.35

var _active_device: StringName = DEFAULT_ACTIVE_DEVICE

const SECTION_GRAPHICS: String = "graphics"
const SECTION_AUDIO: String = "audio"
const SECTION_INPUT: String = "input"
const SECTION_GAMEPAD: String = "gamepad"
const SECTION_CONTROLS: String = "controls"
const SECTION_DEBUG: String = "debug"
const SECTION_PLAYER: String = "player"
const KEY_PLAYER_NAME: String = "name"
const KEY_DEBUG_ENABLED: String = "enabled"

const KEY_PRESET: String = "preset"
const KEY_ADAPTIVE_QUALITY: String = "adaptive_quality"
## The player's per-field edits layered over the base preset (field -> value).
const KEY_GRAPHICS_OVERRIDES: String = "overrides"
## The GraphicsPreset fields the Options Graphics tab may override; anything else in a saved
## file is dropped on load.
const GRAPHICS_OVERRIDE_FIELDS: Array[StringName] = [
	&"ssr_enabled", &"msaa_3d", &"shadow_atlas_size", &"volumetric_fog_enabled",
	&"cloud_puff_density", &"birds_enabled", &"ambient_life_enabled", &"sun_shadow_mode",
	&"sun_shadow_max_distance", &"reflection_probe_mode", &"glow_enabled",
	&"hole_void_animated", &"disc_fine_detail_enabled", &"block_outline_enabled",
	&"block_dissolve_effect_enabled", &"gift_idle_glow_enabled", &"cloud_shadows_enabled",
	&"aurora_enabled", &"vsync_enabled", &"frame_cap_mode", &"fixed_fps", &"render_scale_3d", &"render_scale_3d_mode",
]
const KEY_MASTER_VOLUME_PERCENT: String = "master_volume_percent"
const KEY_MASTER_MUTED: String = "master_muted"
const KEY_MUSIC_VOLUME_PERCENT: String = "music_volume_percent"
const KEY_MUSIC_MUTED: String = "music_muted"
const KEY_SFX_VOLUME_PERCENT: String = "sfx_volume_percent"
const KEY_SFX_MUTED: String = "sfx_muted"
const KEY_WEATHER_VOLUME_PERCENT: String = "weather_volume_percent"
const KEY_WEATHER_MUTED: String = "weather_muted"
const KEY_CAMERA_SHAKE_ENABLED: String = "camera_shake_enabled"
const KEY_FOV_OVERRIDE_DEG: String = "fov_override_deg"
const KEY_WINDOW_MODE: String = "window_mode"
const KEY_UI_SCALE: String = "ui_scale"
const KEY_HUD_SCALE: String = "hud_scale"
const KEY_MINIMAP_SIZE: String = "minimap_size"
const KEY_RUMBLE_ENABLED: String = "rumble_enabled"
const KEY_RUMBLE_STRENGTH: String = "rumble_strength"
const KEY_MOUSE_MOVE_SPEED_SCALE: String = "mouse_move_speed_scale"
const KEY_STICK_MOVE_SPEED_SCALE: String = "stick_move_speed_scale"
## Marks a save written after gamepad_cursor_base_speed was
## raised x1.2; a save without it holds a scale relative to the old base.
const KEY_STICK_SPEED_BASIS: String = "stick_speed_basis"
const STICK_SPEED_BASIS_CURRENT: int = 2
## Old base -> new base ratio (30 -> 36) and the Options slider's range (kept
## in step with ui/menus/OptionsMenu.gd MIN/MAX_MOVE_SPEED_SCALE) for the migration.
const STICK_SPEED_BASE_RATIO: float = 1.2
const STICK_SPEED_MIGRATED_MIN: float = 0.5
const STICK_SPEED_MIGRATED_MAX: float = 2.0

## The three player-facing window modes: exclusive fullscreen, borderless
## fullscreen and windowed. Ids are StringName rather than a GDScript enum so
## they persist to ConfigFile directly (like _current_preset_id) and so
## ui/menus/OptionsMenu.gd's OptionButton can iterate WINDOW_MODE_IDS without
## depending on this script's enum type.
const WINDOW_MODE_FULLSCREEN: StringName = &"fullscreen"
const WINDOW_MODE_BORDERLESS_FULLSCREEN: StringName = &"borderless_fullscreen"
const WINDOW_MODE_WINDOWED: StringName = &"windowed"

## Borderless fullscreen is the default.
const DEFAULT_WINDOW_MODE_ID: StringName = WINDOW_MODE_BORDERLESS_FULLSCREEN

## Display order for the OptionButton in ui/menus/OptionsMenu.gd: exclusive
## fullscreen, then borderless fullscreen, then windowed.
const WINDOW_MODE_IDS: Array[StringName] = [
	WINDOW_MODE_FULLSCREEN,
	WINDOW_MODE_BORDERLESS_FULLSCREEN,
	WINDOW_MODE_WINDOWED,
]

## Human-readable labels for WINDOW_MODE_IDS, keyed the same way; the
## OptionButton reads window_mode_label(id) rather than hand-rolling strings.
const WINDOW_MODE_LABELS: Dictionary[StringName, String] = {
	WINDOW_MODE_FULLSCREEN: "Fullscreen",
	WINDOW_MODE_BORDERLESS_FULLSCREEN: "Borderless Fullscreen",
	WINDOW_MODE_WINDOWED: "Windowed",
}

## Default on: matches the shake game/player/CameraRig.gd applies before the
## player ever opens Options, so a fresh install shows the intended feel.
const DEFAULT_CAMERA_SHAKE_ENABLED: bool = true

## The single source of truth for a fresh install's rumble defaults (see
## config/player/RumbleConfig.gd's DECISION comment). Once
## user://settings.cfg has a [gamepad] section, _load() never reads these
## fields again.
var _rumble_defaults: RumbleConfig = preload("res://config/player/rumble_config.tres")

## Master/Music/SFX/Weather are independent channels, each a plain 0..1 linear
## "slider position" (mapped to dB with linear_to_db; 0% = silent) plus its
## own mute flag.
enum AudioChannel { MASTER, MUSIC, SFX, WEATHER }

const DEFAULT_VOLUME_PERCENT: float = 1.0

## Floor applied whenever a channel is silent (muted, or at 0%). Not a design
## tunable: an engineering constant (-80 dB reads as inaudible on any output
## device), like autoload/Sfx.gd's MUSIC_STEM_MUTE_DB. linear_to_db(0.0) would
## return -INF, an unpleasant value to carry through the volume_db math in
## autoload/Sfx.gd's crossfade/envelope code, so a large-but-finite floor is
## used instead.
const SILENT_VOLUME_DB: float = -80.0

## Two independent block-movement scales: mouse_move_speed_scale multiplies
## game/player/PlayerController.gd's mouse-cursor use of
## GhostTuning.block_move_sensitivity, stick_move_speed_scale multiplies its
## gamepad cursor's max speed. 1.0 = the tuning Resource's own untouched
## default for either. The slider range lives in ui/menus/OptionsMenu.gd (see
## its DECISION), not here.
const DEFAULT_MOUSE_MOVE_SPEED_SCALE: float = 1.0
const DEFAULT_STICK_MOVE_SPEED_SCALE: float = 1.0

const REAL_CONFIG_PATH: String = "user://settings.cfg"
var _config_path: String = REAL_CONFIG_PATH
var _gut_run: bool = false
var _current_preset_id: StringName = DEFAULT_PRESET_ID
## field name -> value, only for fields that differ from the base preset.
## Non-empty means the player's graphics are "Custom".
var _graphics_overrides: Dictionary = {}
## Opt-in adaptive quality. Default OFF (the user decides). The level is
## runtime-only (never saved) and only ever layered over the stored preset.
const DEFAULT_ADAPTIVE_QUALITY: bool = false
var _adaptive_quality: bool = DEFAULT_ADAPTIVE_QUALITY
var _governor_level: int = 0
var _governor_config: QualityGovernorConfig = preload("res://config/graphics/quality_governor.tres")

## Keyed by AudioChannel. Muting never touches the stored percent: toggling
## mute back off reveals whatever percent the slider was already at, so the
## previous level is restored without a second stored "previous" field
## (DECISION, autoload/Settings.gd).
var _channel_volume_percent: Dictionary[int, float] = {
	AudioChannel.MASTER: DEFAULT_VOLUME_PERCENT,
	AudioChannel.MUSIC: DEFAULT_VOLUME_PERCENT,
	AudioChannel.SFX: DEFAULT_VOLUME_PERCENT,
	AudioChannel.WEATHER: DEFAULT_VOLUME_PERCENT,
}
var _channel_muted: Dictionary[int, bool] = {
	AudioChannel.MASTER: false,
	AudioChannel.MUSIC: false,
	AudioChannel.SFX: false,
	AudioChannel.WEATHER: false,
}

## The name the local player typed, "" until they type one (the
## host then seats them as "Player N"). Length cap: NetConfig.max_player_name_length.
var _player_name: String = ""
var _net_config: NetConfig = preload("res://config/net/net_config.tres")
var _camera_shake_enabled: bool = DEFAULT_CAMERA_SHAKE_ENABLED
## 0.0 = no override (the camera uses CameraTuning.fov_deg, which F4 edits).
var _fov_override_deg: float = 0.0
var _window_mode_id: StringName = DEFAULT_WINDOW_MODE_ID
var _ui_scale_tuning: UiScaleTuning = preload("res://config/ui/ui_scale_tuning.tres")
var _ui_scale: float = 1.0
var _hud_scale: float = 1.0
var _minimap_preset: int = 1
var _rumble_enabled: bool = true
var _rumble_strength: float = 1.0
var _mouse_move_speed_scale: float = DEFAULT_MOUSE_MOVE_SPEED_SCALE
var _stick_move_speed_scale: float = DEFAULT_STICK_MOVE_SPEED_SCALE

## action -> Array of persisted InputEvent overrides for that action (never
## the full InputMap default set).
var _key_overrides: Dictionary[StringName, Array] = {}
## User-level debug-mode switch (game/debug/DebugMode.gd's source 3).
## -1 = never set (fall through to the other sources), 0 = off, 1 = on. Edited
## by hand in user://settings.cfg ([debug] enabled=true); there is no in-game
## menu entry on purpose.
var _debug_setting: int = -1


func _ready() -> void:
	AgentProbe.apply()
	# Sharded GUT gates run several Godot processes at once; they must not share
	# (or clobber) the player's user://settings.cfg. Agent probe runs are
	# isolated the same way (per-PID file, never the player's).
	_gut_run = UserPaths.is_isolated_run()
	if _gut_run:
		_config_path = UserPaths.gut_path(REAL_CONFIG_PATH)
		UserPaths.sweep_stale()
	_load()
	_apply_key_overrides()
	apply_ui_scale()


## The player's last-used input device family: a real keyboard/mouse key or
## button press, or mouse motion beyond MOUSE_MOTION_DEVICE_THRESHOLD_PX, sets DEVICE_KEYBOARD_MOUSE; a real
## gamepad button or a stick/trigger beyond JOYPAD_MOTION_DEVICE_THRESHOLD
## sets DEVICE_GAMEPAD. Starts at DEFAULT_ACTIVE_DEVICE (keyboard/mouse) so a
## fresh session's Controls page shows keyboard bindings before any input.
func active_input_device() -> StringName:
	return _active_device


## Only classifies the raw event; no viewport/Control is involved.
func _input(event: InputEvent) -> void:
	var family: StringName = _classify_device(event)
	if family == &"" or family == _active_device:
		return
	_active_device = family
	Events.input_device_changed.emit(_active_device)


func _classify_device(event: InputEvent) -> StringName:
	if event is InputEventKey or event is InputEventMouseButton:
		return DEVICE_KEYBOARD_MOUSE
	if event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() >= MOUSE_MOTION_DEVICE_THRESHOLD_PX:
			return DEVICE_KEYBOARD_MOUSE
		return &""
	if event is InputEventJoypadButton:
		return DEVICE_GAMEPAD
	if event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) >= JOYPAD_MOTION_DEVICE_THRESHOLD:
			return DEVICE_GAMEPAD
		return &""
	return &""


## The preset consumers should apply: the stored one, with the governor's temporary
## overrides on a duplicate while it has shed steps.
func current_graphics_preset() -> GraphicsPreset:
	return QualityGovernor.apply(stored_graphics_preset(), _governor_level, _governor_config)


## The user's chosen preset exactly as stored (never carries governor
## overrides): the base preset duplicated with the player's overrides applied
## (the base itself when there are none). DECISION: `id` stays the base
## preset's id so consumers that branch on it (e.g. the Low snow look) keep
## working; graphics_preset_is_custom() says Custom.
func stored_graphics_preset() -> GraphicsPreset:
	var base: GraphicsPreset = _load_preset_resource(_current_preset_id)
	if base == null or _graphics_overrides.is_empty():
		return base
	var effective: GraphicsPreset = base.duplicate() as GraphicsPreset
	for field: StringName in _graphics_overrides:
		effective.set(field, _graphics_overrides[field])
	return effective


## True once the player has edited any graphics control away from the chosen base preset.
func graphics_preset_is_custom() -> bool:
	return not _graphics_overrides.is_empty()


## The named preset the effective graphics derive from (Low/Medium/High).
func graphics_base_preset_id() -> StringName:
	return _current_preset_id


## Sets one graphics field (see GRAPHICS_OVERRIDE_FIELDS). A value equal to the base preset's own
## drops the override again; DECISION: a set of edits that happens to equal another named preset
## stays "Custom" (only picking a preset by hand returns to a named one).
func set_graphics_override(field: StringName, value: Variant) -> void:
	if not GRAPHICS_OVERRIDE_FIELDS.has(field):
		push_warning("Settings: graphics field %s is not overridable" % field)
		return
	var base: GraphicsPreset = _load_preset_resource(_current_preset_id)
	if base == null:
		return
	var base_value: Variant = base.get(field)
	var coerced: Variant = _coerce_graphics_value(value, base_value)
	if coerced == null:
		return
	coerced = GraphicsPreset.sanitize(field, coerced)
	if coerced == null:
		return
	if is_equal_approx_variant(coerced, base_value):
		if not _graphics_overrides.has(field):
			return
		_graphics_overrides.erase(field)
	else:
		if _graphics_overrides.has(field) and is_equal_approx_variant(_graphics_overrides[field], coerced):
			return
		_graphics_overrides[field] = coerced
	_save()
	graphics_preset_changed.emit(current_graphics_preset())


## Value of a graphics field in the effective (stored) preset.
func graphics_field_value(field: StringName) -> Variant:
	var preset: GraphicsPreset = stored_graphics_preset()
	return preset.get(field) if preset != null else null


static func is_equal_approx_variant(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_FLOAT:
		return is_equal_approx(float(a), float(b))
	return a == b


## Returns `value` converted to the type of `like` (int/float/bool only), or null if it cannot be.
static func _coerce_graphics_value(value: Variant, like: Variant) -> Variant:
	match typeof(like):
		TYPE_BOOL:
			return bool(value) if typeof(value) == TYPE_BOOL else null
		TYPE_INT:
			return int(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else null
		TYPE_FLOAT:
			return float(value) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else null
	return null


func adaptive_quality_enabled() -> bool:
	return _adaptive_quality


func set_adaptive_quality_enabled(enabled: bool) -> void:
	if enabled == _adaptive_quality:
		return
	_adaptive_quality = enabled
	_save()
	if not enabled:
		set_governor_level(0)
	adaptive_quality_setting_changed.emit(enabled)


## Runtime-only; ignored (forced to 0) while the option is off.
func set_governor_level(level: int) -> void:
	var clamped: int = clampi(level, 0, QualityGovernor.LEVEL_RENDER_SCALE) if _adaptive_quality else 0
	if clamped == _governor_level:
		return
	_governor_level = clamped
	var preset: GraphicsPreset = current_graphics_preset()
	if preset != null:
		graphics_preset_changed.emit(preset)


func set_graphics_preset(id: StringName) -> void:
	var preset: GraphicsPreset = _load_preset_resource(id)
	if preset == null:
		push_warning("Settings: unknown graphics preset id %s" % id)
		return
	_current_preset_id = id
	_graphics_overrides.clear()  # picking a preset resets every control to it.
	_save()
	graphics_preset_changed.emit(current_graphics_preset())


# --- Audio channels ----------------------------------------------------------
## Master/Music/SFX volume sliders + mute toggles. Master multiplies every
## channel (autoload/Sfx.gd adds master_volume_db() to every player's own
## baseline); music_volume_db()/sfx_volume_db() additionally scale only their
## own channel, never each other.

func master_volume_percent() -> float:
	return _channel_volume_percent[AudioChannel.MASTER]


func set_master_volume_percent(percent: float) -> void:
	_set_channel_volume_percent(AudioChannel.MASTER, percent)


## Computed from master_volume_percent()/master_muted() rather than stored
## directly -- see SILENT_VOLUME_DB's own doc for the muted/0% case.
func master_volume_db() -> float:
	return _channel_volume_db(AudioChannel.MASTER)


func master_muted() -> bool:
	return _channel_muted[AudioChannel.MASTER]


func set_master_muted(muted: bool) -> void:
	_set_channel_muted(AudioChannel.MASTER, muted)


func toggle_master_mute() -> void:
	set_master_muted(not master_muted())


func music_volume_percent() -> float:
	return _channel_volume_percent[AudioChannel.MUSIC]


func set_music_volume_percent(percent: float) -> void:
	_set_channel_volume_percent(AudioChannel.MUSIC, percent)


func music_volume_db() -> float:
	return _channel_volume_db(AudioChannel.MUSIC)


func music_muted() -> bool:
	return _channel_muted[AudioChannel.MUSIC]


func set_music_muted(muted: bool) -> void:
	_set_channel_muted(AudioChannel.MUSIC, muted)


func toggle_music_mute() -> void:
	set_music_muted(not music_muted())


func sfx_volume_percent() -> float:
	return _channel_volume_percent[AudioChannel.SFX]


func set_sfx_volume_percent(percent: float) -> void:
	_set_channel_volume_percent(AudioChannel.SFX, percent)


func sfx_volume_db() -> float:
	return _channel_volume_db(AudioChannel.SFX)


func sfx_muted() -> bool:
	return _channel_muted[AudioChannel.SFX]


func set_sfx_muted(muted: bool) -> void:
	_set_channel_muted(AudioChannel.SFX, muted)


func toggle_sfx_mute() -> void:
	set_sfx_muted(not sfx_muted())


## Weather channel: weather ambience loops and gust whoosh.
## Scales only itself (plus Master), never the SFX slider.
func weather_volume_percent() -> float:
	return _channel_volume_percent[AudioChannel.WEATHER]


func set_weather_volume_percent(percent: float) -> void:
	_set_channel_volume_percent(AudioChannel.WEATHER, percent)


func weather_volume_db() -> float:
	return _channel_volume_db(AudioChannel.WEATHER)


func weather_muted() -> bool:
	return _channel_muted[AudioChannel.WEATHER]


func set_weather_muted(muted: bool) -> void:
	_set_channel_muted(AudioChannel.WEATHER, muted)


func toggle_weather_mute() -> void:
	set_weather_muted(not weather_muted())


## ui/menus/OptionsMenu.gd's ResetButton: every channel back to 100%, unmuted.
func reset_audio_settings() -> void:
	for channel: AudioChannel in [AudioChannel.MASTER, AudioChannel.MUSIC, AudioChannel.SFX, AudioChannel.WEATHER]:
		_channel_volume_percent[channel] = DEFAULT_VOLUME_PERCENT
		_channel_muted[channel] = false
	_save()
	audio_settings_changed.emit()


func _set_channel_volume_percent(channel: AudioChannel, percent: float) -> void:
	var clamped: float = clampf(percent, 0.0, 1.0)
	_channel_volume_percent[channel] = clamped
	# DECISION (autoload/Settings.gd): dragging the slider above 0% implies
	# the player wants to hear this channel again (the "moving the fader
	# unmutes it" behaviour of a mixing console); nothing else un-mutes a
	# channel on its own.
	if clamped > 0.0 and _channel_muted[channel]:
		_channel_muted[channel] = false
	_save()
	audio_settings_changed.emit()


func _set_channel_muted(channel: AudioChannel, muted: bool) -> void:
	if muted == _channel_muted[channel]:
		return
	_channel_muted[channel] = muted
	_save()
	audio_settings_changed.emit()


## SILENT_VOLUME_DB while muted or at 0%; linear_to_db() of the stored percent otherwise.
func _channel_volume_db(channel: AudioChannel) -> float:
	var percent: float = _channel_volume_percent[channel]
	if _channel_muted[channel] or percent <= 0.0:
		return SILENT_VOLUME_DB
	return linear_to_db(percent)


## The local player's saved display name, "" when never set.
## ui/menus/MainMenu.gd prefills its name field from this and writes every edit back,
## so the name survives page changes, a rebuilt menu and a restart.
func player_name() -> String:
	return _player_name


## Cleans (control characters, trim, max length) and persists `typed`.
func set_player_name(typed: String) -> void:
	var cleaned: String = PlayerNames.clean(typed, _net_config.max_player_name_length)
	if cleaned == _player_name:
		return
	_player_name = cleaned
	_save()
	player_name_changed.emit(_player_name)


## Spec 1.10 "camera shake": read directly by game/player/CameraRig.gd.
func camera_shake_enabled() -> bool:
	return _camera_shake_enabled


func set_camera_shake_enabled(enabled: bool) -> void:
	_camera_shake_enabled = enabled
	_save()
	camera_shake_setting_changed.emit(enabled)


## The player's field of view in degrees, or 0.0 when never chosen.
## DECISION (autoload/Settings.gd): an optional override rather than a second default, so the
## F4 CameraTuning.fov_deg slider stays the baseline until a player picks a value in Options;
## game/player/CameraRig.gd applies this over the tuning value.
func fov_override_deg() -> float:
	return _fov_override_deg


## Applies live (game/player/CameraRig.gd listens and clamps to the CameraTuning range; kept out of
## here so config/player/CameraTuning.gd stays out of the autoload closure, lint_layers L3).
func set_fov_override_deg(degrees: float) -> void:
	_fov_override_deg = maxf(degrees, 0.0)
	_save()
	fov_override_changed.emit(_fov_override_deg)


func reset_fov_override() -> void:
	_fov_override_deg = 0.0
	_save()
	fov_override_changed.emit(_fov_override_deg)


## Read directly by autoload/Rumble.gd, like camera_shake_enabled() above.
func rumble_enabled() -> bool:
	return _rumble_enabled


func set_rumble_enabled(enabled: bool) -> void:
	_rumble_enabled = enabled
	_save()
	rumble_setting_changed.emit(_rumble_enabled, _rumble_strength)


## 0..1, clamped; the range config/player/RumbleConfig.gd's
## global_strength_scale default seeds this from.
func rumble_strength() -> float:
	return _rumble_strength


func set_rumble_strength(strength: float) -> void:
	_rumble_strength = clampf(strength, 0.0, 1.0)
	_save()
	rumble_setting_changed.emit(_rumble_enabled, _rumble_strength)


## ui/menus/OptionsMenu.gd's ResetButton.
func reset_rumble_settings() -> void:
	_rumble_enabled = _rumble_defaults.enabled_by_default
	_rumble_strength = _rumble_defaults.global_strength_scale
	_save()
	rumble_setting_changed.emit(_rumble_enabled, _rumble_strength)


# --- Block movement speed ----------------------------------------------------
## Two independent feel multipliers game/player/PlayerController.gd applies:
## mouse_move_speed_scale to the mouse cursor's block_move_sensitivity,
## stick_move_speed_scale to the gamepad cursor's max speed. Kept separate
## since a mouse and a gamepad player tune their own device's feel
## independently; 1.0 = the tuning Resource's own untouched default for either.

func mouse_move_speed_scale() -> float:
	return _mouse_move_speed_scale


func set_mouse_move_speed_scale(scale: float) -> void:
	# DECISION (autoload/Settings.gd): the designed range (the Options slider's
	# min/max) lives in ui/menus/OptionsMenu.gd (see its DECISION); this clamp is only a generic
	# safety floor so a scale can never reach zero or negative and stall or
	# invert cursor movement.
	_mouse_move_speed_scale = clampf(scale, 0.01, 10.0)
	_save()


func stick_move_speed_scale() -> float:
	return _stick_move_speed_scale


func set_stick_move_speed_scale(scale: float) -> void:
	_stick_move_speed_scale = clampf(scale, 0.01, 10.0)
	_save()


func reset_move_speed_scales() -> void:
	_mouse_move_speed_scale = DEFAULT_MOUSE_MOVE_SPEED_SCALE
	_stick_move_speed_scale = DEFAULT_STICK_MOVE_SPEED_SCALE
	_save()


## The player's UI scale, RELATIVE to the design-mockup scale (1.0 = mockup).
func ui_scale() -> float:
	return _ui_scale


## Sanitizes (UiScaleTuning range + step), persists, applies live and emits ui_scale_changed.
func set_ui_scale(value: float) -> void:
	_ui_scale = _ui_scale_tuning.sanitize(value)
	_save()
	apply_ui_scale()
	ui_scale_changed.emit(_ui_scale)


func reset_ui_scale() -> void:
	set_ui_scale(_ui_scale_tuning.default_scale)


## The in-match HUD scale (separate from the UI scale; same range and step).
func hud_scale() -> float:
	return _hud_scale


## `persist` false applies live without writing the file (a slider drag); the menu saves once on release.
func set_hud_scale(value: float, persist: bool = true) -> void:
	_hud_scale = _ui_scale_tuning.sanitize(value)
	UiScaleTuning.current_hud_scale = _hud_scale
	if persist:
		_save()
	hud_scale_changed.emit(_hud_scale)


func reset_hud_scale() -> void:
	set_hud_scale(_ui_scale_tuning.default_scale)


## Minimap size preset index into UiScaleTuning.minimap_size_presets_px.
func minimap_size_preset() -> int:
	return _minimap_preset


func set_minimap_size_preset(index: int) -> void:
	_minimap_preset = _ui_scale_tuning.sanitize_minimap_preset(index)
	UiScaleTuning.current_minimap_preset = _minimap_preset
	_save()
	minimap_size_changed.emit(_minimap_preset)


func reset_minimap_size() -> void:
	set_minimap_size_preset(_ui_scale_tuning.minimap_default_preset)


## DECISION: one knob, Window.content_scale_factor of the root window, which the
## engine multiplies onto the project stretch (canvas_items, expand): the UI canvas shrinks/grows,
## 3D rendering, cameras and Label3D are untouched. Isolated runs (GUT, agent probes) never touch the
## real window; they only publish the value to UiScaleTuning.current_scale, which ui/theme/UiScale.gd's
## SubViewport emulation reads.
func apply_ui_scale() -> void:
	UiScaleTuning.current_scale = _ui_scale
	UiScaleTuning.current_hud_scale = _hud_scale
	UiScaleTuning.current_minimap_preset = _minimap_preset
	if _gut_run:
		return
	var tree: SceneTree = get_tree()
	if tree != null and tree.root != null:
		tree.root.content_scale_factor = _ui_scale_tuning.effective_factor(_ui_scale)


## The persisted window-mode id. Defaults to DEFAULT_WINDOW_MODE_ID
## (borderless fullscreen) when user://settings.cfg has never stored one.
func window_mode() -> StringName:
	return _window_mode_id


## Validates `id` against WINDOW_MODE_IDS, persists it, emits
## window_mode_changed(id) and applies it immediately via apply_window_mode();
## game/main/Main.gd only calls apply_window_mode() once at boot for the
## persisted value.
func set_window_mode(id: StringName) -> void:
	if not WINDOW_MODE_IDS.has(id):
		push_warning("Settings: unknown window mode id %s" % id)
		return
	_window_mode_id = id
	_save()
	window_mode_changed.emit(id)
	apply_window_mode()


## Human-readable label for `id`, for the OptionButton. Returns the raw id
## string if it is missing from WINDOW_MODE_LABELS, so a stale/unknown
## persisted id still gets something printable.
func window_mode_label(id: StringName) -> String:
	return WINDOW_MODE_LABELS.get(id, String(id))


## Applies the current window_mode() to the real OS window via DisplayServer.
## Safe to call any number of times (idempotent: re-applying the same mode is
## just redundant DisplayServer calls, not observable state churn).
##
## Guarded so it is a no-op whenever there is no real player window to change:
##  - DisplayServer.get_name() == "headless": no window exists at all (every
##    GUT test run, CI, `--headless-host` bot matches).
##  - Engine.is_editor_hint(): the script is running inside the editor itself
##    (tool mode), which owns its own window. Not OS.has_feature("editor"):
##    that is true for every run from this repo's editor binary, including
##    `godot --path .` launches, and would make the setting inert until an
##    export template exists.
##  - `--position`, `--windowed` or `-w` in OS.get_cmdline_args(): an explicit
##    windowed/off-screen CLI request wins over the saved mode. Our own
##    screenshot/probe tools launch with `--windowed --position 10000,10000`
##    specifically so a run never appears on the user's monitor; forcing
##    fullscreen would undo that.
func apply_window_mode() -> void:
	if not _can_apply_window_mode():
		return
	match _window_mode_id:
		WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		WINDOW_MODE_BORDERLESS_FULLSCREEN:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			_restore_windowed_size_and_center()
		_:
			push_warning("Settings: apply_window_mode() has no case for id %s" % _window_mode_id)


func _can_apply_window_mode() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if AgentProbe.is_active():
		return false
	if Engine.is_editor_hint():
		return false
	var args: PackedStringArray = OS.get_cmdline_args()
	if args.has("--position") or args.has("--windowed") or args.has("-w"):
		return false
	# DECISION: Godot consumes its own window flags (--position, --windowed)
	# before OS.get_cmdline_args(), so the check above never fires for the
	# off-screen tool runs. A run that names a scene on the command line
	# (tools/*.tscn, the editor's "Run Current Scene") keeps the project's
	# windowed default instead of the saved fullscreen mode; plain
	# `godot --path .` launches still honour the saved mode.
	for arg: String in args:
		if arg.ends_with(".tscn") or arg.ends_with(".scn"):
			return false
	return true


## Windowed mode's fallback size/position: the size ProjectSettings already
## declares (display/window/size/viewport_width|height), not a magic literal
## duplicated here. Centered via Window.move_to_center() rather than a
## hand-computed screen-size/2 - window-size/2, which would double-count
## whatever DisplayServer.screen_get_size() reports.
func _restore_windowed_size_and_center() -> void:
	var window: Window = get_window()
	if window == null:
		return
	var width: int = int(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var height: int = int(ProjectSettings.get_setting("display/window/size/viewport_height"))
	window.size = Vector2i(width, height)
	window.move_to_center()


## DECISION: overrides are device-class aware (keyboard/mouse vs. gamepad) so
## that remapping one class never deletes the other's bootstrap default (every
## action keeps both a keyboard/mouse and a gamepad binding).
## _key_overrides[action] holds at most one event per class; a new override
## only replaces the stored (and applied) event of the same class.
func set_key_override(action: StringName, event: InputEvent) -> void:
	var stored: Array = _key_overrides.get(action, [])
	var is_gamepad: bool = _is_gamepad_event(event)
	var kept: Array = []
	for item: Variant in stored:
		if item is InputEvent and _is_gamepad_event(item as InputEvent) != is_gamepad:
			kept.append(item)
	kept.append(event)
	_key_overrides[action] = kept
	_apply_single_override(action, event)
	_save()


## Clears every persisted override and reloads the InputMap straight from
## project.godot's [input] section (the bindings tools/bootstrap_project.gd
## wrote), undoing every runtime action_erase_event()/action_add_event() a
## rebind made, without remembering each action's original event.
func reset_key_overrides() -> void:
	_key_overrides.clear()
	InputMap.load_from_project_settings()
	_save()


## Applies every InputMap override from user://settings.cfg. Called once from
## _ready(); never edits project.godot's [input] section -- overrides layer on
## top via InputMap.action_erase_event()/action_add_event() at runtime, one
## device class at a time.
func _apply_key_overrides() -> void:
	for action: StringName in _key_overrides.keys():
		_apply_override(action, _key_overrides[action])


func _apply_override(action: StringName, events: Array) -> void:
	if not InputMap.has_action(action):
		return
	for item: Variant in events:
		if item is InputEvent:
			_apply_single_override(action, item as InputEvent)


## Erases only the action's existing events of the same device class as
## `event` (keyboard/mouse vs. gamepad), then adds `event` -- the other
## class's binding (bootstrap default or its own override) is left in place.
func _apply_single_override(action: StringName, event: InputEvent) -> void:
	var is_gamepad: bool = _is_gamepad_event(event)
	var existing: Array[InputEvent] = InputMap.action_get_events(action)
	for existing_event: InputEvent in existing:
		if _is_gamepad_event(existing_event) == is_gamepad:
			InputMap.action_erase_event(action, existing_event)
	InputMap.action_add_event(action, event)


func _is_gamepad_event(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


## The one path every settings read/write/delete uses. In a GUT run the real
## player file is unreachable: REAL_CONFIG_PATH maps to the per-PID GUT file.
func effective_path() -> String:
	return _config_path


# --- Persistence --------------------------------------------------------------

## See _debug_setting. -1 when the user never set it.
func debug_setting() -> int:
	return _debug_setting


func _load() -> void:
	_debug_setting = -1
	_current_preset_id = DEFAULT_PRESET_ID
	_graphics_overrides.clear()
	_adaptive_quality = DEFAULT_ADAPTIVE_QUALITY
	_governor_level = 0
	_channel_volume_percent = {
		AudioChannel.MASTER: DEFAULT_VOLUME_PERCENT,
		AudioChannel.MUSIC: DEFAULT_VOLUME_PERCENT,
		AudioChannel.SFX: DEFAULT_VOLUME_PERCENT,
		AudioChannel.WEATHER: DEFAULT_VOLUME_PERCENT,
	}
	_channel_muted = {
		AudioChannel.MASTER: false,
		AudioChannel.MUSIC: false,
		AudioChannel.SFX: false,
		AudioChannel.WEATHER: false,
	}
	_player_name = ""
	_camera_shake_enabled = DEFAULT_CAMERA_SHAKE_ENABLED
	_fov_override_deg = 0.0
	_window_mode_id = DEFAULT_WINDOW_MODE_ID
	_ui_scale = _ui_scale_tuning.default_scale
	_hud_scale = _ui_scale_tuning.default_scale
	_minimap_preset = _ui_scale_tuning.minimap_default_preset
	_rumble_enabled = _rumble_defaults.enabled_by_default
	_rumble_strength = _rumble_defaults.global_strength_scale
	_mouse_move_speed_scale = DEFAULT_MOUSE_MOVE_SPEED_SCALE
	_stick_move_speed_scale = DEFAULT_STICK_MOVE_SPEED_SCALE
	_key_overrides.clear()

	var cfg: ConfigFile = ConfigFile.new()
	var err: Error = cfg.load(effective_path())
	if err != OK:
		return  # No file yet (or unreadable): every default above stands.

	_current_preset_id = StringName(cfg.get_value(SECTION_GRAPHICS, KEY_PRESET, DEFAULT_PRESET_ID))
	_adaptive_quality = bool(cfg.get_value(SECTION_GRAPHICS, KEY_ADAPTIVE_QUALITY, DEFAULT_ADAPTIVE_QUALITY))
	_load_graphics_overrides(cfg)

	if cfg.has_section_key(SECTION_AUDIO, KEY_MASTER_VOLUME_PERCENT):
		_channel_volume_percent[AudioChannel.MASTER] = clampf(
			float(cfg.get_value(SECTION_AUDIO, KEY_MASTER_VOLUME_PERCENT, DEFAULT_VOLUME_PERCENT)), 0.0, 1.0
		)
	_channel_muted[AudioChannel.MASTER] = bool(cfg.get_value(SECTION_AUDIO, KEY_MASTER_MUTED, false))
	_channel_volume_percent[AudioChannel.MUSIC] = clampf(
		float(cfg.get_value(SECTION_AUDIO, KEY_MUSIC_VOLUME_PERCENT, DEFAULT_VOLUME_PERCENT)), 0.0, 1.0
	)
	_channel_muted[AudioChannel.MUSIC] = bool(cfg.get_value(SECTION_AUDIO, KEY_MUSIC_MUTED, false))
	_channel_volume_percent[AudioChannel.SFX] = clampf(
		float(cfg.get_value(SECTION_AUDIO, KEY_SFX_VOLUME_PERCENT, DEFAULT_VOLUME_PERCENT)), 0.0, 1.0
	)
	_channel_muted[AudioChannel.SFX] = bool(cfg.get_value(SECTION_AUDIO, KEY_SFX_MUTED, false))

	_channel_volume_percent[AudioChannel.WEATHER] = clampf(
		float(cfg.get_value(SECTION_AUDIO, KEY_WEATHER_VOLUME_PERCENT, DEFAULT_VOLUME_PERCENT)), 0.0, 1.0
	)
	_channel_muted[AudioChannel.WEATHER] = bool(cfg.get_value(SECTION_AUDIO, KEY_WEATHER_MUTED, false))
	_player_name = PlayerNames.clean(
		String(cfg.get_value(SECTION_PLAYER, KEY_PLAYER_NAME, "")), _net_config.max_player_name_length
	)
	_camera_shake_enabled = bool(cfg.get_value(SECTION_GRAPHICS, KEY_CAMERA_SHAKE_ENABLED, DEFAULT_CAMERA_SHAKE_ENABLED))
	_fov_override_deg = maxf(float(cfg.get_value(SECTION_GRAPHICS, KEY_FOV_OVERRIDE_DEG, 0.0)), 0.0)
	var loaded_window_mode_id: StringName = StringName(cfg.get_value(SECTION_GRAPHICS, KEY_WINDOW_MODE, DEFAULT_WINDOW_MODE_ID))
	if WINDOW_MODE_IDS.has(loaded_window_mode_id):
		_window_mode_id = loaded_window_mode_id
	_ui_scale = _ui_scale_tuning.sanitize(
		float(cfg.get_value(SECTION_GRAPHICS, KEY_UI_SCALE, _ui_scale_tuning.default_scale))
	)
	# Migration: a save without a HUD scale keeps the HUD at its old (UI-scaled) size.
	_hud_scale = _ui_scale_tuning.sanitize(
		float(cfg.get_value(SECTION_GRAPHICS, KEY_HUD_SCALE, _ui_scale))
	)
	_minimap_preset = _ui_scale_tuning.sanitize_minimap_preset(
		int(cfg.get_value(SECTION_GRAPHICS, KEY_MINIMAP_SIZE, _ui_scale_tuning.minimap_default_preset))
	)
	_rumble_enabled = bool(cfg.get_value(SECTION_GAMEPAD, KEY_RUMBLE_ENABLED, _rumble_defaults.enabled_by_default))
	_rumble_strength = clampf(
		float(cfg.get_value(SECTION_GAMEPAD, KEY_RUMBLE_STRENGTH, _rumble_defaults.global_strength_scale)), 0.0, 1.0
	)
	_mouse_move_speed_scale = clampf(
		float(cfg.get_value(SECTION_CONTROLS, KEY_MOUSE_MOVE_SPEED_SCALE, DEFAULT_MOUSE_MOVE_SPEED_SCALE)), 0.01, 10.0
	)
	_stick_move_speed_scale = clampf(
		float(cfg.get_value(SECTION_CONTROLS, KEY_STICK_MOVE_SPEED_SCALE, DEFAULT_STICK_MOVE_SPEED_SCALE)), 0.01, 10.0
	)
	# DECISION: there is no settings-version mechanism, so a minimal per-key
	# basis marker is used. A stored stick scale without it is
	# relative to the old base speed: divide by the ratio, clamped to the slider.
	if cfg.has_section_key(SECTION_CONTROLS, KEY_STICK_MOVE_SPEED_SCALE) 			and int(cfg.get_value(SECTION_CONTROLS, KEY_STICK_SPEED_BASIS, 1)) < STICK_SPEED_BASIS_CURRENT:
		_stick_move_speed_scale = clampf(
			_stick_move_speed_scale / STICK_SPEED_BASE_RATIO, STICK_SPEED_MIGRATED_MIN, STICK_SPEED_MIGRATED_MAX
		)

	if cfg.has_section_key(SECTION_DEBUG, KEY_DEBUG_ENABLED):
		_debug_setting = 1 if bool(cfg.get_value(SECTION_DEBUG, KEY_DEBUG_ENABLED, false)) else 0

	if cfg.has_section(SECTION_INPUT):
		for action_key: String in cfg.get_section_keys(SECTION_INPUT):
			var raw: Variant = cfg.get_value(SECTION_INPUT, action_key)
			if raw is Array:
				_key_overrides[StringName(action_key)] = raw as Array


func _save() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(SECTION_GRAPHICS, KEY_PRESET, String(_current_preset_id))
	if not _graphics_overrides.is_empty():
		cfg.set_value(SECTION_GRAPHICS, KEY_GRAPHICS_OVERRIDES, _graphics_overrides)
	cfg.set_value(SECTION_GRAPHICS, KEY_ADAPTIVE_QUALITY, _adaptive_quality)
	cfg.set_value(SECTION_GRAPHICS, KEY_CAMERA_SHAKE_ENABLED, _camera_shake_enabled)
	cfg.set_value(SECTION_GRAPHICS, KEY_FOV_OVERRIDE_DEG, _fov_override_deg)
	cfg.set_value(SECTION_GRAPHICS, KEY_WINDOW_MODE, String(_window_mode_id))
	cfg.set_value(SECTION_GRAPHICS, KEY_UI_SCALE, _ui_scale)
	cfg.set_value(SECTION_GRAPHICS, KEY_HUD_SCALE, _hud_scale)
	cfg.set_value(SECTION_GRAPHICS, KEY_MINIMAP_SIZE, _minimap_preset)
	cfg.set_value(SECTION_GAMEPAD, KEY_RUMBLE_ENABLED, _rumble_enabled)
	cfg.set_value(SECTION_GAMEPAD, KEY_RUMBLE_STRENGTH, _rumble_strength)
	cfg.set_value(SECTION_AUDIO, KEY_MASTER_VOLUME_PERCENT, _channel_volume_percent[AudioChannel.MASTER])
	cfg.set_value(SECTION_AUDIO, KEY_MASTER_MUTED, _channel_muted[AudioChannel.MASTER])
	cfg.set_value(SECTION_AUDIO, KEY_MUSIC_VOLUME_PERCENT, _channel_volume_percent[AudioChannel.MUSIC])
	cfg.set_value(SECTION_AUDIO, KEY_MUSIC_MUTED, _channel_muted[AudioChannel.MUSIC])
	cfg.set_value(SECTION_AUDIO, KEY_SFX_VOLUME_PERCENT, _channel_volume_percent[AudioChannel.SFX])
	cfg.set_value(SECTION_AUDIO, KEY_SFX_MUTED, _channel_muted[AudioChannel.SFX])
	cfg.set_value(SECTION_AUDIO, KEY_WEATHER_VOLUME_PERCENT, _channel_volume_percent[AudioChannel.WEATHER])
	cfg.set_value(SECTION_AUDIO, KEY_WEATHER_MUTED, _channel_muted[AudioChannel.WEATHER])
	cfg.set_value(SECTION_PLAYER, KEY_PLAYER_NAME, _player_name)
	cfg.set_value(SECTION_CONTROLS, KEY_MOUSE_MOVE_SPEED_SCALE, _mouse_move_speed_scale)
	cfg.set_value(SECTION_CONTROLS, KEY_STICK_MOVE_SPEED_SCALE, _stick_move_speed_scale)
	cfg.set_value(SECTION_CONTROLS, KEY_STICK_SPEED_BASIS, STICK_SPEED_BASIS_CURRENT)
	if _debug_setting >= 0:
		cfg.set_value(SECTION_DEBUG, KEY_DEBUG_ENABLED, _debug_setting == 1)
	for action: StringName in _key_overrides.keys():
		cfg.set_value(SECTION_INPUT, String(action), _key_overrides[action])
	if not UserPaths.persistence_allowed():
		return
	var err: Error = cfg.save(effective_path())
	if err != OK:
		push_warning("Settings: failed to save %s (error %d)" % [effective_path(), err])


## Old files have no overrides key (load unchanged); unknown fields, mistyped values and invalid enum values are dropped; numbers are clamped.
func _load_graphics_overrides(cfg: ConfigFile) -> void:
	var raw: Variant = cfg.get_value(SECTION_GRAPHICS, KEY_GRAPHICS_OVERRIDES, {})
	var base: GraphicsPreset = _load_preset_resource(_current_preset_id)
	if not raw is Dictionary or base == null:
		return
	for key: Variant in (raw as Dictionary):
		var field: StringName = StringName(String(key))
		if not GRAPHICS_OVERRIDE_FIELDS.has(field):
			continue
		var base_value: Variant = base.get(field)
		var coerced: Variant = _coerce_graphics_value((raw as Dictionary)[key], base_value)
		if coerced != null:
			coerced = GraphicsPreset.sanitize(field, coerced)  # drop bogus enums, clamp ranges
		if coerced != null and not is_equal_approx_variant(coerced, base_value):
			_graphics_overrides[field] = coerced


func _load_preset_resource(id: StringName) -> GraphicsPreset:
	var path: String = PRESETS_DIR.path_join(String(id) + ".tres")
	if not ResourceLoader.exists(path):
		return null
	return load(path) as GraphicsPreset
