extends Node
## Bontago-1pi.95 probe: the Vs bots lobby with seven bots (private session), one capture. Run windowed with the agent-probe flags and
## --render-size=1920x1080 (docs/AGENT_WORKFLOW.md).
const SETTLE_FRAMES: int = 8
const FALLBACK_SIZE: Vector2i = Vector2i(1920, 1080)

var _vp: SubViewport


func _shot(label: String) -> void:
	for _i: int in range(SETTLE_FRAMES):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path: String = "user://lobby_7bots_%s.png" % label
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
	config.player_count = 8
	config.ai_count = 7
	fake.lobby_data_value = config.to_dict()
	_vp.add_child(lobby)
	await get_tree().process_frame
	lobby.net_provider = fake
	fake.all_peers_ready_value = true
	var data: Dictionary = config.to_dict()
	data["bot_names"] = PackedStringArray(["Velocity", "Monolith", "Gantry", "Velocity", "Monolith", "Gantry", "Velocity"])
	data["roster"] = [{"peer_id": 1, "slot_id": 0, "name": "Tonyflow", "ready": true}]
	Events.net_lobby_data_changed.emit(data)
	lobby._update_host_only_state()
	await _shot("%dx%d" % [_vp.size.x, _vp.size.y])
	get_tree().quit()
