class_name OptionsMenu
extends Control
## docs/M6_PLAN.md package C2: the options menu opened from the Main Menu's
## %OptionsButton (ui/MainMenu.gd's own _on_options_pressed()) -- graphics
## preset picker, master volume slider, custom music folder, and one
## KeyRebindRow per rebindable Input Map action.
##
## Self-contained within ui/MainMenu.gd (does not know about game/Main.gd, the
## same "no deep node paths" convention ui/Tutorial.gd's own header
## documents): MainMenu instances this scene directly and listens for
## `closed` to hide it again, rather than routing through Main.

signal closed

## DECISION (ui/OptionsMenu.gd): a `Variant` test seam, the same reason
## ui/MainMenu.gd's net_provider and ui/TuningPanel.gd's net_provider exist --
## GUT cannot double a plain autoload. Unlike those two, the reason here isn't
## "Net is still a stub": Settings.set_key_override() writes straight onto the
## real, process-global InputMap (autoload/Settings.gd's own doc), so a test
## that rebinds an action through the *real* Settings autoload would leak that
## InputMap change into every other test file sharing this process. Defaults
## to the real Settings autoload; tests overwrite it after add_child() with a
## fresh `Settings.new()` pointed at a temp config path (tests/unit/
## test_settings.gd's own convention) so preset/volume/music-dir assertions
## stay isolated -- the KeyRebindRow capture path is exercised directly in
## isolation instead (see tests/unit/test_options_menu.gd), and any test that
## does go through a live rebind restores the InputMap afterward.
var settings_provider: Variant = null

## Ordered so the OptionButton's item index always maps back to a preset id
## via PRESET_IDS[index] -- alphabetical filename order (config/graphics_
## presets/*.tres: high, low, medium) would scramble the intended quality
## ladder, so this is a literal list, the same way Settings.DEFAULT_PRESET_ID
## is a literal "medium" rather than a directory scan.
const PRESET_IDS: Array[StringName] = [&"low", &"medium", &"high"]
const PRESET_LABELS: Array[String] = ["Low", "Medium", "High"]

## DECISION (ui/OptionsMenu.gd, docs/M6_PLAN.md package C2): an explicit
## allow-list, not "every InputMap action minus a deny-list" -- so a future
## debug hotkey (tools/bootstrap_project.gd's own _actions()) never silently
## becomes player-rebindable just by existing. Excludes every debug-only/
## sandbox-only action (screenshot_capture, net_debug_toggle,
## tuning_panel_toggle, sandbox_*) and throw_aim, which shares its physical
## binding with ghost_place (PlayerController disambiguates by held-item type,
## not by a separate Input Map action -- rebinding it alone would desync that
## pairing).
const REBINDABLE_ACTIONS: Array[StringName] = [
	&"ghost_move_left", &"ghost_move_right", &"ghost_move_forward", &"ghost_move_back",
	&"ghost_place",
	&"rotate_yaw_ccw", &"rotate_yaw_cw", &"rotate_pitch_fwd", &"rotate_pitch_back",
	&"rotate_roll_left", &"rotate_roll_right", &"rotation_mode", &"rotate_reset",
	&"rotate_snap", &"rotate_drag",
	&"hover_raise", &"hover_lower", &"lock_vertical",
	&"camera_mode", &"camera_orbit",
	&"camera_look_left", &"camera_look_right", &"camera_look_up", &"camera_look_down",
	&"camera_pan_left", &"camera_pan_right", &"camera_pan_forward", &"camera_pan_back",
	&"camera_modifier", &"camera_zoom_in", &"camera_zoom_out",
	&"camera_snap_home", &"camera_snap_goal",
	&"pause_menu",
]

const KEY_REBIND_ROW_SCENE: PackedScene = preload("res://ui/KeyRebindRow.tscn")

## DECISION (ui/OptionsMenu.gd): the volume slider's range/step are scene-
## level widget configuration, not a "magic number" a config/*.tres Resource
## needs to own -- CLAUDE.md's no-magic-numbers rule targets gameplay/physics
## tuning that changes game feel; a UI slider's own bounds don't (any range
## that comfortably covers config/AudioConfig.gd's baselines works, and
## AudioConfig itself is the actual tunable this offsets).
const MIN_VOLUME_DB: float = -40.0
const MAX_VOLUME_DB: float = 6.0
const VOLUME_STEP_DB: float = 1.0

@onready var _preset_option: OptionButton = %PresetOption
@onready var _volume_slider: HSlider = %VolumeSlider
@onready var _volume_value_label: Label = %VolumeValueLabel
@onready var _music_dir_edit: LineEdit = %MusicDirEdit
@onready var _browse_button: Button = %BrowseButton
@onready var _music_dir_dialog: FileDialog = %MusicDirDialog
@onready var _camera_shake_check: CheckButton = %CameraShakeCheck
@onready var _rebind_list: VBoxContainer = %RebindList
@onready var _back_button: Button = %BackButton

var _rows: Array[KeyRebindRow] = []


func _ready() -> void:
	if settings_provider == null:
		settings_provider = Settings
	_volume_slider.min_value = MIN_VOLUME_DB
	_volume_slider.max_value = MAX_VOLUME_DB
	_volume_slider.step = VOLUME_STEP_DB

	_build_preset_items()
	_load_current_values()
	_build_rebind_rows()
	_wire_focus_chain()

	_preset_option.item_selected.connect(_on_preset_selected)
	_volume_slider.value_changed.connect(_on_volume_changed)
	_music_dir_edit.text_submitted.connect(_on_music_dir_submitted)
	_music_dir_edit.focus_exited.connect(_on_music_dir_focus_exited)
	_browse_button.pressed.connect(_on_browse_pressed)
	_music_dir_dialog.dir_selected.connect(_on_music_dir_selected)
	_camera_shake_check.toggled.connect(_on_camera_shake_toggled)
	_back_button.pressed.connect(_on_back_pressed)

	_preset_option.grab_focus()


## ui_cancel (Escape / gamepad B, spec 2.10) backs out -- the same
## _unhandled_input()/set_input_as_handled() pattern ui/Tutorial.gd's own
## header documents. A listening KeyRebindRow consumes ui_cancel first
## (Godot delivers _unhandled_input to the deepest node in a branch before its
## ancestors), so this only ever fires while no row is actively capturing.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _build_preset_items() -> void:
	_preset_option.clear()
	for label: String in PRESET_LABELS:
		_preset_option.add_item(label)


func _load_current_values() -> void:
	var preset: GraphicsPreset = settings_provider.current_graphics_preset()
	var preset_index: int = PRESET_IDS.find(preset.id) if preset != null else -1
	_preset_option.select(preset_index if preset_index >= 0 else PRESET_IDS.find(Settings.DEFAULT_PRESET_ID))

	var volume: float = float(settings_provider.master_volume_db())
	_volume_slider.set_value_no_signal(volume)
	_volume_value_label.text = _format_db(volume)

	_music_dir_edit.text = String(settings_provider.custom_music_dir())

	_camera_shake_check.set_pressed_no_signal(bool(settings_provider.camera_shake_enabled()))


func _on_preset_selected(index: int) -> void:
	if index < 0 or index >= PRESET_IDS.size():
		return
	settings_provider.set_graphics_preset(PRESET_IDS[index])


func _on_volume_changed(value: float) -> void:
	_volume_value_label.text = _format_db(value)
	settings_provider.set_master_volume_db(value)


func _format_db(value: float) -> String:
	return "%d dB" % int(round(value))


func _on_music_dir_submitted(text: String) -> void:
	settings_provider.set_custom_music_dir(text)


func _on_music_dir_focus_exited() -> void:
	settings_provider.set_custom_music_dir(_music_dir_edit.text)


func _on_browse_pressed() -> void:
	_music_dir_dialog.current_dir = _music_dir_edit.text
	_music_dir_dialog.popup_centered_ratio()


func _on_music_dir_selected(dir: String) -> void:
	_music_dir_edit.text = dir
	settings_provider.set_custom_music_dir(dir)


func _on_camera_shake_toggled(enabled: bool) -> void:
	settings_provider.set_camera_shake_enabled(enabled)


func _on_back_pressed() -> void:
	closed.emit()


## Test/inspection seam: every KeyRebindRow this menu built, in
## REBINDABLE_ACTIONS order.
func rebind_rows() -> Array[KeyRebindRow]:
	return _rows


func _build_rebind_rows() -> void:
	for child: Node in _rebind_list.get_children():
		_rebind_list.remove_child(child)
		child.queue_free()
	_rows.clear()

	for action: StringName in REBINDABLE_ACTIONS:
		var row: KeyRebindRow = KEY_REBIND_ROW_SCENE.instantiate() as KeyRebindRow
		_rebind_list.add_child(row)
		row.setup(action)
		_rows.append(row)


## Gamepad/keyboard navigability (docs/M6_PLAN.md package C2: "fully
## navigable with gamepad and keyboard"): chains every focusable control top
## to bottom -- PresetOption -> VolumeSlider -> MusicDirEdit -> BrowseButton ->
## each rebind row's own RebindButton in order -> BackButton -> back up to
## PresetOption. Computed at runtime (control.get_path_to()) rather than
## static NodePaths in the .tscn, the same reason ui/MainMenu.gd's own
## _apply_steam_availability() does this for its Steam-availability toggle:
## the rebind rows are built dynamically and don't exist yet when the scene
## file is authored.
func _wire_focus_chain() -> void:
	var chain: Array[Control] = [_preset_option, _volume_slider, _music_dir_edit, _browse_button, _camera_shake_check]
	for row: KeyRebindRow in _rows:
		chain.append(row.rebind_button())
	chain.append(_back_button)

	for i: int in range(chain.size()):
		var current: Control = chain[i]
		var prev: Control = chain[(i - 1 + chain.size()) % chain.size()]
		var next: Control = chain[(i + 1) % chain.size()]
		current.focus_neighbor_top = current.get_path_to(prev)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_mode = Control.FOCUS_ALL
