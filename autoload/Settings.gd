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

const DEFAULT_PRESET_ID: StringName = &"medium"
const PRESETS_DIR: String = "res://config/graphics_presets/"

const SECTION_GRAPHICS: String = "graphics"
const SECTION_AUDIO: String = "audio"
const SECTION_INPUT: String = "input"

const KEY_PRESET: String = "preset"
const KEY_MASTER_DB: String = "master_db"
const KEY_CUSTOM_MUSIC_DIR: String = "custom_music_dir"
const KEY_CAMERA_SHAKE_ENABLED: String = "camera_shake_enabled"

## Bontago-xtq.29 (M7 P4): default on -- matches the shake game/CameraRig.gd
## already applies before the player ever opens Options, so a fresh install
## shows the intended feel rather than a silent off-by-default.
const DEFAULT_CAMERA_SHAKE_ENABLED: bool = true

var _config_path: String = "user://settings.cfg"
var _current_preset_id: StringName = DEFAULT_PRESET_ID
var _master_volume_db: float = 0.0
var _custom_music_dir: String = ""
var _camera_shake_enabled: bool = DEFAULT_CAMERA_SHAKE_ENABLED

## action -> Array of persisted InputEvent overrides for that action (never
## the full InputMap default set -- key_override_events() answers "what has
## the user overridden", not "what is bound").
var _key_overrides: Dictionary[StringName, Array] = {}


func _ready() -> void:
	_load()
	_apply_key_overrides()


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
	_key_overrides.clear()

	var cfg: ConfigFile = ConfigFile.new()
	var err: Error = cfg.load(_config_path)
	if err != OK:
		return  # No file yet (or unreadable): every default above stands.

	_current_preset_id = StringName(cfg.get_value(SECTION_GRAPHICS, KEY_PRESET, DEFAULT_PRESET_ID))
	_master_volume_db = float(cfg.get_value(SECTION_AUDIO, KEY_MASTER_DB, 0.0))
	_custom_music_dir = String(cfg.get_value(SECTION_AUDIO, KEY_CUSTOM_MUSIC_DIR, ""))
	_camera_shake_enabled = bool(cfg.get_value(SECTION_GRAPHICS, KEY_CAMERA_SHAKE_ENABLED, DEFAULT_CAMERA_SHAKE_ENABLED))

	if cfg.has_section(SECTION_INPUT):
		for action_key: String in cfg.get_section_keys(SECTION_INPUT):
			var raw: Variant = cfg.get_value(SECTION_INPUT, action_key)
			if raw is Array:
				_key_overrides[StringName(action_key)] = raw as Array


func _save() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(SECTION_GRAPHICS, KEY_PRESET, String(_current_preset_id))
	cfg.set_value(SECTION_GRAPHICS, KEY_CAMERA_SHAKE_ENABLED, _camera_shake_enabled)
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
