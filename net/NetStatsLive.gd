class_name NetStatsLive
extends NetStatsSource
## Adapter that names the autoloads (Net, SnapshotSync, MatchNet) and assembles one NetStats.
## It is the one place that knows which autoload owns which number.
# DECISION: reads the autoloads by name because SnapshotSync and MatchNet have no class_name,
# the same adapter shape as MatchContextLive.

const MS_PER_S: float = 1000.0

var _bytes: NetRateMeter = null
var _snapshots: NetRateMeter = null


func read() -> NetStats:
	var stats: NetStats = NetStats.new()
	stats.role = int(Net.mode()) as NetStats.Role
	stats.local_slot = Net.local_slot()
	stats.sim_lag_ms = Net.simulated_lag_ms()
	stats.sim_loss = Net.simulated_loss()
	if stats.role == NetStats.Role.OFFLINE:
		_bytes = null
		_snapshots = null
		return stats
	_feed_rates(stats)
	stats.last_snapshot_bytes = SnapshotSync.last_snapshot_bytes()
	stats.last_snapshot_bodies = SnapshotSync.last_snapshot_bodies()
	stats.last_snapshot_fragments = SnapshotSync.last_snapshot_fragments()
	if stats.role == NetStats.Role.HOST:
		_read_peers(stats)
		_read_host_intents(stats)
	else:
		stats.local_rtt_ms = Net.ping_ms()
		stats.interp_delay_ms = SnapshotSync.interpolation_delay_ms()
		stats.arrival_jitter_ms = SnapshotSync.arrival_jitter_ms()
		stats.loss_fraction = SnapshotSync.measured_loss()
		stats.dropped_unknown = SnapshotSync.dropped_unknown()
		_read_client_intents(stats)
	return stats


func set_simulation(lag_ms: float, loss: float) -> void:
	Net.set_simulation(lag_ms, 0.0, loss)


func _feed_rates(stats: NetStats) -> void:
	if _bytes == null:
		var window_s: float = SnapshotSync.config.stats_window
		_bytes = NetRateMeter.new(window_s)
		_snapshots = NetRateMeter.new(window_s)
	var now_s: float = float(Time.get_ticks_msec()) / MS_PER_S
	_bytes.sample(SnapshotSync.snapshot_bytes_total(), now_s)
	_snapshots.sample(SnapshotSync.snapshots_total(), now_s)
	stats.snapshot_bytes_per_s = _bytes.per_second()
	stats.snapshots_per_s = _snapshots.per_second()


func _read_peers(stats: NetStats) -> void:
	var local_id: int = Net.local_peer_id()
	for peer_id: int in Net.peer_ids():
		if peer_id == local_id:
			continue
		var info: Dictionary = Net.peer_info(peer_id)
		var row: NetStats.PeerRow = NetStats.PeerRow.new()
		row.peer_id = peer_id
		row.slot_id = int(info.get(LobbySeats.FIELD_SLOT_ID, -1))
		row.name = str(info.get(LobbySeats.FIELD_NAME, ""))
		row.rtt_ms = Net.ping_ms(peer_id)
		row.rtt_jitter_ms = Net.peer_rtt_jitter_ms(peer_id)
		stats.peers.append(row)


func _read_host_intents(stats: NetStats) -> void:
	var counters: NetCounters = MatchNet.counters
	var slots: Dictionary = {}
	for counter: Dictionary in [counters.sent, counters.accepted, counters.refused, counters.cursors_refused]:
		for slot_id: int in counter.keys():
			slots[slot_id] = true
	var ordered: Array = slots.keys()
	ordered.sort()
	for slot_id: int in ordered:
		var row: NetStats.IntentRow = NetStats.IntentRow.new()
		row.slot_id = slot_id
		row.sent = counters.sent_count(slot_id)
		row.accepted = counters.accepted_count(slot_id)
		row.refused = counters.refused_count(slot_id)
		row.cursors_refused = counters.cursors_refused_count(slot_id)
		stats.intents.append(row)


func _read_client_intents(stats: NetStats) -> void:
	var sent: int = MatchNet.intents_sent(stats.local_slot)
	if sent <= 0:
		return
	var row: NetStats.IntentRow = NetStats.IntentRow.new()
	row.slot_id = stats.local_slot
	row.sent = sent
	stats.intents.append(row)
