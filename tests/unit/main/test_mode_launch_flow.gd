extends GutTest
## Main's one match-world path for every mode: a mode's extras node is attached
## once per built world, freed with it, and a sandbox skips the loading screen.
## Lobby cases run through Main's lobby-start handler; mode cases go through the
## menu entries (start_sandbox_from_menu / start_tutorial_from_menu).

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")

## Main has no class_name (a scene root), so it is held as a Variant.
var _main: Variant = null
var _tiny_map: MapDef
var _saved_gravity_multiplier: float


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	assert_true(Net.is_offline(), "fixture: the real Net must start offline")
	_main = MAIN_SCENE.instantiate()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = _tiny_map
	var tiny_match_config: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true)
	tiny_match_config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(tiny_match_config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	tiny_match_config.rng_seed = 4242
	_main.match_config = tiny_match_config
	add_child_autofree(_main)
	assert_not_null(_main._main_menu, "fixture: Main boots to the main menu")
	_saved_gravity_multiplier = (load("res://config/physics/physics_tuning.tres") as PhysicsTuning).gravity_multiplier


func after_each() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	(load("res://config/physics/physics_tuning.tres") as PhysicsTuning).gravity_multiplier = _saved_gravity_multiplier
	await _settle()


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _lobby_config() -> MatchConfig:
	var config: MatchConfig = (load("res://config/match/match_defaults.tres") as MatchConfig).duplicate(true)
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.rng_seed = 777
	return config


## A normal lobby match: host a session, then what the lobby's Start does.
func _start_lobby_match() -> void:
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "Hostie"), OK)
	_main._on_lobby_start_requested(_lobby_config())


func _count(type_check: Callable) -> int:
	var total: int = 0
	for child: Node in _main.get_children():
		if not child.is_queued_for_deletion() and bool(type_check.call(child)):
			total += 1
	return total


func _local_players() -> int:
	return _count(func(node: Node) -> bool: return node is HotSeat)


func _sandbox_nodes() -> int:
	return _count(func(node: Node) -> bool: return node is Sandbox)


func _tutorial_nodes() -> int:
	return _count(func(node: Node) -> bool: return node is Tutorial)


func _extras_nodes() -> int:
	return _sandbox_nodes() + _tutorial_nodes()


func _rig_pose() -> Transform3D:
	return (_main.get_node("CameraRig") as CameraRig).global_transform


# --- Cases that run on today's lobby path ------------------------------------

func test_lobby_match_builds_one_local_player_and_no_extras() -> void:
	_start_lobby_match()
	await _settle()

	assert_true(_main._world_built, "the world is built")
	assert_eq(_local_players(), 1, "exactly one local player")
	assert_eq(_extras_nodes(), 0, "a lobby match attaches no mode extras")


func test_lobby_match_shows_the_loading_screen() -> void:
	_start_lobby_match()

	assert_true((_main._loading_screen as LoadingScreen).visible, "a lobby match loads behind the loading screen")


func test_leaving_frees_the_local_player() -> void:
	_start_lobby_match()
	await _settle()
	assert_eq(_local_players(), 1, "fixture: a local player exists")

	Net.leave()
	await _settle()

	assert_false(_main._world_built)
	assert_eq(_local_players(), 0, "the local player is gone with the world")
	assert_eq(_extras_nodes(), 0)


func test_restart_rebuilds_exactly_one_local_player() -> void:
	_start_lobby_match()
	await _settle()
	var first: Node = _main._hot_seat

	Match.start_match(Match.config)
	await _settle()

	assert_true(_main._world_built, "the restart built a world again")
	assert_eq(_local_players(), 1, "one local player after the restart, not two")
	assert_ne(_main._hot_seat, first, "a fresh local player, not the old one")
	assert_eq(_extras_nodes(), 0)


func test_restart_resets_the_camera_rig_pose_like_any_rebuild() -> void:
	_start_lobby_match()
	await _settle()
	var built_pose: Transform3D = _rig_pose()
	var rig: CameraRig = _main.get_node("CameraRig") as CameraRig
	rig.global_position += Vector3(7.0, 3.0, -5.0)
	assert_ne(_rig_pose(), built_pose, "fixture: the player moved the camera")

	Match.start_match(Match.config)
	await _settle()

	assert_eq(_rig_pose(), built_pose, "the restart put the camera back to the build pose")


# --- Cases that need the mode launch path -------------------------------------

func test_sandbox_attaches_its_extras_once_for_the_built_world() -> void:
	_main.start_sandbox_from_menu()
	await _settle()

	assert_true(_main._world_built)
	assert_eq(_local_players(), 1, "the sandbox drives the one local player")
	assert_eq(_sandbox_nodes(), 1, "one sandbox extras node")
	assert_eq(_tutorial_nodes(), 0)


func test_tutorial_attaches_its_extras_once_for_the_built_world() -> void:
	_main.start_tutorial_from_menu()
	await _settle()

	assert_true(_main._world_built)
	assert_eq(_local_players(), 1)
	assert_eq(_tutorial_nodes(), 1, "one tutorial extras node")
	assert_eq(_sandbox_nodes(), 0)


func test_restart_attaches_extras_again_and_frees_the_old_ones() -> void:
	_main.start_sandbox_from_menu()
	await _settle()
	var first_extras: Node = _main._sandbox
	var first_player: Node = _main._hot_seat

	Match.start_match(Match.config)
	await _settle()

	assert_eq(_sandbox_nodes(), 1, "exactly one extras node after the restart")
	assert_eq(_local_players(), 1, "exactly one local player after the restart")
	assert_false(is_instance_valid(first_extras), "the old extras node was freed")
	assert_false(is_instance_valid(first_player), "the old local player was freed")
	assert_not_null(_main._sandbox, "the new world has its extras")


func test_restart_keeps_the_mode_so_the_extras_return() -> void:
	_main.start_tutorial_from_menu()
	await _settle()

	Match.start_match(Match.config)
	await _settle()

	assert_eq(_tutorial_nodes(), 1, "a restart is not a return to the lobby: the mode stays")


func test_returning_to_lobby_frees_extras_and_local_player_and_forgets_the_mode() -> void:
	_main.start_sandbox_from_menu()
	await _settle()

	Match.abort_match()
	await _settle()

	assert_eq(_extras_nodes(), 0, "extras freed with the world")
	assert_eq(_local_players(), 0, "local player freed with the world")

	# The mode is forgotten: an ordinary lobby match afterwards has no extras.
	_start_lobby_match()
	await _settle()
	assert_eq(_local_players(), 1)
	assert_eq(_extras_nodes(), 0, "a later lobby match does not inherit the sandbox")


func test_sandbox_skips_the_loading_screen() -> void:
	_main.start_sandbox_from_menu()

	assert_false((_main._loading_screen as LoadingScreen).visible, "sandbox starts at once, no loading screen")


func test_tutorial_shows_the_loading_screen() -> void:
	_main.start_tutorial_from_menu()

	assert_true((_main._loading_screen as LoadingScreen).visible, "only the sandbox skips loading")


func test_sandbox_restart_resets_the_camera_rig_pose_like_any_rebuild() -> void:
	_main.start_sandbox_from_menu()
	await _settle()
	var built_pose: Transform3D = _rig_pose()
	(_main.get_node("CameraRig") as CameraRig).global_position += Vector3(7.0, 3.0, -5.0)
	assert_ne(_rig_pose(), built_pose, "fixture: the player moved the camera")

	Match.start_match(Match.config)
	await _settle()

	assert_eq(_rig_pose(), built_pose, "an F5 restart resets the view, nothing is kept")
