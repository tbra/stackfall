extends GutTest
## core/net/FloodLimits.gd and the flood / wire-cap fields of
## config/net/NetConfig.gd: defaults, sanitize() clamps and the one-row-per-intent
## table that the host's per-peer buckets are built from.

const NET_CONFIG_PATH: String = "res://config/net/net_config.tres"
const FLOOD_PREFIX: String = "flood_"
const BURST_SUFFIX: String = "_burst"
const REFILL_SUFFIX: String = "_refill_per_s"
const EXPECTED_INTENTS: int = 12
const WIRE_CAP_FIELDS: Array[String] = [
	"special_id_max_length",
	"reject_reason_max_length",
	"cat_duration_max_s",
	"handshake_build_max_length",
	"handshake_name_max_length",
	"ping_rtt_max_ms",
]
const HUGE_CURSOR_HZ: float = 1000.0

## Plan defaults: intent -> Vector2(burst, refill_per_s).
const DEFAULTS: Dictionary = {
	&"place": Vector2(6, 4.0),
	&"throw": Vector2(6, 4.0),
	&"cursor": Vector2(30, 30.0),
	&"cat_target": Vector2(30, 30.0),
	&"gift_slot": Vector2(4, 2.0),
	&"set_ready": Vector2(4, 1.0),
	&"loading_ready": Vector2(3, 0.5),
	&"replay_request": Vector2(3, 0.5),
	&"return_lobby": Vector2(3, 0.5),
	&"replay_ack": Vector2(3, 0.5),
	&"pong": Vector2(4, 2.0),
	&"handshake": Vector2(2, 0.2),
}

var _config: NetConfig


func before_each() -> void:
	_config = (load(NET_CONFIG_PATH) as NetConfig).duplicate() as NetConfig


func _flood_fields(suffix: String) -> Array[String]:
	var names: Array[String] = []
	for prop: Dictionary in _config.get_property_list():
		var prop_name: String = String(prop["name"])
		if prop_name.begins_with(FLOOD_PREFIX) and prop_name.ends_with(suffix):
			names.append(prop_name)
	return names


func _intent_of(field: String, suffix: String) -> StringName:
	return StringName(field.trim_prefix(FLOOD_PREFIX).trim_suffix(suffix))


func test_net_config_tres_loads_as_net_config() -> void:
	var loaded: Resource = load(NET_CONFIG_PATH)
	assert_not_null(loaded)
	assert_true(loaded is NetConfig)


func test_there_are_24_flood_fields() -> void:
	assert_eq(_flood_fields(BURST_SUFFIX).size(), EXPECTED_INTENTS)
	assert_eq(_flood_fields(REFILL_SUFFIX).size(), EXPECTED_INTENTS)


func test_every_flood_field_names_a_table_intent() -> void:
	var intents: Array[StringName] = FloodLimits.intents()
	for field: String in _flood_fields(BURST_SUFFIX):
		assert_true(intents.has(_intent_of(field, BURST_SUFFIX)), field)
	for field: String in _flood_fields(REFILL_SUFFIX):
		assert_true(intents.has(_intent_of(field, REFILL_SUFFIX)), field)


func test_shipped_tres_carries_the_plan_defaults() -> void:
	var limits: Dictionary = FloodLimits.from_config(_config)
	for intent: StringName in DEFAULTS:
		assert_eq(limits[intent], DEFAULTS[intent], String(intent))


func test_script_defaults_match_the_tres() -> void:
	var fresh: NetConfig = NetConfig.new()
	assert_eq(FloodLimits.from_config(fresh), FloodLimits.from_config(_config))
	for field: String in WIRE_CAP_FIELDS:
		assert_eq(fresh.get(field), _config.get(field), field)


func test_wire_cap_defaults() -> void:
	assert_eq(_config.special_id_max_length, 32)
	assert_eq(_config.reject_reason_max_length, 48)
	assert_eq(_config.cat_duration_max_s, 60.0)
	assert_eq(_config.handshake_build_max_length, 64)
	assert_eq(_config.handshake_name_max_length, 64)
	assert_eq(_config.ping_rtt_max_ms, 10000)


func test_defaults_are_sane_and_survive_sanitize_unchanged() -> void:
	var before: Dictionary = FloodLimits.from_config(_config)
	_config.sanitize()
	assert_eq(FloodLimits.from_config(_config), before)
	for intent: StringName in before:
		var row: Vector2 = before[intent]
		assert_gte(row.x, 1.0, String(intent))
		assert_gt(row.y, 0.0, String(intent))


func test_from_config_has_exactly_one_row_per_intent() -> void:
	var limits: Dictionary = FloodLimits.from_config(_config)
	var intents: Array[StringName] = FloodLimits.intents()
	assert_eq(intents.size(), EXPECTED_INTENTS)
	assert_eq(limits.size(), intents.size())
	for intent: StringName in intents:
		assert_true(limits.has(intent), String(intent))
		assert_true(limits[intent] is Vector2, String(intent))


func test_intent_constants_are_distinct() -> void:
	var seen: Dictionary = {}
	for intent: StringName in FloodLimits.intents():
		assert_false(seen.has(intent), String(intent))
		seen[intent] = true


func test_from_config_reads_the_config_it_is_given() -> void:
	_config.flood_place_burst = 9
	_config.flood_place_refill_per_s = 2.5
	_config.flood_handshake_burst = 5
	_config.flood_handshake_refill_per_s = 0.7
	var limits: Dictionary = FloodLimits.from_config(_config)
	assert_eq(limits[FloodLimits.INTENT_PLACE], Vector2(9, 2.5))
	assert_eq(limits[FloodLimits.INTENT_HANDSHAKE], Vector2(5, 0.7))


func test_sanitize_clamps_zero_and_negative_bursts_and_refills() -> void:
	for field: String in _flood_fields(BURST_SUFFIX):
		_config.set(field, 0)
	for field: String in _flood_fields(REFILL_SUFFIX):
		_config.set(field, -3.0)
	_config.sanitize()
	var limits: Dictionary = FloodLimits.from_config(_config)
	for intent: StringName in limits:
		var row: Vector2 = limits[intent]
		assert_gte(row.x, 1.0, "burst %s" % intent)
		assert_gt(row.y, 0.0, "refill %s" % intent)
	for field: String in _flood_fields(BURST_SUFFIX):
		assert_eq(int(_config.get(field)), 1, field)


func test_sanitize_raises_cursor_and_cat_refill_to_one_and_a_half_cursor_hz() -> void:
	_config.cursor_hz = 40.0
	_config.flood_cursor_refill_per_s = 1.0
	_config.flood_cat_target_refill_per_s = 1.0
	_config.sanitize()
	assert_almost_eq(_config.flood_cursor_refill_per_s, 60.0, 0.0001)
	assert_almost_eq(_config.flood_cat_target_refill_per_s, 60.0, 0.0001)


func test_sanitize_ties_refill_to_the_clamped_cursor_hz() -> void:
	_config.cursor_hz = HUGE_CURSOR_HZ
	_config.flood_cursor_refill_per_s = 1.0
	_config.flood_cat_target_refill_per_s = 1.0
	_config.sanitize()
	# cursor_hz clamps to 60 first, so the floor is 90, not 1500.
	assert_almost_eq(_config.cursor_hz, 60.0, 0.0001)
	assert_almost_eq(_config.flood_cursor_refill_per_s, 90.0, 0.0001)
	assert_almost_eq(_config.flood_cat_target_refill_per_s, 90.0, 0.0001)


func test_sanitize_does_not_lower_a_generous_cursor_refill() -> void:
	_config.flood_cursor_refill_per_s = 200.0
	_config.flood_cat_target_refill_per_s = 150.0
	_config.sanitize()
	assert_eq(_config.flood_cursor_refill_per_s, 200.0)
	assert_eq(_config.flood_cat_target_refill_per_s, 150.0)


func test_default_cursor_refill_clears_one_and_a_half_cursor_hz() -> void:
	assert_gte(_config.flood_cursor_refill_per_s, 1.5 * _config.cursor_hz)
	assert_gte(_config.flood_cat_target_refill_per_s, 1.5 * _config.cursor_hz)


func test_sanitize_clamps_wire_caps() -> void:
	_config.special_id_max_length = 0
	_config.reject_reason_max_length = -4
	_config.cat_duration_max_s = -1.0
	_config.handshake_build_max_length = 0
	_config.handshake_name_max_length = 1
	_config.ping_rtt_max_ms = -5
	_config.sanitize()
	assert_gte(_config.special_id_max_length, 1)
	assert_gte(_config.reject_reason_max_length, 1)
	assert_gt(_config.cat_duration_max_s, 0.0)
	assert_gte(_config.handshake_build_max_length, 1)
	assert_gte(_config.handshake_name_max_length, _config.max_player_name_length)
	assert_gt(_config.ping_rtt_max_ms, 0)


func test_raw_name_cap_never_drops_below_the_clean_name_cap() -> void:
	_config.max_player_name_length = 64
	_config.handshake_name_max_length = 20
	_config.sanitize()
	assert_eq(_config.handshake_name_max_length, 64)
