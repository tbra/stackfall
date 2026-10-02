class_name OptionsMenu
extends Control
## docs/M6_PLAN.md package C2: the options menu opened from the Main Menu's
## %OptionsButton (ui/MainMenu.gd's own _on_options_pressed()) -- graphics
## preset picker, Master/Music/SFX volume sliders with mute toggles, rumble
## on/off + intensity, a device-aware mouse/stick move-speed slider (Controls
## tab), and one KeyRebindRow per rebindable Input Map action.
##
## Self-contained within ui/MainMenu.gd (does not know about game/Main.gd, the
## same "no deep node paths" convention ui/Tutorial.gd's own header
## documents): MainMenu instances this scene directly and listens for
## `closed` to hide it again, rather than routing through Main.
##
## Bontago-1pi.10 (owner: "too big and crammed ... the controls section where
## you have to scroll both horizontally and vertically"): a left-side
## Settings/Controls tab column replaces the single ever-growing scrolling
## panel, and the Controls page shows only the active input device's
## bindings (ui/KeyRebindRow.gd's own glyph row, autoload/Settings.gd's
## active_input_device()) so a row never needs more than one short glyph
## strip's worth of horizontal space.

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
##
## DECISION (Bontago-8or.19, owner playtest feedback/playtest.md: "many of
## them not mapped to anything"): also excludes ghost_move_left/right/
## forward/back and camera_look_left/right/up/down. Those 8 actions are
## gamepad-axis-only by design (tools/bootstrap_project.gd's own DECISION
## comments; game/PlayerController.gd:824 and game/CameraRig.gd read them via
## Input.get_action_strength() purely for a connected stick -- mouse+keyboard
## ghost movement/look reads raw mouse motion directly instead, which cannot
## be bound to an Input Map action at all, spec 2.5). Listing them here showed
## a K+M player a Rebind button and a raw "Joypad Motion on Axis N ..." string
## with nothing to actually remap for their device -- exactly the reported
## "not mapped to anything" rows. Removing them here is a display-only change
## (docs/AGENT_WORKFLOW.md minor ambiguity: no gameplay rule or [ORIGINAL]
## binding changes); the gamepad bindings themselves are untouched.
##
## Same reasoning excludes rotate_snap: tools/bootstrap_project.gd's own
## comment on that action already documents it as gamepad-RB-only *because*
## rotate_yaw_cw (KEY_S / RB) gives a K+M player the identical single-tap
## 90-degree yaw already -- a real, listed row -- so rotate_snap's own row
## would be a second, K+M-unmappable control for the same function.
const REBINDABLE_ACTIONS: Array[StringName] = [
	&"ghost_place",
	&"rotate_yaw_ccw", &"rotate_yaw_cw", &"rotate_pitch_fwd", &"rotate_pitch_back",
	&"rotate_roll_left", &"rotate_roll_right", &"rotation_mode", &"rotate_reset",
	&"rotate_drag",
	&"hover_raise", &"hover_lower", &"lock_vertical",
	&"camera_mode", &"camera_orbit",
	&"camera_pan_left", &"camera_pan_right", &"camera_pan_forward", &"camera_pan_back",
	&"camera_modifier", &"camera_zoom_in", &"camera_zoom_out",
	&"camera_snap_home", &"camera_snap_goal",
	&"pause_menu",
]

## Bontago-1pi.10 polish pass (owner: "Friendly action names and grouping:
## section headers ... Keep action order sensible"): the Controls list is
## built from this grouping rather than REBINDABLE_ACTIONS' own flat order --
## each entry is one section header + the actions shown under it, in build
## order. Deliberately covers exactly REBINDABLE_ACTIONS' own action set (see
## test_options_menu.gd's own test_sections_cover_every_rebindable_action_
## exactly_once) so a future rebindable action can't silently go missing from
## every section, or end up listed twice.
const SECTIONS: Array[Dictionary] = [
	{
		"name": "Placement",
		"actions": [&"ghost_place", &"hover_raise", &"hover_lower", &"lock_vertical"],
	},
	{
		"name": "Rotation",
		"actions": [
			&"rotate_yaw_ccw", &"rotate_yaw_cw", &"rotate_pitch_fwd", &"rotate_pitch_back",
			&"rotate_roll_left", &"rotate_roll_right", &"rotation_mode", &"rotate_reset",
			&"rotate_drag",
		],
	},
	{
		"name": "Camera",
		"actions": [
			&"camera_mode", &"camera_orbit",
			&"camera_pan_left", &"camera_pan_right", &"camera_pan_forward", &"camera_pan_back",
			&"camera_modifier", &"camera_zoom_in", &"camera_zoom_out",
			&"camera_snap_home", &"camera_snap_goal",
		],
	},
	{
		"name": "Menu / System",
		"actions": [&"pause_menu"],
	},
]

const KEY_REBIND_ROW_SCENE: PackedScene = preload("res://ui/KeyRebindRow.tscn")

## DECISION (Bontago-1pi.10 polish pass, time-budgeted worker package): the
## owner's brief also asks to "combine paired actions on one row where
## natural (e.g. 'Raise / lower block — Wheel')". Deferred for this package
## (not implemented) -- merging two Input Map actions into a single
## rebindable row is a real structural change to KeyRebindRow's own
## one-action-per-row contract (which two events belong to which half of a
## capture, how Reset-to-defaults and device-filtering apply per sub-action)
## and didn't fit the 40-minute budget alongside the rest of this package.
## Every paired action still gets its own clearly labeled row in the same
## section (e.g. Placement's "Raise block" / "Lower block" sit adjacently) --
## a real, disclosed scope reduction, not a silent drop.

## Bontago-1pi.10: reused only for the two tab buttons' pastel pill styling
## (ui/theme/MenuStyleFactory.gd, config/menu_visual_tuning.tres already
## shipped by the just-merged main menu/lobby reskin) -- everything else on
## this menu keeps the shared stackfall_theme.tres Button/OptionButton look.
@export var tuning: MenuVisualTuning = preload("res://config/menu_visual_tuning.tres")

## Footer device hint text (owner: "show a device hint in the footer ...
## matching the active device") and the Controls page's own device caption --
## plain literals rather than a config/*.tres Resource, since these are
## display-only strings, not gameplay/physics tuning (CLAUDE.md's
## no-magic-numbers rule targets those).
const FOOTER_HINT_KEYBOARD_MOUSE: String = "Enter · Esc"
const FOOTER_HINT_GAMEPAD: String = "A Select   B Back   LB / RB Tabs"
const CONTROLS_LABEL_KEYBOARD_MOUSE: String = "Showing keyboard & mouse bindings"
const CONTROLS_LABEL_GAMEPAD: String = "Showing gamepad bindings"

## DECISION (ui/OptionsMenu.gd): the volume/rumble/move-speed sliders' own
## range/step are scene-level widget configuration, not a "magic number" a
## config/*.tres Resource needs to own -- CLAUDE.md's no-magic-numbers rule
## targets gameplay/physics tuning that changes game feel; a UI slider's own
## bounds don't (Settings.gd itself owns each field's real default and
## clamps it to a generic safety floor -- see Settings.set_mouse_move_speed_
## scale()'s own DECISION). Owner request: 0-100% for every volume/rumble
## slider, 50%-200% for the move-speed sliders (default 100%).
const MIN_VOLUME_PERCENT: float = 0.0
const MAX_VOLUME_PERCENT: float = 1.0
const VOLUME_STEP_PERCENT: float = 0.01
const MIN_RUMBLE_STRENGTH: float = 0.0
const MAX_RUMBLE_STRENGTH: float = 1.0
const RUMBLE_STRENGTH_STEP: float = 0.01
const MIN_MOVE_SPEED_SCALE: float = 0.5
const MAX_MOVE_SPEED_SCALE: float = 2.0
const MOVE_SPEED_SCALE_STEP: float = 0.01

## DECISION (ui/OptionsMenu.gd): which speaker icon a mute button shows for a
## given (unmuted, > 0%) volume -- a UI-feel threshold, not a design tunable,
## the same reasoning MIN_VOLUME_PERCENT above and Settings.gd's own
## MOUSE_MOTION_DEVICE_THRESHOLD_PX already give for a plain script const.
const LOW_VOLUME_ICON_THRESHOLD: float = 1.0 / 3.0
const MID_VOLUME_ICON_THRESHOLD: float = 2.0 / 3.0

const SPEAKER_MUTED_ICON: Texture2D = preload("res://assets/ui/icons/speaker_muted.svg")
const SPEAKER_LOW_ICON: Texture2D = preload("res://assets/ui/icons/speaker_low.svg")
const SPEAKER_MID_ICON: Texture2D = preload("res://assets/ui/icons/speaker_mid.svg")
const SPEAKER_HIGH_ICON: Texture2D = preload("res://assets/ui/icons/speaker_high.svg")

## Owner correction (options package, mid-review): "Mouse speed"/"Stick
## speed" labels for the single device-aware MoveSpeedRow on the Controls tab
## (see _refresh_move_speed_row()).
const MOVE_SPEED_LABEL_MOUSE: String = "Mouse speed"
const MOVE_SPEED_LABEL_STICK: String = "Stick speed"

@onready var _preset_option: OptionButton = %PresetOption
@onready var _master_mute_button: Button = %MasterMuteButton
@onready var _master_volume_slider: HSlider = %MasterVolumeSlider
@onready var _master_volume_value_label: Label = %MasterVolumeValueLabel
@onready var _music_mute_button: Button = %MusicMuteButton
@onready var _music_volume_slider: HSlider = %MusicVolumeSlider
@onready var _music_volume_value_label: Label = %MusicVolumeValueLabel
@onready var _sfx_mute_button: Button = %SfxMuteButton
@onready var _sfx_volume_slider: HSlider = %SfxVolumeSlider
@onready var _sfx_volume_value_label: Label = %SfxVolumeValueLabel
@onready var _music_dir_edit: LineEdit = %MusicDirEdit
@onready var _browse_button: Button = %BrowseButton
@onready var _music_dir_dialog: FileDialog = %MusicDirDialog
@onready var _camera_shake_check: CheckButton = %CameraShakeCheck
@onready var _adaptive_quality_check: CheckButton = %AdaptiveQualityCheck
@onready var _window_mode_option: OptionButton = %WindowModeOption
@onready var _rumble_enabled_check: CheckButton = %RumbleEnabledCheck
@onready var _rumble_strength_slider: HSlider = %RumbleStrengthSlider
@onready var _rumble_strength_value_label: Label = %RumbleStrengthValueLabel
@onready var _rebind_list: VBoxContainer = %RebindList
@onready var _back_button: Button = %BackButton
@onready var _reset_button: Button = %ResetButton
@onready var _settings_tab_button: Button = %SettingsTabButton
@onready var _controls_tab_button: Button = %ControlsTabButton
@onready var _settings_page: ScrollContainer = %SettingsPage
@onready var _controls_page: VBoxContainer = %ControlsPage
@onready var _controls_device_label: Label = %ControlsDeviceLabel
@onready var _footer_hint_label: Label = %FooterHintLabel
@onready var _move_speed_label: Label = %MoveSpeedLabel
@onready var _move_speed_slider: HSlider = %MoveSpeedSlider
@onready var _move_speed_value_label: Label = %MoveSpeedValueLabel

var _rows: Array[KeyRebindRow] = []


func _ready() -> void:
	if settings_provider == null:
		settings_provider = Settings
	for slider: HSlider in [_master_volume_slider, _music_volume_slider, _sfx_volume_slider]:
		slider.min_value = MIN_VOLUME_PERCENT
		slider.max_value = MAX_VOLUME_PERCENT
		slider.step = VOLUME_STEP_PERCENT
	_rumble_strength_slider.min_value = MIN_RUMBLE_STRENGTH
	_rumble_strength_slider.max_value = MAX_RUMBLE_STRENGTH
	_rumble_strength_slider.step = RUMBLE_STRENGTH_STEP
	_style_section_header(%DisplaySectionHeader)
	_style_section_header(%AudioSectionHeader)
	_style_section_header(%RumbleSectionHeader)
	for mute_button: Button in [_master_mute_button, _music_mute_button, _sfx_mute_button]:
		_style_mute_button_icon(mute_button)
	_move_speed_slider.min_value = MIN_MOVE_SPEED_SCALE
	_move_speed_slider.max_value = MAX_MOVE_SPEED_SCALE
	_move_speed_slider.step = MOVE_SPEED_SCALE_STEP

	MenuStyleFactory.apply_toggle_chip(_settings_tab_button, tuning.pill_cream_color, tuning.pill_cream_hover_color, tuning.pill_coral_color, tuning.pill_coral_hover_color, tuning.ink_color, tuning)
	MenuStyleFactory.apply_toggle_chip(_controls_tab_button, tuning.pill_cream_color, tuning.pill_cream_hover_color, tuning.pill_coral_color, tuning.pill_coral_hover_color, tuning.ink_color, tuning)

	_build_preset_items()
	_build_window_mode_items()
	_load_current_values()
	# Owner-disabled temporarily; retain saved paths for a future re-enable.
	_music_dir_edit.get_parent().hide()
	_build_rebind_rows()
	_refresh_layout()
	get_viewport().size_changed.connect(_refresh_layout)
	_wire_focus_chain()
	_refresh_device_dependent_ui()

	_preset_option.item_selected.connect(_on_preset_selected)
	_master_volume_slider.value_changed.connect(_on_master_volume_changed)
	_master_mute_button.pressed.connect(_on_master_mute_pressed)
	_music_volume_slider.value_changed.connect(_on_music_volume_changed)
	_music_mute_button.pressed.connect(_on_music_mute_pressed)
	_sfx_volume_slider.value_changed.connect(_on_sfx_volume_changed)
	_sfx_mute_button.pressed.connect(_on_sfx_mute_pressed)
	_music_dir_edit.text_submitted.connect(_on_music_dir_submitted)
	_music_dir_edit.focus_exited.connect(_on_music_dir_focus_exited)
	_browse_button.pressed.connect(_on_browse_pressed)
	_music_dir_dialog.dir_selected.connect(_on_music_dir_selected)
	_camera_shake_check.toggled.connect(_on_camera_shake_toggled)
	_adaptive_quality_check.toggled.connect(_on_adaptive_quality_toggled)
	_window_mode_option.item_selected.connect(_on_window_mode_selected)
	_rumble_enabled_check.toggled.connect(_on_rumble_enabled_toggled)
	_rumble_strength_slider.value_changed.connect(_on_rumble_strength_changed)
	_rumble_strength_slider.drag_ended.connect(_on_rumble_strength_drag_ended)
	_move_speed_slider.value_changed.connect(_on_move_speed_changed)
	_back_button.pressed.connect(_on_back_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_settings_tab_button.toggled.connect(_on_settings_tab_toggled)
	_controls_tab_button.toggled.connect(_on_controls_tab_toggled)
	Events.input_device_changed.connect(_on_input_device_changed)

	_preset_option.grab_focus()


## DECISION (Bontago-mp0.11): the panel follows the usable viewport instead
## of demanding a desktop sized minimum; the settings page scrolls vertically.
func _refresh_layout() -> void:
	var available: Vector2 = get_viewport_rect().size - Vector2.ONE * tuning.menu_edge_margin_px * 2.0
	var panel: PanelContainer = $Frame/Panel
	panel.custom_minimum_size = Vector2(minf(available.x, tuning.menu_max_width_px), available.y)


## Owner: "switch to only gamepad options on gamepad input and switch back on
## mouse/keyboard input" -- both tab buttons share one ButtonGroup
## (ui/OptionsMenu.tscn), so pressing one always un-presses the other and
## fires both toggled signals; each handler only ever needs to show/hide its
## own page.
func _on_settings_tab_toggled(pressed: bool) -> void:
	_settings_page.visible = pressed


func _on_controls_tab_toggled(pressed: bool) -> void:
	_controls_page.visible = pressed


func _on_input_device_changed(_device: StringName) -> void:
	_refresh_device_dependent_ui()


func _refresh_device_dependent_ui() -> void:
	var gamepad: bool = Settings.active_input_device() == Settings.DEVICE_GAMEPAD
	_footer_hint_label.text = FOOTER_HINT_GAMEPAD if gamepad else FOOTER_HINT_KEYBOARD_MOUSE
	_controls_device_label.text = CONTROLS_LABEL_GAMEPAD if gamepad else CONTROLS_LABEL_KEYBOARD_MOUSE
	_refresh_move_speed_row()


## Owner correction (options package, mid-review): one device-aware row on
## the Controls tab rebinds itself to whichever scale the active device
## actually drives -- "Mouse speed" / Settings.mouse_move_speed_scale() on
## keyboard/mouse, "Stick speed" / Settings.stick_move_speed_scale() on
## gamepad -- rather than two rows toggling visibility (DECISION,
## ui/OptionsMenu.gd). Reusing the same Slider node for both means whichever
## control had focus keeps it across a live device switch for free -- no
## separate focus-transfer step needed, since the node itself never changes.
func _refresh_move_speed_row() -> void:
	var gamepad: bool = Settings.active_input_device() == Settings.DEVICE_GAMEPAD
	_move_speed_label.text = MOVE_SPEED_LABEL_STICK if gamepad else MOVE_SPEED_LABEL_MOUSE
	var scale: float = settings_provider.stick_move_speed_scale() if gamepad else settings_provider.mouse_move_speed_scale()
	_move_speed_slider.set_value_no_signal(scale)
	_move_speed_value_label.text = _format_percent(scale)


## ui_cancel (Escape / gamepad B, spec 2.10) backs out -- the same
## _unhandled_input()/set_input_as_handled() pattern ui/Tutorial.gd's own
## header documents. A listening KeyRebindRow consumes ui_cancel first
## (Godot delivers _unhandled_input to the deepest node in a branch before its
## ancestors), so this only ever fires while no row is actively capturing.
func _unhandled_input(event: InputEvent) -> void:
	# KeyRebindRow captures raw input first; this guard also protects direct
	# synthetic action events from changing tabs while a bind is listening.
	for row: KeyRebindRow in _rows:
		if row.is_listening():
			return
	if event.is_action_pressed(&"menu_tab_next") or event.is_action_pressed(&"menu_tab_previous"):
		var target: Button = _controls_tab_button if _settings_tab_button.button_pressed else _settings_tab_button
		target.button_pressed = true
		target.grab_focus()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _build_preset_items() -> void:
	_preset_option.clear()
	for label: String in PRESET_LABELS:
		_preset_option.add_item(label)


## Bontago-xtq.45 (M7 P4): reads Settings.WINDOW_MODE_IDS/window_mode_label()
## directly (a fixed, script-level constant/lookup, not per-provider state)
## rather than duplicating PRESET_LABELS' own hand-written parallel-array
## pattern -- the ids and their display order already live in one place.
func _build_window_mode_items() -> void:
	_window_mode_option.clear()
	for id: StringName in Settings.WINDOW_MODE_IDS:
		_window_mode_option.add_item(Settings.window_mode_label(id))


func _load_current_values() -> void:
	var preset: GraphicsPreset = settings_provider.current_graphics_preset()
	var preset_index: int = PRESET_IDS.find(preset.id) if preset != null else -1
	_preset_option.select(preset_index if preset_index >= 0 else PRESET_IDS.find(Settings.DEFAULT_PRESET_ID))

	_load_channel_row(_master_mute_button, _master_volume_slider, _master_volume_value_label, settings_provider.master_muted(), settings_provider.master_volume_percent())
	_load_channel_row(_music_mute_button, _music_volume_slider, _music_volume_value_label, settings_provider.music_muted(), settings_provider.music_volume_percent())
	_load_channel_row(_sfx_mute_button, _sfx_volume_slider, _sfx_volume_value_label, settings_provider.sfx_muted(), settings_provider.sfx_volume_percent())

	_music_dir_edit.text = String(settings_provider.custom_music_dir())

	_camera_shake_check.set_pressed_no_signal(bool(settings_provider.camera_shake_enabled()))
	_adaptive_quality_check.set_pressed_no_signal(bool(settings_provider.adaptive_quality_enabled()))

	var window_mode_id: StringName = settings_provider.window_mode()
	var window_mode_index: int = Settings.WINDOW_MODE_IDS.find(window_mode_id)
	_window_mode_option.select(window_mode_index if window_mode_index >= 0 else Settings.WINDOW_MODE_IDS.find(Settings.DEFAULT_WINDOW_MODE_ID))

	_rumble_enabled_check.set_pressed_no_signal(bool(settings_provider.rumble_enabled()))
	_rumble_strength_slider.set_value_no_signal(float(settings_provider.rumble_strength()))
	_rumble_strength_value_label.text = _format_percent(float(settings_provider.rumble_strength()))
	_refresh_rumble_strength_enabled()

	_refresh_move_speed_row()


func _load_channel_row(mute_button: Button, slider: HSlider, value_label: Label, muted: bool, percent: float) -> void:
	slider.set_value_no_signal(percent)
	value_label.text = _format_percent(percent)
	(mute_button.get_node("Icon") as TextureRect).texture = _icon_for_channel(muted, percent)


func _on_preset_selected(index: int) -> void:
	if index < 0 or index >= PRESET_IDS.size():
		return
	settings_provider.set_graphics_preset(PRESET_IDS[index])


# --- Audio channels (Master/Music/SFX) ----------------------------------------

func _on_master_volume_changed(value: float) -> void:
	settings_provider.set_master_volume_percent(value)
	_load_channel_row(_master_mute_button, _master_volume_slider, _master_volume_value_label, settings_provider.master_muted(), settings_provider.master_volume_percent())


func _on_master_mute_pressed() -> void:
	settings_provider.toggle_master_mute()
	_load_channel_row(_master_mute_button, _master_volume_slider, _master_volume_value_label, settings_provider.master_muted(), settings_provider.master_volume_percent())


func _on_music_volume_changed(value: float) -> void:
	settings_provider.set_music_volume_percent(value)
	_load_channel_row(_music_mute_button, _music_volume_slider, _music_volume_value_label, settings_provider.music_muted(), settings_provider.music_volume_percent())


func _on_music_mute_pressed() -> void:
	settings_provider.toggle_music_mute()
	_load_channel_row(_music_mute_button, _music_volume_slider, _music_volume_value_label, settings_provider.music_muted(), settings_provider.music_volume_percent())


func _on_sfx_volume_changed(value: float) -> void:
	settings_provider.set_sfx_volume_percent(value)
	_load_channel_row(_sfx_mute_button, _sfx_volume_slider, _sfx_volume_value_label, settings_provider.sfx_muted(), settings_provider.sfx_volume_percent())


func _on_sfx_mute_pressed() -> void:
	settings_provider.toggle_sfx_mute()
	_load_channel_row(_sfx_mute_button, _sfx_volume_slider, _sfx_volume_value_label, settings_provider.sfx_muted(), settings_provider.sfx_volume_percent())


## Muted (or at 0%): the "X" icon. Otherwise picks the 1/2/3-wave icon by
## LOW_VOLUME_ICON_THRESHOLD/MID_VOLUME_ICON_THRESHOLD.
func _icon_for_channel(muted: bool, percent: float) -> Texture2D:
	if muted or percent <= 0.0:
		return SPEAKER_MUTED_ICON
	if percent <= LOW_VOLUME_ICON_THRESHOLD:
		return SPEAKER_LOW_ICON
	if percent <= MID_VOLUME_ICON_THRESHOLD:
		return SPEAKER_MID_ICON
	return SPEAKER_HIGH_ICON


func _format_percent(value: float) -> String:
	return "%d%%" % int(round(value * 100.0))


func _on_music_dir_submitted(_text: String) -> void:
	pass # Custom music override temporarily disabled.


func _on_music_dir_focus_exited() -> void:
	pass


func _on_browse_pressed() -> void:
	pass


func _on_music_dir_selected(_dir: String) -> void:
	pass


## Bontago-1pi.11.37: opt-in governor; the stored preset is never touched.
func _on_adaptive_quality_toggled(enabled: bool) -> void:
	settings_provider.set_adaptive_quality_enabled(enabled)


func _on_camera_shake_toggled(enabled: bool) -> void:
	settings_provider.set_camera_shake_enabled(enabled)


# --- Rumble --------------------------------------------------------------------

## Owner: "an on/off toggle ... slider disabled/greyed when rumble is off" and
## "Nudge a short test rumble ... when the toggle turned on". Rumble.
## trigger_test_pulse() itself is a no-op unless Settings.rumble_enabled() is
## already true and a gamepad is the active device, so this call is safe to
## make unconditionally on every toggle (it only ever buzzes on the "turned
## on, gamepad present" case the brief asks for).
func _on_rumble_enabled_toggled(enabled: bool) -> void:
	settings_provider.set_rumble_enabled(enabled)
	_refresh_rumble_strength_enabled()
	if enabled:
		Rumble.trigger_test_pulse()


func _refresh_rumble_strength_enabled() -> void:
	var enabled: bool = bool(settings_provider.rumble_enabled())
	_rumble_strength_slider.editable = enabled
	_rumble_strength_slider.modulate.a = 1.0 if enabled else 0.5


func _on_rumble_strength_changed(value: float) -> void:
	settings_provider.set_rumble_strength(value)
	_rumble_strength_value_label.text = _format_percent(value)


## Owner: "Nudge a short test rumble when the slider is released". HSlider's
## own drag_ended(value_changed) fires once per drag gesture regardless of how
## many intermediate value_changed signals fired during it.
func _on_rumble_strength_drag_ended(_value_changed: bool) -> void:
	Rumble.trigger_test_pulse()


# --- Block movement speed (Controls tab, device-aware) ------------------------

func _on_move_speed_changed(value: float) -> void:
	if Settings.active_input_device() == Settings.DEVICE_GAMEPAD:
		settings_provider.set_stick_move_speed_scale(value)
	else:
		settings_provider.set_mouse_move_speed_scale(value)
	_move_speed_value_label.text = _format_percent(value)


## Bontago-xtq.45 (M7 P4): unlike every other setter this menu calls,
## Settings.set_window_mode() already applies the change itself (its own doc
## comment: "applies it immediately via apply_window_mode()") -- calling
## apply_window_mode() again here would just be a redundant, no-observable-
## effect re-application of the same mode, so this stays a single call, the
## same shape as _on_preset_selected()/_on_camera_shake_toggled() above.
func _on_window_mode_selected(index: int) -> void:
	if index < 0 or index >= Settings.WINDOW_MODE_IDS.size():
		return
	settings_provider.set_window_mode(Settings.WINDOW_MODE_IDS[index])


func _on_back_pressed() -> void:
	closed.emit()


## Owner: "Add one 'Reset to defaults' action in the footer" -- now also
## resets every audio channel, rumble, and the mouse/stick move-speed scales
## this package adds (owner: "reset by the Reset button"). Reloads the
## InputMap straight from project.godot (Settings.reset_key_overrides()),
## then tells every already-built row to redraw its own glyphs from that
## fresh InputMap state -- cheaper than _build_rebind_rows() rebuilding the
## whole list, and preserves whichever row currently has focus.
func _on_reset_pressed() -> void:
	settings_provider.reset_key_overrides()
	settings_provider.reset_audio_settings()
	settings_provider.reset_rumble_settings()
	settings_provider.reset_move_speed_scales()
	for row: KeyRebindRow in _rows:
		row.refresh()
	_load_current_values()


## Test/inspection seam: every KeyRebindRow this menu built, in SECTIONS
## build order (section by section, in each section's own action order).
func rebind_rows() -> Array[KeyRebindRow]:
	return _rows


## One Label per SECTIONS entry, styled as a small muted section header
## (owner: "section headers (Placement, Rotation, Camera, ... Menu/System)").
func _build_section_header(name: String) -> Label:
	var header: Label = Label.new()
	header.text = name
	_style_section_header(header)
	return header


## Owner (audio/rumble package): "Group rows under section headers (Audio,
## Controller/Controls feel) matching existing style" -- the Settings tab's
## AudioSectionHeader/RumbleSectionHeader are static .tscn Labels (unlike the
## Controls tab's dynamically-built SECTIONS headers above), so this applies
## the exact same muted small-caption look to an existing node instead of
## building a fresh one.
func _style_section_header(header: Label) -> void:
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", tuning.label_muted_color)


## The speaker icons (assets/ui/icons/speaker_*.svg) are plain white fills
## "so they can be modulated to the theme text colour" (brief) -- against
## this menu's cream panel a flat white icon has almost no contrast, so this
## tints the icon to tuning.ink_color, the same dark ink colour
## MenuStyleFactory.apply_toggle_chip() already uses for this menu's tab
## button labels above.
##
## DECISION (ui/OptionsMenu.gd): the icon lives on a child TextureRect
## (%.../MuteButton/Icon), not the Button's own built-in `icon` property --
## a Button icon assigned this deep in this scene's container chain rendered
## with correct properties (icon/rect/visible/modulate all reported normal)
## but was never actually drawn, reproducible in isolation and gone the
## moment the same node was reparented to a shallower tree; a plain
## TextureRect child (the same node type every other icon in the project
## already uses) sidesteps whatever that Button-specific issue is.
func _style_mute_button_icon(button: Button) -> void:
	(button.get_node("Icon") as TextureRect).modulate = tuning.ink_color


func _build_rebind_rows() -> void:
	for child: Node in _rebind_list.get_children():
		_rebind_list.remove_child(child)
		child.queue_free()
	_rows.clear()

	for section: Dictionary in SECTIONS:
		_rebind_list.add_child(_build_section_header(section.get("name", "") as String))
		for action: StringName in (section.get("actions", []) as Array):
			var row: KeyRebindRow = KEY_REBIND_ROW_SCENE.instantiate() as KeyRebindRow
			_rebind_list.add_child(row)
			row.setup(action)
			_rows.append(row)


## Gamepad/keyboard navigability (docs/M6_PLAN.md package C2: "fully
## navigable with gamepad and keyboard"): chains every focusable control top
## to bottom, in the same visual order the Settings tab actually lays rows
## out in (orchestrator review correction) -- PresetOption -> WindowModeOption
## -> CameraShakeCheck -> Master/Music/SFX mute+volume -> Rumble
## toggle+intensity -> MoveSpeedSlider (Controls tab) -> each rebind row (a
## row IS its own Button now, Bontago-1pi.10 polish pass -- no separate child
## RebindButton) in section/build order -> ResetButton -> BackButton -> back
## up to PresetOption. Computed at runtime (control.get_path_to()) rather than
## static NodePaths in the .tscn, the same reason ui/MainMenu.gd's own
## _apply_steam_availability() does this for its Steam-availability toggle:
## the rebind rows are built dynamically and don't exist yet when the scene
## file is authored.
##
## DECISION (Bontago-1pi.10): the two tab buttons are deliberately left out of
## this explicit vertical chain -- they sit in their own column to the left,
## and Godot's own automatic focus-neighbor resolution (used whenever
## focus_neighbor_left/right is left as an empty NodePath, which this method
## never sets) already finds them via ui_left/ui_right from whatever control
## in ContentColumn currently has focus, the ordinary "arrow keys move to the
## nearest Control in that screen direction" behavior every other Control in
## the project already relies on.
func _wire_focus_chain() -> void:
	var chain: Array[Control] = [
		_preset_option,
		_window_mode_option, _camera_shake_check, _adaptive_quality_check,
		_master_mute_button, _master_volume_slider,
		_music_mute_button, _music_volume_slider,
		_sfx_mute_button, _sfx_volume_slider,
		_rumble_enabled_check, _rumble_strength_slider,
		_move_speed_slider,
	]
	for row: KeyRebindRow in _rows:
		chain.append(row.rebind_button())
	chain.append(_reset_button)
	chain.append(_back_button)

	for i: int in range(chain.size()):
		var current: Control = chain[i]
		var prev: Control = chain[(i - 1 + chain.size()) % chain.size()]
		var next: Control = chain[(i + 1) % chain.size()]
		current.focus_neighbor_top = current.get_path_to(prev)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_mode = Control.FOCUS_ALL
