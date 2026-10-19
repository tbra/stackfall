extends GutTest
## net/session/NetCommandLine.gd: every flag Net reads after Godot's "--", bad
## input, and the "+connect_lobby" launch token.


func _parse(args: Array[String]) -> NetCommandLine.Options:
	return NetCommandLine.parse(PackedStringArray(args))


func test_empty_command_line_asks_for_nothing() -> void:
	var o: NetCommandLine.Options = _parse([])
	assert_false(o.has_simulation)
	assert_false(o.steam_public_lobby)
	assert_eq(o.port, 0)
	assert_eq(o.player_name, "")
	assert_false(o.wants_host())
	assert_false(o.host_online)
	assert_false(o.advertise)
	assert_false(o.has_match_config)
	assert_false(o.has_join)


func test_host_flag() -> void:
	var o: NetCommandLine.Options = _parse(["--host"])
	assert_true(o.host)
	assert_false(o.headless_host)
	assert_true(o.wants_host())
	assert_true(o.lan_visible(), "a windowed host is on the LAN browser")


func test_headless_host_is_off_the_lan_unless_advertise() -> void:
	var quiet: NetCommandLine.Options = _parse(["--headless-host"])
	assert_true(quiet.headless_host)
	assert_true(quiet.wants_host())
	assert_false(quiet.lan_visible())
	var loud: NetCommandLine.Options = _parse(["--headless-host", "--advertise"])
	assert_true(loud.advertise)
	assert_true(loud.lan_visible())


func test_host_online_flag() -> void:
	var o: NetCommandLine.Options = _parse(["--host-online"])
	assert_true(o.host_online)
	assert_false(o.wants_host())


func test_steam_public_lobby_flag() -> void:
	assert_true(_parse(["--steam-public-lobby"]).steam_public_lobby)
	assert_false(_parse(["--steam-public-lobby=1"]).steam_public_lobby, "a bare flag only; key=value is not a flag")


func test_port_and_player_name() -> void:
	var o: NetCommandLine.Options = _parse(["--port=48123", "--player-name=Ada Lovelace"])
	assert_eq(o.port, 48123)
	assert_eq(o.player_name, "Ada Lovelace")


func test_player_name_keeps_later_equals_signs() -> void:
	assert_eq(_parse(["--player-name=a=b"]).player_name, "a=b")


func test_simulation_flags() -> void:
	var both: NetCommandLine.Options = _parse(["--sim-lag=120", "--sim-loss=0.05"])
	assert_true(both.has_simulation)
	assert_almost_eq(both.sim_lag_ms, 120.0, 0.0001)
	assert_almost_eq(both.sim_loss, 0.05, 0.0001)
	var lag_only: NetCommandLine.Options = _parse(["--sim-lag=80"])
	assert_true(lag_only.has_simulation)
	assert_almost_eq(lag_only.sim_loss, 0.0, 0.0001)
	var loss_only: NetCommandLine.Options = _parse(["--sim-loss=0.1"])
	assert_true(loss_only.has_simulation)
	assert_almost_eq(loss_only.sim_lag_ms, 0.0, 0.0001)


func test_match_config_path() -> void:
	var o: NetCommandLine.Options = _parse(["--headless-host", "--match-config=cfg/match.tres"])
	assert_true(o.has_match_config)
	assert_eq(o.match_config_path, "cfg/match.tres")


func test_join_address_without_port_uses_the_port_flag() -> void:
	var o: NetCommandLine.Options = _parse(["--join=192.168.1.20", "--port=48000"])
	assert_true(o.has_join)
	assert_eq(o.join_address, "192.168.1.20")
	assert_eq(o.join_port, 48000)


func test_join_address_with_port_beats_the_port_flag() -> void:
	var o: NetCommandLine.Options = _parse(["--join=10.0.0.5:4711", "--port=48000"])
	assert_eq(o.join_address, "10.0.0.5")
	assert_eq(o.join_port, 4711)


func test_join_without_any_port_reads_zero() -> void:
	assert_eq(_parse(["--join=host.example"]).join_port, 0)


func test_leading_dashes_are_stripped_any_number() -> void:
	var o: NetCommandLine.Options = _parse(["-host", "---port=5", "--player-name=x"])
	assert_true(o.host)
	assert_eq(o.port, 5)
	assert_eq(o.player_name, "x")


func test_bad_numbers_read_as_zero() -> void:
	var o: NetCommandLine.Options = _parse(["--port=abc", "--sim-lag=fast", "--sim-loss=", "--join=h:nope"])
	assert_eq(o.port, 0)
	assert_true(o.has_simulation, "the flag is present even when its value is junk")
	assert_almost_eq(o.sim_lag_ms, 0.0, 0.0001)
	assert_almost_eq(o.sim_loss, 0.0, 0.0001)
	assert_eq(o.join_address, "h")
	assert_eq(o.join_port, 0)


func test_negative_port_is_passed_through_for_the_consumer_to_default() -> void:
	assert_eq(_parse(["--port=-7"]).port, -7)


func test_empty_values_are_present_but_empty() -> void:
	var o: NetCommandLine.Options = _parse(["--join=", "--match-config=", "--player-name="])
	assert_true(o.has_join)
	assert_eq(o.join_address, "")
	assert_true(o.has_match_config)
	assert_eq(o.match_config_path, "")
	assert_eq(o.player_name, "")


func test_key_flags_without_a_value_are_ignored() -> void:
	var o: NetCommandLine.Options = _parse(["--join", "--port", "--sim-lag", "--match-config", "--player-name"])
	assert_false(o.has_join)
	assert_false(o.has_simulation)
	assert_false(o.has_match_config)
	assert_eq(o.port, 0)
	assert_eq(o.player_name, "")


func test_value_flags_given_as_a_bare_flag_do_not_start_a_session() -> void:
	var o: NetCommandLine.Options = _parse(["--host=1", "--headless-host=1", "--host-online=1"])
	assert_false(o.wants_host())
	assert_false(o.host_online)


func test_unknown_tokens_are_ignored() -> void:
	var o: NetCommandLine.Options = _parse(["--no-such-flag", "--also=nothing", "plain", "--port=9"])
	assert_eq(o.port, 9)
	assert_false(o.wants_host())


func test_later_duplicate_overwrites_the_earlier_one() -> void:
	assert_eq(_parse(["--port=1", "--port=2"]).port, 2)


func test_roles_can_combine_and_the_consumer_orders_them() -> void:
	var o: NetCommandLine.Options = _parse(["--host", "--host-online", "--join=1.2.3.4"])
	assert_true(o.wants_host())
	assert_true(o.host_online)
	assert_true(o.has_join)


func test_parse_leaves_the_input_untouched() -> void:
	var args: PackedStringArray = PackedStringArray(["--port=5"])
	NetCommandLine.parse(args)
	assert_eq(args, PackedStringArray(["--port=5"]))


# --- +connect_lobby -----------------------------------------------------------

func _lobby(args: Array[String]) -> int:
	return NetCommandLine.connect_lobby_id(PackedStringArray(args))


func test_connect_lobby_reads_the_id_after_the_token() -> void:
	assert_eq(_lobby(["game.exe", "+connect_lobby", "109775241234567890"]), 109775241234567890)


func test_connect_lobby_absent_or_trailing_is_zero() -> void:
	assert_eq(_lobby([]), 0)
	assert_eq(_lobby(["--host"]), 0)
	assert_eq(_lobby(["+connect_lobby"]), 0)


func test_connect_lobby_rejects_non_numeric_and_non_positive() -> void:
	assert_eq(_lobby(["+connect_lobby", "abc"]), 0)
	assert_eq(_lobby(["+connect_lobby", "12x"]), 0)
	assert_eq(_lobby(["+connect_lobby", "0"]), 0)
	assert_eq(_lobby(["+connect_lobby", "-5"]), 0)
	assert_eq(_lobby(["+connect_lobby", ""]), 0)


func test_connect_lobby_only_the_first_token_counts() -> void:
	assert_eq(_lobby(["+connect_lobby", "bad", "+connect_lobby", "77"]), 0)
	assert_eq(_lobby(["+connect_lobby", "5", "+connect_lobby", "77"]), 5)


func test_user_arguments_never_carry_connect_lobby() -> void:
	var o: NetCommandLine.Options = _parse(["+connect_lobby", "5"])
	assert_false(o.wants_host())
	assert_false(o.has_join)
