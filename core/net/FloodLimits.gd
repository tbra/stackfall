class_name FloodLimits
extends RefCounted
## The one NetConfig -> flood limits table: for every host-side intent that a
## peer can send, its token-bucket size and refill rate. Pure data, no clock and
## no per-peer state (that lives in whatever consumes the table, one bucket per
## peer per intent). Callers build it once from the sanitized NetConfig:
## `FloodLimits.from_config(config)`.
##
## A row is `Vector2(burst, refill_per_s)`: x is the bucket size (how many
## requests may arrive back to back), y the sustained tokens per second. The
## row layout is a plain Dictionary so a consumer needs no type from here;
## an intent that is not in the table is not limited.

const INTENT_PLACE: StringName = &"place"
const INTENT_THROW: StringName = &"throw"
const INTENT_CURSOR: StringName = &"cursor"
const INTENT_CAT_TARGET: StringName = &"cat_target"
const INTENT_GIFT_SLOT: StringName = &"gift_slot"
const INTENT_SET_READY: StringName = &"set_ready"
const INTENT_LOADING_READY: StringName = &"loading_ready"
const INTENT_REPLAY_REQUEST: StringName = &"replay_request"
const INTENT_RETURN_LOBBY: StringName = &"return_lobby"
const INTENT_REPLAY_ACK: StringName = &"replay_ack"
const INTENT_PONG: StringName = &"pong"
const INTENT_HANDSHAKE: StringName = &"handshake"


## Every limited intent, in table order.
static func intents() -> Array[StringName]:
	return [
		INTENT_PLACE,
		INTENT_THROW,
		INTENT_CURSOR,
		INTENT_CAT_TARGET,
		INTENT_GIFT_SLOT,
		INTENT_SET_READY,
		INTENT_LOADING_READY,
		INTENT_REPLAY_REQUEST,
		INTENT_RETURN_LOBBY,
		INTENT_REPLAY_ACK,
		INTENT_PONG,
		INTENT_HANDSHAKE,
	]


## StringName intent -> Vector2(burst, refill_per_s), one row per intent(). The
## values are read as they are in `config`; call config.sanitize() first when
## the config did not come from the shipped net_config.tres.
static func from_config(config: NetConfig) -> Dictionary:
	return {
		INTENT_PLACE: _row(config.flood_place_burst, config.flood_place_refill_per_s),
		INTENT_THROW: _row(config.flood_throw_burst, config.flood_throw_refill_per_s),
		INTENT_CURSOR: _row(config.flood_cursor_burst, config.flood_cursor_refill_per_s),
		INTENT_CAT_TARGET: _row(config.flood_cat_target_burst, config.flood_cat_target_refill_per_s),
		INTENT_GIFT_SLOT: _row(config.flood_gift_slot_burst, config.flood_gift_slot_refill_per_s),
		INTENT_SET_READY: _row(config.flood_set_ready_burst, config.flood_set_ready_refill_per_s),
		INTENT_LOADING_READY: _row(config.flood_loading_ready_burst, config.flood_loading_ready_refill_per_s),
		INTENT_REPLAY_REQUEST: _row(config.flood_replay_request_burst, config.flood_replay_request_refill_per_s),
		INTENT_RETURN_LOBBY: _row(config.flood_return_lobby_burst, config.flood_return_lobby_refill_per_s),
		INTENT_REPLAY_ACK: _row(config.flood_replay_ack_burst, config.flood_replay_ack_refill_per_s),
		INTENT_PONG: _row(config.flood_pong_burst, config.flood_pong_refill_per_s),
		INTENT_HANDSHAKE: _row(config.flood_handshake_burst, config.flood_handshake_refill_per_s),
	}


static func _row(burst: int, refill_per_s: float) -> Vector2:
	return Vector2(float(burst), refill_per_s)
