extends GutTest
## Bontago-1pi.85.57: the shared PulseRing and the ring under a landed gift crate.


func _crate() -> GiftCrate:
	var crate: GiftCrate = GiftCrate.new()
	add_child_autofree(crate)
	return crate


func _ring(crate: GiftCrate) -> PulseRing:
	return crate.get_node_or_null(^"LandRing") as PulseRing


func test_landed_crate_has_a_visible_ring() -> void:
	var crate: GiftCrate = _crate()
	assert_not_null(_ring(crate))
	assert_true(_ring(crate).visible, "a crate nothing told to fall lies on the disc")


func test_ring_hidden_while_falling_and_attached_on_land() -> void:
	var crate: GiftCrate = _crate()
	crate.set_falling(true)
	assert_false(_ring(crate).visible, "no ring while descending")
	crate.set_falling(false)
	assert_true(_ring(crate).visible, "ring appears on land")


func test_ring_removed_on_claim_and_with_the_crate() -> void:
	var crate: GiftCrate = _crate()
	crate.gift_id = 7
	Events.gift_claimed.emit(7, 0, &"bomb")
	assert_false(_ring(crate).visible, "claimed: ring gone")
	crate.set_falling(false)
	assert_false(_ring(crate).visible, "a claimed crate never shows it again")
	var other: GiftCrate = _crate()
	other.gift_id = 8
	var ring: PulseRing = _ring(other)
	other.free()
	assert_false(is_instance_valid(ring), "expiry/destroy frees the ring with the crate")


func test_ring_pulses_and_follows_tuning() -> void:
	var crate: GiftCrate = _crate()
	var ring: PulseRing = _ring(crate)
	var tuning: GiftRingTuning = crate.ring_tuning
	assert_gt(tuning.pulse_period_s, 0.0)
	crate._process(tuning.pulse_period_s * 0.25)
	assert_almost_eq(ring.scale.x, 1.0 + tuning.pulse_scale_amplitude, 0.001, "peak of the wave")
	assert_almost_eq(ring.emission_energy(), tuning.emission * (1.0 + tuning.pulse_emission_amplitude), 0.001)


func test_wave_is_zero_without_a_period() -> void:
	assert_eq(PulseRing.wave_at(1.0, 0.0), 0.0)
	assert_almost_eq(PulseRing.wave_at(0.25, 1.0), 1.0, 0.0001)


func test_home_flag_beacon_ring_is_the_shared_component() -> void:
	var flag: HomeFlag = HomeFlag.new()
	add_child_autofree(flag)
	assert_true(flag.get_node(^"Ring") is PulseRing)
