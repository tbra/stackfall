extends Node
## Bontago-1pi.18.8 (QoL Q4): host + one lagged client over real ENet, the QoL
## experiment matrix. One match per cell, restarted in place on the same
## session (a real start_match + net_match_start each time). Cells: every toggle
## OFF (control), each toggle ON alone, all four ON. Every cell runs the same
## phases, and each phase asserts the behaviour the cell's flags predict, so each
## toggle is exercised both on and off:
##   config       the client received the same toggles and claim radius the host runs
##   backlog      expiry: ON queues on the host and the client mirrors the count;
##                OFF the host force-drops the client's slot (auto_drops) and both
##                sides see feed_timer_expired
##   pause_topple host-only topple count (test seam) pauses one slot's timer; ON the
##                host freezes it and the client mirror/display agrees, OFF nothing
##   pause_event  a replicated special trigger pauses every slot, same split
##   gift_slot    a gift for each seat goes to the slot (ON) or the next-block queue
##                (OFF); the client's intent for the HOST'S seat is refused, its
##                own is honoured only when ON
## Host and client run in lock-step through two harness RPCs (h_begin / c_done) so
## a phase never starts before both ends are in it; each end prints one line per
## phase and the host prints the verdict. Exit code: 0 PASS, 1 FAIL, 2 setup,
## 3 hard deadline. Run via tools/run_qol_enet.ps1 (host: --headless-host).

## Net.peer_ids() counts the host too: one host + one client.
const HOST_AND_CLIENT_PEERS: int = 2
const CONNECT_TIMEOUT: float = 20.0
const JOIN_SETTLE_S: float = 1.0
## Whole-process wall-clock ceiling; tools/run_qol_enet.ps1 kills the tree at 180 s.
const HARD_DEADLINE_S: float = 170.0
const PLAYING_TIMEOUT_S: float = 15.0
const CLIENT_REPORT_TIMEOUT_S: float = 40.0
## The host re-sends h_begin until the client acks it (a reliable RPC to the harness
## node was seen missing once on the very first phase of a run).
const BEGIN_ACK_TIMEOUT_S: float = 10.0
const BEGIN_RESEND_S: float = 1.0
const BLOCK_TIMER_S: float = 5.0
const COUNTDOWN_S: float = 1.0
const CELL_SETTLE_S: float = 0.3
## Pause tuning for the matrix (QolExperiments keeps its defaults elsewhere).
const PAUSE_EVENT_S: float = 1.2
const PAUSE_TAIL_S: float = 0.3
const SCAN_INTERVAL_S: float = 0.1
const TOPPLE_MOVING_BLOCKS: int = 6
const BACKLOG_MAX: int = 3
const GOAL_MULTIPLIER: float = 2.5
const SAMPLE_S: float = 0.5
const FROZEN_EPS_S: float = 0.08
const RUNNING_MIN_DROP_S: float = 0.3
const NEGATIVE_WINDOW_S: float = 0.8
const REFUSED_WINDOW_S: float = 0.8
const SPECIAL_ID: StringName = &"anvil"
const HOST_SLOT: int = 0
const CLIENT_SLOT: int = 1
const SLOTS: int = 2

const BIT_PAUSE: int = 1
const BIT_BACKLOG: int = 2
const BIT_RADIUS: int = 4
const BIT_GIFT: int = 8
const CELL_NAMES: PackedStringArray = ["all_off", "timer_pause", "backlog", "goal_radius", "gift_slot", "all_on"]
const CELL_MASKS: PackedInt32Array = [0, BIT_PAUSE, BIT_BACKLOG, BIT_RADIUS, BIT_GIFT, 15]
const PHASES: PackedStringArray = ["config", "backlog", "pause_topple", "pause_event", "gift_slot"]

var _match_net: Node
var _field: Field = null
var _started_msec: int = 0
var _expired: Array[int] = [0, 0]
var _topple_counts: PackedInt32Array = PackedInt32Array([0, 0])
var _client_reports: Dictionary = {}
var _client_started: Dictionary = {}
var _checks: int = 0
var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_started_msec = Time.get_ticks_msec()
	if not Net.apply_command_line():
		get_tree().quit(2)
		return
	_match_net = get_node(^"/root/MatchNet")
	Events.feed_timer_expired.connect(_on_expired)
	if Net.mode() == Net.Mode.HOST:
		await _run_host()
	# A client has nothing to drive: h_begin / h_finish arrive as RPCs.


func _process(_delta: float) -> void:
	if _elapsed_s() > HARD_DEADLINE_S:
		print("QOLENET %s result=FAIL reason=hard_deadline" % _role())
		get_tree().quit(3)


func _elapsed_s() -> float:
	return float(Time.get_ticks_msec() - _started_msec) / 1000.0


func _role() -> String:
	return "host" if Net.mode() == Net.Mode.HOST else "client"


func _on_expired(slot_id: int) -> void:
	if slot_id >= 0 and slot_id < SLOTS:
		_expired[slot_id] += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(condition: Callable, seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await _wait(0.05)
	return condition.call()


func _fake_topple_counts() -> PackedInt32Array:
	return _topple_counts


# --- Cell table -----------------------------------------------------------------

func _cell_qol(mask: int) -> QolExperiments:
	var qol: QolExperiments = QolExperiments.with_toggles(null, mask & BIT_PAUSE != 0, mask & BIT_BACKLOG != 0,
		mask & BIT_RADIUS != 0, mask & BIT_GIFT != 0)
	qol.pause_event_s = PAUSE_EVENT_S
	qol.pause_tail_s = PAUSE_TAIL_S
	qol.topple_scan_interval_s = SCAN_INTERVAL_S
	qol.backlog_max = BACKLOG_MAX
	qol.goal_radius_multiplier = GOAL_MULTIPLIER
	qol.sanitize()
	return qol


func _expected_claim_radius(mask: int) -> float:
	if mask & BIT_RADIUS == 0:
		return 0.0
	return (load("res://config/territory_tuning.tres") as TerritoryTuning).goal_zone_radius * GOAL_MULTIPLIER


func _expected_ids(mask: int) -> PackedStringArray:
	return _cell_qol(mask).active_ids()


# --- Host -------------------------------------------------------------------------

func _run_host() -> void:
	# Net.peer_ids() includes the host itself, so wait for host + one client
	# (Bontago-1pi.18.8: `>= 1` was true at once and the first cell ran before the
	# client joined).
	await _until(func() -> bool: return Net.peer_ids().size() >= HOST_AND_CLIENT_PEERS, CONNECT_TIMEOUT)
	if Net.peer_ids().size() < HOST_AND_CLIENT_PEERS:
		print("QOLENET host result=FAIL reason=no_client")
		get_tree().quit(2)
		return
	await _wait(JOIN_SETTLE_S)
	var map_def: MapDef = MapDef.for_size(MapDef.MapSize.SMALL)
	_field = (load("res://game/Field.tscn") as PackedScene).instantiate() as Field
	_field.map_def = map_def
	add_child(_field)
	var blocks: Node3D = Node3D.new()
	add_child(blocks)
	var registry: BlockRegistry = BlockRegistry.new()
	add_child(registry)
	Match.register_world(_field, registry, blocks)
	for cell: int in range(CELL_MASKS.size()):
		await _host_cell(cell)
	var verdict: String = "PASS" if _failures.is_empty() else "FAIL"
	print("QOLENET host result=%s cells=%d checks=%d failed=%d %s" % [
		verdict, CELL_MASKS.size(), _checks, _failures.size(), ",".join(_failures)])
	rpc(&"h_finish", verdict)
	await _wait(1.0)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _host_cell(cell: int) -> void:
	var mask: int = CELL_MASKS[cell]
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.player_count = SLOTS
	config.hot_seat = false
	config.block_timer = BLOCK_TIMER_S
	config.countdown_seconds = COUNTDOWN_S
	config.qol = _cell_qol(mask)
	_expired = [0, 0]
	_topple_counts = PackedInt32Array([0, 0])
	Match._feed._qol_moving_counts_source = Callable()
	Match.start_match(config)
	# Idempotent: the LOADING state change already sent net_match_start.
	_match_net.call(&"replicate_match_start", Match.config)
	_field.place_flags(Match.config.player_count, Match.config.player_colors, Match.config.goal_flag_count)
	var playing: bool = await _until(func() -> bool: return Match.state() == Match.State.PLAYING, PLAYING_TIMEOUT_S)
	if not playing:
		_record("host", cell, "start", false, "host never reached PLAYING")
	await _wait(CELL_SETTLE_S)
	for phase: String in PHASES:
		if not await _begin_phase(cell, phase):
			_record("host", cell, phase, false, "client never acked h_begin")
			continue
		var host_result: Array = await _host_phase(cell, phase, mask)
		_record("host", cell, phase, bool(host_result[0]), String(host_result[1]))
		var report: Dictionary = await _await_client(cell, phase)
		_record("client", cell, phase, bool(report.get("ok", false)), String(report.get("detail", "")))
	Match._feed._qol_moving_counts_source = Callable()


## Lock-step start: sends h_begin and re-sends it until the client acks (c_started).
func _begin_phase(cell: int, phase: String) -> bool:
	var key: String = "%d/%s" % [cell, phase]
	var deadline: int = Time.get_ticks_msec() + int(BEGIN_ACK_TIMEOUT_S * 1000.0)
	var sends: int = 0
	while not _client_started.has(key) and Time.get_ticks_msec() < deadline:
		rpc(&"h_begin", cell, phase)
		sends += 1
		await _until(func() -> bool: return _client_started.has(key), BEGIN_RESEND_S)
	if sends > 1:
		print("QOLENET host note=h_begin_resent cell=%s phase=%s sends=%d t=%.2f peers=%s" % [
			CELL_NAMES[cell], phase, sends, _elapsed_s(), multiplayer.get_peers()])
	return _client_started.has(key)


func _await_client(cell: int, phase: String) -> Dictionary:
	var key: String = "%d/%s" % [cell, phase]
	await _until(func() -> bool: return _client_reports.has(key), CLIENT_REPORT_TIMEOUT_S)
	return _client_reports.get(key, {"ok": false, "detail": "no client report"}) as Dictionary


func _record(who: String, cell: int, phase: String, ok: bool, detail: String) -> void:
	_checks += 1
	if not ok:
		_failures.append("%s:%s:%s" % [CELL_NAMES[cell], phase, who])
	print("QOLENET %s cell=%s phase=%s ok=%s %s" % [who, CELL_NAMES[cell], phase, ok, detail])


func _host_phase(cell: int, phase: String, mask: int) -> Array:
	match phase:
		"config":
			return await _host_config(mask)
		"backlog":
			return await _host_backlog(mask)
		"pause_topple":
			return await _host_pause_topple(mask)
		"pause_event":
			return await _host_pause_event(mask)
		"gift_slot":
			return await _host_gift(cell, mask)
	return [false, "unknown phase"]


func _host_config(mask: int) -> Array:
	var qol: QolExperiments = Match.config.qol
	var ids: PackedStringArray = qol.active_ids() if qol != null else PackedStringArray(["no_qol"])
	var radius: float = Match.qol_claim_radius()
	var ok: bool = ids == _expected_ids(mask) and is_equal_approx(radius, _expected_claim_radius(mask))
	ok = ok and Match.gift_slot_enabled() == (mask & BIT_GIFT != 0)
	ok = ok and Match.qol_backlog_count(HOST_SLOT) == 0 and Match.qol_backlog_count(CLIENT_SLOT) == 0
	return [ok, "ids=%s claim_radius=%.2f" % [",".join(ids), radius]]


func _host_backlog(mask: int) -> Array:
	var on: bool = mask & BIT_BACKLOG != 0
	var window: float = BLOCK_TIMER_S + 4.0
	if on:
		await _until(func() -> bool: return Match.qol_backlog_count(HOST_SLOT) >= 1 and Match.qol_backlog_count(CLIENT_SLOT) >= 1, window)
	else:
		await _until(func() -> bool: return _expired[CLIENT_SLOT] >= 1 and _expired[HOST_SLOT] >= 1, window)
	await _wait(NEGATIVE_WINDOW_S)
	var b0: int = Match.qol_backlog_count(HOST_SLOT)
	var b1: int = Match.qol_backlog_count(CLIENT_SLOT)
	var drops: int = int(_match_net.call(&"auto_drops", CLIENT_SLOT))
	var ok: bool
	if on:
		# Queued, never forced: no expiry signal, no auto-drop for the remote seat.
		ok = b0 == 1 and b1 == 1 and _expired[HOST_SLOT] == 0 and _expired[CLIENT_SLOT] == 0 and drops == 0
	else:
		ok = b0 == 0 and b1 == 0 and _expired[HOST_SLOT] >= 1 and _expired[CLIENT_SLOT] >= 1 and drops == 1
	return [ok, "backlog=%d/%d expired=%d/%d auto_drops_client=%d" % [b0, b1, _expired[0], _expired[1], drops]]


## Resets both intervals to a full block timer so a pause phase never races a
## leftover expiry (MatchFeed.debug_unlock_slot is the documented test seam).
func _refill_timers() -> void:
	for slot_id: int in range(SLOTS):
		Match._feed.debug_unlock_slot(slot_id)


func _host_pause_topple(mask: int) -> Array:
	var on: bool = mask & BIT_PAUSE != 0
	_refill_timers()
	_topple_counts = PackedInt32Array([0, TOPPLE_MOVING_BLOCKS])
	Match._feed._qol_moving_counts_source = Callable(self, &"_fake_topple_counts")
	var p1: bool = false
	if on:
		p1 = await _until(func() -> bool: return Match.qol_timer_paused(CLIENT_SLOT), 1.5)
	else:
		await _wait(NEGATIVE_WINDOW_S)
		p1 = Match.qol_timer_paused(CLIENT_SLOT)
	var p0: bool = Match.qol_timer_paused(HOST_SLOT)
	var t1a: float = Match.feed_time_left(CLIENT_SLOT)
	var t0a: float = Match.feed_time_left(HOST_SLOT)
	await _wait(SAMPLE_S)
	var d1: float = t1a - Match.feed_time_left(CLIENT_SLOT)
	var d0: float = t0a - Match.feed_time_left(HOST_SLOT)
	var ok: bool
	if on:
		# Only the slot with the moving blocks is frozen; the other keeps counting.
		ok = p1 and not p0 and d1 < FROZEN_EPS_S and d0 > RUNNING_MIN_DROP_S
	else:
		ok = not p1 and not p0 and d1 > RUNNING_MIN_DROP_S and d0 > RUNNING_MIN_DROP_S
	_topple_counts = PackedInt32Array([0, 0])
	if on:
		var cleared: bool = await _until(func() -> bool: return not Match.qol_timer_paused(CLIENT_SLOT), 3.0)
		ok = ok and cleared
	Match._feed._qol_moving_counts_source = Callable()
	return [ok, "paused=%s/%s drop=%.2f/%.2f" % [p0, p1, d0, d1]]


func _host_pause_event(mask: int) -> Array:
	var on: bool = mask & BIT_PAUSE != 0
	_refill_timers()
	# The real path: MatchNet._on_special_triggered pauses the feed and replicates the event.
	Events.special_triggered.emit(0, SPECIAL_ID, Vector3.ZERO, 0)
	var both: bool = false
	if on:
		both = await _until(func() -> bool: return Match.qol_timer_paused(HOST_SLOT) and Match.qol_timer_paused(CLIENT_SLOT), 1.0)
	else:
		await _wait(NEGATIVE_WINDOW_S)
		both = Match.qol_timer_paused(HOST_SLOT) or Match.qol_timer_paused(CLIENT_SLOT)
	var t0a: float = Match.feed_time_left(HOST_SLOT)
	var t1a: float = Match.feed_time_left(CLIENT_SLOT)
	await _wait(SAMPLE_S)
	var d0: float = t0a - Match.feed_time_left(HOST_SLOT)
	var d1: float = t1a - Match.feed_time_left(CLIENT_SLOT)
	var ok: bool
	if on:
		ok = both and d0 < FROZEN_EPS_S and d1 < FROZEN_EPS_S
		var released: bool = await _until(func() -> bool: return not Match.qol_timer_paused(HOST_SLOT) and not Match.qol_timer_paused(CLIENT_SLOT), PAUSE_EVENT_S + 3.0)
		ok = ok and released
	else:
		ok = not both and d0 > RUNNING_MIN_DROP_S and d1 > RUNNING_MIN_DROP_S
	return [ok, "paused_any=%s drop=%.2f/%.2f" % [both, d0, d1]]


func _host_gift(_cell: int, mask: int) -> Array:
	var on: bool = mask & BIT_GIFT != 0
	_refill_timers()
	Match._gifts._queue_claimed_special(HOST_SLOT, SPECIAL_ID)
	Match._gifts._queue_claimed_special(CLIENT_SLOT, SPECIAL_ID)
	# The client now sends an intent for the host's seat (must be refused) and one for its own.
	await _await_client(_cell, "gift_slot")
	var ok: bool
	if on:
		ok = Match.gift_slot_head(HOST_SLOT) == SPECIAL_ID and Match.held_special(HOST_SLOT) == &"" \
			and Match.held_special(CLIENT_SLOT) == SPECIAL_ID and Match.gift_slot_count(CLIENT_SLOT) == 0 \
			and Match.next_special(HOST_SLOT) == &""
	else:
		ok = Match.gift_slot_count(HOST_SLOT) == 0 and Match.gift_slot_count(CLIENT_SLOT) == 0 \
			and Match.held_special(CLIENT_SLOT) == &"" and Match.next_special(CLIENT_SLOT) == SPECIAL_ID
	return [ok, "host_slot=%s/%d held=%s/%s next_client=%s" % [
		Match.gift_slot_head(HOST_SLOT), Match.gift_slot_count(CLIENT_SLOT), Match.held_special(HOST_SLOT),
		Match.held_special(CLIENT_SLOT), Match.next_special(CLIENT_SLOT)]]


# --- Client -------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func h_begin(cell: int, phase: String) -> void:
	if Net.mode() == Net.Mode.HOST or cell < 0 or cell >= CELL_MASKS.size() or not PHASES.has(phase):
		return
	var key: String = "%d/%s" % [cell, phase]
	rpc_id(Net.HOST_PEER_ID, &"c_started", cell, phase)
	if _client_started.has(key) or phase == PHASES[0] and cell == 0:
		print("QOLENET client note=h_begin_rx cell=%s phase=%s dup=%s t=%.2f state=%d" % [
			CELL_NAMES[cell], phase, _client_started.has(key), _elapsed_s(), Match.state()])
	if _client_started.has(key):
		return  # a re-sent h_begin: acked again above, never run twice
	_client_started[key] = true
	var result: Array = await _client_phase(cell, phase, CELL_MASKS[cell])
	var ok: bool = bool(result[0])
	var detail: String = String(result[1])
	_checks += 1
	if not ok:
		_failures.append("%s:%s" % [CELL_NAMES[cell], phase])
	print("QOLENET client cell=%s phase=%s ok=%s %s" % [CELL_NAMES[cell], phase, ok, detail])
	rpc_id(Net.HOST_PEER_ID, &"c_done", cell, phase, ok, detail)


@rpc("any_peer", "call_remote", "reliable")
func c_started(cell: int, phase: String) -> void:
	if Net.mode() != Net.Mode.HOST:
		return
	_client_started["%d/%s" % [cell, phase]] = true


@rpc("any_peer", "call_remote", "reliable")
func c_done(cell: int, phase: String, ok: bool, detail: String) -> void:
	if Net.mode() != Net.Mode.HOST:
		return
	_client_reports["%d/%s" % [cell, phase]] = {"ok": ok, "detail": detail}


@rpc("authority", "call_remote", "reliable")
func h_finish(host_verdict: String) -> void:
	if Net.mode() == Net.Mode.HOST:
		return
	var verdict: String = "PASS" if _failures.is_empty() and host_verdict == "PASS" else "FAIL"
	print("QOLENET client result=%s phases=%d failed=%d host=%s %s" % [
		verdict, _checks, _failures.size(), host_verdict, ",".join(_failures)])
	await _wait(0.5)
	get_tree().quit(0 if verdict == "PASS" else 1)


func _client_phase(cell: int, phase: String, mask: int) -> Array:
	match phase:
		"config":
			return await _client_config(mask)
		"backlog":
			return await _client_backlog(mask)
		"pause_topple":
			return await _client_pause_topple(mask)
		"pause_event":
			return await _client_pause_event(mask)
		"gift_slot":
			return await _client_gift(mask)
	return [false, "unknown phase %d" % cell]


func _client_config(mask: int) -> Array:
	_expired = [0, 0]
	var playing: bool = await _until(func() -> bool: return Match.state() == Match.State.PLAYING and Match.config != null and Match.config.qol != null, PLAYING_TIMEOUT_S)
	if not playing:
		return [false, "client never reached PLAYING with a qol config"]
	var qol: QolExperiments = Match.config.qol
	var want: QolExperiments = _cell_qol(mask)
	var radius: float = Match.qol_claim_radius()
	var ok: bool = qol.active_ids() == want.active_ids() and is_equal_approx(radius, _expected_claim_radius(mask))
	ok = ok and qol.backlog_max == want.backlog_max and is_equal_approx(qol.goal_radius_multiplier, want.goal_radius_multiplier)
	ok = ok and is_equal_approx(qol.pause_event_s, want.pause_event_s) and Match.gift_slot_enabled() == (mask & BIT_GIFT != 0)
	return [ok, "ids=%s claim_radius=%.2f" % [",".join(qol.active_ids()), radius]]


func _client_backlog(mask: int) -> Array:
	var on: bool = mask & BIT_BACKLOG != 0
	var window: float = BLOCK_TIMER_S + 8.0
	if on:
		await _until(func() -> bool: return Match.qol_backlog_count(HOST_SLOT) >= 1 and Match.qol_backlog_count(CLIENT_SLOT) >= 1, window)
	else:
		await _until(func() -> bool: return _expired[CLIENT_SLOT] >= 1, window)
	await _wait(NEGATIVE_WINDOW_S)
	var b0: int = Match.qol_backlog_count(HOST_SLOT)
	var b1: int = Match.qol_backlog_count(CLIENT_SLOT)
	var ok: bool
	if on:
		ok = b0 == 1 and b1 == 1 and _expired[CLIENT_SLOT] == 0
	else:
		ok = b0 == 0 and b1 == 0 and _expired[CLIENT_SLOT] >= 1
	return [ok, "mirror=%d/%d expired_seen=%d/%d" % [b0, b1, _expired[0], _expired[1]]]


func _client_pause_topple(mask: int) -> Array:
	var on: bool = mask & BIT_PAUSE != 0
	var p1: bool = false
	if on:
		p1 = await _until(func() -> bool: return Match.qol_timer_paused(CLIENT_SLOT), 3.0)
	else:
		await _wait(NEGATIVE_WINDOW_S)
		p1 = Match.qol_timer_paused(CLIENT_SLOT)
	var p0: bool = Match.qol_timer_paused(HOST_SLOT)
	var t1a: float = Match.feed_time_left(CLIENT_SLOT)
	await _wait(SAMPLE_S)
	var d1: float = t1a - Match.feed_time_left(CLIENT_SLOT)
	var ok: bool
	if on:
		ok = p1 and not p0 and d1 < FROZEN_EPS_S
		var cleared: bool = await _until(func() -> bool: return not Match.qol_timer_paused(CLIENT_SLOT), 4.0)
		ok = ok and cleared
	else:
		ok = not p1 and not p0 and d1 > RUNNING_MIN_DROP_S
	return [ok, "mirror_paused=%s/%s display_drop=%.2f" % [p0, p1, d1]]


func _client_pause_event(mask: int) -> Array:
	var on: bool = mask & BIT_PAUSE != 0
	var both: bool = false
	if on:
		both = await _until(func() -> bool: return Match.qol_timer_paused(HOST_SLOT) and Match.qol_timer_paused(CLIENT_SLOT), 3.0)
	else:
		await _wait(NEGATIVE_WINDOW_S)
		both = Match.qol_timer_paused(HOST_SLOT) or Match.qol_timer_paused(CLIENT_SLOT)
	var t1a: float = Match.feed_time_left(CLIENT_SLOT)
	await _wait(SAMPLE_S)
	var d1: float = t1a - Match.feed_time_left(CLIENT_SLOT)
	var ok: bool
	if on:
		ok = both and d1 < FROZEN_EPS_S
		var released: bool = await _until(func() -> bool: return not Match.qol_timer_paused(HOST_SLOT) and not Match.qol_timer_paused(CLIENT_SLOT), PAUSE_EVENT_S + 4.0)
		ok = ok and released
	else:
		ok = not both and d1 > RUNNING_MIN_DROP_S
	return [ok, "mirror_paused_any=%s display_drop=%.2f" % [both, d1]]


func _client_gift(mask: int) -> Array:
	var on: bool = mask & BIT_GIFT != 0
	var seen: bool = false
	var queue_untouched: bool = true
	if on:
		seen = await _until(func() -> bool: return Match.gift_slot_head(CLIENT_SLOT) == SPECIAL_ID, 10.0)
		queue_untouched = Match.next_special(CLIENT_SLOT) == &"" and Match.held_special(CLIENT_SLOT) == &""
	else:
		await _wait(NEGATIVE_WINDOW_S)
		seen = Match.gift_slot_count(CLIENT_SLOT) == 0 and Match.gift_slot_head(CLIENT_SLOT) == &""
	# Host authority: a client may only spend its own seat's slot, and only when the toggle is on.
	var sent_foreign: bool = bool(_match_net.call(&"submit_use_gift_slot", HOST_SLOT))
	await _wait(REFUSED_WINDOW_S)
	var foreign_held: bool = Match.held_special(HOST_SLOT) != &""
	var sent_own: bool = bool(_match_net.call(&"submit_use_gift_slot", CLIENT_SLOT))
	var held: bool = false
	if on:
		held = await _until(func() -> bool: return Match.held_special(CLIENT_SLOT) == SPECIAL_ID, 10.0)
	else:
		await _wait(REFUSED_WINDOW_S)
		held = Match.held_special(CLIENT_SLOT) != &""
	var ok: bool
	if on:
		ok = seen and queue_untouched and sent_foreign and sent_own and not foreign_held and held \
			and Match.gift_slot_head(CLIENT_SLOT) == &""
	else:
		ok = seen and sent_own and not foreign_held and not held
	return [ok, "slot_seen=%s queue_untouched=%s sent=%s/%s foreign_held=%s own_held=%s" % [
		seen, queue_untouched, sent_foreign, sent_own, foreign_held, held]]
