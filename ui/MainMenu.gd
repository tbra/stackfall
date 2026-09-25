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

@onready var _name_edit: LineEdit = %NameEdit
@onready var _host_button: Button = %HostButton
@onready var _sandbox_button: Button = %SandboxButton
@onready var _tutorial_button: Button = %TutorialButton
@onready var _quit_button: Button = %QuitButton
@onready var _game_list: ItemList = %GameList
@onready var _refresh_button: Button = %RefreshButton
@onready var _direct_ip_edit: LineEdit = %DirectIpEdit
@onready var _direct_join_button: Button = %DirectJoinButton
@onready var _status_label: Label = %StatusLabel

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


func _ready() -> void:
	net_provider = Net
	_host_button.pressed.connect(_on_host_pressed)
	_sandbox_button.pressed.connect(_on_sandbox_pressed)
	_tutorial_button.pressed.connect(_on_tutorial_pressed)
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
		_host_button, _sandbox_button, _tutorial_button, _quit_button, _refresh_button, _direct_join_button,
		_host_online_button, _refresh_steam_button,
	]
	for button: BaseButton in buttons:
		button.pressed.connect(_on_sound_button_pressed)
		button.mouse_entered.connect(_on_sound_button_hovered)


func _on_sound_button_pressed() -> void:
	Sfx.play(AudioConfig.EVENT_CLICK)


func _on_sound_button_hovered() -> void:
	Sfx.play(AudioConfig.EVENT_HOVER)


func _on_host_pressed() -> void:
	var err: Error = net_provider.host_game(0, _player_name())
	if err != OK:
		_show_status("Could not host: %s" % error_string(err))


func _on_sandbox_pressed() -> void:
	sandbox_requested.emit()


func _on_tutorial_pressed() -> void:
	tutorial_requested.emit()


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
	if available:
		net_provider.refresh_lobby_list()
		_steam_refresh_countdown_s = float(net_provider.config.steam_lobby_list_refresh_s)
	# DECISION (ui/MainMenu.gd): the .tscn wires HostButton -> SteamSection ->
	# GameList as the happy-path (Steam available) up/down focus chain
	# declaratively. When Steam is unavailable the section is hidden, so
	# bridge the ui_up/ui_down (incl. gamepad D-pad) chain straight from
	# HostButton to GameList instead of leaving it pointed at hidden controls.
	if available:
		_host_button.focus_neighbor_bottom = _host_button.get_path_to(_host_online_button)
		_game_list.focus_neighbor_top = _game_list.get_path_to(_refresh_steam_button)
	else:
		_host_button.focus_neighbor_bottom = _host_button.get_path_to(_game_list)
		_game_list.focus_neighbor_top = _game_list.get_path_to(_host_button)


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
