extends GutTest
## core/net/NetSim.gd: clock-injected lag/loss determinism (docs/M3a_PLAN.md P1).


func test_is_idle_true_at_zero_lag_and_loss() -> void:
	var sim: NetSim = NetSim.new(0.0, 0.0, 0.0, 1)
	assert_true(sim.is_idle())


func test_is_idle_false_once_lag_or_loss_is_set() -> void:
	assert_false(NetSim.new(100.0, 0.0, 0.0, 1).is_idle())
	assert_false(NetSim.new(0.0, 0.0, 0.02, 1).is_idle())


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


func test_1000_packets_deliver_in_submission_order_none_early() -> void:
	var sim: NetSim = NetSim.new(100.0, 20.0, 0.02, 1234)
	var submitted: Array = []
	for i: int in range(1000):
		if sim.submit(i, 0.0, true):
			submitted.append(i)

	# Drain in small time increments so a packet can never be observed before
	# its own delivery time, and collect everything that arrives.
	var delivered: Array = []
	var t: float = 0.0
	while sim.pending_count() > 0 and t < 5.0:
		delivered.append_array(sim.drain(t))
		t += 0.005

	assert_eq(delivered.size(), submitted.size(), "every kept packet must eventually be delivered")
	assert_eq(delivered, submitted, "delivery order must match submission order, jitter included")


func test_drop_rate_within_one_percent_of_configured_loss() -> void:
	var sim: NetSim = NetSim.new(100.0, 0.0, 0.02, 42)
	for i: int in range(1000):
		sim.submit(i, 0.0, true)
	var rate: float = float(sim.dropped_count()) / float(sim.submitted_count())
	assert_almost_eq(rate, 0.02, 0.01)


func test_reset_clears_queue_and_counters() -> void:
	var sim: NetSim = NetSim.new(50.0, 0.0, 0.0, 1)
	sim.submit("a", 0.0, false)
	sim.reset()
	assert_eq(sim.pending_count(), 0)
	assert_eq(sim.submitted_count(), 0)
	assert_eq(sim.dropped_count(), 0)
	assert_eq(sim.drain(1000.0).size(), 0)


func test_configure_retunes_without_dropping_queued_packets() -> void:
	var sim: NetSim = NetSim.new(100.0, 0.0, 0.0, 1)
	sim.submit("a", 0.0, false)
	sim.configure(0.0, 0.0, 0.0)
	assert_eq(sim.pending_count(), 1, "already-queued packet must survive a re-tune")
	assert_eq(sim.drain(0.1).size(), 1)
