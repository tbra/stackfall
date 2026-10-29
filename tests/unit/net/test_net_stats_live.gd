extends GutTest
## NetStatsLive: the adapter that reads Net, SnapshotSync and MatchNet into one
## NetStats. Offline, and hosting over loopback ENet. A client reading needs a
## second process and is covered by the ENet harness, not here.

const LAG_MS: float = 100.0
const LOSS: float = 0.02
const HOST_SLOT: int = 0
const BUSY_SLOT: int = 1
const OTHER_BUSY_SLOT: int = 3
const UNTOUCHED_SLOT: int = 2

var _source: NetStatsLive = null


func before_each() -> void:
	Net.leave()
	MatchNet.reset_counters()
	Net.set_simulation(0.0, 0.0, 0.0)
	_source = NetStatsLive.new()


func after_each() -> void:
	Net.leave()
	MatchNet.reset_counters()
	Net.set_simulation(0.0, 0.0, 0.0)


func _host() -> void:
	assert_eq(Net.host_game(0, "x", false), OK, "fixture: loopback host")


func _row(stats: NetStats, slot_id: int) -> NetStats.IntentRow:
	for row: NetStats.IntentRow in stats.intents:
		if row.slot_id == slot_id:
			return row
	return null


# --- Offline -------------------------------------------------------------------

func test_offline_reads_the_offline_role_with_no_rows() -> void:
	var stats: NetStats = _source.read()
	assert_eq(stats.role, NetStats.Role.OFFLINE)
	assert_eq(stats.peers.size(), 0)
	assert_eq(stats.intents.size(), 0)
	assert_eq(stats.local_slot, 0)


func test_offline_rates_and_snapshot_numbers_are_zero() -> void:
	var stats: NetStats = _source.read()
	assert_eq(stats.snapshot_bytes_per_s, 0.0)
	assert_eq(stats.snapshots_per_s, 0.0)
	assert_eq(stats.last_snapshot_bytes, 0)
	assert_eq(stats.dropped_unknown, 0)
	assert_eq(stats.local_rtt_ms, 0.0)


func test_every_read_is_a_fresh_object() -> void:
	var first: NetStats = _source.read()
	var second: NetStats = _source.read()
	assert_ne(first, second)


func test_the_live_simulation_is_read_back() -> void:
	Net.set_simulation(LAG_MS, 0.0, LOSS)
	var stats: NetStats = _source.read()
	assert_eq(stats.sim_lag_ms, LAG_MS)
	assert_almost_eq(stats.sim_loss, LOSS, 0.0001)


func test_set_simulation_on_the_source_reaches_the_simulator() -> void:
	_source.set_simulation(LAG_MS, LOSS)
	var stats: NetStats = _source.read()
	assert_eq(stats.sim_lag_ms, LAG_MS)
	assert_almost_eq(stats.sim_loss, LOSS, 0.0001)
	assert_eq(float(Net.call(&"simulated_lag_ms")), LAG_MS, "Net itself reports the same state")


func test_set_simulation_to_zero_clears_it() -> void:
	_source.set_simulation(LAG_MS, LOSS)
	_source.set_simulation(0.0, 0.0)
	var stats: NetStats = _source.read()
	assert_eq(stats.sim_lag_ms, 0.0)
	assert_eq(stats.sim_loss, 0.0)


func test_a_simulation_set_on_net_first_is_what_the_source_reads() -> void:
	# The source holds no copy: the live NetSim is the source of truth.
	_source.set_simulation(LAG_MS, LOSS)
	Net.set_simulation(0.0, 0.0, 0.0)
	assert_eq(_source.read().sim_lag_ms, 0.0)


# --- Host over loopback ENet -----------------------------------------------------

func test_a_host_reads_the_host_role_and_slot() -> void:
	_host()
	var stats: NetStats = _source.read()
	assert_eq(stats.role, NetStats.Role.HOST)
	assert_eq(stats.local_slot, HOST_SLOT)
	assert_eq(stats.peers.size(), 0, "no remote peer has joined")


func test_a_host_with_no_counter_activity_has_no_intent_rows() -> void:
	_host()
	assert_eq(_source.read().intents.size(), 0)


func test_a_host_reports_a_row_for_a_slot_with_counters() -> void:
	_host()
	MatchNet.counters.count_sent(BUSY_SLOT)
	MatchNet.counters.count_sent(BUSY_SLOT)
	MatchNet.counters.count_accepted(BUSY_SLOT)
	MatchNet.counters.count_refused(BUSY_SLOT)
	var row: NetStats.IntentRow = _row(_source.read(), BUSY_SLOT)
	assert_not_null(row, "the active slot has a row")
	if row == null:
		return
	assert_eq(row.sent, 2)
	assert_eq(row.accepted, 1)
	assert_eq(row.refused, 1)
	assert_eq(row.cursors_refused, 0)


func test_a_host_row_carries_the_refused_cursor_count() -> void:
	_host()
	MatchNet.counters.count_cursor_refused(BUSY_SLOT)
	var row: NetStats.IntentRow = _row(_source.read(), BUSY_SLOT)
	assert_not_null(row, "a slot whose only counter is cursors_refused still has a row")
	if row != null:
		assert_eq(row.cursors_refused, 1)


func test_an_untouched_slot_has_no_row() -> void:
	_host()
	MatchNet.counters.count_sent(BUSY_SLOT)
	var stats: NetStats = _source.read()
	assert_null(_row(stats, UNTOUCHED_SLOT))
	assert_null(_row(stats, HOST_SLOT))
	assert_eq(stats.intents.size(), 1)


func test_each_active_slot_gets_exactly_one_row() -> void:
	_host()
	MatchNet.counters.count_sent(BUSY_SLOT)
	MatchNet.counters.count_accepted(BUSY_SLOT)
	MatchNet.counters.count_refused(OTHER_BUSY_SLOT)
	var stats: NetStats = _source.read()
	assert_eq(stats.intents.size(), 2)
	assert_eq(_row(stats, OTHER_BUSY_SLOT).refused, 1)


func test_counters_cleared_between_matches_drop_the_rows() -> void:
	_host()
	MatchNet.counters.count_sent(BUSY_SLOT)
	MatchNet.reset_counters()
	assert_eq(_source.read().intents.size(), 0)


func test_leaving_the_session_reads_offline_again() -> void:
	_host()
	Net.leave()
	var stats: NetStats = _source.read()
	assert_eq(stats.role, NetStats.Role.OFFLINE)
	assert_eq(stats.peers.size(), 0)
