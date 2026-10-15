extends GutTest
## core/net/NetSim.gd: clock-injected lag/loss determinism.


func test_lag_delays_delivery_by_the_right_amount() -> void:
	var sim: NetSim = NetSim.new(100.0, 0.0, 0.0, 1)
	sim.submit("packet", 0.0, false)
	assert_eq(sim.drain(0.0).size(), 0, "must not be deliverable before lag elapses")
	assert_eq(sim.drain(0.0999).size(), 0, "must not be deliverable 0.1 ms early")
	var delivered: Array = sim.drain(0.1)
	assert_eq(delivered.size(), 1)
	assert_eq(delivered[0], "packet")


func test_droppable_false_never_drops_even_at_full_loss() -> void:
	var sim: NetSim = NetSim.new(0.0, 0.0, 1.0, 7)
	for i: int in range(200):
		assert_true(sim.submit("p%d" % i, 0.0, false), "reliable traffic must never be dropped")
	assert_eq(sim.dropped_count(), 0)
	assert_eq(sim.drain(0.0).size(), 200)


func test_drop_rate_within_one_percent_of_configured_loss() -> void:
	var sim: NetSim = NetSim.new(100.0, 0.0, 0.02, 42)
	for i: int in range(1000):
		sim.submit(i, 0.0, true)
	var rate: float = float(sim.dropped_count()) / float(sim.submitted_count())
	assert_almost_eq(rate, 0.02, 0.01)

