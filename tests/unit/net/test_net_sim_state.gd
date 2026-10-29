extends GutTest
## The live simulator state is readable: NetSim.lag_ms()/loss() and
## Net.simulated_lag_ms()/simulated_loss() report what was configured.

const LAG_MS: float = 100.0
const LOSS: float = 0.02
const OTHER_LAG_MS: float = 40.0
const JITTER_MS: float = 15.0
const TOLERANCE: float = 0.0001


func after_each() -> void:
	Net.set_simulation(0.0, 0.0, 0.0)


func test_a_new_sim_reports_its_constructor_values() -> void:
	var sim: NetSim = NetSim.new(LAG_MS, JITTER_MS, LOSS, 1)
	assert_eq(sim.lag_ms(), LAG_MS)
	assert_almost_eq(sim.loss(), LOSS, TOLERANCE)


func test_a_default_sim_reports_zero() -> void:
	var sim: NetSim = NetSim.new()
	assert_eq(sim.lag_ms(), 0.0)
	assert_eq(sim.loss(), 0.0)


func test_configure_is_read_back() -> void:
	var sim: NetSim = NetSim.new()
	sim.configure(LAG_MS, 0.0, LOSS)
	assert_eq(sim.lag_ms(), LAG_MS)
	assert_almost_eq(sim.loss(), LOSS, TOLERANCE)
	sim.configure(OTHER_LAG_MS, 0.0, 0.0)
	assert_eq(sim.lag_ms(), OTHER_LAG_MS)
	assert_eq(sim.loss(), 0.0)


func test_reported_values_are_the_clamped_ones() -> void:
	var sim: NetSim = NetSim.new()
	sim.configure(-5.0, 0.0, 3.0)
	assert_eq(sim.lag_ms(), 0.0, "negative lag clamps to zero")
	assert_eq(sim.loss(), 1.0, "loss above 1 clamps to 1")
	sim.configure(LAG_MS, 0.0, -0.5)
	assert_eq(sim.loss(), 0.0, "negative loss clamps to zero")


func test_the_state_agrees_with_is_idle() -> void:
	var sim: NetSim = NetSim.new()
	assert_true(sim.is_idle())
	assert_eq(sim.lag_ms(), 0.0)
	sim.configure(LAG_MS, 0.0, 0.0)
	assert_false(sim.is_idle())
	assert_eq(sim.lag_ms(), LAG_MS)


func test_net_reports_the_simulation_it_was_given() -> void:
	Net.set_simulation(LAG_MS, 0.0, LOSS)
	assert_eq(Net.simulated_lag_ms(), LAG_MS)
	assert_almost_eq(Net.simulated_loss(), LOSS, TOLERANCE)


func test_net_reports_zero_after_the_simulation_is_cleared() -> void:
	Net.set_simulation(LAG_MS, 0.0, LOSS)
	Net.set_simulation(0.0, 0.0, 0.0)
	assert_eq(Net.simulated_lag_ms(), 0.0)
	assert_eq(Net.simulated_loss(), 0.0)
