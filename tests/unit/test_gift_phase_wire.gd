extends GutTest

const MatchNetScript := preload("res://net/MatchNet.gd")

## One numbering for gift phases: MatchGifts owns it, MatchNet.GiftWirePhase aliases it.


func test_wire_enum_matches_match_gifts_numbering() -> void:
	assert_eq(int(MatchNetScript.GiftWirePhase.FALLING), MatchGifts.FALLING)
	assert_eq(int(MatchNetScript.GiftWirePhase.LANDED), MatchGifts.LANDED)
	assert_eq(int(MatchNetScript.GiftWirePhase.LEGACY), MatchGifts.WIRE_LEGACY)
	assert_eq(int(MatchNetScript.GiftWirePhase.REMOVED), MatchGifts.WIRE_REMOVED)


func test_all_phases_distinct_and_valid() -> void:
	var seen: Dictionary = {}
	for phase: int in MatchNetScript.GiftWirePhase.values():
		assert_true(MatchGifts.is_valid_wire_phase(phase))
		assert_false(seen.has(phase))
		seen[phase] = true


func test_out_of_range_phase_rejected() -> void:
	assert_false(MatchGifts.is_valid_wire_phase(-1))
	assert_false(MatchGifts.is_valid_wire_phase(4))
	var net: Node = MatchNetScript.new()
	assert_false(net._set_gift_wire_phase(5, 99))
	assert_false(net._set_gift_wire_phase(5, -1))
	assert_false(net._gift_wire_phases.has(5))
	assert_true(net._set_gift_wire_phase(5, MatchGifts.LANDED))
	net.free()
