class_name MatchWireEvents
extends RefCounted
## Names of the match-flow events mirrored over net_match_event, copied byte-for-byte
## from the EVENT_* consts of net/MatchNet.gd (StringNames, so a packet capture reads as
## itself). Stub: the per-event argument-shape table arrives with the event applier split.

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


## Argument shape of `event` (one typeof per arg); an empty array means unknown event.
static func shape_of(event: StringName) -> Array:
	push_error("MatchWireEvents.shape_of is a stub until M4: %s" % event)
	return []
