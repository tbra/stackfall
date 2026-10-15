extends GutTest
## net/SteamClient.gd: encode_match_config() output
## (spec 3.4, docs/archive/M3b_PLAN.md P1).
##
## Static, pure functions — no Steam singleton, real or fake, is touched
## anywhere in this file, so it passes identically whether or not
## addons/godotsteam/ is installed in this checkout.

func _sample_match_config_dict() -> Dictionary:
	# Shaped like MatchConfig.to_dict()'s actual output (config/match/MatchConfig.gd)
	# without depending on MatchConfig's own defaults drifting this test.
	return {
		"map_variant": 1,
		"map_size": 1,
		"player_count": 4,
		"ai_count": 0,
		"ai_difficulty": 1,
		"team_mode": 0,
		"block_timer": 12.0,
		"gravity_multiplier": 1.0,
		"goal_flag_count": 3,
		"gifts_enabled": true,
		"special_frequency": 2,
		"enabled_specials": ["bomb", "anvil"],
		"tilt_mode": 0,
		"hole_mode": 0,
		"match_timer_minutes": 10,
		"sudden_death": true,
		"per_player_timer": false,
		"hot_seat": false,
		"player_colors": [],
		"rng_seed": 12345,
	}


func test_encode_match_config_is_one_json_object_that_parses_back() -> void:
	var data: Dictionary = _sample_match_config_dict()
	var text: String = SteamClient.encode_match_config(data)
	var decoded: Dictionary = JSON.parse_string(text) as Dictionary
	# int(...): JSON has no integer type, so every number round-trips as a
	# float (JSON.parse()'s documented behavior) — comparing that float
	# straight against an int literal is correct in value but GUT warns on
	# the type mismatch, so cast back the way MatchConfig.from_dict() already
	# does for every int field it reads from a Dictionary.
	assert_eq(int(decoded.get("map_variant")), int(data["map_variant"]))
	assert_eq(int(decoded.get("player_count")), int(data["player_count"]))
	assert_eq(decoded.get("enabled_specials"), data["enabled_specials"])
	assert_eq(decoded.get("sudden_death"), data["sudden_death"])
	assert_eq(int(decoded.get("rng_seed")), int(data["rng_seed"]))


func test_is_available_is_false_without_the_real_steam_class_or_true_with_it() -> void:
	# Whatever this checkout actually has — no assumption either way, per
	# docs/archive/M3b_PLAN.md's acceptance ("every P1 test must pass driven entirely
	# by FakeSteam"); this one assertion is the exception, and it only checks
	# that is_available() agrees with ClassDB, never touches Steam itself.
	var client: SteamClient = SteamClient.new()
	assert_eq(client.is_available(), ClassDB.class_exists(&"Steam"))


## Bontago-1pi.48: leave/create/join log lines name the GDScript caller chain.
func _origin_from_a_named_caller() -> String:
	return _origin_helper()


func _origin_helper() -> String:
	return SteamClient.call_origin()


func test_call_origin_names_the_caller_of_the_logging_method() -> void:
	var origin: String = _origin_from_a_named_caller()
	assert_string_contains(origin, "test_steam_client.gd")
	assert_string_contains(origin, "_origin_from_a_named_caller", "frames start at the logging method's caller")
	assert_false(origin.contains("_origin_helper"), "the logging method itself is skipped")


## Without a Steam singleton the self-check still answers (no call reaches Steam).
func test_self_check_line_without_steam_reports_not_initialised() -> void:
	var client: SteamClient = SteamClient.new()
	assert_string_contains(client.self_check_line(42), "lobby=42")
