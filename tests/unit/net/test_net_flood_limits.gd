extends GutTest
## core/net/FloodLimits.gd and the flood / wire-cap fields of
## config/net/NetConfig.gd: sanitize() clamps and the one-row-per-intent table that the host's
## per-peer buckets are built from.

const NET_CONFIG_PATH: String = "res://config/net/net_config.tres"
const FLOOD_PREFIX: String = "flood_"
const BURST_SUFFIX: String = "_burst"
const REFILL_SUFFIX: String = "_refill_per_s"
const UNIQUE_BURST_BASE: int = 10
const UNIQUE_REFILL_STEP: float = 0.25
const HUGE_CURSOR_HZ: float = 1000.0

## Every intent a host-side bucket exists for.
const INTENTS: Array[StringName] = [
	FloodLimits.INTENT_PLACE,
	FloodLimits.INTENT_THROW,
	FloodLimits.INTENT_CURSOR,
	FloodLimits.INTENT_CAT_TARGET,
	FloodLimits.INTENT_GIFT_SLOT,
	FloodLimits.INTENT_SET_READY,
	FloodLimits.INTENT_LOADING_READY,
	FloodLimits.INTENT_REPLAY_REQUEST,
	FloodLimits.INTENT_RETURN_LOBBY,
	FloodLimits.INTENT_REPLAY_ACK,
	FloodLimits.INTENT_PONG,
	FloodLimits.INTENT_HANDSHAKE,
]

var _config: NetConfig


func before_each() -> void:
	_config = (load(NET_CONFIG_PATH) as NetConfig).duplicate() as NetConfig


func _burst_field(intent: StringName) -> String:
	return FLOOD_PREFIX + String(intent) + BURST_SUFFIX


func _refill_field(intent: StringName) -> String:
	return FLOOD_PREFIX + String(intent) + REFILL_SUFFIX


func test_defaults_are_sane_and_survive_sanitize_unchanged() -> void:
	var before: Dictionary = FloodLimits.from_config(_config)
	_config.sanitize()
	assert_eq(FloodLimits.from_config(_config), before)
	for intent: StringName in before:
		var row: Vector2 = before[intent]
		assert_gte(row.x, 1.0, String(intent))
		assert_gt(row.y, 0.0, String(intent))


func test_from_config_has_exactly_one_vector_row_per_intent() -> void:
	var limits: Dictionary = FloodLimits.from_config(_config)
	assert_eq(limits.size(), INTENTS.size())
	for intent: StringName in INTENTS:
		assert_true(limits.has(intent), String(intent))
		assert_true(limits[intent] is Vector2, String(intent))


func test_every_intent_row_reads_its_own_config_fields() -> void:
	var expected: Dictionary = {}
	for i: int in range(INTENTS.size()):
		var burst: int = UNIQUE_BURST_BASE + i
		var refill: float = UNIQUE_REFILL_STEP * float(i + 1)
		_config.set(_burst_field(INTENTS[i]), burst)
		_config.set(_refill_field(INTENTS[i]), refill)
		expected[INTENTS[i]] = Vector2(float(burst), refill)
	var limits: Dictionary = FloodLimits.from_config(_config)
	for intent: StringName in INTENTS:
		assert_eq(limits[intent], expected[intent], String(intent))


func test_sanitize_clamps_zero_and_negative_bursts_and_refills() -> void:
	for intent: StringName in INTENTS:
		_config.set(_burst_field(intent), 0)
		_config.set(_refill_field(intent), -3.0)
	_config.sanitize()
	var limits: Dictionary = FloodLimits.from_config(_config)
	for intent: StringName in limits:
		var row: Vector2 = limits[intent]
		assert_gte(row.x, 1.0, "burst %s" % intent)
		assert_gt(row.y, 0.0, "refill %s" % intent)
	for intent: StringName in INTENTS:
		assert_eq(int(_config.get(_burst_field(intent))), 1, String(intent))


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
