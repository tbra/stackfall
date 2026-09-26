extends GutTest
## autoload/Net.gd: `--match-config=<path>` command-line flag (Bontago-3k0,
## deferred from Bontago-keo.19). Host-only override for the MatchConfig a
## `--headless-host` match starts from; extends the existing
## `_apply_command_line_args` parser rather than a parallel path.
##
## Same "independent Net instance" pattern as test_net_session.gd: Net.gd has
## no class_name (it must not collide with the `Net` autoload singleton), so
## each side below is built from the preloaded script and held through a
## `Variant`-typed reference, with its own MultiplayerAPI scoped to its own
## node path.

const _NET_SCRIPT: GDScript = preload("res://autoload/Net.gd")

const _TURN_BASED_FIXTURE: String = "res://tests/fixtures/match_configs/turn_based.tres"
const _TEAMS_2_FIXTURE: String = "res://tests/fixtures/match_configs/teams_2.tres"
const _SUDDEN_DEATH_FIXTURE: String = "res://tests/fixtures/match_configs/sudden_death.tres"
const _PHYSICAL_BALANCE_FIXTURE: String = "res://tests/fixtures/match_configs/physical_balance.tres"

## Ports increment per test so a socket the OS hasn't fully released yet from
## the previous test can never collide with the next one. Chosen clear of the
## ranges already claimed by other *_next_port statics (see test_net_session.gd
## 47800, test_match_lifecycle.gd 47900, test_main.gd 48000,
## test_headless_bot_match.gd 48300, test_field_map_def.gd /
## test_hover_cap_real_match.gd 48700).
static var _next_port: int = 48900

var _node: Variant


func _make_side(node_name: String) -> Variant:
	var node: Node = _NET_SCRIPT.new()
	node.name = node_name
	var path: NodePath = NodePath(String(get_path()) + "/" + node_name)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), path)
	add_child_autofree(node)
	return node


func before_each() -> void:
	_node = _make_side("CmdNet")


func after_each() -> void:
	if _node != null:
		_node.leave()
	await get_tree().process_frame
	await get_tree().process_frame


func _take_port() -> int:
	var port: int = _next_port
	_next_port += 1
	return port


func test_match_config_flag_parsed_and_fixture_loaded() -> void:
	var started: bool = _node._apply_command_line_args(PackedStringArray([
		"--headless-host",
		"--port=%d" % _take_port(),
		"--match-config=%s" % _TURN_BASED_FIXTURE,
	]))
	assert_true(started)
	assert_eq(_node.mode(), Net.Mode.HOST)
	var override: MatchConfig = _node.match_config_override()
	assert_not_null(override)
	assert_true(override.turn_based)


func test_match_config_flag_loads_each_m6_mode_fixture() -> void:
	var fixtures_by_mode: Dictionary = {
		"teams_2": _TEAMS_2_FIXTURE,
		"sudden_death": _SUDDEN_DEATH_FIXTURE,
		"physical_balance": _PHYSICAL_BALANCE_FIXTURE,
	}
	for mode_name: String in fixtures_by_mode:
		var side: Variant = _make_side("CmdNet_%s" % mode_name)
		side._apply_command_line_args(PackedStringArray([
			"--headless-host",
			"--port=%d" % _take_port(),
			"--match-config=%s" % String(fixtures_by_mode[mode_name]),
		]))
		var override: MatchConfig = side.match_config_override()
		assert_not_null(override, "%s fixture should have loaded" % mode_name)
		match mode_name:
			"teams_2":
				assert_eq(override.team_mode, MatchConfig.TeamMode.TEAMS_2)
			"sudden_death":
				assert_true(override.sudden_death)
			"physical_balance":
				assert_eq(override.tilt_mode, MatchConfig.TiltMode.PHYSICAL_BALANCE)
		side.leave()


func test_match_config_flag_wrong_path_falls_back_to_null() -> void:
	_node._apply_command_line_args(PackedStringArray([
		"--headless-host",
		"--port=%d" % _take_port(),
		"--match-config=res://tests/fixtures/match_configs/does_not_exist.tres",
	]))
	assert_push_error("no resource at that path", "a bad path must be logged, not silent")
	assert_null(_node.match_config_override())


func test_match_config_flag_wrong_resource_type_falls_back_to_null() -> void:
	_node._apply_command_line_args(PackedStringArray([
		"--headless-host",
		"--port=%d" % _take_port(),
		# net_config.tres is a real, loadable resource, but a NetConfig, not a
		# MatchConfig -- the wrong-type rejection path, not the missing-path one.
		"--match-config=res://config/net_config.tres",
	]))
	assert_push_error("is not a MatchConfig", "a wrong-type resource must be logged, not silent")
	assert_null(_node.match_config_override())


func test_match_config_flag_ignored_without_host_flag() -> void:
	# A listener to join against so the --join branch actually runs (and can
	# be observed to ignore --match-config) rather than failing to connect.
	var host: Variant = _make_side("CmdNet_ListenHost")
	var host_port: int = _take_port()
	host._apply_command_line_args(PackedStringArray(["--headless-host", "--port=%d" % host_port]))

	_node._apply_command_line_args(PackedStringArray([
		"--join=127.0.0.1",
		"--port=%d" % host_port,
		"--match-config=%s" % _TURN_BASED_FIXTURE,
	]))
	assert_null(_node.match_config_override())

	host.leave()
	await get_tree().process_frame
	await get_tree().process_frame


func test_match_config_flag_absent_leaves_override_null() -> void:
	_node._apply_command_line_args(PackedStringArray([
		"--headless-host",
		"--port=%d" % _take_port(),
	]))
	assert_null(_node.match_config_override())
