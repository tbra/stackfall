extends GutTest
## net/match/GiftWireGuard.gd: the client's gift wire state. Every transition and refusal of the
## check-and-mark calls, the field edge of note_spawn, the special-id check and the state kept
## across a rebind, asserted through the guard's public calls only.

const FIELD_RADIUS: float = 20.0
const GIFT: int = 5
const INSIDE: Vector2 = Vector2(3.0, 4.0)

var _guard: GiftWireGuard
var _host: FieldHost
var _config: NetConfig


## FakeHostPort answering the one read the guard makes: the running match's field radius.
class FieldHost extends FakeHostPort:
	var running: MatchConfig = null

	func config() -> MatchConfig:
		return running


func _config_with_radius(radius: float) -> MatchConfig:
	var map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	map.field_radius = radius
	var match_config: TinyMapMatchConfig = TinyMapMatchConfig.new()
	match_config.set_tiny_map(map)
	return match_config


func before_each() -> void:
	_host = FieldHost.new()
	_host.running = _config_with_radius(FIELD_RADIUS)
	_config = load("res://config/net/net_config.tres") as NetConfig
	_guard = GiftWireGuard.new()
	_guard.bind(_host, _config)


# --- flight ---------------------------------------------------------------------------------


func test_a_new_gift_may_begin_flight_once() -> void:
	assert_true(_guard.begin_flight(GIFT))
	assert_false(_guard.begin_flight(GIFT), "a replay of the same flight is refused")


func test_flight_is_refused_after_landing_and_after_removal() -> void:
	assert_true(_guard.begin_flight(GIFT))
	assert_true(_guard.land(GIFT))
	assert_false(_guard.begin_flight(GIFT), "landed")
	assert_true(_guard.begin_flight(GIFT + 1))
	assert_true(_guard.remove(GIFT + 1))
	assert_false(_guard.begin_flight(GIFT + 1), "removed")


func test_flight_after_a_spawn_notice_is_allowed() -> void:
	assert_true(_guard.note_spawn(GIFT, INSIDE))
	assert_true(_guard.begin_flight(GIFT), "a spawn-only gift may start falling")
	assert_false(_guard.begin_flight(GIFT))


# --- landing --------------------------------------------------------------------------------


func test_landing_needs_a_falling_gift() -> void:
	assert_false(_guard.land(GIFT), "unknown gift")
	assert_true(_guard.note_spawn(GIFT, INSIDE))
	assert_false(_guard.land(GIFT), "spawn-only gift")
	assert_true(_guard.begin_flight(GIFT))
	assert_true(_guard.land(GIFT))
	assert_false(_guard.land(GIFT), "already landed")


func test_a_refused_landing_leaves_the_gift_able_to_fall_and_land() -> void:
	assert_false(_guard.land(GIFT))
	assert_true(_guard.begin_flight(GIFT), "the refused landing marked nothing")
	assert_true(_guard.land(GIFT))


func test_a_removed_gift_cannot_land() -> void:
	assert_true(_guard.begin_flight(GIFT))
	assert_true(_guard.remove(GIFT))
	assert_false(_guard.land(GIFT))


# --- spawn notice ---------------------------------------------------------------------------


func test_a_spawn_notice_is_accepted_once() -> void:
	assert_true(_guard.note_spawn(GIFT, INSIDE))
	assert_false(_guard.note_spawn(GIFT, INSIDE), "already notified")
	assert_false(_guard.note_spawn(GIFT, Vector2.ZERO), "also refused at another position")


func test_a_spawn_notice_after_landing_or_removal_is_refused() -> void:
	assert_true(_guard.begin_flight(GIFT + 1))
	assert_true(_guard.land(GIFT + 1))
	assert_false(_guard.note_spawn(GIFT + 1, INSIDE), "landed")
	assert_true(_guard.begin_flight(GIFT + 2))
	assert_true(_guard.remove(GIFT + 2))
	assert_false(_guard.note_spawn(GIFT + 2, INSIDE), "removed")


func test_a_spawn_notice_for_a_falling_gift_not_yet_notified_is_accepted() -> void:
	assert_true(_guard.begin_flight(GIFT))
	assert_true(_guard.note_spawn(GIFT, INSIDE))
	assert_false(_guard.note_spawn(GIFT, INSIDE))


func test_the_field_edge_is_inclusive_up_to_one_hundredth() -> void:
	assert_true(_guard.note_spawn(1, Vector2(FIELD_RADIUS, 0.0)), "on the rim")
	assert_true(_guard.note_spawn(2, Vector2(0.0, -(FIELD_RADIUS + 0.005))), "within the 0.01 tolerance")
	assert_false(_guard.note_spawn(3, Vector2(FIELD_RADIUS + 0.02, 0.0)), "past the tolerance")
	assert_false(_guard.note_spawn(4, Vector2(FIELD_RADIUS, FIELD_RADIUS)), "a corner outside the disc")


func test_a_refused_position_does_not_mark_the_gift() -> void:
	assert_false(_guard.note_spawn(GIFT, Vector2(FIELD_RADIUS * 2.0, 0.0)))
	assert_true(_guard.note_spawn(GIFT, INSIDE), "a good notice afterwards is still accepted")


func test_a_non_finite_position_is_refused() -> void:
	assert_false(_guard.note_spawn(GIFT, Vector2(NAN, 0.0)))
	assert_false(_guard.note_spawn(GIFT, Vector2(0.0, NAN)))
	assert_false(_guard.note_spawn(GIFT, Vector2(INF, 0.0)))
	assert_false(_guard.note_spawn(GIFT, Vector2(0.0, -INF)))
	assert_true(_guard.note_spawn(GIFT, INSIDE), "nothing was marked")


func test_a_negative_id_spawn_notice_is_refused() -> void:
	assert_false(_guard.note_spawn(-1, INSIDE))


func test_a_spawn_notice_without_a_running_match_is_refused() -> void:
	_host.running = null
	assert_false(_guard.note_spawn(GIFT, INSIDE))


# --- removal --------------------------------------------------------------------------------


func test_removal_is_accepted_once_for_any_non_negative_id() -> void:
	assert_true(_guard.remove(GIFT), "an unknown gift may still be removed")
	assert_false(_guard.remove(GIFT), "already removed")
	assert_true(_guard.remove(0), "zero is a valid id")


func test_a_negative_id_removal_is_refused_every_time() -> void:
	assert_false(_guard.remove(-1))
	assert_false(_guard.remove(-1), "it was never marked")


func test_removal_is_accepted_from_every_live_phase() -> void:
	assert_true(_guard.note_spawn(1, INSIDE))
	assert_true(_guard.remove(1), "spawn-only")
	assert_true(_guard.begin_flight(2))
	assert_true(_guard.remove(2), "falling")
	assert_true(_guard.begin_flight(3))
	assert_true(_guard.land(3))
	assert_true(_guard.remove(3), "landed")


func test_gifts_are_tracked_independently() -> void:
	assert_true(_guard.begin_flight(1))
	assert_true(_guard.remove(2))
	assert_true(_guard.land(1), "gift 2 being removed did not touch gift 1")
	assert_true(_guard.begin_flight(3))


# --- reset and rebind -----------------------------------------------------------------------


func test_reset_forgets_every_gift() -> void:
	assert_true(_guard.begin_flight(1))
	assert_true(_guard.land(1))
	assert_true(_guard.note_spawn(2, INSIDE))
	assert_true(_guard.remove(3))
	_guard.reset()
	assert_true(_guard.begin_flight(1), "a landed gift is new again")
	assert_true(_guard.note_spawn(2, INSIDE), "the notified flag is cleared")
	assert_true(_guard.remove(3), "a removed gift is new again")


func test_a_rebind_keeps_the_phase_and_notified_state() -> void:
	assert_true(_guard.begin_flight(1))
	assert_true(_guard.note_spawn(2, INSIDE))
	assert_true(_guard.remove(3))
	var other: FieldHost = FieldHost.new()
	other.running = _host.running
	_guard.bind(other, _config)
	assert_false(_guard.begin_flight(1), "still falling")
	assert_true(_guard.land(1))
	assert_false(_guard.note_spawn(2, INSIDE), "still notified")
	assert_false(_guard.remove(3), "still removed")


func test_a_rebind_reads_the_new_hosts_field() -> void:
	var other: FieldHost = FieldHost.new()
	other.running = _config_with_radius(2.0)
	_guard.bind(other, _config)
	assert_false(_guard.note_spawn(GIFT, Vector2(5.0, 0.0)), "outside the new, smaller field")
	assert_true(_guard.note_spawn(GIFT, Vector2(1.0, 0.0)))


# --- special ids ----------------------------------------------------------------------------


func test_the_pending_placeholder_and_every_roster_id_are_accepted() -> void:
	assert_true(_guard.special_id_ok(SpecialIds.PENDING))
	var roster: Array[SpecialDef] = SpecialDef.load_all_specials()
	assert_gt(roster.size(), 0)
	for def: SpecialDef in roster:
		assert_true(_guard.special_id_ok(def.id), "%s is a roster member" % def.id)


func test_a_well_formed_id_outside_the_roster_is_refused() -> void:
	assert_false(_guard.special_id_ok(&"not_a_real_special"))


func test_malformed_ids_are_refused() -> void:
	assert_false(_guard.special_id_ok(&""), "empty")
	assert_false(_guard.special_id_ok(&"with space"))
	assert_false(_guard.special_id_ok(&"dash-ed"))
	assert_false(_guard.special_id_ok(&"slash/ed"))
	assert_false(_guard.special_id_ok(&"naïve"), "non-ASCII")


func test_an_over_long_id_is_refused_even_when_it_starts_with_a_roster_member() -> void:
	var roster: Array[SpecialDef] = SpecialDef.load_all_specials()
	var padded: String = String(roster[0].id) + "_".repeat(_config.special_id_max_length)
	assert_false(_guard.special_id_ok(StringName(padded)))
	assert_false(_guard.special_id_ok(StringName("a".repeat(_config.special_id_max_length + 1))))


func test_every_guard_answers_from_the_roster_with_no_state_shared_between_guards() -> void:
	var other: GiftWireGuard = GiftWireGuard.new()
	other.bind(_host, _config)
	var roster: Array[SpecialDef] = SpecialDef.load_all_specials()
	assert_false(other.special_id_ok(&"not_a_real_special"))
	for def: SpecialDef in roster:
		assert_true(other.special_id_ok(def.id), "%s on a second guard" % def.id)
		assert_true(_guard.special_id_ok(def.id), "%s on the first guard" % def.id)
	assert_true(other.special_id_ok(SpecialIds.PENDING))


func test_special_ids_are_still_accepted_after_the_roster_cache_is_released() -> void:
	assert_true(_guard.special_id_ok(SpecialIds.PENDING))
	SpecialDef.release_cache()
	var fresh: GiftWireGuard = GiftWireGuard.new()
	fresh.bind(_host, _config)
	for def: SpecialDef in SpecialDef.load_all_specials():
		assert_true(_guard.special_id_ok(def.id), "%s on the old guard" % def.id)
		assert_true(fresh.special_id_ok(def.id), "%s on a new guard" % def.id)
	assert_false(fresh.special_id_ok(&"not_a_real_special"))
