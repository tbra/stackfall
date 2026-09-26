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

@onready var _name_edit: LineEdit = %NameEdit
@onready var _host_button: Button = %HostButton
@onready var _sandbox_button: Button = %SandboxButton
@onready var _tutorial_button: Button = %TutorialButton
@onready var _options_button: Button = %OptionsButton
@onready var _quit_button: Button = %QuitButton
@onready var _center: CenterContainer = %Center
@onready var _game_list: ItemList = %GameList
@onready var _refresh_button: Button = %RefreshButton
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
@onready var _title_accent: ColorRect = %TitleAccent
@onready var _name_label: Label = %NameLabel
@onready var _join_label: Label = %JoinLabel

## M3b (docs/M3b_PLAN.md P3): the Steam section vs. the "not available" notice
## (spec 3.4: "Hide the online menu entries and show a notice").
@onready var _steam_section: VBoxContainer = %SteamSection
@onready var _host_online_button: Button = %HostOnlineButton
@onready var _steam_lobby_list: ItemList = %SteamLobbyList
@onready var _refresh_steam_button: Button = %RefreshSteamButton
@onready var _steam_unavailable_label: Label = %SteamUnavailableLabel

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

## The live OptionsMenu.tscn instance while it's open, or null. Tracked here
## (rather than letting OptionsMenu free itself on `closed`) so
## _on_options_closed() can both queue_free() it and restore focus in one
## place, the same "one owner frees what it opened" convention
## _on_quit_pressed() implicitly follows via get_tree().quit().
var _options_menu: OptionsMenu = null


func _ready() -> void:
	net_provider = Net
	_host_button.pressed.connect(_on_host_pressed)
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
	_apply_steam_availability()
	_host_button.grab_focus()


func _process(delta: float) -> void:
	if not _steam_section.visible:
		return
	_steam_refresh_countdown_s -= delta
	if _steam_refresh_countdown_s <= 0.0:
		_on_refresh_steam_pressed()


func _exit_tree() -> void:
	if net_provider != null:
		net_provider.stop_discovery()


# --- Button handlers ---------------------------------------------------------

## assets-audio package: UI button press/hover has no Events signal of its
## own (it isn't gameplay), so this calls Sfx directly -- the one named
## exception to "Sfx listens, nothing calls it" (autoload/Sfx.gd's header).
func _connect_click_and_hover_sounds() -> void:
	var buttons: Array[BaseButton] = [
		_host_button, _sandbox_button, _tutorial_button, _options_button, _quit_button, _refresh_button,
		_direct_join_button, _host_online_button, _refresh_steam_button,
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
	# DECISION (ui/MainMenu.gd, Bontago-xtq.32 redo, gap item 3): mockup 10's
	# title is a bespoke two-tone block-cube wordmark (individual cube glyphs).
	# Reproduced here as bold two-tone BBCode text in the shared font instead
	# of building per-letter cube meshes/glyphs -- captures the two-tone split
	# without a new glyph-authoring pipeline; disclosed as a simplification.
	_title.text = "[b][color=#%s]Stack[/color][color=#%s]fall[/color][/b]" % [
		tuning.ink_color.to_html(false), tuning.pill_coral_color.to_html(false),
	]
	_title_accent.color = tuning.pill_coral_color
	_name_label.add_theme_color_override("font_color", tuning.label_muted_color)
	_join_label.add_theme_color_override("font_color", tuning.label_muted_color)

	_front_card.add_theme_stylebox_override("panel", MenuStyleFactory.make_card(tuning.card_cream_color, tuning))
	_shadow_apricot.add_theme_stylebox_override("panel", MenuStyleFactory.make_card(tuning.card_shadow_apricot_color, tuning))
	_shadow_mint.add_theme_stylebox_override("panel", MenuStyleFactory.make_card(tuning.card_shadow_mint_color, tuning))
	_front_card.resized.connect(_sync_shadow_card_sizes)
	call_deferred("_sync_shadow_card_sizes")

	_game_list.add_theme_stylebox_override("panel", MenuStyleFactory.make_well(tuning))
	_steam_lobby_list.add_theme_stylebox_override("panel", MenuStyleFactory.make_well(tuning))

	MenuStyleFactory.apply_pill(_host_button, tuning.pill_coral_color, tuning.pill_coral_hover_color, tuning.label_ink_light_color, tuning)
	MenuStyleFactory.apply_pill(_host_online_button, tuning.pill_cream_color, tuning.pill_cream_hover_color, tuning.ink_color, tuning)
	MenuStyleFactory.apply_pill(_refresh_button, tuning.pill_cream_color, tuning.pill_cream_hover_color, tuning.ink_color, tuning)
	MenuStyleFactory.apply_pill(_refresh_steam_button, tuning.pill_cream_color, tuning.pill_cream_hover_color, tuning.ink_color, tuning)
	MenuStyleFactory.apply_pill(_direct_join_button, tuning.pill_dark_slate_color, tuning.pill_dark_slate_hover_color, tuning.label_ink_light_color, tuning)
	MenuStyleFactory.apply_pill(_sandbox_button, tuning.pill_mint_color, tuning.pill_mint_hover_color, tuning.ink_color, tuning)
	MenuStyleFactory.apply_pill(_tutorial_button, tuning.pill_powder_blue_color, tuning.pill_powder_blue_hover_color, tuning.ink_color, tuning)
	MenuStyleFactory.apply_pill(_options_button, tuning.pill_cream_color, tuning.pill_cream_hover_color, tuning.ink_color, tuning)
	MenuStyleFactory.apply_pill(_quit_button, tuning.pill_cream_color, tuning.pill_cream_hover_color, tuning.ink_color, tuning)


## Keeps %ShadowApricot/%ShadowMint's custom_minimum_size a fixed
## tuning.card_offset_px larger than %Panel's own current size on every axis,
## so CenterContainer (which centers every child on the same point) renders
## them as a "matting border" peeking out evenly around the front card.
# DECISION (ui/MainMenu.gd, Bontago-xtq.32 redo, gap item 2): mockup 10 shows
# the two shadow cards diagonally offset (down-right), not centered evenly on
# all sides. An evenly-centered "matting" look was chosen instead of a custom
# manual-position wrapper Control, trading exact diagonal offset fidelity for
# much lower layout risk within the verification budget; disclosed in the
# handback as not pixel-perfect against the mockup.
func _sync_shadow_card_sizes() -> void:
	var base: Vector2 = _front_card.size
	var offset: Vector2 = Vector2.ONE * tuning.card_offset_px
	_shadow_apricot.custom_minimum_size = base + offset * 2.0
	_shadow_mint.custom_minimum_size = base + offset


func _on_host_pressed() -> void:
	var err: Error = net_provider.host_game(0, _player_name())
	if err != OK:
		_show_status("Could not host: %s" % error_string(err))


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


## Toggles the Steam section vs. the "not available" notice (spec 3.4: "Hide
## the online menu entries and show a notice"). Reads net_provider directly
## rather than taking a bool parameter, so a test can mutate a FakeNet's
## `steam_available_value` and re-call this the same way test_lobby.gd
## re-calls `_update_host_only_state()` after mutating its fake.
func _apply_steam_availability() -> void:
	var available: bool = net_provider != null and bool(net_provider.steam_available())
	_steam_section.visible = available
	_steam_unavailable_label.visible = not available
	# DECISION (ui/MainMenu.gd, Bontago-xtq.32 redo, gap item 4): %HostOnlineButton
	# now stays in its %HostRow slot beside %HostButton always -- "hidden/disabled
	# ... same layout slot kept" -- so only %SteamSection (the lobby list below
	# Host) still changes shape when Steam is unavailable. It is disabled in
	# place instead of hidden with its parent.
	_host_online_button.disabled = not available
	if available:
		net_provider.refresh_lobby_list()
		_steam_refresh_countdown_s = float(net_provider.config.steam_lobby_list_refresh_s)
	# DECISION (ui/MainMenu.gd): bridge the ui_up/ui_down (incl. gamepad D-pad)
	# chain from %HostRow straight to %GameList's well when %SteamSection is
	# hidden, the same way the previous version bridged past a hidden
	# %HostOnlineButton.
	var below_host: Control = _steam_lobby_list if available else _game_list
	_host_button.focus_neighbor_bottom = _host_button.get_path_to(below_host)
	_host_online_button.focus_neighbor_bottom = _host_online_button.get_path_to(below_host)
	_game_list.focus_neighbor_top = (
		_game_list.get_path_to(_refresh_steam_button) if available
		else _game_list.get_path_to(_host_button)
	)


func _player_name() -> String:
	var typed: String = _name_edit.text.strip_edges()
	return typed if typed != "" else "Player"


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
