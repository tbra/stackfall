class_name MatchWireEvents
extends RefCounted
## Names of the match-flow events mirrored over net_match_event (StringNames, so a packet
## capture reads as itself), and the argument shape of each.

const STATE_CHANGED: StringName = &"state_changed"
const COUNTDOWN: StringName = &"countdown"
const TURN_CHANGED: StringName = &"turn_changed"
const FEED_ISSUED: StringName = &"feed_issued"
const FEED_EXPIRED: StringName = &"feed_expired"
const QOL_FEED: StringName = &"qol_feed"
const GIFT_SLOT: StringName = &"gift_slot"
const PLACEMENT_REJECTED: StringName = &"placement_rejected"
const PLACEMENT_RELOCATED: StringName = &"placement_relocated"
const PLAYER_ELIMINATED: StringName = &"player_eliminated"
const MATCH_WON: StringName = &"match_won"
const MODE_STATE: StringName = &"mode_state"
const MATCH_RESULTS: StringName = &"match_results"
const GIFT_FLIGHT: StringName = &"gift_flight_spawned"
const GIFT_LANDED: StringName = &"gift_landed"
const GIFT_SPAWNED: StringName = &"gift_spawned"
const GIFT_CLAIMED: StringName = &"gift_claimed"
const GIFT_EXPIRED: StringName = &"gift_expired"
const SPECIAL_TRIGGERED: StringName = &"special_triggered"
const SPECIAL_CONSUMED: StringName = &"special_consumed"
const GLUE_CHARGES: StringName = &"glue_charges_changed"
const BLOCK_GLUED: StringName = &"block_glued_changed"
const BLOCK_OWNER_CHANGED: StringName = &"block_owner_changed"
const BLOCK_FROZEN: StringName = &"block_frozen_changed"
const CAT_STARTED: StringName = &"cat_started"
const CAT_ENDED: StringName = &"cat_ended"
const BLOCK_DISSOLVE_STARTED: StringName = &"block_dissolve_started"
const SLOT_REPLAY: StringName = &"slot_replay"
const MATCH_CLOCK: StringName = &"match_clock"
const LOADING_GATE: StringName = &"loading_gate"
const LIVE_SCORES: StringName = &"live_scores"


const _V3: int = TYPE_VECTOR3
const _V2: int = TYPE_VECTOR2
const _SN: int = TYPE_STRING_NAME
const _I: int = TYPE_INT
const _F: int = TYPE_FLOAT
const _B: int = TYPE_BOOL
const _D: int = TYPE_DICTIONARY

## Event name -> one Variant.Type per argument, exactly the payload the host sends (a short or
## long args array is refused, never defaulted). See WireLimits.args_shape_ok for the leniencies.
const _SHAPES: Dictionary = {
	STATE_CHANGED: [_I],
	COUNTDOWN: [_I],
	TURN_CHANGED: [_I],
	FEED_ISSUED: [_I, _SN, _SN, _I, _F, _B],
	FEED_EXPIRED: [_I],
	QOL_FEED: [_I, _I, _B],
	GIFT_SLOT: [_I, TYPE_ARRAY, _SN, _SN],
	PLACEMENT_REJECTED: [_I, _SN],
	PLACEMENT_RELOCATED: [_I, _V2],
	PLAYER_ELIMINATED: [_I, _I, _I],
	MATCH_WON: [_I],
	MODE_STATE: [_D],
	MATCH_RESULTS: [_D],
	GIFT_FLIGHT: [_I, _V3, _V3],
	GIFT_LANDED: [_I, _V3],
	GIFT_SPAWNED: [_I, _V2],
	GIFT_CLAIMED: [_I, _I, _SN, _SN],
	GIFT_EXPIRED: [_I],
	SPECIAL_TRIGGERED: [_I, _SN, _V3, _I],
	SPECIAL_CONSUMED: [_I, _SN],
	GLUE_CHARGES: [_I, _I, _I],
	BLOCK_GLUED: [_I, _B],
	BLOCK_OWNER_CHANGED: [_I, _I],
	BLOCK_FROZEN: [_I, _B],
	CAT_STARTED: [_I, _I, _V3, _F],
	CAT_ENDED: [_I],
	BLOCK_DISSOLVE_STARTED: [_I],
	SLOT_REPLAY: [_I, _SN, _SN, _I, _F, _B, _SN, _SN, _SN, _SN],
	MATCH_CLOCK: [_F],
	LOADING_GATE: [TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT32_ARRAY, _B],
	LIVE_SCORES: [_D],
}


## Argument shape of `event` (one typeof per arg); an empty array means unknown event.
static func shape_of(event: StringName) -> Array:
	return (_SHAPES.get(event, []) as Array).duplicate()

