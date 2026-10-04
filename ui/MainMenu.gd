class_name MainMenu
extends Control
## The game's front door (spec 3.4 "LAN discovery"; docs/M3a_PLAN.md P4).
##
## Owner decision (docs/M3a_PLAN.md question 3): hot-seat is unlisted — this
## menu offers only Host, Join (LAN list or direct IP), Sandbox (docs/
## M6_PLAN.md package B1, spec 2.7), Tutorial (docs/M6_PLAN.md package B3,
## spec 2.7) and Quit. Hot-seat is reachable solely through the `--hot-seat`
## command-line flag, which `Net.apply_command_line()` / `game/Main.gd`
## handle before this scene is even shown.
##
## Connects to Events and calls Net directly, the same "no deep node paths"
## convention ui/HUD.gd uses; it does not know about ui/Lobby.gd or
## game/Main.gd. Whoever owns scene switching (the integrator's Main) listens
## for Events.net_mode_changed to know when to move on.

## DECISION (ui/MainMenu.gd): `Variant` test seam, the same reason
## game/PlayerController.gd and ui/HUD.gd have one — GUT cannot double a
## plain autoload, and Net is still P1's stub while this lands. Defaults to
## the real Net autoload; tests overwrite it with a FakeNet after
## add_child().
var net_provider: Variant = null

## docs/M6_PLAN.md package B1: game/Main.gd instantiates this scene directly
## (`_show_main_menu()`) and connects to this signal the same way it connects
## to ui/Lobby.gd's own `start_requested` -- a direct child-signal connection,
## not the Events bus, since Main already owns this node's lifetime and this
## menu "does not know about ... game/Main.gd" (this file's own header
## comment above). Sandbox is still unlisted in the sense that spec 3.4 never
## asked for it in the Host/Join/Quit set this header describes, but the
## Main Menu is the one entry point spec 2.7 gives it (unlike hot-seat, which
## stays command-line only).
signal sandbox_requested

## docs/M6_PLAN.md package B3: %TutorialButton's own signal, the same direct
## child-signal convention sandbox_requested above uses -- game/Main.gd's
## start_tutorial_from_menu() connects to this in _show_main_menu(),
## mirroring its own start_sandbox_from_menu() hookup.
signal tutorial_requested
signal bots_requested(player_name: String)

## Bontago-1pi.70: the Debug page's Gift demo button asks game/Main.gd to start
## the sandbox with the gift-demo preset. Only ever emitted while debug mode is
## on: the entry is not even visible otherwise.
signal gift_demo_requested

## Tagline shown on the Debug page in place of the wordmark's own tagline.
const DEBUG_TAGLINE: String = "DEBUG · GIFT DEMO"

## docs/M6_PLAN.md package C2: OptionsMenu.tscn is instanced/freed directly by
## this menu (ui/OptionsMenu.gd's own header: "self-contained ... MainMenu
## instances this scene directly"), not routed through game/Main.gd -- the
## same reason sandbox_requested/tutorial_requested above are direct
## child-signal emits rather than an Events bus post, except this signal never
## even needs to leave MainMenu: _on_options_pressed()/_on_options_closed()
## below are both handlers and emitter in one file.
const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/OptionsMenu.tscn")

## M7 P7 (Bontago-xtq.32 redo): every pastel pill/well/card color and the
## offset-shadow-card geometry the layered-pastel mockups call for, so none of
## the styling below is a magic number (CLAUDE.md "No magic numbers").
@export var tuning: MenuVisualTuning = preload("res://config/menu_visual_tuning.tres")

@onready var _name_row: HBoxContainer = $Center/Panel/Layout/NameRow
@onready var _name_edit: LineEdit = %NameEdit
@onready var _host_button: Button = %HostButton
@onready var _join_button: Button = %JoinButton
@onready var _play_local_button: Button = %PlayLocalButton
@onready var _bots_button: Button = %BotsButton
@onready var _back_button: Button = %BackButton
## Bontago-1pi.34: the debug-only entry. A corner overlay on the menu root (not
## a child of the card's containers), so showing or hiding it can never move
## any other control; %GiftDemoButton lives on the Debug page.
@onready var _debug_button: Button = %DebugButton
@onready var _gift_demo_button: Button = %GiftDemoButton
@onready var _host_row: HBoxContainer = $Center/Panel/Layout/HostRow
@onready var _join_tab_row: HBoxContainer = %JoinTabRow
@onready var _join_lan_tab_button: Button = %JoinLanTabButton
@onready var _join_steam_tab_button: Button = %JoinSteamTabButton
@onready var _title_wrap: Control = $Center/Panel/Layout/TitleWrap
@onready var _tagline: Label = $Center/Panel/Layout/Tagline
@onready var _game_list_stack: Control = $Center/Panel/Layout/LanGamesWell/LanGamesLayout/GameListStack
@onready var _steam_list_stack: Control = $Center/Panel/Layout/SteamSection/SteamGamesWell/SteamGamesLayout/SteamListStack
@onready var _sandbox_button: Button = %SandboxButton
@onready var _tutorial_button: Button = %TutorialButton
@onready var _options_button: Button = %OptionsButton
@onready var _quit_button: Button = %QuitButton
@onready var _center: CenterContainer = %Center
@onready var _game_list: ItemList = %GameList
@onready var _refresh_button: Button = %RefreshButton
## Bontago-mp0.3.5 (review r1, item 5): the sunken "well" card wrapping the
## header row + %GameList + %DirectRow -- one sunken panel instead of a
## standalone tall Refresh button and separator lines.
@onready var _lan_games_well: PanelContainer = %LanGamesWell
@onready var _direct_ip_edit: LineEdit = %DirectIpEdit
@onready var _direct_join_button: Button = %DirectJoinButton
@onready var _status_label: Label = %StatusLabel

## M7 P7 (Bontago-xtq.32 redo, gap item 2): the offset triple-card stack --
## %ShadowApricot/%ShadowMint sit behind %Panel (the front card) in the same
## CenterContainer, so all three share one center point and %Panel's own size
## decides how far the shadow cards' larger custom_minimum_size peeks out.
@onready var _front_card: PanelContainer = %Panel
@onready var _shadow_apricot: Panel = %ShadowApricot
@onready var _shadow_mint: Panel = %ShadowMint
@onready var _title: RichTextLabel = %Title
## Bontago-mp0.3.5 (review r1, item 2): a solid-color offset copy behind
## %Title, giving "Stackfall" the mockup's soft drop-shadow instead of flat
## two-tone text. Positioned in _apply_visual_style() from tuning.title_shadow_offset_px.
@onready var _title_shadow: RichTextLabel = %TitleShadow
@onready var _title_accent: ColorRect = %TitleAccent
@onready var _name_label: Label = %NameLabel
@onready var _join_label: Label = %JoinLabel
## Bontago-mp0.3.5: mockup 10's bottom-right controller hint is a pill, not a
## bare Label -- %GamepadHintPill wraps the existing %GamepadHintBar Label in
## a PanelContainer so it reads as a chip instead of floating text.
@onready var _gamepad_hint_pill: PanelContainer = %GamepadHintPill
@onready var _glyph_a: PanelContainer = %GlyphA
@onready var _glyph_a_label: Label = %GlyphALabel
@onready var _glyph_b: PanelContainer = %GlyphB
@onready var _glyph_b_label: Label = %GlyphBLabel
@onready var _select_label: Label = %SelectLabel
@onready var _back_label: Label = %BackLabel
@onready var _keyboard_label: Label = %KeyboardLabel

## M3b (docs/M3b_PLAN.md P3): the Steam section vs. the "not available" notice
## (spec 3.4: "Hide the online menu entries and show a notice").
@onready var _steam_section: VBoxContainer = %SteamSection
@onready var _host_online_button: Button = %HostOnlineButton
## Bontago-mp0.3.7: the sunken "well" card wrapping the Steam header row +
## %SteamLobbyList -- same one-sunken-panel treatment as %LanGamesWell
## (Bontago-mp0.3.5 review r1, item 5), replacing the old standalone tall
## "Refresh" button + bare sunken %SteamLobbyList.
@onready var _steam_games_well: PanelContainer = %SteamGamesWell
@onready var _steam_lobby_list: ItemList = %SteamLobbyList
@onready var _refresh_steam_button: Button = %RefreshSteamButton
@onready var _empty_state_label: Label = %EmptyStateLabel
## Bontago-mp0.3.7: "No lobbies yet" inside the Steam well while
## _steam_lobbies is empty, mirroring %EmptyStateLabel's own role for
## %GameList (_rebuild_game_list()'s own "blank white box" fix).
@onready var _steam_empty_state_label: Label = %SteamEmptyStateLabel

var _games: Array[Dictionary] = []
var _steam_lobbies: Array[Dictionary] = []

## Seconds until the next automatic refresh_lobby_list() poll while the Steam
## section is visible (docs/M3b_PLAN.md: "Steam's request_lobby_list() is
## pull-based ... call it on a config.steam_lobby_list_refresh_s timer"). A
## plain accumulator rather than a Timer node, since it only needs to run
## while _steam_section is visible and reads its interval from
## net_provider.config, which a Timer node's `wait_time` can't do without its
## own extra wiring code anyway.
var _steam_refresh_countdown_s: float = 0.0

const PAGE_HOME: int = 0
const PAGE_JOIN: int = 1
const PAGE_LOCAL: int = 2
const PAGE_DEBUG: int = 3
var _page: int = PAGE_HOME
## DECISION (Bontago-1pi.34): "debug mode" is the project's single switch,
## DebugMode.is_enabled() (game/DebugMode.gd: F1-F4 overlays, sandbox hotkeys),
## not a bare OS.is_debug_build(): the owner's `godot --path .` runs are debug
## runs automatically, `-- --no-debug` previews the player build, and an
## exported build never shows the entry. Read once per menu instance.
var _debug_entry_enabled: bool = false
var _home_tagline: String = ""
var _regular_card_style: StyleBoxFlat
var _join_card_style: StyleBoxFlat
var _join_steam_tab: bool = false
var _host_dialog: ConfirmationDialog = null
var _host_steam_choice: Button = null

## The live OptionsMenu.tscn instance while it's open, or null. Tracked here
## (rather than letting OptionsMenu free itself on `closed`) so
## _on_options_closed() can both queue_free() it and restore focus in one
## place, the same "one owner frees what it opened" convention
## _on_quit_pressed() implicitly follows via get_tree().quit().
var _options_menu: OptionsMenu = null


func _ready() -> void:
	net_provider = Net
	_debug_entry_enabled = DebugMode.is_enabled()
	_home_tagline = _tagline.text
	_host_button.pressed.connect(_on_host_pressed)
	_join_button.pressed.connect(_on_join_pressed)
	_join_lan_tab_button.pressed.connect(_on_join_lan_tab_pressed)
	_join_steam_tab_button.pressed.connect(_on_join_steam_tab_pressed)
	_play_local_button.pressed.connect(_on_play_local_pressed)
	_bots_button.pressed.connect(_on_bots_pressed)
	_debug_button.pressed.connect(_on_debug_pressed)
	_gift_demo_button.pressed.connect(_on_gift_demo_pressed)
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
	_apply_steam_availability()
	get_viewport().size_changed.connect(_refresh_layout)
	_front_card.minimum_size_changed.connect(_refresh_layout)
	_set_page(PAGE_HOME)


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
	if _page != PAGE_HOME and not _host_dialog.visible and event.is_action_pressed("ui_cancel"):
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
		_gift_demo_button,
	]
	for button: BaseButton in buttons:
		button.pressed.connect(_on_sound_button_pressed)
		button.mouse_entered.connect(_on_sound_button_hovered)


func _on_sound_button_pressed() -> void:
	Sfx.play(AudioConfig.EVENT_CLICK)


func _on_sound_button_hovered() -> void:
	Sfx.play(AudioConfig.EVENT_HOVER)


# --- Visual style (Bontago-xtq.32 redo: layered-pastel look) -----------------

## Wires every pill/well/card StyleBoxFlat from ui/theme/MenuStyleFactory.gd
## and config/MenuVisualTuning.gd onto this scene's existing nodes. Runs once
## from _ready() -- none of it changes at runtime except the shadow-card sizes
## (_sync_shadow_card_sizes(), hooked to %Panel's own `resized` signal since
## %SteamSection toggling visibility changes the front card's height).
func _apply_visual_style() -> void:
	# DECISION (ui/MainMenu.gd, Bontago-mp0.3.5 review r2, item b): mockup 10's
	# wordmark is a single dark colour ("Stackfall" all one tone) with only
	# the offset shadow copy carrying the peach accent -- the earlier two-tone
	# coral "fall" (Bontago-xtq.32 redo's own simplification of a bespoke
	# block-cube wordmark) is dropped in favor of matching that single-colour
	# read exactly.
	_title.text = "[img=40x48]res://assets/ui/stackfall_mark.svg[/img] [font_size=44][b][color=#%s]Stackfall[/color][/b][/font_size]" % [
		tuning.ink_color.to_html(false),
	]
	# Bontago-mp0.3.5 (review r1, item 2): a solid peach/coral silhouette copy
	# of the same text, offset by tuning.title_shadow_offset_px and drawn
	# first (it's TitleWrap's first child), reading as a soft drop shadow
	# behind the real two-tone title.
	_title_shadow.text = "[img=40x48]res://assets/ui/stackfall_mark.svg[/img] [font_size=44][b][color=#%s]Stackfall[/color][/b][/font_size]" % [
		tuning.title_shadow_color.to_html(false),
	]
	_title_shadow.position = tuning.title_shadow_offset_px
	_title_shadow.modulate.a = 0.9
	_title_wrap.custom_minimum_size.y = tuning.menu_title_height_px
	_title_accent.color = tuning.pill_coral_color
	_title_accent.hide()
	_name_label.add_theme_color_override("font_color", tuning.label_muted_color)
	_join_label.add_theme_color_override("font_color", tuning.label_muted_color)

	_regular_card_style = MenuStyleFactory.make_card(tuning.card_cream_color, tuning)
	_join_card_style = _regular_card_style.duplicate() as StyleBoxFlat
	_join_card_style.set_content_margin_all(tuning.menu_compact_card_margin_px)
	_front_card.add_theme_stylebox_override("panel", _regular_card_style)
	_front_card.custom_minimum_size.x = tuning.menu_card_width_px
	$Center/Panel/Layout.add_theme_constant_override("separation", tuning.menu_separation_px)
	_game_list_stack.custom_minimum_size.y = tuning.menu_lan_list_height_px
	_steam_list_stack.custom_minimum_size.y = tuning.menu_steam_list_height_px
	_shadow_apricot.add_theme_stylebox_override("panel", MenuStyleFactory.make_card(tuning.card_shadow_apricot_color, tuning))
	_shadow_mint.add_theme_stylebox_override("panel", MenuStyleFactory.make_card(tuning.card_shadow_mint_color, tuning))
	_front_card.resized.connect(_sync_shadow_card_sizes)
	call_deferred("_sync_shadow_card_sizes")

	_lan_games_well.add_theme_stylebox_override("panel", MenuStyleFactory.make_well(tuning))
	_game_list.add_theme_stylebox_override("panel", MenuStyleFactory.make_flat_list(tuning))
	# Bontago-mp0.3.7: %SteamGamesWell is the sunken card (like %LanGamesWell);
	# %SteamLobbyList itself is the flat white list inside it (like %GameList),
	# not a second sunken box.
	_steam_games_well.add_theme_stylebox_override("panel", MenuStyleFactory.make_well(tuning))
	_steam_lobby_list.add_theme_stylebox_override("panel", MenuStyleFactory.make_flat_list(tuning))
	_name_edit.add_theme_stylebox_override("normal", MenuStyleFactory.make_well(tuning))
	_name_edit.add_theme_stylebox_override("focus", MenuStyleFactory.make_well(tuning))
	_direct_ip_edit.add_theme_stylebox_override("normal", MenuStyleFactory.make_flat_list(tuning))
	_direct_ip_edit.add_theme_stylebox_override("focus", MenuStyleFactory.make_flat_list(tuning))

	MenuStyleFactory.apply_pill(_host_button, tuning.pill_coral_color, tuning.pill_coral_hover_color, tuning.label_ink_light_color, tuning)
	MenuStyleFactory.apply_pill(_join_button, tuning.pill_powder_blue_color, tuning.pill_powder_blue_hover_color, tuning.ink_color, tuning)
	MenuStyleFactory.apply_pill(_join_lan_tab_button, tuning.pill_mint_color, tuning.pill_mint_hover_color, tuning.ink_color, tuning)
	MenuStyleFactory.apply_pill(_join_steam_tab_button, tuning.pill_powder_blue_color, tuning.pill_powder_blue_hover_color, tuning.ink_color, tuning)
	MenuStyleFactory.apply_pill(_play_local_button, tuning.pill_mint_color, tuning.pill_mint_hover_color, tuning.ink_color, tuning)
	MenuStyleFactory.apply_pill(_bots_button, tuning.pill_coral_color, tuning.pill_coral_hover_color, tuning.label_ink_light_color, tuning)
	MenuStyleFactory.apply_pill(_back_button, tuning.pill_cream_color, tuning.pill_cream_hover_color, tuning.ink_color, tuning)
	MenuStyleFactory.apply_pill(_host_online_button, tuning.pill_cream_color, tuning.pill_cream_hover_color, tuning.ink_color, tuning)
	MenuStyleFactory.apply_pill(_refresh_button, tuning.pill_cream_color, tuning.pill_cream_hover_color, tuning.ink_color, tuning)
	MenuStyleFactory.apply_pill(_refresh_steam_button, tuning.pill_cream_color, tuning.pill_cream_hover_color, tuning.ink_color, tuning)
	MenuStyleFactory.apply_pill(_direct_join_button, tuning.pill_dark_slate_color, tuning.pill_dark_slate_hover_color, tuning.label_ink_light_color, tuning)
	MenuStyleFactory.apply_pill(_sandbox_button, tuning.pill_mint_color, tuning.pill_mint_hover_color, tuning.ink_color, tuning)
	MenuStyleFactory.apply_pill(_tutorial_button, tuning.pill_powder_blue_color, tuning.pill_powder_blue_hover_color, tuning.ink_color, tuning)
	MenuStyleFactory.apply_pill(_options_button, tuning.pill_cream_color, tuning.pill_cream_hover_color, tuning.ink_color, tuning)
	MenuStyleFactory.apply_pill(_quit_button, tuning.pill_cream_color, tuning.pill_cream_hover_color, tuning.ink_color, tuning)
	# Bontago-1pi.34: dev-only pills reuse the existing palette (dark slate for
	# the corner entry so it reads as a tool, not a game mode); no icons, so
	# they stay clear of the shared icon-colour overrides below.
	MenuStyleFactory.apply_pill(_debug_button, tuning.pill_dark_slate_color, tuning.pill_dark_slate_hover_color, tuning.label_ink_light_color, tuning)
	MenuStyleFactory.apply_pill(_gift_demo_button, tuning.pill_powder_blue_color, tuning.pill_powder_blue_hover_color, tuning.ink_color, tuning)
	# SVG icons import at a large intrinsic size. Let Join controls scale the
	# icon into a tuned row height so the full page fits the visible canvas.
	for button: Button in [_join_lan_tab_button, _join_steam_tab_button,
			_refresh_button, _refresh_steam_button, _direct_join_button, _back_button]:
		button.expand_icon = true
		button.custom_minimum_size.y = tuning.menu_compact_button_height_px
	# DECISION (Bontago-1pi.37): icons are white-source SVGs and every pill's
	# icon, like its label, takes the one ink MenuStyleFactory.apply_pill() sets
	# for all draw states (normal/focus/hover/pressed) -- no per-node icon or
	# focus-colour overrides here, so a focused button can never flip its icon
	# to the theme's default white.
	_gamepad_hint_pill.add_theme_stylebox_override("panel", MenuStyleFactory.make_badge(tuning.pill_cream_color, tuning))
	MenuStyleFactory.apply_glyph_circle(_glyph_a, _glyph_a_label, tuning)
	MenuStyleFactory.apply_glyph_circle(_glyph_b, _glyph_b_label, tuning)
	for label: Label in [_select_label, _back_label, _keyboard_label]:
		label.add_theme_color_override("font_color", tuning.ink_color)


## Shift the painted back cards diagonally while retaining container layout.
## StyleBox expansion changes drawing only, avoiding a resize/sort feedback loop.
func _sync_shadow_card_sizes() -> void:
	var base: Vector2 = _front_card.size
	var offset: Vector2 = Vector2.ONE * tuning.card_offset_px
	_shadow_apricot.custom_minimum_size = base
	_shadow_mint.custom_minimum_size = base
	for layer: Panel in [_shadow_apricot, _shadow_mint]:
		var distance: float = offset.x * (2.0 if layer == _shadow_mint else 1.0)
		var style: StyleBoxFlat = layer.get_theme_stylebox("panel") as StyleBoxFlat
		style.expand_margin_left = distance
		style.expand_margin_top = distance
		style.expand_margin_right = -distance
		style.expand_margin_bottom = -distance


## DECISION: the front page has one Host entry. Its modal keeps local and
## Steam transport choices in one place and leaves Join discovery off the home
## page. Steam is disabled in the modal when the runtime lacks it.
func _build_host_dialog() -> void:
	_host_dialog = ConfirmationDialog.new()
	_host_dialog.title = "Host game"
	_host_dialog.dialog_text = "How should friends connect?"
	_host_dialog.ok_button_text = "Host locally"
	_host_dialog.confirmed.connect(_on_host_local_confirmed)
	_host_steam_choice = _host_dialog.add_button("Host on Steam", false, "steam")
	_host_dialog.custom_action.connect(_on_host_custom_action)
	add_child(_host_dialog)
	_host_steam_choice.disabled = not bool(net_provider.steam_available())


func _on_host_pressed() -> void:
	_host_dialog.popup_centered()
	_host_dialog.get_ok_button().grab_focus()


func _on_host_local_confirmed() -> void:
	var err: Error = net_provider.host_game(0, _player_name())
	if err != OK:
		_show_status("Could not host: %s" % error_string(err))


func _on_host_custom_action(action: StringName) -> void:
	if action == &"steam":
		_host_dialog.hide()
		_on_host_online_pressed()


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
	bots_requested.emit(_player_name())


## Bontago-1pi.34 seam: shows/hides the debug entry on a live menu (the answer
## is otherwise read once from DebugMode.is_enabled() in _ready()). Turning it
## off while the Debug page is open returns to the home page.
func set_debug_entry_enabled(enabled: bool) -> void:
	_debug_entry_enabled = enabled
	_set_page(PAGE_HOME if _page == PAGE_DEBUG and not enabled else _page)


## The existing discovery controls remain on a dedicated Join page. The local
## choices stay together on Play local; the front page is a short navigation
## screen that also fits smaller viewports.
##
## Bontago-1pi.34/36: the name field only belongs to the pages that host or
## join (Home, Join) -- Play local and Debug hide it, so Vs bots (the first
## Play local option) is what takes focus there. The debug corner pill is an
## overlay outside every container, so toggling it moves nothing else.
func _set_page(page: int, focus_target: Control = null) -> void:
	_page = page
	var join_page: bool = page == PAGE_JOIN
	_front_card.add_theme_stylebox_override("panel", _join_card_style if join_page else _regular_card_style)
	$Center/Panel/Layout.add_theme_constant_override("separation", tuning.menu_compact_separation_px if join_page else tuning.menu_separation_px)
	_game_list_stack.custom_minimum_size.y = tuning.menu_compact_list_height_px if join_page else tuning.menu_lan_list_height_px
	_steam_list_stack.custom_minimum_size.y = tuning.menu_compact_list_height_px if join_page else tuning.menu_steam_list_height_px
	_title_wrap.visible = not join_page
	_tagline.visible = not join_page
	_tagline.text = DEBUG_TAGLINE if page == PAGE_DEBUG else _home_tagline
	_name_row.visible = page == PAGE_HOME or join_page
	_name_edit.visible = page == PAGE_HOME or join_page
	_host_row.visible = page == PAGE_HOME
	_host_online_button.hide()
	_join_tab_row.visible = page == PAGE_JOIN
	_join_steam_tab_button.disabled = not _steam_available()
	_steam_section.visible = page == PAGE_JOIN and _join_steam_tab and _steam_available()
	_lan_games_well.visible = page == PAGE_JOIN and not _join_steam_tab
	_refresh_layout()
	_play_local_button.visible = page == PAGE_HOME
	_options_button.visible = page == PAGE_HOME
	_quit_button.visible = page == PAGE_HOME
	_bots_button.visible = page == PAGE_LOCAL
	_sandbox_button.visible = page == PAGE_LOCAL
	_tutorial_button.visible = page == PAGE_LOCAL
	_gift_demo_button.visible = page == PAGE_DEBUG
	_back_button.visible = page != PAGE_HOME
	_debug_button.visible = _debug_entry_enabled and page == PAGE_HOME
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


func _steam_available() -> bool:
	return net_provider != null and bool(net_provider.steam_available())


# --- Controller / keyboard focus ----------------------------------------------
#
# Bontago-1pi.38/39: every neighbour is wired here, per page, from the controls
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
		_gift_demo_button, _back_button, _join_lan_tab_button, _join_steam_tab_button,
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
			_wire_cycle_row([_gift_demo_button, _back_button])
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


## Bontago-1pi.23: the home page is a 2-column grid (Host | Join over Play
## local | Options | Quit), so up/down/left/right follow what is drawn instead
## of stepping sideways through a single linear chain. With the debug entry on,
## its corner pill sits between the bottom row and the name field in the
## up/down wrap (it is drawn at the bottom-left of the screen).
func _wire_home_grid_focus() -> void:
	var top_row: Array[Control] = [_host_button, _join_button]
	var bottom_row: Array[Control] = [_play_local_button, _options_button, _quit_button]
	var below_bottom_row: Control = _debug_button if _debug_entry_enabled else _name_edit
	var above_name: Control = _debug_button if _debug_entry_enabled else _play_local_button
	for control: Control in top_row:
		_link(control, SIDE_TOP, _name_edit)
	for index: int in range(bottom_row.size()):
		var control: Control = bottom_row[index]
		var above: Control = top_row[mini(index * top_row.size() / bottom_row.size(), top_row.size() - 1)]
		_link(control, SIDE_TOP, above)
		_link(control, SIDE_BOTTOM, below_bottom_row)
		_link(control, SIDE_LEFT, bottom_row[maxi(index - 1, 0)])
		_link(control, SIDE_RIGHT, bottom_row[mini(index + 1, bottom_row.size() - 1)])
	_link(_host_button, SIDE_BOTTOM, _play_local_button)
	_link(_join_button, SIDE_BOTTOM, _options_button)
	_link(_host_button, SIDE_LEFT, _host_button)
	_link(_host_button, SIDE_RIGHT, _join_button)
	_link(_join_button, SIDE_LEFT, _host_button)
	_link(_join_button, SIDE_RIGHT, _join_button)
	_link(_name_edit, SIDE_TOP, above_name)
	_link(_name_edit, SIDE_BOTTOM, _host_button)
	_link(_name_edit, SIDE_LEFT, _name_edit)
	_link(_name_edit, SIDE_RIGHT, _name_edit)
	if _debug_entry_enabled:
		_link(_debug_button, SIDE_TOP, _play_local_button)
		_link(_debug_button, SIDE_BOTTOM, _name_edit)
		_link(_debug_button, SIDE_LEFT, _debug_button)
		_link(_debug_button, SIDE_RIGHT, _debug_button)


## Compact Join keeps its controls on screen at a small window size without
## shrinking fonts. Home and Play local keep the wordmark at every size.
func _refresh_layout() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	# DECISION (Bontago-mp0.11): ultrawide composition centers the card;
	# regular aspect ratios leave space for the diorama on the right.
	var wide: bool = viewport_size.x / viewport_size.y > 2.0
	_center.anchor_left = tuning.menu_wide_anchor_left if wide else 0.0
	_center.anchor_right = tuning.menu_wide_anchor_right if wide else 0.51
	# DECISION (Bontago-mp0.18): the card's minimum width (icon buttons) can
	# exceed the anchored column, and a CenterContainer then pushes it off the
	# left edge. Keep a tunable left margin and widen the column to fit.
	var margin: float = tuning.menu_card_left_margin_px
	var card_width: float = _front_card.get_combined_minimum_size().x
	var column_right: float = _center.anchor_right * viewport_size.x
	_center.offset_left = margin
	_center.offset_right = maxf(0.0, margin + card_width - column_right)


func _on_sandbox_pressed() -> void:
	sandbox_requested.emit()


func _on_tutorial_pressed() -> void:
	tutorial_requested.emit()


## docs/M6_PLAN.md package C2: hides %Center (this menu's own root layout)
## rather than this whole MainMenu, so the background stays visible behind
## OptionsMenu's own semi-transparent %Background -- matches OptionsMenu.tscn
## being authored as an overlay, not a full scene swap.
func _on_options_pressed() -> void:
	if _options_menu != null:
		return
	_options_menu = OPTIONS_MENU_SCENE.instantiate() as OptionsMenu
	_center.visible = false
	add_child(_options_menu)
	_options_menu.closed.connect(_on_options_closed)


func _on_options_closed() -> void:
	if _options_menu != null:
		_options_menu.queue_free()
		_options_menu = null
	_center.visible = true
	_options_button.grab_focus()


func _on_refresh_pressed() -> void:
	net_provider.stop_discovery()
	net_provider.start_discovery()


func _on_direct_join_pressed() -> void:
	var parsed: Dictionary = parse_address(_direct_ip_edit.text)
	if not bool(parsed.get("valid", false)):
		_show_status("Enter an address like 1.2.3.4 or 1.2.3.4:47999")
		return
	_join(str(parsed.get("address", "")), int(parsed.get("port", 0)))


func _on_game_activated(index: int) -> void:
	if index < 0 or index >= _games.size():
		return
	var game: Dictionary = _games[index]
	_join(str(game.get("address", "")), int(game.get("port", 0)))


func _on_quit_pressed() -> void:
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
	# Bontago-mp0.3.5 (review r1, item 5): "Searching for games..." inside the
	# well instead of a blank white box while LAN discovery has found nothing
	# yet.
	_empty_state_label.visible = _games.is_empty()
	# Bontago-1pi.38: an empty list does nothing, so it leaves the focus chain.
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
	# Bontago-mp0.3.7: "No lobbies yet" inside the well instead of a blank
	# white box, the same _rebuild_game_list() fix for %GameList.
	_steam_empty_state_label.visible = _steam_lobbies.is_empty()
	_wire_focus()


## Toggles the Steam section vs. a disabled Host Online pill (spec 3.4: "Hide
## the online menu entries and show a notice"). Reads net_provider directly
## rather than taking a bool parameter, so a test can mutate a FakeNet's
## `steam_available_value` and re-call this the same way test_lobby.gd
## re-calls `_update_host_only_state()` after mutating its fake.
##
## Bontago-mp0.3.5 (review r1, item 4): the old permanent "Steam not
## available - hidden. Host/join over LAN or direct IP below." paragraph is
## gone -- %HostOnlineButton's own tooltip carries that explanation only when
## it's actually disabled, instead of a standing block of card-width text.
func _apply_steam_availability() -> void:
	var available: bool = net_provider != null and bool(net_provider.steam_available())
	if not available:
		_join_steam_tab = false
	_join_steam_tab_button.disabled = not available
	_steam_section.visible = available and _page == PAGE_JOIN and _join_steam_tab
	_lan_games_well.visible = _page == PAGE_JOIN and not _join_steam_tab
	if _host_steam_choice != null:
		_host_steam_choice.disabled = not available
		_host_steam_choice.tooltip_text = "" if available else "Steam is unavailable; host locally instead."
	_wire_focus()
	if available:
		net_provider.refresh_lobby_list()
		_steam_refresh_countdown_s = float(net_provider.config.steam_lobby_list_refresh_s)


## Bontago-mp0.3.7 (capture-only): tools/capture_mockup08.gd's own
## `--force-steam-ui` flag calls this to show %SteamSection on a machine
## where Steam isn't actually available, mirroring ui/Lobby.gd's
## debug_open_advanced_rules_popup() -- a capture/test-only seam, not a
## player-facing feature. [param sample_lobby] fills the well with one
## placeholder row so the row style is visible too; false leaves it on the
## "No lobbies yet" empty state.
func debug_force_steam_ui(sample_lobby: bool = true) -> void:
	_steam_section.visible = true
	_host_online_button.tooltip_text = ""
	_host_online_button.disabled = false
	if sample_lobby:
		_on_steam_lobbies_discovered([
			{"lobby_id": 1, "name": "Alice's lobby", "players": 2, "max": 8, "map": "Round"},
		])
	else:
		_on_steam_lobbies_discovered([])


## Bontago-1pi.49: the name field shows the saved name every time a menu is
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


## Split out from the button handler so it can be unit-tested without a
## scene tree (mirrors net/LanDiscovery.gd's encode_advert/decode_advert
## split). Accepts "1.2.3.4" and "1.2.3.4:47999" (spec 3.4's direct-IP
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
