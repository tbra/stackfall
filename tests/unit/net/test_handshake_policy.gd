extends GutTest
## core/net/HandshakePolicy.gd (the pure join decision, in the order the old
## Net._rpc_handshake checked) and NetRoster.handle_handshake (raw-length caps, then
## the per-sender HANDSHAKE bucket, then the policy). No sockets, synthetic clock.

const HOST_BUILD: String = "1.2.3"
const MAX_BUILD_LEN: int = 16
const MAX_NAME_LEN: int = 24
const MAX_TOKEN_LEN: int = 8
const SENDER: int = 77
const TOKEN: String = "tok"
const DROPPED_SLOT: int = 2
const FREE_ROOM: int = 4
const OPEN_SEAT: int = 3

var _can_reclaim_calls: int = 0
var _pick_calls: int = 0
var _reclaim_ok: bool = true
var _seat: int = OPEN_SEAT


func before_each() -> void:
	_can_reclaim_calls = 0
	_pick_calls = 0
	_reclaim_ok = true
	_seat = OPEN_SEAT


func _can_reclaim(_slot_id: int) -> bool:
	_can_reclaim_calls += 1
	return _reclaim_ok


func _pick() -> int:
	_pick_calls += 1
	return _seat


func _state(overrides: Dictionary = {}) -> Dictionary:
	var state: Dictionary = {
		"is_host": true,
		"host_build": HOST_BUILD,
		"joins_open": true,
		"match_in_progress": false,
		"free_capacity": FREE_ROOM,
		"reservations": {},
		"held_slots": {0: true, 1: true},
		"can_reclaim_seat": Callable(self, &"_can_reclaim"),
		"pick_open_seat": Callable(self, &"_pick"),
		"max_build_len": MAX_BUILD_LEN,
		"max_name_len": MAX_NAME_LEN,
		"max_token_len": MAX_TOKEN_LEN,
	}
	state.merge(overrides, true)
	return state


func _request(overrides: Dictionary = {}) -> Dictionary:
	var request: Dictionary = {
		"sender": SENDER, "build": HOST_BUILD, "name": "Pat", "token": "", "already_seated": false,
	}
	request.merge(overrides, true)
	return request


# --- The policy table ------------------------------------------------------------

func test_error_codes_match_the_net_join_error_enum() -> void:
	assert_eq(HandshakePolicy.ERROR_VERSION_MISMATCH, Net.JoinError.VERSION_MISMATCH)
	assert_eq(HandshakePolicy.ERROR_SERVER_FULL, Net.JoinError.SERVER_FULL)
	assert_eq(HandshakePolicy.ERROR_MATCH_IN_PROGRESS, Net.JoinError.MATCH_IN_PROGRESS)


func test_not_host_drops() -> void:
	var decision: HandshakePolicy.Decision = HandshakePolicy.decide(_request(), _state({"is_host": false}))
	assert_eq(decision.kind, HandshakePolicy.Decision.Kind.DROP)
	assert_eq(decision.drop_reason, HandshakePolicy.DROP_NOT_HOST)


func test_duplicate_sender_drops_before_the_version_check() -> void:
	var decision: HandshakePolicy.Decision = HandshakePolicy.decide(
		_request({"already_seated": true, "build": "other"}), _state()
	)
	assert_eq(decision.kind, HandshakePolicy.Decision.Kind.DROP, "a seated peer's second handshake is ignored, not refused")
	assert_eq(decision.drop_reason, HandshakePolicy.DROP_DUPLICATE)


func test_version_mismatch_refuses_with_the_version_error() -> void:
	var decision: HandshakePolicy.Decision = HandshakePolicy.decide(_request({"build": "0.0.1"}), _state())
	assert_eq(decision.kind, HandshakePolicy.Decision.Kind.REFUSE)
	assert_eq(decision.error, HandshakePolicy.ERROR_VERSION_MISMATCH)


func test_version_is_checked_before_joins_open_and_capacity() -> void:
	var decision: HandshakePolicy.Decision = HandshakePolicy.decide(
		_request({"build": "other"}), _state({"joins_open": false, "free_capacity": 0})
	)
	assert_eq(decision.error, HandshakePolicy.ERROR_VERSION_MISMATCH)


func test_lobby_join_closed_refuses_match_in_progress() -> void:
	var decision: HandshakePolicy.Decision = HandshakePolicy.decide(_request(), _state({"joins_open": false}))
	assert_eq(decision.kind, HandshakePolicy.Decision.Kind.REFUSE)
	assert_eq(decision.error, HandshakePolicy.ERROR_MATCH_IN_PROGRESS)


func test_closed_wins_over_full_so_a_late_joiner_learns_the_real_reason() -> void:
	var decision: HandshakePolicy.Decision = HandshakePolicy.decide(
		_request(), _state({"joins_open": false, "free_capacity": 0})
	)
	assert_eq(decision.error, HandshakePolicy.ERROR_MATCH_IN_PROGRESS)


func test_full_lobby_refuses_server_full() -> void:
	var decision: HandshakePolicy.Decision = HandshakePolicy.decide(_request(), _state({"free_capacity": 0}))
	assert_eq(decision.kind, HandshakePolicy.Decision.Kind.REFUSE)
	assert_eq(decision.error, HandshakePolicy.ERROR_SERVER_FULL)


func test_lobby_accept_takes_the_lowest_free_slot() -> void:
	var decision: HandshakePolicy.Decision = HandshakePolicy.decide(
		_request(), _state({"held_slots": {0: true, 2: true}})
	)
	assert_eq(decision.kind, HandshakePolicy.Decision.Kind.ACCEPT)
	assert_eq(decision.slot_id, 1, "the hole below the top is filled first")
	var reserved: HandshakePolicy.Decision = HandshakePolicy.decide(
		_request(), _state({"held_slots": {0: true, 2: true}, "reservations": {"t": 1}})
	)
	assert_eq(reserved.slot_id, 3, "a reserved slot is not free")
	assert_eq(_pick_calls, 0, "the seat policy is a mid-match question only")


func test_mid_match_reclaim_returns_the_reserved_slot() -> void:
	var decision: HandshakePolicy.Decision = HandshakePolicy.decide(
		_request({"token": TOKEN}),
		_state({"match_in_progress": true, "reservations": {TOKEN: DROPPED_SLOT}})
	)
	assert_eq(decision.kind, HandshakePolicy.Decision.Kind.RECLAIM)
	assert_eq(decision.slot_id, DROPPED_SLOT)
	assert_eq(_pick_calls, 0)


func test_mid_match_reclaim_skips_joins_open_and_capacity() -> void:
	var decision: HandshakePolicy.Decision = HandshakePolicy.decide(
		_request({"token": TOKEN}),
		_state({"match_in_progress": true, "joins_open": false, "free_capacity": 0, "reservations": {TOKEN: DROPPED_SLOT}})
	)
	assert_eq(decision.kind, HandshakePolicy.Decision.Kind.RECLAIM, "its own departure freed the room")


func test_mid_match_reclaim_refused_by_the_seat_policy_falls_through_to_a_late_join() -> void:
	_reclaim_ok = false
	var decision: HandshakePolicy.Decision = HandshakePolicy.decide(
		_request({"token": TOKEN}),
		_state({"match_in_progress": true, "reservations": {TOKEN: DROPPED_SLOT}})
	)
	assert_eq(_can_reclaim_calls, 1)
	assert_eq(decision.kind, HandshakePolicy.Decision.Kind.ACCEPT, "a lapsed grace is a brand-new late joiner")
	assert_eq(decision.slot_id, OPEN_SEAT)


func test_mid_match_reclaim_of_a_slot_a_live_peer_holds_is_not_given_back() -> void:
	var decision: HandshakePolicy.Decision = HandshakePolicy.decide(
		_request({"token": TOKEN}),
		_state({"match_in_progress": true, "reservations": {TOKEN: 1}})
	)
	assert_ne(decision.kind, HandshakePolicy.Decision.Kind.RECLAIM)
	assert_eq(_can_reclaim_calls, 0)


func test_mid_match_reclaim_needs_a_known_token_and_an_installed_policy() -> void:
	var unknown: HandshakePolicy.Decision = HandshakePolicy.decide(
		_request({"token": "nope"}), _state({"match_in_progress": true, "reservations": {TOKEN: DROPPED_SLOT}})
	)
	assert_ne(unknown.kind, HandshakePolicy.Decision.Kind.RECLAIM)
	var no_policy: HandshakePolicy.Decision = HandshakePolicy.decide(
		_request({"token": TOKEN}),
		_state({"match_in_progress": true, "reservations": {TOKEN: DROPPED_SLOT}, "can_reclaim_seat": Callable()})
	)
	assert_ne(no_policy.kind, HandshakePolicy.Decision.Kind.RECLAIM)


func test_mid_match_new_joiner_closed_or_full_is_refused() -> void:
	var closed: HandshakePolicy.Decision = HandshakePolicy.decide(
		_request(), _state({"match_in_progress": true, "joins_open": false})
	)
	assert_eq(closed.error, HandshakePolicy.ERROR_MATCH_IN_PROGRESS)
	var full: HandshakePolicy.Decision = HandshakePolicy.decide(
		_request(), _state({"match_in_progress": true, "free_capacity": 0})
	)
	assert_eq(full.error, HandshakePolicy.ERROR_SERVER_FULL, "spectators count against the connection budget")


func test_mid_match_new_joiner_takes_the_open_seat_or_spectates() -> void:
	var seated: HandshakePolicy.Decision = HandshakePolicy.decide(_request(), _state({"match_in_progress": true}))
	assert_eq(seated.kind, HandshakePolicy.Decision.Kind.ACCEPT)
	assert_eq(seated.slot_id, OPEN_SEAT)
	_seat = -1
	var spectator: HandshakePolicy.Decision = HandshakePolicy.decide(_request(), _state({"match_in_progress": true}))
	assert_eq(spectator.slot_id, -1)
	var no_policy: HandshakePolicy.Decision = HandshakePolicy.decide(
		_request(), _state({"match_in_progress": true, "pick_open_seat": Callable()})
	)
	assert_eq(no_policy.slot_id, -1, "no seat policy: every late joiner spectates")


func test_mid_match_never_hands_out_a_held_or_reserved_seat() -> void:
	_seat = 1
	var held: HandshakePolicy.Decision = HandshakePolicy.decide(_request(), _state({"match_in_progress": true}))
	assert_eq(held.slot_id, -1, "a seat a live peer holds")
	_seat = DROPPED_SLOT
	var reserved: HandshakePolicy.Decision = HandshakePolicy.decide(
		_request(), _state({"match_in_progress": true, "reservations": {"someone": DROPPED_SLOT}})
	)
	assert_eq(reserved.slot_id, -1, "a seat a departed peer reserved")


func test_oversize_strings_drop_without_a_reply() -> void:
	var fields: Dictionary = {
		"build": "b".repeat(MAX_BUILD_LEN + 1),
		"name": "n".repeat(MAX_NAME_LEN + 1),
		"token": "t".repeat(MAX_TOKEN_LEN + 1),
	}
	for field: String in fields.keys():
		var decision: HandshakePolicy.Decision = HandshakePolicy.decide(_request({field: fields[field]}), _state())
		assert_eq(decision.kind, HandshakePolicy.Decision.Kind.DROP, "%s over its cap" % field)
		assert_eq(decision.drop_reason, HandshakePolicy.DROP_OVERSIZE, field)


func test_strings_at_the_cap_pass() -> void:
	var decision: HandshakePolicy.Decision = HandshakePolicy.decide(
		_request({"name": "n".repeat(MAX_NAME_LEN), "token": "t".repeat(MAX_TOKEN_LEN)}), _state()
	)
	assert_eq(decision.kind, HandshakePolicy.Decision.Kind.ACCEPT)


func test_oversize_build_is_dropped_not_a_version_mismatch() -> void:
	var decision: HandshakePolicy.Decision = HandshakePolicy.decide(
		_request({"build": "x".repeat(MAX_BUILD_LEN * 4)}), _state()
	)
	assert_eq(decision.kind, HandshakePolicy.Decision.Kind.DROP)


# --- NetRoster.handle_handshake: caps, then the HANDSHAKE bucket, then the policy ---

func _roster() -> NetRoster:
	var config: NetConfig = NetConfig.new()
	config.sanitize()
	var roster: NetRoster = NetRoster.new(config)
	roster.add_host("Hostie", HOST_BUILD, true)
	return roster


func _burst(roster: NetRoster) -> int:
	return roster.config.flood_handshake_burst


func test_roster_seats_an_honest_handshake() -> void:
	var roster: NetRoster = _roster()
	var decision: HandshakePolicy.Decision = roster.handle_handshake(SENDER, HOST_BUILD, "Pat", "", 0.0)
	assert_eq(decision.kind, HandshakePolicy.Decision.Kind.ACCEPT)
	assert_eq(decision.slot_id, 1)


func test_roster_stores_a_raw_control_and_bidi_name_cleaned() -> void:
	# A tampered client skips the cleaning join_game() does: the host's own check is what stores the name.
	var roster: NetRoster = _roster()
	var raw: String = "\u202e  Mal\tlory\n\u200b"
	var decision: HandshakePolicy.Decision = roster.handle_handshake(SENDER, HOST_BUILD, raw, "", 0.0)
	assert_eq(decision.kind, HandshakePolicy.Decision.Kind.ACCEPT, "control characters alone are not a refusal")
	roster.accept(SENDER, HOST_BUILD, raw, decision.slot_id)
	assert_eq(roster.peer_info(SENDER)["name"], "Mallory", "trimmed, control and bidi characters stripped")
	assert_eq(roster.peer_info(SENDER)["name"], PlayerNames.clean(raw, roster.config.max_player_name_length))


func test_roster_seats_a_name_of_only_control_characters_as_player_n() -> void:
	var roster: NetRoster = _roster()
	var raw: String = "\u202e\t\u200b\n"
	var decision: HandshakePolicy.Decision = roster.handle_handshake(SENDER, HOST_BUILD, raw, "", 0.0)
	roster.accept(SENDER, HOST_BUILD, raw, decision.slot_id)
	assert_eq(roster.peer_info(SENDER)["name"], PlayerNames.fallback_for_slot(decision.slot_id))
	assert_true(roster.peer_info(SENDER)["name_auto"], "the host's Player N, not a typed name")


func test_roster_default_name_cap_admits_the_longest_cleaned_name() -> void:
	var roster: NetRoster = _roster()
	var longest: String = "n".repeat(roster.config.max_player_name_length)
	var decision: HandshakePolicy.Decision = roster.handle_handshake(SENDER, HOST_BUILD, longest, "", 0.0)
	assert_eq(decision.kind, HandshakePolicy.Decision.Kind.ACCEPT)


func test_roster_drops_an_oversize_name_without_charging_the_bucket() -> void:
	var roster: NetRoster = _roster()
	var oversize: String = "n".repeat(roster.config.handshake_name_max_length + 1)
	for _i: int in range(_burst(roster) * 3):
		var decision: HandshakePolicy.Decision = roster.handle_handshake(SENDER, HOST_BUILD, oversize, "", 0.0)
		assert_eq(decision.drop_reason, HandshakePolicy.DROP_OVERSIZE)
	var honest: HandshakePolicy.Decision = roster.handle_handshake(SENDER, HOST_BUILD, "Pat", "", 0.0)
	assert_eq(honest.kind, HandshakePolicy.Decision.Kind.ACCEPT, "the bucket is still full")


func test_roster_handshake_flood_is_a_silent_drop_after_burst() -> void:
	var roster: NetRoster = _roster()
	var burst: int = _burst(roster)
	var drops: int = 0
	var passed: int = 0
	for _i: int in range(burst * 3):
		var decision: HandshakePolicy.Decision = roster.handle_handshake(SENDER, "wrong", "Pat", "", 0.0)
		if decision.kind == HandshakePolicy.Decision.Kind.DROP:
			assert_eq(decision.drop_reason, HandshakePolicy.DROP_FLOOD)
			drops += 1
		else:
			assert_eq(decision.kind, HandshakePolicy.Decision.Kind.REFUSE)
			passed += 1
	assert_eq(passed, burst, "exactly the burst reaches the policy")
	assert_eq(drops, burst * 2)


func test_roster_handshake_bucket_is_per_sender_and_refills() -> void:
	var roster: NetRoster = _roster()
	var burst: int = _burst(roster)
	for _i: int in range(burst + 1):
		roster.handle_handshake(SENDER, "wrong", "Pat", "", 0.0)
	var other: HandshakePolicy.Decision = roster.handle_handshake(SENDER + 1, "wrong", "Pat", "", 0.0)
	assert_eq(other.kind, HandshakePolicy.Decision.Kind.REFUSE, "another sender is unaffected")
	var refill_s: float = 1.0 / roster.config.flood_handshake_refill_per_s
	var later: HandshakePolicy.Decision = roster.handle_handshake(SENDER, "wrong", "Pat", "", refill_s + 0.01)
	assert_eq(later.kind, HandshakePolicy.Decision.Kind.REFUSE, "one token back after 1/refill seconds")


func test_roster_forget_flood_gives_a_rejoin_a_full_bucket() -> void:
	var roster: NetRoster = _roster()
	for _i: int in range(_burst(roster) + 2):
		roster.handle_handshake(SENDER, "wrong", "Pat", "", 0.0)
	assert_eq(roster.handle_handshake(SENDER, "wrong", "Pat", "", 0.0).kind, HandshakePolicy.Decision.Kind.DROP)
	roster.forget_flood(SENDER)
	assert_eq(roster.handle_handshake(SENDER, "wrong", "Pat", "", 0.0).kind, HandshakePolicy.Decision.Kind.REFUSE)


func test_roster_not_hosting_drops_everything() -> void:
	var roster: NetRoster = NetRoster.new(NetConfig.new())
	var decision: HandshakePolicy.Decision = roster.handle_handshake(SENDER, HOST_BUILD, "Pat", "", 0.0)
	assert_eq(decision.drop_reason, HandshakePolicy.DROP_NOT_HOST)


func test_roster_duplicate_sender_is_dropped() -> void:
	var roster: NetRoster = _roster()
	roster.accept(SENDER, HOST_BUILD, "Pat", 1)
	var decision: HandshakePolicy.Decision = roster.handle_handshake(SENDER, HOST_BUILD, "Pat", "", 0.0)
	assert_eq(decision.drop_reason, HandshakePolicy.DROP_DUPLICATE)
