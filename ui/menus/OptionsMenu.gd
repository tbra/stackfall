class_name OptionsMenu
extends Control
## docs/archive/M6_PLAN.md package C2: the options menu opened from the Main Menu's
## %OptionsButton (ui/menus/MainMenu.gd's own _on_options_pressed()) -- graphics
## preset picker, Master/Music/SFX volume sliders with mute toggles, rumble
## on/off + intensity, a device-aware mouse/stick move-speed slider (Controls
## tab), and one KeyRebindRow per rebindable Input Map action.
##
## Self-contained within ui/menus/MainMenu.gd (does not know about game/main/Main.gd, the
## same "no deep node paths" convention ui/menus/Tutorial.gd's own header
## documents): MainMenu instances this scene directly and listens for
## `closed` to hide it again, rather than routing through Main.
##
## Bontago-1pi.10 (owner: "too big and crammed ... the controls section where
## you have to scroll both horizontally and vertically"): category tabs replace
## the single ever-growing scrolling panel (Bontago-1pi.159.3: now a horizontal
## UiTabs strip, Game / Graphics / Controls, and the pages are built from the
## ui/components rows), and the Controls page shows only the active input device's
## bindings (ui/menus/KeyRebindRow.gd's own glyph row, autoload/Settings.gd's
## active_input_device()) so a row never needs more than one short glyph
## strip's worth of horizontal space.

signal closed

## DECISION (ui/menus/OptionsMenu.gd): a `Variant` test seam, the same reason
## ui/menus/MainMenu.gd's net_provider and ui/debug/TuningPanel.gd's net_provider exist --
## GUT cannot double a plain autoload. Unlike those two, the reason here isn't
## "Net is still a stub": Settings.set_key_override() writes straight onto the
## real, process-global InputMap (autoload/Settings.gd's own doc), so a test
## that rebinds an action through the *real* Settings autoload would leak that
## InputMap change into every other test file sharing this process. Defaults
## to the real Settings autoload; tests overwrite it after add_child() with a
## fresh `Settings.new()` pointed at a temp config path (tests/unit/
## test_settings.gd's own convention) so preset/volume/music-dir assertions
## stay isolated -- the KeyRebindRow capture path is exercised directly in
## isolation instead (see tests/unit/ui/test_options_menu.gd), and any test that
## does go through a live rebind restores the InputMap afterward.
var settings_provider: Variant = null

## Ordered so the OptionButton's item index always maps back to a preset id
## via PRESET_IDS[index] -- alphabetical filename order (config/graphics_
## presets/*.tres: high, low, medium) would scramble the intended quality
## ladder, so this is a literal list, the same way Settings.DEFAULT_PRESET_ID
## is a literal "medium" rather than a directory scan.
## Bontago-1pi.204 review: the shared camera tuning the game uses, so F4 edits and .tres changes show here.
const _SHARED_CAMERA_TUNING: CameraTuning = preload("res://config/player/camera_tuning.tres")
const PRESET_IDS: Array[StringName] = GraphicsSettingsTab.PRESET_IDS
const PRESET_LABELS: Array[String] = GraphicsSettingsTab.PRESET_LABELS

## DECISION (ui/menus/OptionsMenu.gd, docs/archive/M6_PLAN.md package C2): an explicit
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
## comments; game/player/PlayerController.gd:824 and game/player/CameraRig.gd read them via
## Input.get_action_strength() purely for a connected stick -- mouse+keyboard
## ghost movement/look reads raw mouse motion directly instead, which cannot
## be bound to an Input Map action at all, spec 2.5). Listing them here showed
## a K+M player a Rebind button and a raw "Joypad Motion on Axis N ..." string
## with nothing to actually remap for their device -- exactly the reported
## "not mapped to anything" rows. Removing them here is a display-only change
## (a minor ambiguity per CLAUDE.md: no gameplay rule or [ORIGINAL]
## binding changes); the gamepad bindings themselves are untouched.
##
## Bontago-1pi.159.63 (owner decision 1pi.159.62): rotate_snap (B, 90 degree tap) and
## rotate_drag_pad (RT held + left stick) are now listed too, as the gamepad page's own
## "Rotate 90 deg" / "Free rotate (hold)" rows; they carry no keyboard binding, so
## ui/menus/KeyRebindRow.gd PAD_ONLY_ACTIONS hides them on the mouse/keyboard page.
const REBINDABLE_ACTIONS: Array[StringName] = [
	&"ghost_place", &"use_gift_slot",
	&"rotate_yaw_ccw", &"rotate_yaw_cw", &"rotate_pitch_fwd", &"rotate_pitch_back",
	&"rotate_roll_left", &"rotate_roll_right", &"rotation_mode", &"rotate_reset",
	&"rotate_drag", &"rotate_snap", &"rotate_drag_pad",
	&"hover_raise", &"hover_lower", &"lock_vertical",
	&"camera_mode", &"camera_orbit",
	&"camera_pan_left", &"camera_pan_right", &"camera_pan_forward", &"camera_pan_back",
	&"camera_modifier", &"camera_zoom_in", &"camera_zoom_out",
	&"camera_snap_home", &"camera_snap_goal", &"camera_reset",
	&"pause_menu",
	&"show_scores",
	&"chat_open",
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
		"actions": [&"ghost_place", &"use_gift_slot", &"hover_raise", &"hover_lower", &"lock_vertical"],
	},
	{
		"name": "Rotation",
		"actions": [
			&"rotate_yaw_ccw", &"rotate_yaw_cw", &"rotate_pitch_fwd", &"rotate_pitch_back",
			&"rotate_roll_left", &"rotate_roll_right", &"rotation_mode", &"rotate_reset",
			&"rotate_drag", &"rotate_snap", &"rotate_drag_pad",
		],
	},
	{
		"name": "Camera",
		"actions": [
			&"camera_mode", &"camera_orbit",
			&"camera_pan_left", &"camera_pan_right", &"camera_pan_forward", &"camera_pan_back",
			&"camera_modifier", &"camera_zoom_in", &"camera_zoom_out",
			&"camera_snap_home", &"camera_snap_goal", &"camera_reset",
		],
	},
	{
		"name": "Menu / System",
		"actions": [&"pause_menu", &"show_scores", &"chat_open"],
	},
]

## Bontago-1pi.159.3: the category tabs. Owner 2026-10-10: the first one reads "Game" (it was
## "Settings"); ids, node names and every stored settings key are unchanged.
const TAB_GAME: StringName = &"game"
const TAB_GRAPHICS: StringName = &"graphics"
const TAB_CONTROLS: StringName = &"controls"
## [id, label, unique node name] per tab, left to right.
const TAB_ENTRIES: Array[Array] = [
	[TAB_GAME, "Game", "SettingsTabButton"],
	[TAB_GRAPHICS, "Graphics", "GraphicsTabButton"],
	[TAB_CONTROLS, "Controls", "ControlsTabButton"],
]
const SECTION_DISPLAY: String = "Display"
const SECTION_AUDIO: String = "Audio"
const SECTION_RUMBLE: String = "Rumble"
const ROW_WINDOW: String = "Window"
const ROW_UI_SCALE: String = "UI scale"
const ROW_HUD_SCALE: String = "HUD scale"
const ROW_MINIMAP_SIZE: String = "Minimap size"
const ROW_CAMERA_SHAKE: String = "Camera shake"
const ROW_ADAPTIVE_QUALITY: String = "Adaptive quality"
const ROW_FOV: String = "Field of view"
const ROW_MASTER_VOLUME: String = "Master volume"
const ROW_MUSIC_VOLUME: String = "Music volume"
const ROW_SFX_VOLUME: String = "SFX volume"
const ROW_WEATHER_VOLUME: String = "Weather volume"
const ROW_RUMBLE: String = "Rumble"
const ROW_RUMBLE_INTENSITY: String = "Rumble intensity"

const KEY_REBIND_ROW_SCENE: PackedScene = preload("res://ui/menus/KeyRebindRow.tscn")

## Bontago-hfa.4 (UI reskin P2): sizes specific to the Options/Pause/rebinding screens; every
## colour and radius comes from ArcadeVisualTuning through MenuStyleFactory.arcade_tuning().
const OPTIONS_TUNING: OptionsVisualTuning = preload("res://config/ui/options_visual_tuning.tres")
const ON_WORD: String = "ON"
const OFF_WORD: String = "OFF"
const STATE_WORD_NAME: String = "StateWord"
const THEME_VARIATION_DISPLAY: StringName = &"DisplayLabel"
const THEME_VARIATION_CAPTION: StringName = &"CaptionLabel"
const THEME_VARIATION_FIELD: StringName = &"FieldLabel"

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
## (ui/theme/MenuStyleFactory.gd, config/ui/menu_visual_tuning.tres already
## shipped by the just-merged main menu/lobby reskin) -- everything else on
## this menu keeps the shared stackfall_theme.tres Button/OptionButton look.
@export var tuning: MenuVisualTuning = preload("res://config/ui/menu_visual_tuning.tres")

## Footer device hint text (owner: "show a device hint in the footer ...
## matching the active device") and the Controls page's own device caption --
## plain literals rather than a config/*.tres Resource, since these are
## display-only strings, not gameplay/physics tuning (CLAUDE.md's
## no-magic-numbers rule targets those).
## Bontago-1pi.71: InputPromptFlow templates -- `{action}` renders the bound
## action's glyph for the active device, so no key or button name is typed here.
const FOOTER_HINT_KEYBOARD_MOUSE: String = "{ui_accept} Select   {ui_cancel} Back"
const FOOTER_HINT_GAMEPAD: String = "{ui_accept} Select   {ui_cancel} Back   {menu_tab_previous} {menu_tab_next} Tabs"
const CONTROLS_LABEL_KEYBOARD_MOUSE: String = "Showing keyboard & mouse bindings"
const CONTROLS_LABEL_GAMEPAD: String = "Showing gamepad bindings"

## DECISION (ui/menus/OptionsMenu.gd): the volume/rumble/move-speed sliders' own
## range/step are scene-level widget configuration, not a "magic number" a
## config/*.tres Resource needs to own -- CLAUDE.md's no-magic-numbers rule
## targets gameplay/physics tuning that changes game feel; a UI slider's own
## bounds don't (Settings.gd itself owns each field's real default and
## clamps it to a generic safety floor -- see Settings.set_mouse_move_speed_
## scale()'s own DECISION). Owner request: 0-100% for every volume/rumble
## slider, 50%-200% for the move-speed sliders (default 100%).
## Bontago-1pi.159.3: the Game / Controls meters are UiSegmentMeters (cells, not a continuous slider).
## DECISION: volume and rumble use 20 cells (5% per cell), the move-speed scale 15 cells (0.1x per cell,
## so 100% sits exactly on a cell); the UI-scale meter has one cell per UiScaleTuning step. The readout
## of volume / rumble shows the stored value, so a saved 73% still reads 73% until it is edited.
const PERCENT_METER_CELLS: int = 20
const MOVE_SPEED_CELLS: int = 15
const MIN_VOLUME_PERCENT: float = 0.0
const MAX_VOLUME_PERCENT: float = 1.0
const MIN_RUMBLE_STRENGTH: float = 0.0
const MAX_RUMBLE_STRENGTH: float = 1.0
const MIN_MOVE_SPEED_SCALE: float = 0.5
const MAX_MOVE_SPEED_SCALE: float = 2.0

## DECISION (ui/menus/OptionsMenu.gd): which speaker icon a mute button shows for a
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
## Help-line key of the Mouse / Stick speed row (text in config/ui/option_help_table.tres).
const MOVE_SPEED_HELP_KEY: String = "MoveSpeedSlider"
const MOVE_SPEED_LABEL_MOUSE: String = "Mouse speed"
const MOVE_SPEED_LABEL_STICK: String = "Stick speed"

## Bontago-1pi.11.86: the Graphics page (preset picker + per-setting controls), built in code.
@onready var _graphics_page: GraphicsSettingsTab = %GraphicsPage
@onready var _rebind_list: VBoxContainer = %RebindList
@onready var _back_button: Button = %BackButton
@onready var _reset_button: Button = %ResetButton
@onready var _tabs: UiTabs = %Tabs
@onready var _help_line: UiHelpLine = %HelpLine
@onready var _settings_page: ScrollContainer = %SettingsPage
@onready var _settings_fields: VBoxContainer = %SettingsFields
@onready var _controls_page: VBoxContainer = %ControlsPage
@onready var _controls_device_label: Label = %ControlsDeviceLabel
@onready var _footer_hint_label: InputPromptFlow = %FooterHintLabel

## Bontago-1pi.159.3: the Game and Controls pages are built from design-system components
## (UiRow / UiSection / UiToggle / UiDropdown / UiSegmentMeter / UiIconButton), so their controls are
## plain members assigned by _build_game_page() / _build_move_speed_row(), each registered under its
## old %UniqueName (probes, tests and the focus chain keep resolving the same names).
var _master_mute_button: UiIconButton = null
var _master_volume_slider: UiSegmentMeter = null
var _music_mute_button: UiIconButton = null
var _music_volume_slider: UiSegmentMeter = null
var _sfx_mute_button: UiIconButton = null
var _sfx_volume_slider: UiSegmentMeter = null
var _weather_mute_button: UiIconButton = null
var _weather_volume_slider: UiSegmentMeter = null
var _camera_shake_check: UiToggle = null
var _adaptive_quality_check: UiToggle = null
var _fov_slider: UiSegmentMeter = null
var _window_mode_option: UiDropdown = null
var _ui_scale_slider: UiSegmentMeter = null
var _hud_scale_slider: UiSegmentMeter = null
var _minimap_size_option: UiDropdown = null
var _rumble_enabled_check: UiToggle = null
var _rumble_strength_slider: UiSegmentMeter = null
var _move_speed_label: Label = null
var _move_speed_slider: UiSegmentMeter = null

var _rows: Array[KeyRebindRow] = []
## Bontago-1pi.150: a mouse drag on the UI-scale meter previews the % and applies on release
## (rescaling the canvas under the cursor mid-drag would make the pointer run away).
var _dragging_meter: UiSegmentMeter = null
## Each component meter's value range, so its cell count maps to the setting's own unit.
var _meter_ranges: Dictionary[UiSegmentMeter, Vector2] = {}
## True after present() until the Graphics page re-reads Settings (see present()).
var _graphics_stale: bool = false


func _ready() -> void:
	if settings_provider == null:
		settings_provider = Settings
	_adopt_panel_layout()
	_build_game_page()
	_build_move_speed_row()
	_build_tabs()
	_help_line.bind(_settings_page.get_parent() as Control)
	_graphics_page.build(func() -> Variant: return settings_provider, self)
	UiBlockButton.style(_reset_button, UiBlockButton.Look.SECONDARY, true)
	UiBlockButton.style(_back_button, UiBlockButton.Look.SECONDARY, true)
	_controls_device_label.theme_type_variation = THEME_VARIATION_CAPTION
	_controls_page.add_theme_constant_override("separation", MenuStyleFactory.arcade_tuning().space_3_px)

	_build_window_mode_items()
	_load_current_values()
	_build_rebind_rows()
	_refresh_layout()
	get_viewport().size_changed.connect(_refresh_layout)
	_wire_focus_chain()
	_refresh_device_dependent_ui()

	_master_volume_slider.value_changed.connect(_on_meter_changed.bind(_master_volume_slider))
	_master_mute_button.pressed.connect(_on_master_mute_pressed)
	_music_volume_slider.value_changed.connect(_on_meter_changed.bind(_music_volume_slider))
	_music_mute_button.pressed.connect(_on_music_mute_pressed)
	_sfx_volume_slider.value_changed.connect(_on_meter_changed.bind(_sfx_volume_slider))
	_sfx_mute_button.pressed.connect(_on_sfx_mute_pressed)
	_weather_volume_slider.value_changed.connect(_on_meter_changed.bind(_weather_volume_slider))
	_weather_mute_button.pressed.connect(_on_weather_mute_pressed)
	_camera_shake_check.toggled.connect(_on_camera_shake_toggled)
	_adaptive_quality_check.toggled.connect(_on_adaptive_quality_toggled)
	_fov_slider.value_changed.connect(_on_meter_changed.bind(_fov_slider))
	_window_mode_option.item_selected.connect(_on_window_mode_selected)
	_rumble_enabled_check.toggled.connect(_on_rumble_enabled_toggled)
	_ui_scale_slider.value_changed.connect(_on_meter_changed.bind(_ui_scale_slider))
	_ui_scale_slider.gui_input.connect(_on_scale_meter_gui_input.bind(_ui_scale_slider))
	_hud_scale_slider.gui_input.connect(_on_scale_meter_gui_input.bind(_hud_scale_slider))
	_hud_scale_slider.value_changed.connect(_on_meter_changed.bind(_hud_scale_slider))
	_minimap_size_option.item_selected.connect(_on_minimap_size_selected)
	_rumble_strength_slider.value_changed.connect(_on_meter_changed.bind(_rumble_strength_slider))
	_rumble_strength_slider.gui_input.connect(_on_rumble_strength_gui_input)
	_move_speed_slider.value_changed.connect(_on_meter_changed.bind(_move_speed_slider))
	_back_button.pressed.connect(_on_back_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	Events.input_device_changed.connect(_on_input_device_changed)

	_window_mode_option.grab_focus()


## DECISION (Bontago-1pi.11.92): the opener (MainMenu / PauseMenu) builds this menu once and
## keeps it hidden between opens instead of freeing it (the ~390 ms rebuild per open).
## dismiss() hides it and stops its back-gesture input; present() shows it again exactly as a
## fresh _ready() left it: Game tab, values re-read from Settings, window-mode row focused.
func dismiss() -> void:
	visible = false
	set_process_unhandled_input(false)


func present() -> void:
	set_process_unhandled_input(true)
	visible = true
	_tabs.select(TAB_GAME)
	_settings_page.scroll_vertical = 0
	# The Graphics page re-reads Settings only when its tab is shown (_on_tab_changed): that
	# refresh is the one costly part (~36 ms). Device-dependent UI is already kept current by
	# _on_input_device_changed while hidden, so it is not redone here.
	_graphics_stale = true
	_load_current_values(false)
	_window_mode_option.grab_focus()


## The design-system panel (UiPanel: plate, heading with flare bullet, content column) adopts the
## authored page layout, so the screen owns no plate / heading / spacing code of its own.
func _adopt_panel_layout() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var scrim: Color = arcade.disc_900_color
	scrim.a = arcade.scrim_alpha
	($Background as ColorRect).color = scrim
	var panel: UiPanel = $Frame/Panel as UiPanel
	var layout: Control = panel.get_node("Layout") as Control
	panel.content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for child: Node in layout.get_children():
		child.reparent(panel.content, false)
		child.owner = self
	panel.remove_child(layout)
	layout.free()


## Registers [param node] under [param unique_name] (`%Name` lookups) once it is in the tree.
func _register(node: Node, unique_name: String) -> void:
	node.name = unique_name
	node.owner = self
	node.unique_name_in_owner = true


## Game page: Display / Audio / Rumble sections of UiRows (toggles, dropdown, meters).
func _build_game_page() -> void:
	_settings_fields.add_theme_constant_override("separation", MenuStyleFactory.arcade_tuning().space_4_px)
	var display: VBoxContainer = _add_section(SECTION_DISPLAY)
	_window_mode_option = UiDropdown.new()
	_add_row(display, ROW_WINDOW, _window_mode_option, "WindowModeOption")
	_ui_scale_slider = _make_meter(UiScaleTuning.shared().min_scale, UiScaleTuning.shared().max_scale, ui_scale_cell_count())
	_add_row(display, ROW_UI_SCALE, _ui_scale_slider, "UiScaleSlider")
	_ui_scale_slider.formatter = func(cells: int) -> String: return _format_percent(_meter_value(_ui_scale_slider, cells))
	_hud_scale_slider = _make_meter(UiScaleTuning.shared().min_scale, UiScaleTuning.shared().max_scale, ui_scale_cell_count())
	_add_row(display, ROW_HUD_SCALE, _hud_scale_slider, "HudScaleSlider")
	_hud_scale_slider.formatter = func(cells: int) -> String: return _format_percent(_meter_value(_hud_scale_slider, cells))
	_minimap_size_option = UiDropdown.new()
	_add_row(display, ROW_MINIMAP_SIZE, _minimap_size_option, "MinimapSizeOption")
	for label: String in UiScaleTuning.shared().minimap_size_labels:
		_minimap_size_option.add_item(label)
	_camera_shake_check = UiToggle.new()
	_add_row(display, ROW_CAMERA_SHAKE, _camera_shake_check, "CameraShakeCheck")
	_adaptive_quality_check = UiToggle.new()
	_add_row(display, ROW_ADAPTIVE_QUALITY, _adaptive_quality_check, "AdaptiveQualityCheck")
	var lens: CameraTuning = _SHARED_CAMERA_TUNING
	_fov_slider = _make_meter(lens.fov_min_deg, lens.fov_max_deg, _fov_cell_count(lens))
	_add_row(display, ROW_FOV, _fov_slider, "FovSlider")
	_fov_slider.formatter = func(cells: int) -> String: return "%d°" % roundi(_meter_value(_fov_slider, cells))

	var audio: VBoxContainer = _add_section(SECTION_AUDIO)
	_master_volume_slider = _make_percent_meter()
	_master_mute_button = _add_channel_row(audio, ROW_MASTER_VOLUME, _master_volume_slider, "Master")
	_master_volume_slider.formatter = func(_cells: int) -> String: return _format_percent(float(settings_provider.master_volume_percent()))
	_music_volume_slider = _make_percent_meter()
	_music_mute_button = _add_channel_row(audio, ROW_MUSIC_VOLUME, _music_volume_slider, "Music")
	_music_volume_slider.formatter = func(_cells: int) -> String: return _format_percent(float(settings_provider.music_volume_percent()))
	_sfx_volume_slider = _make_percent_meter()
	_sfx_mute_button = _add_channel_row(audio, ROW_SFX_VOLUME, _sfx_volume_slider, "Sfx")
	_sfx_volume_slider.formatter = func(_cells: int) -> String: return _format_percent(float(settings_provider.sfx_volume_percent()))
	_weather_volume_slider = _make_percent_meter()
	_weather_mute_button = _add_channel_row(audio, ROW_WEATHER_VOLUME, _weather_volume_slider, "Weather")
	_weather_volume_slider.formatter = func(_cells: int) -> String: return _format_percent(float(settings_provider.weather_volume_percent()))

	var rumble: VBoxContainer = _add_section(SECTION_RUMBLE)
	_rumble_enabled_check = UiToggle.new()
	_add_row(rumble, ROW_RUMBLE, _rumble_enabled_check, "RumbleEnabledCheck")
	_rumble_strength_slider = _make_percent_meter()
	_add_row(rumble, ROW_RUMBLE_INTENSITY, _rumble_strength_slider, "RumbleStrengthSlider")
	_rumble_strength_slider.formatter = func(_cells: int) -> String: return _format_percent(float(settings_provider.rumble_strength()))
	for first: Control in [_window_mode_option, _master_mute_button, _rumble_enabled_check]:
		_reveal_section_on_focus(first, first.get_parent().get_parent().get_parent() as UiSection)


## Controls page: the device-aware Mouse / Stick speed row between the caption and the rebind list.
func _build_move_speed_row() -> void:
	var row: UiRow = UiRow.new().setup(MOVE_SPEED_LABEL_MOUSE)
	_move_speed_label = row.label
	_move_speed_slider = _make_meter(MIN_MOVE_SPEED_SCALE, MAX_MOVE_SPEED_SCALE, MOVE_SPEED_CELLS)
	row.add_item(_move_speed_slider)
	UiHelpLine.tag(row, MOVE_SPEED_HELP_KEY)
	_controls_page.add_child(row)
	_controls_page.move_child(row, _controls_device_label.get_index() + 1)
	_register(_move_speed_slider, "MoveSpeedSlider")
	_register(_move_speed_label, "MoveSpeedLabel")
	_move_speed_slider.formatter = func(_cells: int) -> String: return _format_percent(_active_move_speed())


## One UiSection (caption header + Body column) on the Game page; returns its Body.
func _add_section(title: String) -> VBoxContainer:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var section: UiSection = UiSection.new()
	section.title = title
	section.add_theme_constant_override("separation", arcade.space_2_px)
	var body: VBoxContainer = VBoxContainer.new()
	body.name = UiSection.BODY_NAME
	body.add_theme_constant_override("separation", arcade.space_3_px)
	section.add_child(body)
	_settings_fields.add_child(section)
	return body


func _add_row(parent: Control, label_text: String, control: Control, unique_name: String) -> UiRow:
	var row: UiRow = UiRow.new().setup(label_text, control)
	parent.add_child(row)
	UiHelpLine.tag(row, unique_name)
	_register(control, unique_name)
	return row


## A volume row: mute block, then the meter (its readout is the meter's own value cell).
func _add_channel_row(parent: Control, label_text: String, meter: UiSegmentMeter, channel: String) -> UiIconButton:
	var mute: UiIconButton = UiIconButton.new()
	mute.set_icon_texture(SPEAKER_HIGH_ICON)
	var row: UiRow = UiRow.new().setup(label_text, mute)
	row.add_item(meter)
	parent.add_child(row)
	_register(mute, channel + "MuteButton")
	_register(meter, channel + "VolumeSlider")
	return mute


## Cells on the FOV meter: one per CameraTuning.fov_step_deg (a non-positive step falls back to one cell).
func _fov_cell_count(lens: CameraTuning) -> int:
	if lens.fov_step_deg <= 0.0:
		return 1
	return maxi(1, roundi((lens.fov_max_deg - lens.fov_min_deg) / lens.fov_step_deg))


## A UiSegmentMeter with [param cells] cells mapped onto [param low]..[param high].
func _make_meter(low: float, high: float, cells: int) -> UiSegmentMeter:
	var meter: UiSegmentMeter = UiSegmentMeter.new()
	meter.step_count = cells
	_meter_ranges[meter] = Vector2(low, high)
	return meter


func _make_percent_meter() -> UiSegmentMeter:
	return _make_meter(MIN_VOLUME_PERCENT, MAX_VOLUME_PERCENT, PERCENT_METER_CELLS)


## The setting value [param cells] filled cells of [param meter] stand for.
func _meter_value(meter: UiSegmentMeter, cells: int) -> float:
	var span: Vector2 = _meter_ranges[meter]
	return span.x + (span.y - span.x) * float(cells) / float(meter.step_count)


## The filled-cell count showing [param value] on [param meter] (nearest cell).
func _meter_cells(meter: UiSegmentMeter, value: float) -> int:
	var span: Vector2 = _meter_ranges[meter]
	return roundi((value - span.x) / (span.y - span.x) * float(meter.step_count))


## Sets [param meter] to show [param value] without emitting.
func _show_meter_value(meter: UiSegmentMeter, value: float) -> void:
	meter.set_value_silent(_meter_cells(meter, value))
	meter.queue_redraw()


## One cell per UI-scale step (so 100% sits exactly on a cell).
static func ui_scale_cell_count() -> int:
	var tuning: UiScaleTuning = UiScaleTuning.shared()
	return roundi((tuning.max_scale - tuning.min_scale) / tuning.step)


## The three category tabs (UiTabs, LB / RB cycle them). The node names stay the same
## `%SettingsTabButton` / `%GraphicsTabButton` / `%ControlsTabButton` ids that tests and probes
## use; the first tab's label is "Game" (owner 2026-10-10), its stored settings keys are unchanged.
func _build_tabs() -> void:
	# Shoulder handling stays here: it must not fire while a binding row is listening.
	_tabs.handle_shoulders = false
	for entry: Array in TAB_ENTRIES:
		var id: StringName = entry[0] as StringName
		_tabs.add_tab(id, entry[1] as String)
		var tab: UiTab = _tabs.get_tab(id)
		_register(tab, entry[2] as String)
		tab.toggled.connect(_on_tab_toggled.bind(id))
	_tabs.tab_changed.connect(_on_tab_changed)


## DECISION (Bontago-mp0.11): the panel follows the usable viewport instead
## of demanding a desktop sized minimum; the settings page scrolls vertically.
func _refresh_layout() -> void:
	var available: Vector2 = get_viewport_rect().size - Vector2.ONE * tuning.menu_edge_margin_px * 2.0
	var panel: PanelContainer = $Frame/Panel
	panel.custom_minimum_size = Vector2(minf(available.x, tuning.menu_max_width_px), available.y)


## A category tab became active (click, LB / RB, or code): show only its page. Owner: "switch to
## only gamepad options on gamepad input and switch back on mouse/keyboard input".
func _on_tab_changed(id: StringName) -> void:
	_settings_page.visible = id == TAB_GAME
	_graphics_page.visible = id == TAB_GRAPHICS
	if id == TAB_GRAPHICS and _graphics_stale:
		_graphics_stale = false
		_graphics_page.refresh_from_settings()
	_controls_page.visible = id == TAB_CONTROLS
	_wire_tab_focus()
	_trap_focus()


## A tab's `button_pressed` was set from code (tests, probes): route it through the bar.
func _on_tab_toggled(pressed: bool, id: StringName) -> void:
	if pressed:
		_tabs.select(id)


## Bontago-1pi.71: a rebind of ui_accept/ui_cancel/menu_tab_* must show in the footer glyphs.
func _on_row_rebind_captured(_action: StringName, _event: InputEvent) -> void:
	_footer_hint_label.refresh()


func _on_input_device_changed(_device: StringName) -> void:
	_refresh_device_dependent_ui()


func _refresh_device_dependent_ui() -> void:
	var gamepad: bool = Settings.active_input_device() == Settings.DEVICE_GAMEPAD
	_footer_hint_label.set_template(FOOTER_HINT_GAMEPAD if gamepad else FOOTER_HINT_KEYBOARD_MOUSE)
	_controls_device_label.text = CONTROLS_LABEL_GAMEPAD if gamepad else CONTROLS_LABEL_KEYBOARD_MOUSE
	_refresh_move_speed_row()
	# Bontago-1pi.41: which rows exist on the page depends on the device (rows
	# with no gamepad function hide), so the focus chain follows it.
	_wire_focus_chain()
	_refresh_row_bands()


## Bontago-hfa.4: alternate (lightly banded) binding rows, counted over the rows the active
## device page actually shows so a hidden row never breaks the rhythm.
func _refresh_row_bands() -> void:
	var shown: int = 0
	for row: KeyRebindRow in _rows:
		if not row.is_available_on_active_device():
			continue
		row.set_banded(shown % 2 == 1)
		shown += 1


## Owner correction (options package, mid-review): one device-aware row on
## the Controls tab rebinds itself to whichever scale the active device
## actually drives -- "Mouse speed" / Settings.mouse_move_speed_scale() on
## keyboard/mouse, "Stick speed" / Settings.stick_move_speed_scale() on
## gamepad -- rather than two rows toggling visibility (DECISION,
## ui/menus/OptionsMenu.gd). Reusing the same Slider node for both means whichever
## control had focus keeps it across a live device switch for free -- no
## separate focus-transfer step needed, since the node itself never changes.
func _refresh_move_speed_row() -> void:
	var gamepad: bool = Settings.active_input_device() == Settings.DEVICE_GAMEPAD
	_move_speed_label.text = MOVE_SPEED_LABEL_STICK if gamepad else MOVE_SPEED_LABEL_MOUSE
	_show_meter_value(_move_speed_slider, _active_move_speed())


## The stored move-speed scale of the active input device.
func _active_move_speed() -> float:
	if Settings.active_input_device() == Settings.DEVICE_GAMEPAD:
		return float(settings_provider.stick_move_speed_scale())
	return float(settings_provider.mouse_move_speed_scale())


## ui_cancel (Escape / gamepad B, spec 2.10) backs out -- the same
## _unhandled_input()/set_input_as_handled() pattern ui/menus/Tutorial.gd's own
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
		var ids: Array[StringName] = _tabs.tab_ids()
		var step: int = 1 if event.is_action_pressed(&"menu_tab_next") else -1
		_tabs.select(ids[UiTabs.next_index(ids.find(_tabs.current), step, ids.size())], true)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


## Bontago-xtq.45 (M7 P4): reads Settings.WINDOW_MODE_IDS/window_mode_label()
## directly (a fixed, script-level constant/lookup, not per-provider state)
## rather than duplicating PRESET_LABELS' own hand-written parallel-array
## pattern -- the ids and their display order already live in one place.
func _build_window_mode_items() -> void:
	_window_mode_option.clear()
	for id: StringName in Settings.WINDOW_MODE_IDS:
		_window_mode_option.add_item(Settings.window_mode_label(id))


func _load_current_values(include_graphics: bool = true) -> void:
	if include_graphics:
		_graphics_stale = false
		_graphics_page.refresh_from_settings()

	_load_channel_row(_master_mute_button, _master_volume_slider, settings_provider.master_muted(), settings_provider.master_volume_percent())
	_load_channel_row(_music_mute_button, _music_volume_slider, settings_provider.music_muted(), settings_provider.music_volume_percent())
	_load_channel_row(_sfx_mute_button, _sfx_volume_slider, settings_provider.sfx_muted(), settings_provider.sfx_volume_percent())
	_load_channel_row(_weather_mute_button, _weather_volume_slider, settings_provider.weather_muted(), settings_provider.weather_volume_percent())

	_camera_shake_check.set_on_silent(bool(settings_provider.camera_shake_enabled()))
	_adaptive_quality_check.set_on_silent(bool(settings_provider.adaptive_quality_enabled()))

	var window_mode_id: StringName = settings_provider.window_mode()
	var window_mode_index: int = Settings.WINDOW_MODE_IDS.find(window_mode_id)
	_window_mode_option.select(window_mode_index if window_mode_index >= 0 else Settings.WINDOW_MODE_IDS.find(Settings.DEFAULT_WINDOW_MODE_ID))

	_show_meter_value(_fov_slider, _current_fov_deg())
	_show_meter_value(_ui_scale_slider, float(settings_provider.ui_scale()))
	_show_meter_value(_hud_scale_slider, float(settings_provider.hud_scale()))
	_minimap_size_option.select(int(settings_provider.minimap_size_preset()))
	_rumble_enabled_check.set_on_silent(bool(settings_provider.rumble_enabled()))
	_show_meter_value(_rumble_strength_slider, float(settings_provider.rumble_strength()))
	_refresh_rumble_strength_enabled()

	_refresh_move_speed_row()


## Shows one volume row: the meter at [param percent] (dust cells and no input while muted, so a
## muted channel reads as off) and the speaker icon for its state.
func _load_channel_row(mute_button: UiIconButton, slider: UiSegmentMeter, muted: bool, percent: float) -> void:
	_show_meter_value(slider, percent)
	mute_button.set_icon_texture(_icon_for_channel(muted, percent))
	slider.editable = not muted


func _on_preset_selected(index: int) -> void:
	_graphics_page.pick_preset(index)


# --- Audio channels (Master/Music/SFX) ----------------------------------------

## A component meter moved by the user: converts its cells to the setting's unit and hands them to the
## per-setting handler below (the UI-scale and rumble-intensity meters also see mouse drags, see
## _on_scale_meter_gui_input()).
func _on_meter_changed(cells: int, meter: UiSegmentMeter) -> void:
	var value: float = _meter_value(meter, cells)
	if meter == _master_volume_slider:
		_on_master_volume_changed(value)
	elif meter == _music_volume_slider:
		_on_music_volume_changed(value)
	elif meter == _sfx_volume_slider:
		_on_sfx_volume_changed(value)
	elif meter == _weather_volume_slider:
		_on_weather_volume_changed(value)
	elif meter == _ui_scale_slider:
		_on_ui_scale_changed(value)
	elif meter == _hud_scale_slider:
		# Previews live during a mouse drag; the release saves (see _on_scale_meter_gui_input).
		settings_provider.set_hud_scale(value, _dragging_meter != _hud_scale_slider)
	elif meter == _rumble_strength_slider:
		_on_rumble_strength_changed(value)
	elif meter == _move_speed_slider:
		_on_move_speed_changed(value)
	elif meter == _fov_slider:
		settings_provider.set_fov_override_deg(value)


func _on_master_volume_changed(value: float) -> void:
	settings_provider.set_master_volume_percent(value)
	_load_channel_row(_master_mute_button, _master_volume_slider, settings_provider.master_muted(), settings_provider.master_volume_percent())


func _on_master_mute_pressed() -> void:
	settings_provider.toggle_master_mute()
	_load_channel_row(_master_mute_button, _master_volume_slider, settings_provider.master_muted(), settings_provider.master_volume_percent())


func _on_music_volume_changed(value: float) -> void:
	settings_provider.set_music_volume_percent(value)
	_load_channel_row(_music_mute_button, _music_volume_slider, settings_provider.music_muted(), settings_provider.music_volume_percent())


func _on_music_mute_pressed() -> void:
	settings_provider.toggle_music_mute()
	_load_channel_row(_music_mute_button, _music_volume_slider, settings_provider.music_muted(), settings_provider.music_volume_percent())


func _on_sfx_volume_changed(value: float) -> void:
	settings_provider.set_sfx_volume_percent(value)
	_load_channel_row(_sfx_mute_button, _sfx_volume_slider, settings_provider.sfx_muted(), settings_provider.sfx_volume_percent())


func _on_sfx_mute_pressed() -> void:
	settings_provider.toggle_sfx_mute()
	_load_channel_row(_sfx_mute_button, _sfx_volume_slider, settings_provider.sfx_muted(), settings_provider.sfx_volume_percent())


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


func _on_weather_volume_changed(value: float) -> void:
	settings_provider.set_weather_volume_percent(value)
	_load_channel_row(_weather_mute_button, _weather_volume_slider, settings_provider.weather_muted(), settings_provider.weather_volume_percent())


func _on_weather_mute_pressed() -> void:
	settings_provider.toggle_weather_mute()
	_load_channel_row(_weather_mute_button, _weather_volume_slider, settings_provider.weather_muted(), settings_provider.weather_volume_percent())


## Bontago-1pi.11.37: opt-in governor; the stored preset is never touched.
func _on_adaptive_quality_toggled(enabled: bool) -> void:
	settings_provider.set_adaptive_quality_enabled(enabled)


## The lens the slider shows: the player's saved value, else the CameraTuning baseline.
func _current_fov_deg() -> float:
	var chosen: float = float(settings_provider.fov_override_deg())
	return chosen if chosen > 0.0 else _SHARED_CAMERA_TUNING.fov_deg


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
	_rumble_strength_slider.editable = bool(settings_provider.rumble_enabled())


func _on_minimap_size_selected(index: int) -> void:
	settings_provider.set_minimap_size_preset(index)


func _on_ui_scale_changed(value: float) -> void:
	if _dragging_meter != _ui_scale_slider:
		settings_provider.set_ui_scale(value)


## A mouse drag on the UI-scale meter previews and applies on release (Bontago-1pi.150); on the HUD-scale
## meter it applies live but saves once on release (Bontago-1pi.193). The press marks the dragged meter before
## the meter's own handler sets the value, the release commits it.
func _on_scale_meter_gui_input(event: InputEvent, meter: UiSegmentMeter) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if click.pressed:
		_dragging_meter = meter
	elif _dragging_meter == meter:
		_dragging_meter = null
		var value: float = _meter_value(meter, meter.value)
		if meter == _ui_scale_slider:
			settings_provider.set_ui_scale(value)
		else:
			settings_provider.set_hud_scale(value)


func _on_rumble_strength_changed(value: float) -> void:
	settings_provider.set_rumble_strength(value)


## Owner: "Nudge a short test rumble when the slider is released" (mouse release only, like the
## HSlider's drag_ended it replaces).
func _on_rumble_strength_gui_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click != null and click.button_index == MOUSE_BUTTON_LEFT and not click.pressed:
		Rumble.trigger_test_pulse()


# --- Block movement speed (Controls tab, device-aware) ------------------------

func _on_move_speed_changed(value: float) -> void:
	if Settings.active_input_device() == Settings.DEVICE_GAMEPAD:
		settings_provider.set_stick_move_speed_scale(value)
	else:
		settings_provider.set_mouse_move_speed_scale(value)


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
	settings_provider.reset_ui_scale()
	settings_provider.reset_hud_scale()
	settings_provider.reset_minimap_size()
	settings_provider.reset_fov_override()
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
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	header.text = header.text.to_upper()
	header.theme_type_variation = THEME_VARIATION_FIELD
	header.add_theme_font_size_override("font_size", arcade.font_size_label_px)
	header.add_theme_color_override("font_color", arcade.sand_color)
	# Bontago-hfa.4: a .sa-group rule header -- the label sits above a disc-600 rule.
	var spacing: StyleBoxEmpty = StyleBoxEmpty.new()
	spacing.content_margin_bottom = float(arcade.space_2_px + OPTIONS_TUNING.group_rule_px)
	header.add_theme_stylebox_override("normal", spacing)
	var rule: ColorRect = ColorRect.new()
	rule.color = arcade.disc_600_color
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	rule.offset_top = -float(OPTIONS_TUNING.group_rule_px)
	rule.offset_bottom = 0.0
	header.add_child(rule)


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
			row.rebind_captured.connect(_on_row_rebind_captured)
			_rows.append(row)
	_refresh_row_bands()


## Gamepad/keyboard navigability (docs/archive/M6_PLAN.md package C2: "fully
## navigable with gamepad and keyboard"): chains every focusable control top
## to bottom, in the same visual order the Settings tab actually lays rows
## out in (orchestrator review correction) -- PresetOption -> WindowModeOption
## -> CameraShakeCheck -> Master/Music/SFX mute+volume -> Rumble
## toggle+intensity -> MoveSpeedSlider (Controls tab) -> each rebind row (a
## row IS its own Button now, Bontago-1pi.10 polish pass -- no separate child
## RebindButton) in section/build order -> ResetButton -> BackButton -> back
## up to PresetOption. Computed at runtime (control.get_path_to()) rather than
## static NodePaths in the .tscn, the same reason ui/menus/MainMenu.gd's own
## _apply_steam_availability() does this for its Steam-availability toggle:
## the rebind rows are built dynamically and don't exist yet when the scene
## file is authored.
##
## DECISION (Bontago-1pi.159.3): the tab strip is horizontal above the pages, so the tabs are not in
## this chain; _wire_tab_focus() links the visible page's first control and the tabs both ways.
## (Before this the tabs were a left column reached by the engine's automatic ui_left resolution.)
func _wire_focus_chain() -> void:
	var chain: Array[Control] = [
		_window_mode_option, _ui_scale_slider, _hud_scale_slider, _minimap_size_option, _camera_shake_check, _adaptive_quality_check, _fov_slider,
		_master_mute_button, _master_volume_slider,
		_music_mute_button, _music_volume_slider,
		_sfx_mute_button, _sfx_volume_slider,
		_weather_mute_button, _weather_volume_slider,
		_rumble_enabled_check, _rumble_strength_slider,
		_move_speed_slider,
	]
	for row: KeyRebindRow in _rows:
		# Bontago-1pi.41: a row hidden on the gamepad page (no pad function,
		# KeyRebindRow.PAD_NOT_APPLICABLE) must not be a focus-chain stop.
		if row.is_available_on_active_device():
			chain.append(row.rebind_button())
	chain.append_array(_graphics_page.focus_controls())
	chain.append(_reset_button)
	chain.append(_back_button)

	for i: int in range(chain.size()):
		var current: Control = chain[i]
		var prev: Control = chain[(i - 1 + chain.size()) % chain.size()]
		var next: Control = chain[(i + 1) % chain.size()]
		current.focus_neighbor_top = current.get_path_to(prev)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_mode = Control.FOCUS_ALL
	# Bontago-1pi.159.50/.51: the footer pair is a row, so ui_left / ui_right swap between them.
	_reset_button.focus_neighbor_right = _reset_button.get_path_to(_back_button)
	_back_button.focus_neighbor_left = _back_button.get_path_to(_reset_button)
	_reset_button.focus_neighbor_left = _reset_button.get_path_to(_back_button)
	_back_button.focus_neighbor_right = _back_button.get_path_to(_reset_button)
	_wire_tab_focus()
	_trap_focus()


## Bontago-1pi.159.15: no control inside the Options window may have a neighbour (or next /
## previous) outside it, or a dropdown's ui_left / ui_right jumps to the screen underneath.
## Re-run after every chain re-wire (device change) and tab switch; pages are built once in
## _ready, so these two call sites cover lazily-changed page content.
func _trap_focus() -> void:
	UiFocusTrap.trap(self)


## Bontago-1pi.159.3: the tab strip sits above the pages. ui_up from the visible page's first control
## reaches the active tab, ui_down from any tab reaches that first control (ui_left / ui_right on a
## tab step to its neighbour tab inside UiTabs), and ui_up from a tab wraps to Back.
func _wire_tab_focus() -> void:
	var first: Control = _first_focus_of_page(_tabs.current)
	var active: Control = _tabs.get_tab(_tabs.current)
	if first == null or active == null:
		return
	first.focus_neighbor_top = first.get_path_to(active)
	for id: StringName in _tabs.tab_ids():
		var tab: UiTab = _tabs.get_tab(id)
		tab.focus_neighbor_bottom = tab.get_path_to(first)
		tab.focus_neighbor_top = tab.get_path_to(_back_button)


## FocusScrollContainer only reveals caption Labels that are siblings of the focused control; a
## UiSection's caption sits in its own header row, so a section's first control reveals the header
## itself when it takes focus (walking up never leaves the caption clipped).
func _reveal_section_on_focus(control: Control, section: UiSection) -> void:
	control.focus_entered.connect(_reveal_section.bind(section))


func _reveal_section(section: UiSection) -> void:
	_settings_page.ensure_control_visible.call_deferred(section.get_child(0) as Control)


func _first_focus_of_page(id: StringName) -> Control:
	if id == TAB_GRAPHICS:
		var graphics: Array[Control] = _graphics_page.focus_controls()
		return graphics[0] if not graphics.is_empty() else null
	if id == TAB_CONTROLS:
		return _move_speed_slider
	return _window_mode_option
