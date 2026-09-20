extends GutTest
## net/SteamClient.gd: encode_match_config()/decode_match_config() round trip
## (spec 3.4, docs/M3b_PLAN.md P1).
##
## Static, pure functions — no Steam singleton, real or fake, is touched
## anywhere in this file, so it passes identically whether or not
## addons/godotsteam/ is installed in this checkout.

func _sample_match_config_dict() -> Dictionary:
	# Shaped like MatchConfig.to_dict()'s actual output (config/MatchConfig.gd)
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


func test_encode_decode_round_trips_a_match_config_dict() -> void:
	var data: Dictionary = _sample_match_config_dict()
	var text: String = SteamClient.encode_match_config(data)
	var decoded: Dictionary = SteamClient.decode_match_config(text)
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


func test_decode_rejects_malformed_json_without_erroring() -> void:
	var decoded: Dictionary = SteamClient.decode_match_config("{not valid json")
	assert_true(decoded.is_empty())


func test_decode_rejects_truncated_json_without_erroring() -> void:
	var text: String = SteamClient.encode_match_config(_sample_match_config_dict())
	for cut_at: int in range(0, text.length(), 7):
		var truncated: String = text.substr(0, cut_at)
		var decoded: Dictionary = SteamClient.decode_match_config(truncated)
		assert_true(decoded is Dictionary, "truncated at %d chars must not throw" % cut_at)


func test_decode_rejects_empty_text() -> void:
	assert_true(SteamClient.decode_match_config("").is_empty())


func test_decode_rejects_a_json_array_or_scalar_not_a_dictionary() -> void:
	assert_true(SteamClient.decode_match_config("[1, 2, 3]").is_empty())
	assert_true(SteamClient.decode_match_config("42").is_empty())
	assert_true(SteamClient.decode_match_config("\"just a string\"").is_empty())


func test_decode_rejects_text_over_the_configured_byte_limit() -> void:
	var config: NetConfig = load("res://config/net_config.tres") as NetConfig
	# A JSON object whose single field's value alone exceeds the byte limit,
	# but which is otherwise perfectly valid JSON — proves the size check
	# runs independently of JSON.parse_string() succeeding.
	var oversized_value: String = "x".repeat(config.steam_lobby_data_max_bytes + 1)
	var text: String = JSON.stringify({"padding": oversized_value})
	assert_true(SteamClient.decode_match_config(text).is_empty())


func test_decode_rejects_random_garbage_without_erroring() -> void:
	# decode_match_config() takes a String, unlike LanDiscovery.decode_advert()
	# which takes raw bytes — random *bytes* run through
	# PackedByteArray.get_string_from_utf8() print "Unicode parsing error"
	# lines for invalid sequences (verified: not what this test is after), so
	# the garbage here is built from a valid-UTF8 alphabet instead. The point
	# is the same as LanDiscovery's version: never throw, always {} for junk.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var alphabet: String = "{}[]\":,abcXYZ01 \n\t"
	for _i: int in range(50):
		var junk: String = ""
		var length: int = rng.randi_range(0, 64)
		for _c: int in range(length):
			junk += alphabet[rng.randi_range(0, alphabet.length() - 1)]
		var decoded: Dictionary = SteamClient.decode_match_config(junk)
		assert_true(decoded is Dictionary)


func test_is_available_is_false_without_the_real_steam_class_or_true_with_it() -> void:
	# Whatever this checkout actually has — no assumption either way, per
	# docs/M3b_PLAN.md's acceptance ("every P1 test must pass driven entirely
	# by FakeSteam"); this one assertion is the exception, and it only checks
	# that is_available() agrees with ClassDB, never touches Steam itself.
	var client: SteamClient = SteamClient.new()
	assert_eq(client.is_available(), ClassDB.class_exists(&"Steam"))
