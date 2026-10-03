extends Node
## Bontago-1pi.53 (PL1a): off-screen capture of the lobby's players panel -- host view,
## 3 humans + 2 bots, once with teams off and once with teams on (one Random pick, one
## Hard bot). Writes the cropped Players card of each state (full lobby too) and
## prints the paths.
##   godot --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy \
##     --path . res://tools/screenshot_lobby_players.tscn -- --agent-probe --render-size=1280x720 [--out=<dir>]
const SETTLE_FRAMES: int = 6
const OUT_PREFIX: String = "--out="
const HUMANS: int = 3
const BOTS: int = 2
const HARD_BOT_ORDINAL: int = 1
const RANDOM_HUMAN_PEER: int = 2

var _output_dir: String = "user://"


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(OUT_PREFIX):
			_output_dir = arg.trim_prefix(OUT_PREFIX)
	var viewport: SubViewport = AgentProbe.make_render_viewport(self, Vector2i(1280, 720))
	var lobby: Lobby = (load("res://ui/Lobby.tscn") as PackedScene).instantiate() as Lobby
	viewport.add_child(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = true
	fake.is_offline_value = true
	for index: int in range(HUMANS):
		fake.slots_by_peer[index + 1] = index
		fake.names_by_peer[index + 1] = ["Mira", "Tomas", "Ines"][index]
	lobby.net_provider = fake
	(lobby.get_node("%PlayerCountSpin") as SpinBox).value = HUMANS + BOTS
	(lobby.get_node("%AiCountSpin") as SpinBox).value = BOTS
	lobby._on_setting_changed()
	await _settle()
	await _capture(viewport, lobby, "teams_off")

	var panel: LobbyPlayersPanel = lobby.get_node("%PlayersPanel") as LobbyPlayersPanel
	panel.teams_toggled.emit(true)
	await _settle()
	var random_row: LobbySeatRow = (panel._player_rows[RANDOM_HUMAN_PEER - 1] as LobbySeatRow)
	random_row.team_cycle_requested.emit(random_row.seat_key, true)
	await _settle()
	var bot_row: LobbySeatRow = (panel._player_rows[HUMANS + HARD_BOT_ORDINAL] as LobbySeatRow)
	bot_row.difficulty_chosen.emit(bot_row.seat_key, MatchConfig.AiDifficulty.HARD)
	await _settle()
	# Focus ring on a colour box, as a pad user would see it.
	(panel._player_rows[0] as LobbySeatRow).color_button.grab_focus()
	await _settle()
	await _capture(viewport, lobby, "teams_on")
	get_tree().quit()


func _settle() -> void:
	for _frame: int in range(SETTLE_FRAMES):
		await get_tree().process_frame


func _capture(viewport: SubViewport, lobby: Lobby, label: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_output_dir)
	var card: Control = lobby.get_node("%PlayersCard") as Control
	var rect: Rect2i = Rect2i(card.get_global_rect())
	var crop: Image = image.get_region(rect.intersection(Rect2i(Vector2i.ZERO, image.get_size())))
	var full_path: String = _output_dir.path_join("lobby_players_%s_full.png" % label)
	var crop_path: String = _output_dir.path_join("lobby_players_%s.png" % label)
	var error_full: Error = ContactSheet.save_capture(image, full_path)
	var error_crop: Error = ContactSheet.save_capture(crop, crop_path)
	print("LOBBY_PLAYERS_CAPTURE %s error=%d %s error=%d" % [
		ProjectSettings.globalize_path(crop_path), error_crop, ProjectSettings.globalize_path(full_path), error_full,
	])
