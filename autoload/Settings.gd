extends Node
## User settings: graphics preset, audio levels, control bindings, music folder.
##
## Persisted to a single user://settings.cfg ConfigFile, loaded once in
## _ready() (this autoload already runs before any scene, project.godot's
## [autoload] section) and saved on every setter -- small, infrequent
## writes, no debouncing needed (docs/M6_PLAN.md package C1).
##
## Settings only stores the user's choices and emits signals; it never
## touches a Viewport/Environment or plays audio itself -- C2 (options menu)
## and later consumers apply graphics_preset_changed/audio_settings_changed
## to the actual render/audio state.

signal graphics_preset_changed(preset: GraphicsPreset)
signal audio_settings_changed()
signal camera_shake_setting_changed(enabled: bool)
signal window_mode_changed(id: StringName)

## autoload/Rumble.gd reads rumble_enabled()/rumble_strength() directly (the
## same camera_shake_enabled() precedent); this fires so a future
## ui/OptionsMenu.gd row can live-update without polling.
signal rumble_setting_changed(enabled: bool, strength: float)

const DEFAULT_PRESET_ID: StringName = &"medium"
const PRESETS_DIR: String = "res://config/graphics_presets/"

## Bontago-1pi.10 (owner: "default to only showing mouse/keyboard, switch to
## showing only gamepad options on gamepad input and switch back on mouse/
## keyboard input"). ui/OptionsMenu.gd's Controls page and ui/KeyRebindRow.gd
## read active_input_device() to decide which device's binding glyphs to
## show; Events.input_device_changed lets both live-swap without reopening
## the menu.
const DEVICE_KEYBOARD_MOUSE: StringName = &"keyboard_mouse"
const DEVICE_GAMEPAD: StringName = &"gamepad"
const DEFAULT_ACTIVE_DEVICE: StringName = DEVICE_KEYBOARD_MOUSE

## DECISION (Bontago-1pi.10): a UI-feel/detection threshold, not gameplay or
## physics tuning (CLAUDE.md's no-magic-numbers rule targets those), the same
## reasoning ui/OptionsMenu.gd's own MIN_VOLUME_DB/MAX_VOLUME_DB DECISION
## gives for a plain script const instead of a config/*.tres Resource.
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

const KEY_PRESET: String = "preset"
const KEY_MASTER_DB: String = "master_db"
const KEY_CUSTOM_MUSIC_DIR: String = "custom_music_dir"
const KEY_CAMERA_SHAKE_ENABLED: String = "camera_shake_enabled"
const KEY_WINDOW_MODE: String = "window_mode"
const KEY_RUMBLE_ENABLED: String = "rumble_enabled"
const KEY_RUMBLE_STRENGTH: String = "rumble_strength"

## Bontago-xtq.45 (M7 P4): the three player-facing window modes, exclusive
## fullscreen, borderless fullscreen and windowed. Ids are StringName rather
## than a real GDScript enum so they persist to ConfigFile directly (same
## pattern as _current_preset_id) and so a future ui/OptionsMenu.gd
## OptionButton can iterate WINDOW_MODE_IDS without depending on this
## script's enum type.
const WINDOW_MODE_FULLSCREEN: StringName = &"fullscreen"
const WINDOW_MODE_BORDERLESS_FULLSCREEN: StringName = &"borderless_fullscreen"
const WINDOW_MODE_WINDOWED: StringName = &"windowed"

## Owner request (Bontago-xtq.45): borderless fullscreen is the default.
const DEFAULT_WINDOW_MODE_ID: StringName = WINDOW_MODE_BORDERLESS_FULLSCREEN

## Display order for the future OptionButton (ui/OptionsMenu.gd, a separate
## package) -- exclusive fullscreen, then borderless fullscreen, then windowed.
const WINDOW_MODE_IDS: Array[StringName] = [
	WINDOW_MODE_FULLSCREEN,
	WINDOW_MODE_BORDERLESS_FULLSCREEN,
	WINDOW_MODE_WINDOWED,
]

## Human-readable labels for WINDOW_MODE_IDS, keyed the same way -- the future
## OptionButton reads window_mode_label(id) rather than hand-rolling display
## strings next to this script's own ids.
const WINDOW_MODE_LABELS: Dictionary[StringName, String] = {
	WINDOW_MODE_FULLSCREEN: "Fullscreen",
	WINDOW_MODE_BORDERLESS_FULLSCREEN: "Borderless Fullscreen",
	WINDOW_MODE_WINDOWED: "Windowed",
}

## Bontago-xtq.29 (M7 P4): default on -- matches the shake game/CameraRig.gd
## already applies before the player ever opens Options, so a fresh install
## shows the intended feel rather than a silent off-by-default.
const DEFAULT_CAMERA_SHAKE_ENABLED: bool = true

## Bontago (rumble package): the single source of truth for a fresh install's
## rumble defaults -- see config/RumbleConfig.gd's own DECISION comment. Once
## user://settings.cfg has a [gamepad] section, _load() never reads these
## fields again.
var _rumble_defaults: RumbleConfig = preload("res://config/rumble_config.tres")

var _config_path: String = "user://settings.cfg"
var _current_preset_id: StringName = DEFAULT_PRESET_ID
var _master_volume_db: float = 0.0
var _custom_music_dir: String = ""
var _camera_shake_enabled: bool = DEFAULT_CAMERA_SHAKE_ENABLED
var _window_mode_id: StringName = DEFAULT_WINDOW_MODE_ID
var _rumble_enabled: bool = true
var _rumble_strength: float = 1.0

## action -> Array of persisted InputEvent overrides for that action (never
## the full InputMap default set -- key_override_events() answers "what has
## the user overridden", not "what is bound").
var _key_overrides: Dictionary[StringName, Array] = {}


func _ready() -> void:
	_load()
	_apply_key_overrides()


## The player's last-used input device family (Bontago-1pi.10): real keyboard/
## mouse key or button press, or mouse motion beyond
## MOUSE_MOTION_DEVICE_THRESHOLD_PX, sets DEVICE_KEYBOARD_MOUSE; a real
## gamepad button or a stick/trigger beyond JOYPAD_MOTION_DEVICE_THRESHOLD
## sets DEVICE_GAMEPAD. Starts at DEFAULT_ACTIVE_DEVICE (keyboard/mouse) so a
## fresh session's Controls page shows keyboard bindings before any input.
func active_input_device() -> StringName:
	return _active_device


## Settings is a plain autoload Node (project.godot's [autoload] section), so
## it receives _input() for every node in the tree the same as any other --
## no viewport/Control involved, this only ever classifies the raw event.
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


## Test seam: forces the active device without pushing a real InputEvent
## through Input.parse_input_event() (the same "inject state GUT can't
## otherwise reach" role set_config_path_for_test() plays below).
func set_active_input_device_for_test(family: StringName) -> void:
	if family == _active_device:
		return
	_active_device = family
	Events.input_device_changed.emit(_active_device)


func current_graphics_preset() -> GraphicsPreset:
	return _load_preset_resource(_current_preset_id)


func set_graphics_preset(id: StringName) -> void:
	var preset: GraphicsPreset = _load_preset_resource(id)
	if preset == null:
		push_warning("Settings: unknown graphics preset id %s" % id)
		return
	_current_preset_id = id
	_save()
	graphics_preset_changed.emit(preset)


func master_volume_db() -> float:
	return _master_volume_db


func set_master_volume_db(db: float) -> void:
	_master_volume_db = db
	_save()
	audio_settings_changed.emit()


## "" means: use the bundled folder (no custom override).
func custom_music_dir() -> String:
	return _custom_music_dir


func set_custom_music_dir(path: String) -> void:
	_custom_music_dir = path
	_save()
	audio_settings_changed.emit()


## Bontago-xtq.29 (M7 P4, spec 2.10 "camera shake"): read directly by
## game/CameraRig.gd (autoload/Sfx.gd's own master_volume_db()/
## custom_music_dir() precedent -- a plain-bool feel setting, not something
## that needs a per-test provider seam the way ui/OptionsMenu.gd's InputMap
## rebinding does).
func camera_shake_enabled() -> bool:
	return _camera_shake_enabled


func set_camera_shake_enabled(enabled: bool) -> void:
	_camera_shake_enabled = enabled
	_save()
	camera_shake_setting_changed.emit(enabled)


## Bontago (rumble package): read directly by autoload/Rumble.gd, the same
## way camera_shake_enabled() above is read directly by game/CameraRig.gd.
## No Options menu row yet -- ui/OptionsMenu.gd ownership is a separate,
## in-flight package; follow-up work adds the row and calls these setters.
func rumble_enabled() -> bool:
	return _rumble_enabled


func set_rumble_enabled(enabled: bool) -> void:
	_rumble_enabled = enabled
	_save()
	rumble_setting_changed.emit(_rumble_enabled, _rumble_strength)


## 0..1, clamped -- the same range config/RumbleConfig.gd's
## global_strength_scale default seeds this from.
func rumble_strength() -> float:
	return _rumble_strength


func set_rumble_strength(strength: float) -> void:
	_rumble_strength = clampf(strength, 0.0, 1.0)
	_save()
	rumble_setting_changed.emit(_rumble_enabled, _rumble_strength)


## Bontago-xtq.45 (M7 P4): the persisted window-mode id. Defaults to
## DEFAULT_WINDOW_MODE_ID (borderless fullscreen) when user://settings.cfg has
## never stored one.
func window_mode() -> StringName:
	return _window_mode_id


## Validates `id` against WINDOW_MODE_IDS, persists it, emits
## window_mode_changed(id) and applies it immediately via apply_window_mode()
## -- game/Main.gd (a separate package) only needs to call apply_window_mode()
## once at boot for the persisted value; every later change goes through here.
func set_window_mode(id: StringName) -> void:
	if not WINDOW_MODE_IDS.has(id):
		push_warning("Settings: unknown window mode id %s" % id)
		return
	_window_mode_id = id
	_save()
	window_mode_changed.emit(id)
	apply_window_mode()


## Human-readable label for `id`, for the future OptionButton. Returns the raw
## id string if it's somehow missing from WINDOW_MODE_LABELS (must not happen
## for any id in WINDOW_MODE_IDS, but an OptionButton reading a stale/unknown
## persisted id should still get something printable rather than crash).
func window_mode_label(id: StringName) -> String:
	return WINDOW_MODE_LABELS.get(id, String(id))


## Applies the current window_mode() to the real OS window via DisplayServer.
## Safe to call any number of times (idempotent: re-applying the same mode is
## just redundant DisplayServer calls, not observable state churn).
##
## Bontago-xtq.45: guarded so it is a no-op whenever there is no real player
## window to change:
##  - DisplayServer.get_name() == "headless": no window exists at all (every
##    GUT test run, CI, `--headless-host` bot matches).
##  - Engine.is_editor_hint(): the script is running inside the editor itself
##    (tool mode), which owns its own window. Not OS.has_feature("editor"):
##    that is true for every run from this repo's editor binary, including the
##    owner's own `godot --path .` launches, and would make the setting inert
##    until an export template exists (orchestrator correction, xtq.45).
##  - `--position`, `--windowed` or `-w` in OS.get_cmdline_args(): an explicit
##    windowed/off-screen CLI request wins over the saved mode. Our own
##    screenshot/probe tools launch with `--windowed --position 10000,10000`
##    specifically so a run never appears on the owner's monitor; forcing
##    fullscreen (now also the project default) would undo that.
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
	if Engine.is_editor_hint():
		return false
	var args: PackedStringArray = OS.get_cmdline_args()
	if args.has("--position") or args.has("--windowed") or args.has("-w"):
		return false
	return true


## Windowed mode's fallback size/position: the "sane size" ProjectSettings
## already declares for the whole project (display/window/size/viewport_
## width|height, the same values the engine itself uses to size the very
## first window it opens), not a magic literal duplicated here. Centered on
## whatever screen it ends up on via Window.move_to_center() rather than a
## hand-computed screen-size/2 - window-size/2, which would double-count
## whatever DisplayServer.screen_get_size() already reports.
func _restore_windowed_size_and_center() -> void:
	var window: Window = get_window()
	if window == null:
		return
	var width: int = int(ProjectSettings.get_setting("display/window/size/viewport_width"))
	var height: int = int(ProjectSettings.get_setting("display/window/size/viewport_height"))
	window.size = Vector2i(width, height)
	window.move_to_center()


## Persisted overrides only, not the InputMap's full current binding set.
func key_override_events(action: StringName) -> Array[InputEvent]:
	var events: Array[InputEvent] = []
	if not _key_overrides.has(action):
		return events
	var stored: Array = _key_overrides[action]
	for item: Variant in stored:
		if item is InputEvent:
			events.append(item)
	return events


## DECISION: overrides are device-class aware (keyboard/mouse vs. gamepad) so
## that remapping one class never deletes the other's bootstrap default --
## CLAUDE.md requires every action to keep both a keyboard/mouse and a
## gamepad binding. _key_overrides[action] therefore holds at most one event
## per class; setting a new override only replaces the stored (and applied)
## event of the same class, never the other class's entry.
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


## Bontago-1pi.10 polish pass (owner: "Add one 'Reset to defaults' action in
## the footer"): clears every persisted override and reloads the InputMap
## straight from project.godot's own [input] section -- the exact bindings
## tools/bootstrap_project.gd wrote there, undoing every runtime
## action_erase_event()/action_add_event() a rebind ever made, without this
## file needing to remember what each action's original event was.
func reset_key_overrides() -> void:
	_key_overrides.clear()
	InputMap.load_from_project_settings()
	_save()


## Applies every InputMap override from user://settings.cfg. Called once from
## _ready(); never touches tools/bootstrap_project.gd's own generated
## defaults -- overrides layer on top via InputMap.action_erase_event()/
## action_add_event() at runtime, one device class at a time (CLAUDE.md:
## "don't hand-edit the [input] section" -- this doesn't; it's a runtime API
## call, not a project.godot edit).
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


# --- Test seam ---------------------------------------------------------------

## Points a fresh Settings instance at a temp settings.cfg path instead of
## user://settings.cfg and immediately (re)loads from it, reapplying any
## persisted key overrides just like _ready() would -- the same
## Variant/path seam pattern autoload/Sfx.gd's set_root_dir_for_test() uses
## for a value GUT can't otherwise inject into the real singleton.
func set_config_path_for_test(path: String) -> void:
	_config_path = path
	_load()
	_apply_key_overrides()


# --- Persistence --------------------------------------------------------------

func _load() -> void:
	_current_preset_id = DEFAULT_PRESET_ID
	_master_volume_db = 0.0
	_custom_music_dir = ""
	_camera_shake_enabled = DEFAULT_CAMERA_SHAKE_ENABLED
	_window_mode_id = DEFAULT_WINDOW_MODE_ID
	_rumble_enabled = _rumble_defaults.enabled_by_default
	_rumble_strength = _rumble_defaults.global_strength_scale
	_key_overrides.clear()

	var cfg: ConfigFile = ConfigFile.new()
	var err: Error = cfg.load(_config_path)
	if err != OK:
		return  # No file yet (or unreadable): every default above stands.

	_current_preset_id = StringName(cfg.get_value(SECTION_GRAPHICS, KEY_PRESET, DEFAULT_PRESET_ID))
	_master_volume_db = float(cfg.get_value(SECTION_AUDIO, KEY_MASTER_DB, 0.0))
	_custom_music_dir = String(cfg.get_value(SECTION_AUDIO, KEY_CUSTOM_MUSIC_DIR, ""))
	_camera_shake_enabled = bool(cfg.get_value(SECTION_GRAPHICS, KEY_CAMERA_SHAKE_ENABLED, DEFAULT_CAMERA_SHAKE_ENABLED))
	var loaded_window_mode_id: StringName = StringName(cfg.get_value(SECTION_GRAPHICS, KEY_WINDOW_MODE, DEFAULT_WINDOW_MODE_ID))
	if WINDOW_MODE_IDS.has(loaded_window_mode_id):
		_window_mode_id = loaded_window_mode_id
	_rumble_enabled = bool(cfg.get_value(SECTION_GAMEPAD, KEY_RUMBLE_ENABLED, _rumble_defaults.enabled_by_default))
	_rumble_strength = clampf(
		float(cfg.get_value(SECTION_GAMEPAD, KEY_RUMBLE_STRENGTH, _rumble_defaults.global_strength_scale)), 0.0, 1.0
	)

	if cfg.has_section(SECTION_INPUT):
		for action_key: String in cfg.get_section_keys(SECTION_INPUT):
			var raw: Variant = cfg.get_value(SECTION_INPUT, action_key)
			if raw is Array:
				_key_overrides[StringName(action_key)] = raw as Array


func _save() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(SECTION_GRAPHICS, KEY_PRESET, String(_current_preset_id))
	cfg.set_value(SECTION_GRAPHICS, KEY_CAMERA_SHAKE_ENABLED, _camera_shake_enabled)
	cfg.set_value(SECTION_GRAPHICS, KEY_WINDOW_MODE, String(_window_mode_id))
	cfg.set_value(SECTION_GAMEPAD, KEY_RUMBLE_ENABLED, _rumble_enabled)
	cfg.set_value(SECTION_GAMEPAD, KEY_RUMBLE_STRENGTH, _rumble_strength)
	cfg.set_value(SECTION_AUDIO, KEY_MASTER_DB, _master_volume_db)
	cfg.set_value(SECTION_AUDIO, KEY_CUSTOM_MUSIC_DIR, _custom_music_dir)
	for action: StringName in _key_overrides.keys():
		cfg.set_value(SECTION_INPUT, String(action), _key_overrides[action])
	var err: Error = cfg.save(_config_path)
	if err != OK:
		push_warning("Settings: failed to save %s (error %d)" % [_config_path, err])


func _load_preset_resource(id: StringName) -> GraphicsPreset:
	var path: String = PRESETS_DIR.path_join(String(id) + ".tres")
	if not ResourceLoader.exists(path):
		return null
	return load(path) as GraphicsPreset
