extends Node
## Bontago-1pi.83 probe: the Vs bots lobby (one human, one auto-added bot, private session),
## Advanced collapsed then expanded. Run windowed with the agent-probe flags and
## --render-size=1920x1080 (docs/AGENT_WORKFLOW.md).
const SETTLE_FRAMES: int = 8
const FALLBACK_SIZE: Vector2i = Vector2i(1920, 1080)

var _vp: SubViewport


func _shot(label: String) -> void:
	for _i: int in range(SETTLE_FRAMES):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path: String = "user://lobby_vsbots_%s.png" % label
	_vp.get_texture().get_image().save_png(path)
	print("SHOT %s %s" % [label, ProjectSettings.globalize_path(path)])


func _ready() -> void:
	_vp = AgentProbe.make_render_viewport(self, FALLBACK_SIZE)
	var lobby: Lobby = (load("res://ui/Lobby.tscn") as PackedScene).instantiate() as Lobby
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = true
	fake.is_offline_value = true
	fake.is_private_session_value = true
	fake.slots_by_peer[1] = 0
	fake.names_by_peer[1] = "Tonyflow"
	var config: MatchConfig = MatchConfig.new()
	config.player_count = 2
	config.ai_count = 1
	fake.lobby_data_value = config.to_dict()
	_vp.add_child(lobby)
	await get_tree().process_frame
	lobby.net_provider = fake
	lobby._republish_roster_if_host()
	lobby._on_add_bot_requested()
	await _shot("collapsed")
	for section: LobbySection in lobby._sections():
		section.set_advanced_open(true)
	(lobby.get_node("%GameSection") as LobbySection).advanced_button.grab_focus()
	await _shot("expanded")
	get_tree().quit()
