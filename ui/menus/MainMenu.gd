class_name MainMenu
extends Control
## The game's front door (spec 2.6 "LAN discovery"; docs/archive/M3a_PLAN.md P4).
##
##  docs/archive/M3a_PLAN.md question 3: hot-seat is unlisted — this
## menu offers only Host, Join (LAN list or direct IP), Sandbox (docs/
## M6_PLAN.md package B1, spec 1.2), Tutorial (docs/archive/M6_PLAN.md package B3,
## spec 1.2) and Quit. Hot-seat is reachable solely through the `--hot-seat`
## command-line flag, which `Net.apply_command_line()` / `game/main/Main.gd`
## handle before this scene is even shown.
##
## Connects to Events and calls Net directly, the same "no deep node paths"
## convention ui/hud/HUD.gd uses; it does not know about ui/lobby/Lobby.gd or
## game/main/Main.gd. Whoever owns scene switching (the integrator's Main) listens
## for Events.net_mode_changed to know when to move on.

## DECISION (ui/menus/MainMenu.gd): `Variant` test seam, the same reason
## game/player/PlayerController.gd and ui/hud/HUD.gd have one — GUT cannot double a
## plain autoload, and Net is still P1's stub while this lands. Defaults to
## the real Net autoload; tests overwrite it with a FakeNet after
## add_child().
var net_provider: Variant = null

## docs/archive/M6_PLAN.md package B1: game/main/Main.gd instantiates this scene directly
## (`_show_main_menu()`) and connects to this signal the same way it connects
## to ui/lobby/Lobby.gd's own `start_requested` -- a direct child-signal connection,
## not the Events bus, since Main already owns this node's lifetime and this
## menu "does not know about ... game/main/Main.gd" (this file's own header
## comment above). Sandbox is still unlisted in the sense that spec 2.6 never
## asked for it in the Host/Join/Quit set this header describes, but the
## Main Menu is the one entry point spec 1.2 gives it (unlike hot-seat, which
## stays command-line only).
signal sandbox_requested

## docs/archive/M6_PLAN.md package B3: %TutorialButton's own signal, the same direct
## child-signal convention sandbox_requested above uses -- game/main/Main.gd's
## start_tutorial_from_menu() connects to this in _show_main_menu(),
## mirroring its own start_sandbox_from_menu() hookup.
signal tutorial_requested
signal bots_requested(player_name: String)

## the Debug page's Gift demo button asks game/main/Main.gd to start
## the sandbox with the gift-demo preset. Only ever emitted while debug mode is
## on: the entry is not even visible otherwise.
signal gift_demo_requested
signal tower_topple_requested
## the Debug page's Watch bots picker confirmed; game/main/Main.gd starts the all-bot match.
signal watch_bots_requested(options: RefCounted)

## Tagline shown on the Debug page in place of the wordmark's own tagline.
const DEBUG_TAGLINE: String = "DEBUG · GIFT DEMO"
const WATCH_BOTS_DIALOG_PATH: String = "res://ui/menus/WatchBotsDialog.gd"
const HOST_DIALOG_TITLE: String = "Host game"
const HOST_LOCAL_ID: StringName = &"local"
const HOST_STEAM_ID: StringName = &"steam"
const HOST_LOCAL_TEXT: String = "Host locally"
const HOST_STEAM_TEXT: String = "Host on Steam"
const HOST_DIALOG_QUESTION: String = "How should friends connect?"
const HOST_STEAM_UNAVAILABLE: String = "Steam is unavailable; host locally instead."

## docs/archive/M6_PLAN.md package C2: OptionsMenu.tscn is instanced/freed directly by
## this menu (ui/menus/OptionsMenu.gd's own header: "self-contained ... MainMenu
## instances this scene directly"), not routed through game/main/Main.gd -- the
## same reason sandbox_requested/tutorial_requested above are direct
## child-signal emits rather than an Events bus post, except this signal never
## even needs to leave MainMenu: _on_options_pressed()/_on_options_closed()
## below are both handlers and emitter in one file.
const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/menus/OptionsMenu.tscn")

## Well/list/compact-page sizes and the menu render budget (config/ui/menu_visual_tuning.tres);
## colours and block recipes come from ArcadeVisualTuning through MenuStyleFactory.
@export var tuning: MenuVisualTuning = preload("res://config/ui/menu_visual_tuning.tres")
## UI reskin P1: left column, scrim and lockup geometry.
@export var layout: MainMenuTuning = preload("res://config/ui/main_menu_tuning.tres")

@onready var _name_row: UiField = %NameField
@onready var _name_edit: LineEdit = _name_row.edit
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _play_local_button: Button = %PlayLocalButton
@onready var _bots_button: Button = %BotsButton
@onready var _back_button: Button = %BackButton
## the debug-only entry. A corner overlay on the menu root (not
## a child of the card's containers), so showing or hiding it can never move
## any other control; %GiftDemoButton lives on the Debug page.
@onready var _debug_button: Button = %DebugButton
@onready var _gift_demo_button: Button = %GiftDemoButton
@onready var _tower_topple_button: Button = %TowerToppleButton
@onready var _watch_bots_button: Button = %WatchBotsButton
## build label (BuildVersion.label()) in the top-right corner beside the Debug pill (moved off the bottom edge, which collided with the button column on short canvases).
@onready var _build_version_label: UiText = %BuildVersionLabel
@onready var _host_row: VBoxContainer = $Center/Panel/Layout/HostRow
@onready var _small_row: HBoxContainer = %SmallRow
@onready var _section_gap: Control = %SectionGap
@onready var _scrim: TextureRect = %Scrim
@onready var _join_tab_row: UiTabs = %JoinTabRow
## The two join tabs, added to the UiTabs bar in _ready() (still reachable as %JoinLanTabButton / %JoinSteamTabButton).
var _join_lan_tab_button: UiTab = null
var _join_steam_tab_button: UiTab = null
var _syncing_tabs: bool = false
@onready var _title_wrap: Control = $Center/Panel/Layout/TitleWrap
@onready var _tagline: UiText = $Center/Panel/Layout/Tagline
@onready var _game_list_stack: Control = $Center/Panel/Layout/LanGamesWell/LanGamesLayout/GameListStack
@onready var _steam_list_stack: Control = $Center/Panel/Layout/SteamSection/SteamGamesWell/SteamGamesLayout/SteamListStack
@onready var _sandbox_button: Button = %SandboxButton
@onready var _tutorial_button: Button = %TutorialButton
@onready var _options_button: Button = %OptionsButton
@onready var _quit_button: Button = %QuitButton
@onready var _center: CenterContainer = %Center
@onready var _game_list: ItemList = %GameList
@onready var _refresh_button: Button = %RefreshButton
## review r1, item 5: the sunken "well" card wrapping the
## header row + %GameList + %DirectRow -- one sunken panel instead of a
## standalone tall Refresh button and separator lines.
@onready var _lan_games_well: UiWell = %LanGamesWell
@onready var _direct_ip_field: UiField = %DirectIpField
@onready var _direct_ip_edit: LineEdit = _direct_ip_field.edit
@onready var _direct_join_button: Button = %DirectJoinButton
@onready var _status_label: UiText = %StatusLabel

## The transparent column plate: the buttons sit directly on the backdrop scrim.
@onready var _front_card: MarginContainer = %Panel
@onready var _title: TextureRect = %Title
@onready var _join_label: UiText = %JoinLabel
## mockup 10's bottom-right controller hint is a pill, not a
## bare Label -- %GamepadHintPill wraps the existing %GamepadHintBar Label in
## a PanelContainer so it reads as a chip instead of floating text.
@onready var _gamepad_hint_pill: UiWell = %GamepadHintPill
@onready var _hint_row: InputPromptFlow = %GamepadHintRow

## M3b (docs/archive/M3b_PLAN.md P3): the Steam section vs. the "not available" notice
## (spec 2.6: "Hide the online menu entries and show a notice").
@onready var _steam_section: VBoxContainer = %SteamSection
@onready var _host_online_button: Button = %HostOnlineButton
## the sunken "well" card wrapping the Steam header row +
## %SteamLobbyList -- same one-sunken-panel treatment as %LanGamesWell
## (review r1, item 5), replacing the old standalone tall
## "Refresh" button + bare sunken %SteamLobbyList.
@onready var _steam_games_well: UiWell = %SteamGamesWell
@onready var _steam_lobby_list: ItemList = %SteamLobbyList
@onready var _refresh_steam_button: Button = %RefreshSteamButton
@onready var _empty_state_label: Label = %EmptyStateLabel
## "No lobbies yet" inside the Steam well while
## _steam_lobbies is empty, mirroring %EmptyStateLabel's own role for
## %GameList (_rebuild_game_list()'s own "blank white box" fix).
@onready var _steam_empty_state_label: Label = %SteamEmptyStateLabel

var _games: Array[Dictionary] = []
var _steam_lobbies: Array[Dictionary] = []

## Seconds until the next automatic refresh_lobby_list() poll while the Steam
## section is visible (docs/archive/M3b_PLAN.md: "Steam's request_lobby_list() is
## pull-based ... call it on a config.steam_lobby_list_refresh_s timer"). A
## plain accumulator rather than a Timer node, since it only needs to run
## while _steam_section is visible and reads its interval from
## net_provider.config, which a Timer node's `wait_time` can't do without its
## own extra wiring code anyway.
var _steam_refresh_countdown_s: float = 0.0

const TAB_LAN: StringName = &"lan"
const TAB_STEAM: StringName = &"steam"
const JOIN_LAN_TAB_TEXT: String = "LAN / IP"
const JOIN_STEAM_TAB_TEXT: String = "STEAM"
const PAGE_HOME: int = 0
const PAGE_JOIN: int = 1
const PAGE_LOCAL: int = 2
const PAGE_DEBUG: int = 3
var _page: int = PAGE_HOME
## DECISION: "debug mode" is the project's single switch,
## DebugMode.is_enabled() (game/debug/DebugMode.gd: F1-F4 overlays, sandbox hotkeys),
## not a bare OS.is_debug_build(): the owner's `godot --path .` runs are debug
## runs automatically, `-- --no-debug` previews the player build, and an
## exported build never shows the entry. Read once per menu instance.
var _debug_entry_enabled: bool = false
var _home_tagline: String = ""
var _join_steam_tab: bool = false
var _host_dialog: UiDialog = null
var _host_steam_choice: Button = null
## built only while debug mode is on (see _build_watch_bots_dialog()).
var _watch_bots_dialog: UiDialog = null

## The live OptionsMenu.tscn instance while it's open, or null. Tracked here
## (rather than letting OptionsMenu free itself on `closed`) so
## _on_options_closed() can both queue_free() it and restore focus in one
## place, the same "one owner frees what it opened" convention
## _on_quit_pressed() implicitly follows via get_tree().quit().
var _options_menu: OptionsMenu = null
## the built-once Options window, hidden between opens (see OptionsMenu.present()).
var _options_cache: OptionsMenu = null
## Restores the focus modes UiFocusTrap.suspend_outside() cleared while Options is open.
var _restore_focus: Callable = Callable()


func _ready() -> void:
	net_provider = Net
	_debug_entry_enabled = DebugMode.is_enabled()
	_home_tagline = _tagline.text
	_register_component_names()
	_build_join_tabs()
	_add_searching_cells()
	_build_version_label.text = BuildVersion.label()
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_join_tab_row.tab_changed.connect(_on_join_tab_changed)
	_play_local_button.pressed.connect(_on_play_local_pressed)
	_bots_button.pressed.connect(_on_bots_pressed)
	_debug_button.pressed.connect(_on_debug_pressed)
	_gift_demo_button.pressed.connect(_on_gift_demo_pressed)
	_tower_topple_button.pressed.connect(_on_tower_topple_pressed)
	_watch_bots_button.pressed.connect(_on_watch_bots_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_init_name_field()
	_sandbox_button.pressed.connect(_on_sandbox_pressed)
	_tutorial_button.pressed.connect(_on_tutorial_pressed)
	_options_button.pressed.connect(_on_options_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_refresh_button.pressed.connect(_on_refresh_pressed)
	_direct_join_button.pressed.connect(_on_direct_join_pressed)
	_game_list.item_activated.connect(_on_game_activated)
	_host_online_button.pressed.connect(_on_host_online_pressed)
	_refresh_steam_button.pressed.connect(_on_refresh_steam_pressed)
	_steam_lobby_list.item_activated.connect(_on_steam_lobby_activated)
	_connect_click_and_hover_sounds()
	Events.net_games_discovered.connect(_on_games_discovered)
	Events.net_join_failed.connect(_on_join_failed)
	Events.net_steam_lobbies_discovered.connect(_on_steam_lobbies_discovered)
	net_provider.start_discovery()
	_apply_visual_style()
	_build_host_dialog()
	_build_watch_bots_dialog()
	_apply_steam_availability()
	get_viewport().size_changed.connect(_refresh_layout)
	_front_card.minimum_size_changed.connect(_refresh_layout)
	_set_page(PAGE_HOME)


## The inner nodes of the UiField / UiTabs components keep their old unique names, so the scene's
## %NameEdit / %DirectIpEdit / %JoinLanTabButton / %JoinSteamTabButton lookups still resolve.
func _register_component_names() -> void:
	_name_edit.name = &"NameEdit"
	_direct_ip_edit.name = &"DirectIpEdit"
	for edit: LineEdit in [_name_edit, _direct_ip_edit]:
		edit.owner = self
		edit.unique_name_in_owner = true


func _build_join_tabs() -> void:
	_join_tab_row.add_tab(TAB_LAN, JOIN_LAN_TAB_TEXT)
	_join_tab_row.add_tab(TAB_STEAM, JOIN_STEAM_TAB_TEXT)
	_join_lan_tab_button = _join_tab_row.get_tab(TAB_LAN)
	_join_steam_tab_button = _join_tab_row.get_tab(TAB_STEAM)
	_join_lan_tab_button.name = &"JoinLanTabButton"
	_join_steam_tab_button.name = &"JoinSteamTabButton"
	for tab: UiTab in [_join_lan_tab_button, _join_steam_tab_button]:
		tab.owner = self
		tab.unique_name_in_owner = true


## A tab press (mouse, Enter, stick or d-pad step) switches the transport; _set_page() mirrors
## page state back onto the bar without re-entering here.
func _on_join_tab_changed(id: StringName) -> void:
	if _syncing_tabs:
		return
	if id == TAB_STEAM:
		_on_join_steam_tab_pressed()
	else:
		_on_join_lan_tab_pressed()


func _process(delta: float) -> void:
	if not _steam_section.visible:
		return
	_steam_refresh_countdown_s -= delta
	if _steam_refresh_countdown_s <= 0.0:
		_on_refresh_steam_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if _page == PAGE_JOIN and bool(net_provider.steam_available()):
		if event.is_action_pressed("menu_tab_next"):
			_on_join_steam_tab_pressed()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("menu_tab_previous"):
			_on_join_lan_tab_pressed()
			get_viewport().set_input_as_handled()
			return
	if _page != PAGE_HOME and not _host_dialog.visible and not _watch_bots_open() and event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if net_provider != null:
		net_provider.stop_discovery()


# --- Button handlers ---------------------------------------------------------

## assets-audio package: UI button press/hover has no Events signal of its
## own (it isn't gameplay), so this calls Sfx directly -- the one named
## exception to "Sfx listens, nothing calls it" (autoload/Sfx.gd's header).
func _connect_click_and_hover_sounds() -> void:
	var buttons: Array[BaseButton] = [
		_host_button, _join_button, _join_lan_tab_button, _join_steam_tab_button, _play_local_button, _sandbox_button, _tutorial_button,
		_bots_button, _back_button, _options_button, _quit_button, _refresh_button,
		_direct_join_button, _refresh_steam_button, _debug_button,
		_gift_demo_button, _watch_bots_button,
	]
	for button: BaseButton in buttons:
		button.pressed.connect(_on_sound_button_pressed)
		button.mouse_entered.connect(_on_sound_button_hovered)


func _on_sound_button_pressed() -> void:
	Sfx.play(AudioConfig.EVENT_CLICK)


func _on_sound_button_hovered() -> void:
	Sfx.play(AudioConfig.EVENT_HOVER)


# --- Visual style (Stackfall Arcade) -------------------------------------------

## Dresses the scene's nodes in the Arcade look: a transparent left column over a disc-dark scrim,
## the lockup, one flare primary per page and disc-600 secondary blocks. Every colour is an
## ArcadeVisualTuning token (through MenuStyleFactory) and every size a MainMenuTuning /
## MenuVisualTuning export. Runs once from _ready().
func _apply_visual_style() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	_title_wrap.custom_minimum_size.y = layout.lockup_height_px
	_section_gap.custom_minimum_size.y = layout.section_gap_px
	_tagline.tint = arcade.sand_color
	_status_label.tint = arcade.alert_color
	_scrim.texture = _build_scrim_texture(arcade)
	_scrim.offset_right = layout.scrim_width_px
	_front_card.custom_minimum_size.x = layout.column_width_px
	_set_column_gap(layout.block_gap_px)
	_game_list_stack.custom_minimum_size.y = tuning.menu_lan_list_height_px
	_steam_list_stack.custom_minimum_size.y = tuning.menu_steam_list_height_px

	# The block looks (Host / Vs bots / Join IP primary, the rest secondary) are UiBlockButton exports
	# in the scene; only the layout heights come from MainMenuTuning.
	for large: Button in [_host_button, _join_button, _play_local_button, _bots_button, _sandbox_button,
			_tutorial_button, _gift_demo_button, _tower_topple_button, _watch_bots_button]:
		large.custom_minimum_size.y = layout.block_height_px
	# Options | Quit share the row (a small UiBlockButton hugs its content by default).
	for half: Button in [_options_button, _quit_button]:
		half.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# SVG icons import at a large intrinsic size; let the controls scale them into the row height.
	for button: Button in [_refresh_button, _refresh_steam_button, _direct_join_button, _back_button]:
		button.expand_icon = true
	_hint_row.set_text_color(arcade.sand_color)


## The vertical gap between the column's blocks.
func _set_column_gap(gap_px: int) -> void:
	($Center/Panel/Layout as UiStack).gap_px = gap_px


## The scrim behind the column: disc-900 at the scrim opacity, solid for the first
## scrim_solid_fraction of the width, then fading to nothing over the backdrop image.
func _build_scrim_texture(arcade: ArcadeVisualTuning) -> GradientTexture2D:
	var solid: Color = Color(arcade.disc_900_color, arcade.scrim_alpha)
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, layout.scrim_solid_fraction, 1.0])
	gradient.colors = PackedColorArray([solid, solid, Color(solid, 0.0)])
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = layout.scrim_texture_width_px
	texture.height = 1
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.RIGHT
	return texture


## DECISION: the front page has one Host entry. Its modal keeps local and
## Steam transport choices in one place and leaves Join discovery off the home
## page. Steam is disabled in the modal when the runtime lacks it.
## The host dialog's question, plus the Steam-unavailable reason while Steam is missing (inline, not a tooltip).
func _refresh_host_dialog_text(steam_available: bool) -> void:
	if _host_dialog == null:
		return
	_host_dialog.dialog_text = HOST_DIALOG_QUESTION if steam_available else HOST_DIALOG_QUESTION + "\n" + HOST_STEAM_UNAVAILABLE


func _build_host_dialog() -> void:
	_host_dialog = UiDialog.new()
	_host_dialog.title = HOST_DIALOG_TITLE
	_refresh_host_dialog_text(bool(net_provider.steam_available()))
	_host_dialog.add_action(HOST_LOCAL_ID, HOST_LOCAL_TEXT, UiBlockButton.Look.PRIMARY)
	_host_steam_choice = _host_dialog.add_action(HOST_STEAM_ID, HOST_STEAM_TEXT, UiBlockButton.Look.SECONDARY)
	_host_dialog.action_chosen.connect(_on_host_dialog_action)
	add_child(_host_dialog)
	_host_steam_choice.disabled = not bool(net_provider.steam_available())


func _on_host_pressed() -> void:
	_host_dialog.open()


func _on_host_dialog_action(id: StringName) -> void:
	if id == HOST_LOCAL_ID:
		_on_host_local_confirmed()
	elif id == HOST_STEAM_ID:
		_on_host_online_pressed()


func _on_host_local_confirmed() -> void:
	var err: Error = net_provider.host_game(0, _player_name())
	if err != OK:
		_show_status("Could not host: %s" % error_string(err))


func _on_join_pressed() -> void:
	_join_steam_tab = false
	_set_page(PAGE_JOIN)


func _on_join_lan_tab_pressed() -> void:
	_join_steam_tab = false
	_set_page(PAGE_JOIN)
	_join_lan_tab_button.grab_focus()


func _on_join_steam_tab_pressed() -> void:
	if not bool(net_provider.steam_available()):
		return
	_join_steam_tab = true
	_set_page(PAGE_JOIN)
	_join_steam_tab_button.grab_focus()


func _on_play_local_pressed() -> void:
	_set_page(PAGE_LOCAL)


func _on_debug_pressed() -> void:
	if _debug_entry_enabled:
		_set_page(PAGE_DEBUG)


func _on_gift_demo_pressed() -> void:
	if _debug_entry_enabled:
		gift_demo_requested.emit()


func _on_tower_topple_pressed() -> void:
	if _debug_entry_enabled:
		tower_topple_requested.emit()


func _watch_bots_open() -> bool:
	return _watch_bots_dialog != null and _watch_bots_dialog.visible


func _on_watch_bots_pressed() -> void:
	if _debug_entry_enabled and _watch_bots_dialog != null:
		_watch_bots_dialog.call(&"present")


func _build_watch_bots_dialog() -> void:
	if not _debug_entry_enabled:
		return
	# DECISION: loaded by path, like Main's other debug tools, so the picker and its
	# stepper/toggle components stay out of the Main.tscn compile closure (tools/lint_layers.py L4).
	var dialog_script: GDScript = load(WATCH_BOTS_DIALOG_PATH) as GDScript
	_watch_bots_dialog = dialog_script.new() as UiDialog
	_watch_bots_dialog.connect(&"confirmed", _on_watch_bots_confirmed)
	add_child(_watch_bots_dialog)


func _on_watch_bots_confirmed(options: RefCounted) -> void:
	if _debug_entry_enabled:
		watch_bots_requested.emit(options)


## Back (button, Esc or gamepad B) returns to the home page with focus on the
## button that opened the page just left, so the controller never loses its
## place.
func _on_back_pressed() -> void:
	var opener: Control = _host_button
	match _page:
		PAGE_JOIN:
			opener = _join_button
		PAGE_LOCAL:
			opener = _play_local_button
		PAGE_DEBUG:
			opener = _debug_button
	_set_page(PAGE_HOME, opener)


func _on_bots_pressed() -> void:
	var bot_host_name: String = _player_name()
	if net_provider.has_method(&"resolve_local_name"):
		# the Steam persona wins when Steam is up.
		bot_host_name = String(net_provider.resolve_local_name(bot_host_name))
	bots_requested.emit(bot_host_name)


## seam: shows/hides the debug entry on a live menu (the answer
## is otherwise read once from DebugMode.is_enabled() in _ready()). Turning it
## off while the Debug page is open returns to the home page.
func set_debug_entry_enabled(enabled: bool) -> void:
	_debug_entry_enabled = enabled
	_set_page(PAGE_HOME if _page == PAGE_DEBUG and not enabled else _page)


## The existing discovery controls remain on a dedicated Join page. The local
## choices stay together on Play local; the front page is a short navigation
## screen that also fits smaller viewports.
##
## /36: the name field only belongs to the pages that host or
## join (Home, Join) -- Play local and Debug hide it, so Vs bots (the first
## Play local option) is what takes focus there. The debug corner pill is an
## overlay outside every container, so toggling it moves nothing else.
func _set_page(page: int, focus_target: Control = null) -> void:
	_page = page
	var join_page: bool = page == PAGE_JOIN
	_set_column_gap(tuning.menu_compact_separation_px if join_page else layout.block_gap_px)
	_game_list_stack.custom_minimum_size.y = tuning.menu_compact_list_height_px if join_page else tuning.menu_lan_list_height_px
	_steam_list_stack.custom_minimum_size.y = tuning.menu_compact_list_height_px if join_page else tuning.menu_steam_list_height_px
	_title_wrap.visible = not join_page
	_tagline.visible = not join_page
	_section_gap.visible = not join_page
	_tagline.text = DEBUG_TAGLINE if page == PAGE_DEBUG else _home_tagline
	_name_row.visible = page == PAGE_HOME or join_page
	_name_edit.visible = page == PAGE_HOME or join_page
	_host_row.visible = page == PAGE_HOME
	_host_online_button.hide()
	_join_tab_row.visible = page == PAGE_JOIN
	_sync_join_tabs(_steam_available())
	_steam_section.visible = page == PAGE_JOIN and _join_steam_tab and _steam_available()
	_lan_games_well.visible = page == PAGE_JOIN and not _join_steam_tab
	_refresh_layout()
	_play_local_button.visible = page == PAGE_HOME
	_small_row.visible = page == PAGE_HOME
	_options_button.visible = page == PAGE_HOME
	_quit_button.visible = page == PAGE_HOME
	_bots_button.visible = page == PAGE_LOCAL
	_sandbox_button.visible = page == PAGE_LOCAL
	_tutorial_button.visible = page == PAGE_LOCAL
	_gift_demo_button.visible = page == PAGE_DEBUG
	_tower_topple_button.visible = page == PAGE_DEBUG
	_watch_bots_button.visible = page == PAGE_DEBUG
	_back_button.visible = page != PAGE_HOME
	_debug_button.visible = _debug_entry_enabled and page == PAGE_HOME
	_build_version_label.visible = page == PAGE_HOME
	_wire_focus()
	var target: Control = focus_target if focus_target != null else _default_focus(page)
	if target.focus_mode != Control.FOCUS_NONE:
		target.grab_focus()


## The control that takes focus when a page opens (its first/primary action).
func _default_focus(page: int) -> Control:
	match page:
		PAGE_JOIN:
			return _join_lan_tab_button
		PAGE_LOCAL:
			return _bots_button
		PAGE_DEBUG:
			return _gift_demo_button
	return _host_button


## Mirrors the transport choice onto the tab bar (Steam disabled without Steam, the active tab
## following _join_steam_tab) without re-entering _on_join_tab_changed().
func _sync_join_tabs(steam_ready: bool) -> void:
	_syncing_tabs = true
	_join_tab_row.set_tab_disabled(TAB_STEAM, not steam_ready)
	_join_tab_row.select(TAB_STEAM if _join_steam_tab and steam_ready else TAB_LAN)
	_syncing_tabs = false


func _steam_available() -> bool:
	return net_provider != null and bool(net_provider.steam_available())


# --- Controller / keyboard focus ----------------------------------------------
#
# /39: every neighbour is wired here, per page, from the controls
# that are actually usable right now. The scene file carries no focus_neighbor_*
# paths any more (the stale ones pointed at controls that are hidden on the
# page in question, and Godot then hops through them to nowhere -- Tutorial's
# "right" went to the hidden Options button). Controls that can do nothing
# (a disabled Steam button, an empty list) are made FOCUS_NONE and left out of
# the chain, so the pad can no longer land on a control that does nothing.

## Every control this menu wires, so a page change can clear stale neighbours.
func _wired_controls() -> Array[Control]:
	return [
		_name_edit, _host_button, _join_button, _play_local_button, _options_button, _quit_button,
		_debug_button, _bots_button, _sandbox_button, _tutorial_button,
		_gift_demo_button, _tower_topple_button, _watch_bots_button, _back_button, _join_lan_tab_button, _join_steam_tab_button,
		_refresh_button, _game_list, _direct_ip_edit, _direct_join_button, _refresh_steam_button,
		_steam_lobby_list,
	]


func _wire_focus() -> void:
	_sync_focus_modes()
	var sides: Array[Side] = [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]
	for control: Control in _wired_controls():
		for side: Side in sides:
			control.set_focus_neighbor(side, NodePath())
	match _page:
		PAGE_HOME:
			_wire_home_grid_focus()
		PAGE_LOCAL:
			_wire_cycle_row([_bots_button, _sandbox_button, _tutorial_button, _back_button])
		PAGE_DEBUG:
			_wire_cycle_row([_gift_demo_button, _tower_topple_button, _watch_bots_button, _back_button])
		_:
			_wire_join_focus()


## Disabled Steam buttons and empty lists cannot do anything, so they must not
## take focus. A control that loses focus this way hands it to its fallback.
func _sync_focus_modes() -> void:
	var steam_ready: bool = _steam_available()
	_set_focusable(_join_steam_tab_button, steam_ready, _join_lan_tab_button)
	if _host_steam_choice != null:
		_set_focusable(_host_steam_choice, steam_ready, null)
	_set_focusable(_game_list, _game_list.item_count > 0, _refresh_button)
	_set_focusable(_steam_lobby_list, _steam_lobby_list.item_count > 0, _refresh_steam_button)


func _set_focusable(control: Control, focusable: bool, fallback: Control) -> void:
	var wanted: Control.FocusMode = Control.FOCUS_ALL if focusable else Control.FOCUS_NONE
	if control.focus_mode == wanted:
		return
	var had_focus: bool = control.has_focus()
	control.focus_mode = wanted
	if had_focus and not focusable and fallback != null and fallback.is_visible_in_tree():
		fallback.grab_focus()


func _link(from: Control, side: Side, to: Control) -> void:
	from.set_focus_neighbor(side, from.get_path_to(to))


## One row of buttons where left/right and up/down both step through the row
## and wrap, so every direction reaches every option (Play local, Debug).
func _wire_cycle_row(row: Array[Control]) -> void:
	var count: int = row.size()
	for index: int in range(count):
		var control: Control = row[index]
		_link(control, SIDE_LEFT, row[(index - 1 + count) % count])
		_link(control, SIDE_RIGHT, row[(index + 1) % count])
		_link(control, SIDE_TOP, row[(index - 1 + count) % count])
		_link(control, SIDE_BOTTOM, row[(index + 1) % count])


## Rows drawn top to bottom: left/right clamp inside a row, up/down wrap around
## the page and keep the column where the next row is that wide.
func _wire_grid(rows: Array[Array]) -> void:
	var row_count: int = rows.size()
	for row_index: int in range(row_count):
		var row: Array = rows[row_index]
		var above: Array = rows[(row_index - 1 + row_count) % row_count]
		var below: Array = rows[(row_index + 1) % row_count]
		for column: int in range(row.size()):
			var control: Control = row[column] as Control
			_link(control, SIDE_LEFT, row[maxi(column - 1, 0)] as Control)
			_link(control, SIDE_RIGHT, row[mini(column + 1, row.size() - 1)] as Control)
			_link(control, SIDE_TOP, above[mini(column, above.size() - 1)] as Control)
			_link(control, SIDE_BOTTOM, below[mini(column, below.size() - 1)] as Control)


func _wire_join_focus() -> void:
	var tabs: Array[Control] = [_join_lan_tab_button]
	if _join_steam_tab_button.focus_mode != Control.FOCUS_NONE:
		tabs.append(_join_steam_tab_button)
	var rows: Array[Array] = [[_name_edit], tabs]
	if _steam_section.visible:
		rows.append([_refresh_steam_button])
		if _steam_lobby_list.focus_mode != Control.FOCUS_NONE:
			rows.append([_steam_lobby_list])
	else:
		rows.append([_refresh_button])
		if _game_list.focus_mode != Control.FOCUS_NONE:
			rows.append([_game_list])
		rows.append([_direct_ip_edit, _direct_join_button])
	rows.append([_back_button])
	_wire_grid(rows)


## The home page is one column read top to bottom: Name, Host, Join, Play offline, then the
## Options | Quit row. Up/down wrap round the page (through the debug entry when it is on) and
## left/right only move inside the Options | Quit row, clamping elsewhere so a stray press never
## leaves the column.
func _wire_home_grid_focus() -> void:
	var rows: Array[Array] = [[_name_edit], [_host_button], [_join_button], [_play_local_button], [_options_button, _quit_button]]
	if _debug_entry_enabled:
		rows.append([_debug_button])
	_wire_grid(rows)


## The column is pinned to the left edge at every aspect ratio (the backdrop image fills the rest): the
## CenterContainer spans the column plus its margins and centres the card vertically. A card whose
## minimum width exceeds the column (icon buttons on the Join page) widens the container instead of
## being pushed off the left edge.
func _refresh_layout() -> void:
	var margin: float = layout.column_left_margin_px
	var card_width: float = maxf(_front_card.get_combined_minimum_size().x, layout.column_width_px)
	_center.offset_left = margin
	_center.offset_right = margin + card_width


func _on_sandbox_pressed() -> void:
	sandbox_requested.emit()


func _on_tutorial_pressed() -> void:
	tutorial_requested.emit()


## docs/archive/M6_PLAN.md package C2: hides %Center (this menu's own root layout)
## rather than this whole MainMenu, so the background stays visible behind
## OptionsMenu's own semi-transparent %Background -- matches OptionsMenu.tscn
## being authored as an overlay, not a full scene swap.
func _on_options_pressed() -> void:
	if _options_menu != null:
		return
	var first_open: bool = _options_cache == null
	if first_open:
		_options_cache = OPTIONS_MENU_SCENE.instantiate() as OptionsMenu
	_options_menu = _options_cache
	_center.visible = false
	if first_open:
		add_child(_options_menu)
	else:
		_options_menu.present()
	# nothing behind Options may take pad / arrow focus while it is open.
	_restore_focus = UiFocusTrap.suspend_outside(_options_menu, self)
	if not _options_menu.closed.is_connected(_on_options_closed):
		_options_menu.closed.connect(_on_options_closed)


func _on_options_closed() -> void:
	if _options_menu != null:
		_options_menu.dismiss()
		_options_menu = null
	if _restore_focus.is_valid():
		_restore_focus.call()
		_restore_focus = Callable()
	_center.visible = true
	_options_button.grab_focus()


func _on_refresh_pressed() -> void:
	net_provider.stop_discovery()
	net_provider.start_discovery()


func _on_direct_join_pressed() -> void:
	var parsed: Dictionary = resolve_join_text(_direct_ip_edit.text)
	if not bool(parsed.get("valid", false)):
		_show_status(str(parsed.get("reason", "Enter an address like 1.2.3.4 or 1.2.3.4:47999")))
		return
	_join(str(parsed.get("address", "")), int(parsed.get("port", 0)))


func _on_game_activated(index: int) -> void:
	if index < 0 or index >= _games.size():
		return
	var game: Dictionary = _games[index]
	_join(str(game.get("address", "")), int(game.get("port", 0)))


func _on_quit_pressed() -> void:
	# let the AudioServer free stopped playbacks before exit (no quit-time leaks).
	await Sfx.drain_for_quit()
	QuitFlag.mark()
	get_tree().quit()


func _on_host_online_pressed() -> void:
	var err: Error = net_provider.host_online(_player_name())
	if err != OK:
		_show_status("Could not host online: %s" % error_string(err))


func _on_refresh_steam_pressed() -> void:
	net_provider.refresh_lobby_list()
	_steam_refresh_countdown_s = float(net_provider.config.steam_lobby_list_refresh_s)


func _on_steam_lobby_activated(index: int) -> void:
	if index < 0 or index >= _steam_lobbies.size():
		return
	var lobby: Dictionary = _steam_lobbies[index]
	var err: Error = net_provider.join_lobby(int(lobby.get("lobby_id", 0)), _player_name())
	if err != OK:
		_show_status("Could not join: %s" % error_string(err))


# --- Events reactions --------------------------------------------------------

func _on_join_failed(_error: int, detail: String) -> void:
	_show_status(detail if detail != "" else "Join failed.")


func _on_games_discovered(games: Array[Dictionary]) -> void:
	_games = games
	_rebuild_game_list()


func _on_steam_lobbies_discovered(lobbies: Array[Dictionary]) -> void:
	_steam_lobbies = lobbies
	_rebuild_steam_lobby_list()


# --- Helpers -----------------------------------------------------------------

func _join(address: String, port: int) -> void:
	var err: Error = net_provider.join_game(address, port, _player_name())
	if err != OK:
		_show_status("Could not join: %s" % error_string(err))


## components.md ServerRow: three pulsing cells under the "Searching for
## games..." line. They are a child of the label, so they show and hide with it.
## DECISION: SEARCH_CELLS_GAP_PX below the label's centre line is a layout offset, one line of the
## caption text, not a tunable.
const SEARCH_CELLS_GAP_PX: float = 22.0
## The line moves up by this much so line + cells are centred in the well.
const SEARCH_LABEL_LIFT_PX: float = 24.0


func _add_searching_cells() -> void:
	var cells: SearchingCells = SearchingCells.new()
	cells.name = "SearchingCells"
	_empty_state_label.offset_bottom = -SEARCH_LABEL_LIFT_PX
	_empty_state_label.add_child(cells)
	cells.set_anchors_preset(Control.PRESET_CENTER)
	cells.position = Vector2(-SearchingCells.row_width() * 0.5, SEARCH_CELLS_GAP_PX) + _empty_state_label.size * 0.5
	_empty_state_label.resized.connect(func() -> void:
		cells.position = Vector2(-SearchingCells.row_width() * 0.5, SEARCH_CELLS_GAP_PX) + _empty_state_label.size * 0.5)


func _rebuild_game_list() -> void:
	_game_list.clear()
	for game: Dictionary in _games:
		var label: String = "%s  (%d/%d)  %s:%d" % [
			str(game.get("name", "?")),
			int(game.get("players", 0)),
			int(game.get("max", 0)),
			str(game.get("address", "")),
			int(game.get("port", 0)),
		]
		_game_list.add_item(label)
	# review r1, item 5: "Searching for games..." inside the
	# well instead of a blank white box while LAN discovery has found nothing
	# yet.
	_empty_state_label.visible = _games.is_empty()
	# an empty list does nothing, so it leaves the focus chain.
	_wire_focus()


func _rebuild_steam_lobby_list() -> void:
	_steam_lobby_list.clear()
	for lobby: Dictionary in _steam_lobbies:
		var label: String = "%s  (%d/%d)  %s" % [
			str(lobby.get("name", "?")),
			int(lobby.get("players", 0)),
			int(lobby.get("max", 0)),
			str(lobby.get("map", "")),
		]
		_steam_lobby_list.add_item(label)
	# "No lobbies yet" inside the well instead of a blank
	# white box, the same _rebuild_game_list() fix for %GameList.
	_steam_empty_state_label.visible = _steam_lobbies.is_empty()
	_wire_focus()


## Toggles the Steam section vs. a disabled Host Online pill (spec 2.6: "Hide
## the online menu entries and show a notice"). Reads net_provider directly
## rather than taking a bool parameter, so a test can mutate a FakeNet's
## `steam_available_value` and re-call this the same way test_lobby.gd
## re-calls `_update_host_only_state()` after mutating its fake.
##
## review r1, item 4: the old permanent "Steam not
## available - hidden. Host/join over LAN or direct IP below." paragraph is
## gone -- the host dialog's text carries that explanation only when Steam is
## unavailable (no tooltips), instead of a standing block of card-width text.
func _apply_steam_availability() -> void:
	var available: bool = net_provider != null and bool(net_provider.steam_available())
	if not available:
		_join_steam_tab = false
	_sync_join_tabs(available)
	_steam_section.visible = available and _page == PAGE_JOIN and _join_steam_tab
	_lan_games_well.visible = _page == PAGE_JOIN and not _join_steam_tab
	if _host_steam_choice != null:
		_host_steam_choice.disabled = not available
	_refresh_host_dialog_text(available)
	_wire_focus()
	if available:
		net_provider.refresh_lobby_list()
		_steam_refresh_countdown_s = float(net_provider.config.steam_lobby_list_refresh_s)


## the name field shows the saved name every time a menu is
## built (a rebuilt menu used to reset it to "Player"), and every edit is saved
## straight away, so it also survives restarts and the Host/Join page switches.
func _init_name_field() -> void:
	_name_edit.max_length = int(net_provider.config.max_player_name_length)
	_name_edit.text = Settings.player_name()
	_name_edit.text_changed.connect(_on_name_text_changed)
	Settings.player_name_changed.connect(_on_saved_name_changed)


func _on_name_text_changed(typed: String) -> void:
	Settings.set_player_name(typed)


## Settings changed the name from somewhere other than this field: follow it,
## unless the field already reads the same once cleaned (typing a trailing space
## must not be rewritten under the player's cursor).
func _on_saved_name_changed(saved: String) -> void:
	if _clean_typed_name() != saved:
		_name_edit.text = saved
		_name_edit.caret_column = saved.length()


func _clean_typed_name() -> String:
	return PlayerNames.clean(_name_edit.text, int(net_provider.config.max_player_name_length))


## The typed name, cleaned. "" when nothing is typed: the host then seats this
## player as "Player N" (Net._accept_peer, host_game), and over Steam a joiner
## with no typed name uses the persona name.
func _player_name() -> String:
	return _clean_typed_name()


func show_status(text: String) -> void:
	_show_status(text)


func _show_status(text: String) -> void:
	_status_label.text = text


## the direct-join field takes an IP[:port] or a join code (core/net/JoinCode.gd).
## Returns parse_address()'s shape, plus a "reason" for a bad code.
static func resolve_join_text(text: String) -> Dictionary:
	if JoinCode.looks_like_code(text):
		return JoinCode.decode(text)
	return parse_address(text)


## Split out from the button handler so it can be unit-tested without a
## scene tree (mirrors net/LanDiscovery.gd's encode_advert/decode_advert
## split). Accepts "1.2.3.4" and "1.2.3.4:47999" (spec 2.6's direct-IP
## fallback); rejects anything else without throwing.
static func parse_address(text: String) -> Dictionary:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return {"valid": false}
	var host: String = trimmed
	var port: int = 0
	if trimmed.contains(":"):
		var parts: PackedStringArray = trimmed.split(":")
		if parts.size() != 2:
			return {"valid": false}
		host = parts[0]
		if not parts[1].is_valid_int():
			return {"valid": false}
		port = int(parts[1])
		if port < 1 or port > 65535:
			return {"valid": false}
	var octets: PackedStringArray = host.split(".")
	if octets.size() != 4:
		return {"valid": false}
	for octet: String in octets:
		if not octet.is_valid_int():
			return {"valid": false}
		var value: int = int(octet)
		if value < 0 or value > 255:
			return {"valid": false}
	return {"valid": true, "address": host, "port": port}
