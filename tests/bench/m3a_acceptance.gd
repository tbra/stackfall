extends Node
## End-to-end network acceptance for M3a (spec Part 4 M3a "4 local instances
## play a full match ... a client with 100 ms simulated lag and 2% packet
## loss sees smooth towers; placements are never duplicated or lost";
## docs/M3a_PLAN.md P4).
##
## Run with a role from the command line, exactly as Net.apply_command_line()
## parses it (spec 3.4 "Testing"):
##   godot --headless --path . res://tests/bench/m3a_acceptance.tscn -- \
##       --headless-host --port=47778 --expect-peers=4
##   godot --headless --path . res://tests/bench/m3a_acceptance.tscn -- \
##       --join=127.0.0.1:47778 --sim-lag=100 --sim-loss=0.02
## tools/run_m3a_local.ps1 / .sh drive one host and N-1 clients from a single
## command; `--expect-peers` is this script's own flag (Net.apply_command_line()
## has no such thing), read directly off OS.get_cmdline_user_args() so the
## host knows how many peers to wait for before starting.
##
## Review item 2 (M4 P2c-ii acceptance): passing `--throw-pass` to every
## instance (tools/run_m3a_local.ps1 -ThrowPass / .sh THROW_PASS=1) runs an
## additional phase after the placement phase above, proving
## MatchNet.submit_throw()/net_request_throw() over a real ENet transport --
## an accepted throw for slot THROW_SLOT_ID (clamped speed, continuous_cd,
## pending count back to zero on both the host AND, since Bontago-1en.21's
## EVENT_SPECIAL_CONSUMED replication, the throwing client itself) and a
## refused one outside that slot's own territory. Off by default, so the
## existing placement-only regression's
## command line and behavior are unchanged. Reports a second, independent
## `M3A_THROW result=PASS|FAIL` line (see _throw_check()); a throw failure
## still fails the whole run's exit code via M3A_ACCEPT's own summary (see
## _ready()'s own comment on why no separate ps1/sh parsing is needed for
## that).
##
## **Must be a .tscn, not a -s script.** Commit 12d2ec2's finding: a script
## run with `-s` executes as a bare SceneTree, where autoload identifiers
## (Net, Match) do not resolve. tests/bench/m2_acceptance.tscn set this
## precedent; this scene follows it.
##
## **Why this may only print "harness_blocked" today.** This package (P4)
## lands in parallel with P1 (autoload/Net.gd, net/LanDiscovery.gd), P2
## (net/SnapshotSync.gd, net/Interpolator.gd) and P3 (autoload/Match.gd's
## host gates, net/MatchNet.gd's real RPC bodies), all against the interface
## stubs docs/M3a_PLAN.md committed. Two things are not real yet, and both
## are checked explicitly rather than assumed:
##   1. **MatchNet isn't a registered autoload yet.** docs/M3a_PLAN.md's
##      integration order step 5 has the integrator add `MatchNet=` to
##      project.godot's [autoload] *after* P1-P3 land — P4 must not touch
##      that section itself. So this script finds it dynamically at
##      /root/MatchNet and calls it through Object.call() rather than the
##      bare `MatchNet.xxx()` a finished build will use; if the node isn't
##      there yet, that alone is reason enough to stop.
##   2. **Net is a stub.** Net.host_game()/join_game() currently return OK
##      without opening a socket, so Net.mode() never leaves OFFLINE.
##      _wait_for_connection() requires it to actually reach HOST or CLIENT
##      within CONNECT_TIMEOUT_SECONDS.
## Either guard failing prints one `M3A_ACCEPT harness_blocked` line naming
## the stubbed layer and exits 2 — a code distinct from PASS (0) and a real
## assertion FAILURE (1), so tools/run_m3a_local.* can tell "nothing to test
## yet" apart from "something is broken". Once a real MatchNet is registered
## and Net actually connects, a third guard (_matchnet_is_wired(), a single
## probe intent checked against intents_sent()) catches the remaining case
## where the autoload exists but its methods are still stubs returning
## harmless defaults — otherwise a councer-vs-counter assertion could read
## zero on both sides and report a hollow PASS.
##
## **What this proves once every layer is real.** Every connected slot fires
## INTENTS_PER_CLIENT scripted placements at its own home flag (always inside
## its own territory, so a refusal can only be a network-level one — wrong
## slot or a stale feed_seq — never a PlacementRules rejection) through
## MatchNet.submit_place(), exactly as PlayerController will once P3 lands.
## The host then checks, per docs/M3a_PLAN.md "Proving placements are never
## duplicated or lost": per slot, intents_accepted + intents_refused ==
## intents_sent; and that the number of Events.block_placed spawns equals the
## sum of every slot's intents_accepted (auto_drops is always 0 here — see
## INTENT_SPACING_SECONDS' own comment). Every client checks that no
## Events.block_replicated net_id repeats and that it replicated at least one
## block, plus P2's Interpolator.dropped_unknown_count() opportunistically
## (only if that autoload exists yet — it isn't P4's package to gate on).
##
## Bontago-mv0.10 follow-up (spec 2.4 "[ORIGINAL target]" fixed-interval
## cadence): a deliberate release now locks the slot until its interval's
## boundary, so all INTENTS_PER_CLIENT scripted releases have to be spaced a
## full interval apart to land as genuine, individually-accepted releases
## instead of mostly refused as locked. The host config's block_timer is held
## at MatchConfig.BLOCK_TIMER_MIN (not BLOCK_TIMER_MAX, the old choice made
## when placements reissued instantly) specifically so that spacing is short
## enough to keep every slot's INTENTS_PER_CLIENT round trip well inside
## tools/run_m3a_local.ps1's wrapper timeout.

const CONNECT_TIMEOUT_SECONDS: float = 8.0
const MATCHNET_PROBE_TIMEOUT_SECONDS: float = 2.0
const INTENTS_PER_CLIENT: int = 6
## Bontago-mv0.10: how long a released piece stays locked before the next one
## may go out -- one full fixed interval (MatchConfig.BLOCK_TIMER_MIN, the
## host's own config below) plus a fixed margin for the send/settle/RTT time
## a real placement and (for a client) its SimLag/SimLoss round trip cost, so
## a scripted release always lands after its slot's interval boundary already
## unlocked it, never while still locked. Held at BLOCK_TIMER_MIN, not
## BLOCK_TIMER_MAX (this script's own pre-cadence choice): auto_drops stays 0
## either way -- every scripted release spends its interval's one piece well
## before the boundary, so nothing is ever left unspent for _tick_feed() to
## force -- but MIN is what keeps INTENTS_PER_CLIENT releases per slot inside
## the wrapper's timeout.
const INTERVAL_MARGIN_SECONDS: float = 0.5
const INTENT_SPACING_SECONDS: float = MatchConfig.BLOCK_TIMER_MIN + INTERVAL_MARGIN_SECONDS
const RESULT_WAIT_SECONDS: float = 5.0
const PLACE_HEIGHT: float = 0.6
## Spacing between a slot's scripted placements, in cube_size multiples, kept
## well inside TerritoryTuning.home_radius (6 m) so every one of them lands
## in the slot's own home circle regardless of map size.
const OFFSET_STEP: float = 1.5

## Review item 2: an optional throw phase, gated on --throw-pass (default
## off, so the existing placement-only regression is unchanged), proving
## M4 P2c-ii's submit_throw()/net_request_throw() over a real ENet transport
## rather than only FakeNet unit tests. Always slot 1 (the first, and in
## tools/run_m3a_local.*'s own default -Peers 2 usage the only, client) --
## this phase does not attempt to generalise to every peer, only to prove the
## wire path end to end for one of them.
const THROW_SLOT_ID: int = 1
## Distinct, out-of-band gift ids (no real crate spawner runs in this
## harness, so nothing else can ever claim these) for the two claims this
## phase queues: one the accepted throw spends, one queued again afterward so
## the negative (outside-territory) throw below is refused by ThrowRules'
## own territory check rather than by "nothing pending" (see
## _run_host_throw_phase()'s own comment).
const THROW_GIFT_ID_ACCEPT: int = 900001
const THROW_GIFT_ID_REJECT: int = 900002
## Comfortably above SpecialTuning.throw_max_speed (25 m/s) so the host's own
## clamp (spec 3.4: "the host clamps velocity to throw_max_speed") is the
## thing actually under test, not merely "a velocity was accepted."
const THROW_VELOCITY_SPEED: float = 40.0
## Review fix: offset from the slot's own home_position the accepted throw
## releases at (see _run_client_throw_phase()'s own comment). Unlike a unit
## test, this harness's host runs real Jolt physics continuously, and the
## placement phase already scattered six blocks within OFFSET_STEP *
## {-1,0,1}/{0,1} of home_position (~2.1 m radius) -- releasing straight into
## that cluster let the thrown block collide almost immediately, losing most
## of its speed before this script's own poll could ever read it
## (reproduced: an observed post-throw speed of ~9.6 m/s against the ~25.0
## the clamp should have left it at). (-3.0, -3.0) clears that whole cluster
## (>1.5 m margin) while its magnitude (~4.24 m) stays well inside
## TerritoryTuning.home_radius (6 m), so the release point is still
## unambiguously inside the slot's own territory.
const THROW_ORIGIN_OFFSET: Vector2 = Vector2(-3.0, -3.0)
## Review fix: how close the clamped speed must land to throw_max_speed to
## count as "clamped, not still ~40 (unclamped) or ~0 (an unrelated
## auto-drop, see THROW_MIN_SPEED_TO_COUNT_AS_THROWN below)". Loosened from an
## original 1% once the actual harness run showed *why* 1% assumes an
## instantaneous read this design cannot deliver: this script detects the new
## block by polling every _wait_for_condition tick (up to 0.05s later), during
## which real, continuously-running Jolt physics (not a GUT test's frozen
## world) has already added a tick or two of gravity to the vertical
## component. 5% (1.25 m/s here) comfortably covers that detection latency
## while staying nowhere near "unclamped" (40) or "auto-dropped" (~0) --
## still a real, meaningful clamp check, not a rubber stamp.
const THROW_SPEED_TOLERANCE_FRACTION: float = 0.05
## Review fix: the slot always holds *some* ordinary piece and MatchConfig.
## BLOCK_TIMER_MIN (3 s, held by _run_host()'s own config) keeps ticking
## throughout this multi-second phase's own claim/round-trip waits -- an
## auto-drop (spec 2.5) for that ordinary piece is expected, unrelated
## background noise here, not a bug, and it always releases at rest (no
## velocity ever set on an ordinary placement or auto-drop). A thrown special
## never does: even after clamping it still leaves at throw_max_speed (25),
## so any observed speed above this threshold, for this slot, can only be the
## one throw this phase actually sent -- see _run_host_throw_phase()'s own
## use of it, both to find the real block among any interleaved auto-drops
## and to prove the negative throw spawned no *thrown* block (an auto-drop
## for the slot's ordinary piece may well still occur meanwhile, and is not
## itself a failure).
const THROW_MIN_SPEED_TO_COUNT_AS_THROWN: float = 5.0
## Point well outside any shipped map's field_radius (tens of meters), so a
## throw released there is unambiguously "outside your own territory"
## (spec 2.5) rather than merely off this particular map's disk edge.
const THROW_OUTSIDE_TERRITORY_POINT: Vector2 = Vector2(500.0, 500.0)
## How long the client polls after a host-side claim before giving up on
## seeing it replicate (SimLag/SimLoss-tolerant; see _wait_for_condition()).
const THROW_CLAIM_WAIT_SECONDS: float = 4.0
## How long either side waits for a submitted throw's round trip (request out,
## spawn/rejection back) to settle before checking results.
const THROW_RESULT_WAIT_SECONDS: float = 3.0

var _failures: Array[String] = []
## Review item 2: kept separate from _failures so "M3A_THROW result=..."
## reports only the throw phase's own criteria; folded into _failures before
## the final quit() so a throw failure still fails the whole harness run
## (and therefore tools/run_m3a_local.* via its existing non-zero-exit check,
## with no ps1/sh changes needed for that part).
var _throw_failures: Array[String] = []
var _blocks_spawned: int = 0
var _seen_net_ids: Dictionary = {}
var _duplicate_net_id: bool = false

## Review item 2: the most recent Block this instance saw placed for each
## slot (host: built locally by _spawn_block(); client: never built at all in
## this bare-scene harness -- see _on_block_placed()'s own comment -- so this
## dictionary is host-only in practice). Read only through _fast_block_for_
## slot() below, never directly, because an ordinary auto-drop can overwrite
## it with an unrelated block at any time (see that function's own comment).
var _last_block_by_slot: Dictionary = {}
## Review item 2, host only: sticky per-slot "last block this instance ever
## saw moving faster than THROW_MIN_SPEED_TO_COUNT_AS_THROWN" -- see
## _fast_block_for_slot()'s own comment for why this has to be sticky rather
## than re-derived live from _last_block_by_slot on every read.
var _last_thrown_block_by_slot: Dictionary = {}
## Review item 2, client only: every Events.placement_rejected this instance
## has seen since the last time the throw phase cleared it, {slot_id, reason}
## dictionaries in order. A fresh Array per throw attempt would miss a
## rejection that arrives during the polling gap between "send" and "start
## checking"; connecting once in _ready() and clearing between attempts does
## not.
var _rejected_events: Array[Dictionary] = []

## Bontago-1en.21, client only: every Events.special_consumed this instance's
## own slot has seen since the last time the throw phase cleared it, mirroring
## _rejected_events' own pattern above -- {slot_id, special_id} dictionaries
## in order. Waiting for this event to arrive is the robust proof "the host's
## pop replicated", independent of pending_special_count()'s own transient
## value: under -sim-lag/-sim-loss a retransmit can deliver this event and the
## *next* claim's own replication back-to-back in the same frame, so a poll of
## the derived count alone could miss the intermediate zero entirely (see
## _run_client_throw_phase()'s own DECISION).
var _consumed_events: Array[Dictionary] = []

## Bontago-1en.21, client only: every Events.gift_claimed this instance's own
## slot has seen, in order, since _ready() connected it -- an append-only log
## (unlike Match.pending_special_count(), which both a claim and a consumed
## pop can move in either direction), used to detect the throw phase's own
## *second* claim (THROW_GIFT_ID_REJECT) robustly: "size() grew past a
## baseline" is always well-defined regardless of how the derived queue depth
## happens to read at any one polled instant (see _run_client_throw_phase()'s
## own DECISION on why the derived count alone is not enough there).
var _claimed_events: Array[Dictionary] = []

## Found dynamically at /root/MatchNet — see the header's guard 1. Once the
## integrator registers the real autoload this still resolves correctly;
## nothing here needs to change.
var _match_net: Node = null


func _ready() -> void:
	var had_role: bool = Net.apply_command_line()
	print("M3A_ACCEPT start had_role=%s mode=%d" % [had_role, Net.mode()])
	if not had_role:
		if _role_flag_was_given():
			# A role flag is right there in the command line, so a false
			# return means Net.apply_command_line() itself hasn't parsed it
			# yet (true of the P1 stub, which always returns false) rather
			# than a harness usage mistake.
			print("M3A_ACCEPT harness_blocked layer=Net reason=apply_command_line_stub")
		else:
			print("M3A_ACCEPT harness_blocked layer=harness reason=no_role_flag " +
				"(pass --headless-host or --join=<ip:port> after --)")
		get_tree().quit(2)
		return

	_match_net = get_node_or_null(^"/root/MatchNet")
	if _match_net == null:
		print("M3A_ACCEPT harness_blocked layer=MatchNet reason=autoload_not_registered_yet")
		get_tree().quit(2)
		return

	Events.block_placed.connect(_on_block_placed)
	Events.block_replicated.connect(_on_block_replicated)
	Events.placement_rejected.connect(_on_placement_rejected)
	Events.special_consumed.connect(_on_special_consumed)
	Events.gift_claimed.connect(_on_gift_claimed_for_slot)

	if not await _wait_for_connection():
		print("M3A_ACCEPT harness_blocked layer=Net reason=stub_no_transport mode=%d peers=%d" % [
			Net.mode(), Net.peer_ids().size()
		])
		get_tree().quit(2)
		return

	if not await _matchnet_is_wired():
		print("M3A_ACCEPT harness_blocked layer=MatchNet reason=stub_does_not_track_intents")
		get_tree().quit(2)
		return

	if Net.mode() == Net.Mode.HOST:
		await _run_host()
	else:
		await _run_client()

	# Review item 2: opt-in, after the placement phase's own checks are
	# already recorded, so a throw failure never masks or reorders the
	# placement regression's own M3A_ACCEPT accounting.
	if _throw_pass_enabled():
		if Net.mode() == Net.Mode.HOST:
			await _run_host_throw_phase()
		else:
			await _run_client_throw_phase()
		print("M3A_THROW result=%s failures=%d" % ["PASS" if _throw_failures.is_empty() else "FAIL", _throw_failures.size()])
		for throw_failure: String in _throw_failures:
			print("M3A_THROW failure %s" % throw_failure)
		_failures.append_array(_throw_failures)

	print("M3A_ACCEPT result=%s failures=%d" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	for failure: String in _failures:
		print("M3A_ACCEPT failure %s" % failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


# --- MatchNet, called dynamically until it is a real autoload (see header) --

func _submit_place(slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion, auto_drop: bool) -> void:
	_match_net.call(&"submit_place", slot_id, origin, orientation_index, free_quat, auto_drop, _feed_seq_for(slot_id))


## Review item 2: MatchNet.submit_throw()'s own harness-side call site,
## mirroring _submit_place() exactly (M4 P2c-ii, net/MatchNet.gd:submit_throw
## -- called dynamically for the same "not a registered autoload yet" reason
## as every other _match_net.call() here).
func _submit_throw(slot_id: int, origin: Vector3, velocity: Vector3) -> void:
	_match_net.call(
		&"submit_throw", slot_id, origin, 0, Quaternion.IDENTITY, velocity, _feed_seq_for(slot_id)
	)


func _intents_sent(slot_id: int) -> int:
	return int(_match_net.call(&"intents_sent", slot_id))


func _intents_accepted(slot_id: int) -> int:
	return int(_match_net.call(&"intents_accepted", slot_id))


func _intents_refused(slot_id: int) -> int:
	return int(_match_net.call(&"intents_refused", slot_id))


## Bontago-mv0.10 follow-up: docs/M3a_PLAN.md's real invariant is
## "blocks_spawned == sum(intents_accepted) + auto_drops", not
## "== sum(intents_accepted)" -- the simpler form only held while block_timer
## was pinned at BLOCK_TIMER_MAX and nothing sent fast enough to ever reach a
## boundary. This cadence's own scripted spacing means an interval never
## goes deliberately unspent, but the pre-existing dual-submission design for
## a remote slot (the host's own local copy AND that slot's real client both
## fire a release every round) can still lose an occasional round to
## SimLag/SimLoss jitter on the client side, and the one interval that lands
## on is force-released by the host's own timer -- a genuine, spec-2.5
## auto-drop, not a bug, and it must count here or the invariant it is
## proving would be checked with a term missing.
func _auto_drops(slot_id: int) -> int:
	return int(_match_net.call(&"auto_drops", slot_id))


func _replicated_block_count() -> int:
	return int(_match_net.call(&"replicated_block_count"))


func _feed_seq_for(slot_id: int) -> int:
	if Match.has_method(&"feed_seq"):
		return int(Match.call(&"feed_seq", slot_id))
	return 0


# --- Stub guards ---------------------------------------------------------------

func _wait_for_connection() -> bool:
	var deadline_ms: int = Time.get_ticks_msec() + int(CONNECT_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline_ms:
		if Net.mode() == Net.Mode.HOST:
			return true
		if Net.mode() == Net.Mode.CLIENT and Net.peer_ids().size() >= 2:
			return true
		await get_tree().create_timer(0.1).timeout
	return false


## Sends one throwaway intent for this instance's own slot and checks that
## MatchNet actually counted it, rather than trusting a stub's return value.
func _matchnet_is_wired() -> bool:
	var slot_id: int = Net.local_slot()
	var before: int = _intents_sent(slot_id)
	_submit_place(slot_id, Vector3.ZERO, 0, Quaternion.IDENTITY, false)
	var deadline_ms: int = Time.get_ticks_msec() + int(MATCHNET_PROBE_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline_ms:
		if _intents_sent(slot_id) != before:
			return true
		await get_tree().create_timer(0.05).timeout
	return false


# --- Host --------------------------------------------------------------------

func _run_host() -> void:
	var expected_peers: int = _int_arg("--expect-peers=", 1)
	if not await _wait_for_peer_count(expected_peers):
		print("M3A_ACCEPT harness_blocked layer=Net reason=peers_did_not_join expected=%d got=%d" % [
			expected_peers, Net.peer_ids().size()
		])
		get_tree().quit(2)
		return

	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.player_count = expected_peers
	config.hot_seat = false
	# Bontago-mv0.10: the shortest legal interval, not the longest (this
	# script's own pre-cadence choice) -- see INTENT_SPACING_SECONDS' comment
	# on why a short interval, not a long one, is what keeps this harness's
	# scripted releases inside the wrapper timeout now that a deliberate
	# release locks the slot until its interval boundary. auto_drops still
	# never fires: every scripted release spends its interval's one piece
	# long before the boundary, so nothing is ever left unspent to force
	# (docs/M3a_PLAN.md "Proving placements are never duplicated or lost").
	config.block_timer = MatchConfig.BLOCK_TIMER_MIN
	config.rng_seed = 20260918

	var field: Field = (load("res://game/Field.tscn") as PackedScene).instantiate() as Field
	field.map_def = MapDef.for_size(config.map_size)
	add_child(field)
	var blocks: Node3D = Node3D.new()
	add_child(blocks)
	var registry: BlockRegistry = BlockRegistry.new()
	add_child(registry)

	Match.register_world(field, registry, blocks)
	Match.start_match(config)
	_match_net.call(&"replicate_match_start", Match.config)
	field.place_flags(Match.config.player_count, Match.config.player_colors, Match.config.goal_flag_count)
	field.set_overlay_source(Match.raster(), Match.config.player_colors)

	await get_tree().create_timer(Match.COUNTDOWN_SECONDS + 0.5).timeout

	# Bontago-mv0.10: one release per slot per round, not every one of a
	# slot's INTENTS_PER_CLIENT releases back to back before moving to the
	# next slot. Spec 2.4 "[ORIGINAL target]": "players act concurrently" --
	# every slot's interval started at the same instant (Match._begin_
	# playing() seeds them all together), so round-robining keeps that true
	# here too, and keeps this loop's total wait at INTENTS_PER_CLIENT *
	# INTENT_SPACING_SECONDS regardless of player_count, not that times
	# player_count, which is what kept this harness inside
	# tools/run_m3a_local.ps1's wrapper timeout at 4 peers.
	for i: int in range(INTENTS_PER_CLIENT):
		for slot_id: int in range(Match.config.player_count):
			var home: Vector2 = Match.slot(slot_id).home_position
			var spot: Vector2 = home + _offset_for_index(i)
			var origin: Vector3 = field.world_from_disk_local(spot, PLACE_HEIGHT)
			_submit_place(slot_id, origin, 0, Quaternion.IDENTITY, false)
		await get_tree().create_timer(INTENT_SPACING_SECONDS).timeout

	await get_tree().create_timer(RESULT_WAIT_SECONDS).timeout

	var accepted_total: int = 0
	var auto_drop_total: int = 0
	for slot_id: int in range(Match.config.player_count):
		var sent: int = _intents_sent(slot_id)
		var accepted: int = _intents_accepted(slot_id)
		var refused: int = _intents_refused(slot_id)
		var auto_dropped: int = _auto_drops(slot_id)
		accepted_total += accepted
		auto_drop_total += auto_dropped
		_check(
			"per_slot_accept_refuse_%d" % slot_id, accepted + refused == sent,
			"slot=%d accepted=%d refused=%d sent=%d auto_drops=%d" % [slot_id, accepted, refused, sent, auto_dropped]
		)
	# docs/M3a_PLAN.md's full invariant, not the "auto_drops is always 0"
	# simplification this script used while block_timer sat at BLOCK_TIMER_MAX
	# (see INTENT_SPACING_SECONDS' and _auto_drops()'s own comments on why
	# that assumption no longer holds under the fixed-interval cadence).
	_check(
		"blocks_spawned_matches_accepted", _blocks_spawned == accepted_total + auto_drop_total,
		"blocks_spawned=%d accepted_total=%d auto_drop_total=%d" % [_blocks_spawned, accepted_total, auto_drop_total]
	)


## Review item 2: proves M4 P2c-ii's request_throw over a real ENet
## transport. Runs only when --throw-pass is given, after the placement
## phase's own checks are already recorded (_ready()'s own comment). Skips
## cleanly (one informational PASS line, no failure) when there is no
## THROW_SLOT_ID client in this run, so a `-Peers 1` sanity run still works.
func _run_host_throw_phase() -> void:
	if Match.config.player_count <= THROW_SLOT_ID:
		_throw_check(
			"throw_phase_skipped_not_enough_players", true,
			"player_count=%d needs > %d" % [Match.config.player_count, THROW_SLOT_ID]
		)
		return

	# --- Accepted throw: queue a special for THROW_SLOT_ID the same way a
	# real crate claim does (MatchGifts.apply_replicated_claim() plus the
	# Events.gift_claimed emit _on_gift_claimed() listens for -- see
	# net/MatchNet.gd:_on_gift_claimed()), then let the real wire carry it to
	# the client exactly like a real claim would.
	#
	# Review fix: detection below filters on THROW_MIN_SPEED_TO_COUNT_AS_
	# THROWN rather than merely "a new block for this slot" -- the slot's own
	# feed timer (MatchConfig.BLOCK_TIMER_MIN, 3 s) keeps ticking throughout
	# this phase's multi-second waits, so an unrelated auto-drop of the
	# slot's ordinary held piece (spec 2.5, always released at rest) can and
	# did interleave with the throw's own spawn in practice (reproduced: a
	# second, unrelated block appeared while this phase was still waiting on
	# the *next* claim to replicate). Only the throw itself ever leaves a
	# block moving this fast, so filtering on speed finds the right one
	# regardless of how many ordinary auto-drops land around it.
	Match._gifts.apply_replicated_claim(THROW_GIFT_ID_ACCEPT, THROW_SLOT_ID, MatchGifts.PENDING_SPECIAL_ID)
	Events.gift_claimed.emit(THROW_GIFT_ID_ACCEPT, THROW_SLOT_ID, MatchGifts.PENDING_SPECIAL_ID)

	if not await _wait_for_condition(
		func() -> bool: return _fast_block_for_slot(THROW_SLOT_ID) != null,
		THROW_CLAIM_WAIT_SECONDS + THROW_RESULT_WAIT_SECONDS
	):
		_throw_check(
			"throw_accepted_block_spawned", false,
			"no block moving > %.1f m/s for slot=%d within %.1fs" % [
				THROW_MIN_SPEED_TO_COUNT_AS_THROWN, THROW_SLOT_ID,
				THROW_CLAIM_WAIT_SECONDS + THROW_RESULT_WAIT_SECONDS
			]
		)
		return
	var thrown_block: Block = _fast_block_for_slot(THROW_SLOT_ID)
	_throw_check("throw_accepted_block_spawned", true, "net_id=%d" % thrown_block.net_id)

	var special_tuning: SpecialTuning = load("res://config/special_tuning.tres") as SpecialTuning
	var speed: float = thrown_block.linear_velocity.length()
	var tolerance: float = special_tuning.throw_max_speed * THROW_SPEED_TOLERANCE_FRACTION
	_throw_check(
		"throw_speed_clamped_to_max", absf(speed - special_tuning.throw_max_speed) <= tolerance,
		"speed=%.3f throw_max_speed=%.3f tolerance=%.3f" % [speed, special_tuning.throw_max_speed, tolerance]
	)
	_throw_check(
		"throw_continuous_cd_set", thrown_block.continuous_cd,
		"continuous_cd=%s" % thrown_block.continuous_cd
	)
	var pending_after: int = Match.pending_special_count(THROW_SLOT_ID)
	_throw_check(
		"throw_host_pending_count_zero", pending_after == 0,
		"pending_special_count(%d)=%d" % [THROW_SLOT_ID, pending_after]
	)

	# --- Negative: queue a second special so the coming refusal is genuinely
	# ThrowRules' "outside your own territory" (spec 2.5), not merely "no
	# special pending" (the first claim's was already spent above).
	Match._gifts.apply_replicated_claim(THROW_GIFT_ID_REJECT, THROW_SLOT_ID, MatchGifts.PENDING_SPECIAL_ID)
	Events.gift_claimed.emit(THROW_GIFT_ID_REJECT, THROW_SLOT_ID, MatchGifts.PENDING_SPECIAL_ID)

	# The client's own _run_client_throw_phase() does the actual send and the
	# "was it rejected" assertions; this side only has to confirm no *second
	# thrown* block landed for the slot while that plays out (an ordinary
	# auto-drop for the slot's held piece may still legitimately occur in the
	# meantime -- see this function's own opening comment -- and is not
	# itself a failure here).
	await get_tree().create_timer(THROW_CLAIM_WAIT_SECONDS + THROW_RESULT_WAIT_SECONDS).timeout
	var after_negative: Block = _fast_block_for_slot(THROW_SLOT_ID)
	_throw_check(
		"throw_outside_territory_spawned_nothing_on_host", after_negative == thrown_block,
		"slot=%d accepted_net_id=%d observed_after_net_id=%d" % [
			THROW_SLOT_ID, thrown_block.net_id, after_negative.net_id if after_negative != null else -1
		]
	)


func _wait_for_peer_count(expected: int) -> bool:
	var deadline_ms: int = Time.get_ticks_msec() + int(CONNECT_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline_ms:
		if Net.peer_ids().size() >= expected:
			return true
		await get_tree().create_timer(0.1).timeout
	return Net.peer_ids().size() >= expected


## A client's own Match.start_match() only runs once net/MatchNet.gd's
## net_match_start RPC arrives from the host, so this is also this
## instance's confirmation that reset_counters() has already fired (see
## _run_client()'s comment).
func _wait_for_match_playing() -> bool:
	var deadline_ms: int = Time.get_ticks_msec() + int(CONNECT_TIMEOUT_SECONDS * 1000.0) + int(RESULT_WAIT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline_ms:
		if Match.state() == Match.State.PLAYING:
			return true
		await get_tree().create_timer(0.1).timeout
	return Match.state() == Match.State.PLAYING


# --- Client ------------------------------------------------------------------

func _run_client() -> void:
	var slot_id: int = Net.local_slot()
	# A client's Godot process typically finishes booting and connecting well
	# before the host reaches PLAYING (which waits on every peer joining,
	# then the countdown) -- with nothing gating it, this loop used to start
	# firing the moment two peers were merely visible. net/MatchNet.gd's
	# net_match_start() handler calls reset_counters() the instant it applies
	# the host's config, so any scripted intent sent before that arrives (or
	# before its RTT lands the accept/refuse back) got wiped mid-count,
	# producing a "sent" total that no longer matched INTENTS_PER_CLIENT even
	# though nothing was actually duplicated or lost. Waiting for PLAYING
	# (the same state the host's own script waits for before its loop) means
	# this script's counting phase starts only after that one reset has
	# already happened.
	if not await _wait_for_match_playing():
		print("M3A_ACCEPT harness_blocked layer=Match reason=match_never_reached_playing")
		get_tree().quit(2)
		return
	# Bontago-mv0.31: a baseline, not an assumed zero. _matchnet_is_wired()
	# already sent one throwaway probe intent for this same slot before
	# _run_client() ever started (see its own doc) -- reset_counters() above
	# is expected to wipe it, but whether it actually lands before or after
	# that probe is a race between this process's own _ready() sequence and
	# the host's net_match_start RPC arriving, and -sim-lag/-sim-loss can flip
	# it (seen once as client_sent_matches_script sent=7 expected=6, %TEMP%/
	# consumed_m3a_2peer_run7.log). Counting the delta across exactly this
	# loop's own sends, rather than trusting the absolute counter is 0 going
	# in, is correct regardless of which side of that race the probe landed
	# on -- and regardless of anything else that might otherwise leave a
	# stray count behind before this point.
	var baseline_sent: int = _intents_sent(slot_id)
	_check(
		"client_baseline_sent_at_most_one", baseline_sent <= 1,
		"baseline=%d" % baseline_sent
	)
	# Bontago-mv0.10: spaced the same one-interval-plus-margin apart as the
	# host's own script (INTENT_SPACING_SECONDS' comment), so this client's
	# own releases land after its slot's interval boundary unlocks each one
	# instead of being refused as locked.
	for i: int in range(INTENTS_PER_CLIENT):
		var spot: Vector2 = _offset_for_index(i)
		var origin: Vector3 = Vector3(spot.x, PLACE_HEIGHT, spot.y)
		_submit_place(slot_id, origin, 0, Quaternion.IDENTITY, false)
		await get_tree().create_timer(INTENT_SPACING_SECONDS).timeout

	await get_tree().create_timer(RESULT_WAIT_SECONDS).timeout

	var sent: int = _intents_sent(slot_id) - baseline_sent
	_check(
		"client_sent_matches_script", sent == INTENTS_PER_CLIENT,
		"sent=%d expected=%d" % [sent, INTENTS_PER_CLIENT]
	)
	_check("client_no_duplicate_net_id", not _duplicate_net_id, "a net_id was replicated twice")
	_check(
		"client_replicated_at_least_one_block", _replicated_block_count() > 0,
		"replicated_block_count=%d" % _replicated_block_count()
	)

	# P2's counter, opportunistic: only asserted if net/Interpolator.gd has
	# landed with it registered somewhere reachable, so this scene doesn't
	# hard-fail against a package that isn't P4's to gate on.
	var snapshot_sync: Node = get_node_or_null(^"/root/SnapshotSync")
	if snapshot_sync != null and snapshot_sync.has_method(&"dropped_unknown_count"):
		var dropped: int = int(snapshot_sync.call(&"dropped_unknown_count"))
		var one_snapshot_worth: int = 32  # generous upper bound; see NetConfig.max_packet_bytes / a body record
		_check(
			"client_dropped_unknown_stays_low", dropped < one_snapshot_worth,
			"dropped_unknown_count=%d" % dropped
		)


## Review item 2: the client half of the throw phase. Only THROW_SLOT_ID's own
## client does anything -- every other client in a >2-peer run returns
## immediately, since this phase proves the wire path for one participant,
## not every peer (THROW_SLOT_ID's own comment).
func _run_client_throw_phase() -> void:
	var slot_id: int = Net.local_slot()
	if slot_id != THROW_SLOT_ID:
		return

	# --- Accepted throw ---------------------------------------------------
	var pending_before: int = Match.pending_special_count(slot_id)
	if not await _wait_for_condition(
		func() -> bool: return Match.pending_special_count(slot_id) > pending_before,
		THROW_CLAIM_WAIT_SECONDS
	):
		_throw_check(
			"throw_client_learned_pending_special", false,
			"pending_special_count(%d) still %d after %.1fs" % [
				slot_id, Match.pending_special_count(slot_id), THROW_CLAIM_WAIT_SECONDS
			]
		)
		return
	_throw_check(
		"throw_client_learned_pending_special", true,
		"pending_special_count(%d)=%d" % [slot_id, Match.pending_special_count(slot_id)]
	)

	# DECISION (tests/bench/m3a_acceptance.gd, Bontago-1en.21): captured here,
	# before the throw below is even submitted -- at this exact point exactly
	# one claim (the accepted one) can possibly exist, since the host's own
	# second claim is only ever queued after it independently confirms this
	# throw's own block exists, which cannot happen before the throw itself
	# is sent. Capturing any later (e.g. once the accepted throw's own
	# consumed-event has been confirmed below) is NOT safe: reproduced with
	# both -Peers 2 and -Peers 4, the second claim's own replication can
	# arrive close enough behind the first's consumed-event replication that
	# a later snapshot already includes it, leaving no "one more claim"
	# transition for the wait near the end of this function to ever detect.
	var claims_before_throw: int = _claimed_events.size()

	# Bontago-1en.21 (was a known limitation, now fixed): the host replicates
	# a "special consumed" event (Events.special_consumed / net/MatchNet.gd's
	# EVENT_SPECIAL_CONSUMED) the moment it pops the queue for an accepted
	# throw or placement, so this client eventually learns its own special
	# was actually spent -- not just stay at pending_special_count() == 1
	# forever, which was this package's own bug. See the DECISION below on
	# why that is proved by waiting for the *event*, not by re-polling the
	# count the way "throw_client_learned_pending_special" above does.
	#
	# Review fix: offset away from home_position, not home_position itself --
	# the placement phase's own six releases per slot already scattered
	# blocks within OFFSET_STEP * {-1,0,1}/{0,1} of home (up to ~2.1 m), and a
	# throw released right into that cluster collided with one of them within
	# a tick or two, losing most of its speed before this script ever reads
	# it (reproduced: observed speed=9.6 against an expected ~25.0 after
	# clamping). THROW_ORIGIN_OFFSET clears that whole cluster by design (see
	# its own comment) while staying well inside TerritoryTuning.home_radius.
	var home: Vector2 = Match.slot(slot_id).home_position + THROW_ORIGIN_OFFSET
	var origin: Vector3 = Vector3(home.x, PLACE_HEIGHT, home.y)
	var before_replicated: int = _replicated_block_count()
	_rejected_events.clear()
	_consumed_events.clear()
	_submit_throw(slot_id, origin, Vector3(THROW_VELOCITY_SPEED, 0.0, 0.0))

	# DECISION (tests/bench/m3a_acceptance.gd, Bontago-1en.21): waits for the
	# Events.special_consumed *event* to arrive (via _consumed_events, an
	# _on_placement_rejected-style listener -- see its own field comment),
	# not for Match.pending_special_count(slot_id) to read back down to zero.
	# Reproduced against THROW_SLOT_ID's own -sim-lag=100 -sim-loss=0.02
	# client (tools/run_m3a_local.ps1's default):
	# an ENet retransmit after a lost packet can deliver this event and the
	# *next* claim's own EVENT_GIFT_CLAIMED replication in the same client
	# frame, so polling the derived count risked reading only their *net*
	# effect (back to 1, having skipped 0 entirely) and never observing the
	# transient zero at all -- a false "still 1" failure for a decrement that
	# genuinely happened. The event itself always fires exactly once for this
	# throw's own pop, strictly before that next claim's own dispatch (both
	# ride net_match_event on the same reliable channel, in send order), so
	# it is unaffected by whether the *count* ever visibly rests at zero.
	var got_consumed_event: bool = await _wait_for_condition(
		func() -> bool: return not _consumed_events.is_empty(),
		THROW_CLAIM_WAIT_SECONDS + THROW_RESULT_WAIT_SECONDS
	)
	_throw_check(
		"throw_client_pending_count_zero", got_consumed_event,
		"consumed_events=%s pending_special_count(%d)=%d" % [
			_consumed_events, slot_id, Match.pending_special_count(slot_id)
		]
	)
	_throw_check(
		"throw_client_no_rejection", _rejected_events.is_empty(),
		"rejected_events=%s" % [_rejected_events]
	)
	var after_replicated: int = _replicated_block_count()
	# Review fix: ">=", not "==" -- MatchConfig.BLOCK_TIMER_MIN (3 s) can
	# legitimately auto-drop the slot's ordinary held piece during this same
	# window (see _fast_block_for_slot()'s own comment for the full story),
	# which also replicates and also bumps this same counter. This still
	# proves the accepted throw's own block specifically arrived over the
	# snapshot pipeline (throw_client_no_rejection above already rules out a
	# refusal for *this* request), just not that it was the only spawn.
	_throw_check(
		"throw_client_block_arrived", after_replicated >= before_replicated + 1,
		"replicated_block_count before=%d after=%d" % [before_replicated, after_replicated]
	)

	# --- Negative: a release point outside this slot's own territory ------
	# Waiting for _claimed_events to grow past the baseline captured above
	# proves the host's second claim (_run_host_throw_phase()'s own
	# THROW_GIFT_ID_REJECT) has already been applied host-side too -- the
	# host always applies a claim to itself before broadcasting it, so by the
	# time this client observes the new entry, the coming refusal is
	# guaranteed to be ThrowRules' territory check, not "nothing pending".
	if not await _wait_for_condition(
		func() -> bool: return _claimed_events.size() > claims_before_throw,
		THROW_CLAIM_WAIT_SECONDS
	):
		_throw_check(
			"throw_client_learned_second_pending_special", false,
			"claimed_events=%s after %.1fs" % [_claimed_events, THROW_CLAIM_WAIT_SECONDS]
		)
		return
	_throw_check(
		"throw_client_learned_second_pending_special", true,
		"claimed_events=%s pending_special_count(%d)=%d" % [
			_claimed_events, slot_id, Match.pending_special_count(slot_id)
		]
	)

	var far_origin: Vector3 = Vector3(
		THROW_OUTSIDE_TERRITORY_POINT.x, PLACE_HEIGHT, THROW_OUTSIDE_TERRITORY_POINT.y
	)
	_rejected_events.clear()
	_submit_throw(slot_id, far_origin, Vector3(1.0, 0.0, 0.0))
	await get_tree().create_timer(THROW_RESULT_WAIT_SECONDS).timeout

	# Review fix: no "replicated_block_count unchanged" check here -- an
	# ordinary auto-drop for this slot's held piece (see
	# _fast_block_for_slot()'s own comment) can legitimately bump this same
	# counter while this waits, regardless of whether the throw above was
	# refused, so it would not actually be testing this negative case.
	# _run_host_throw_phase()'s own "no *thrown* (fast) block" check already
	# covers "nothing spawned specifically from this request"; the signal
	# that is reliable here, on the client, is that the request came back
	# rejected at all.
	_throw_check(
		"throw_outside_territory_rejected", not _rejected_events.is_empty(),
		"rejected_events=%s" % [_rejected_events]
	)


# --- Helpers -----------------------------------------------------------------

func _offset_for_index(i: int) -> Vector2:
	var column: int = i % 3 - 1
	var row: int = i / 3
	return Vector2(float(column), float(row)) * OFFSET_STEP


## Review item 2: `block` used to be discarded (`_block`) -- now recorded per
## slot so _run_host_throw_phase() can tell a *new* spawn for THROW_SLOT_ID
## apart from the placement phase's own six. Locally built blocks always have
## `owner_slot` set (game/Block.gd:owner_slot, set by BlockFactory.build());
## harmless on a client too, where no local Block is ever built at all in
## this bare-scene harness (Events.block_placed only fires from a *local*
## spawn -- Match.register_world() is never called client-side here, so
## MatchPlacement._spawn_block() never runs there either), so
## _last_block_by_slot simply stays empty on a client, which
## _run_client_throw_phase() never reads.
func _on_block_placed(block: RigidBody3D, _shape_id: StringName) -> void:
	_blocks_spawned += 1
	var typed: Block = block as Block
	if typed != null:
		_last_block_by_slot[typed.owner_slot] = typed


## Review item 2: `_last_block_by_slot[slot_id]` alone is not enough to find
## (or rule out) a *thrown* block for THROW_SLOT_ID, because MatchConfig.
## BLOCK_TIMER_MIN (3 s) keeps ticking through this phase's multi-second
## waits and can auto-drop the slot's ordinary held piece in between polls,
## overwriting the dictionary entry with an unrelated, at-rest block (spec
## 2.5; reproduced during this package's own review pass). A thrown special
## always leaves the host clamped to at least throw_max_speed's own ballpark
## (25 m/s), which no ordinary placement or auto-drop ever does, so speed is
## what actually identifies it. The result is cached into
## _last_thrown_block_by_slot rather than recomputed from the live velocity
## on every call: the thrown block's own speed decays (gravity, eventually
## landing) well before this phase's *later* checks re-read it, and a fresh
## live read at that point would wrongly read as "gone" even though nothing
## further happened to it.
func _fast_block_for_slot(slot_id: int) -> Block:
	var current: Block = _last_block_by_slot.get(slot_id) as Block
	if current != null and current.linear_velocity.length() > THROW_MIN_SPEED_TO_COUNT_AS_THROWN:
		_last_thrown_block_by_slot[slot_id] = current
	return _last_thrown_block_by_slot.get(slot_id) as Block


func _on_block_replicated(_block: RigidBody3D, net_id: int) -> void:
	if _seen_net_ids.has(net_id):
		_duplicate_net_id = true
	_seen_net_ids[net_id] = true


## Review item 2, client only in practice (see this file's other
## _run_client_throw_phase()): records every rejection this instance's own
## slot receives so the negative throw case can prove one actually arrived,
## and the accepted case can prove none did.
func _on_placement_rejected(slot_id: int, reason: StringName) -> void:
	# Review fix: EVENT_PLACEMENT_REJECTED broadcasts to every peer (net/
	# MatchNet.gd's replicate_match_event(), not targeted rpc_id()), so an
	# unrelated refusal for another slot (host's own auto-drop, say) would
	# otherwise show up here too and could spuriously fail
	# throw_client_no_rejection below. Only this instance's own slot's
	# rejections are what "no placement_rejected reaches it" (this package's
	# own brief) actually means.
	if slot_id != Net.local_slot():
		return
	_rejected_events.append({"slot_id": slot_id, "reason": reason})


## Bontago-1en.21: _on_placement_rejected's own twin for Events.special_
## consumed -- see _consumed_events' own field comment for why this is
## more reliable proof of arrival than polling pending_special_count().
func _on_special_consumed(slot_id: int, special_id: StringName) -> void:
	if slot_id != Net.local_slot():
		return
	_consumed_events.append({"slot_id": slot_id, "special_id": special_id})


## Bontago-1en.21: see _claimed_events' own field comment. Named _for_slot,
## not _on_gift_claimed, so it reads distinctly from net/MatchNet.gd's own
## same-named host-side handler in any shared log/backtrace.
func _on_gift_claimed_for_slot(_gift_id: int, slot_id: int, special_id: StringName) -> void:
	if slot_id != Net.local_slot():
		return
	_claimed_events.append({"slot_id": slot_id, "special_id": special_id})


func _role_flag_was_given() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--headless-host" or arg.begins_with("--join="):
			return true
	return false


## Review item 2: --throw-pass is this harness's own flag, exactly like
## --expect-peers above (Net.apply_command_line() has no equivalent), read
## directly off OS.get_cmdline_user_args(). Default off, so the existing
## placement-only regression's command line and behavior are unchanged.
func _throw_pass_enabled() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--throw-pass":
			return true
	return false


func _int_arg(flag: String, default_value: int) -> int:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(flag):
			var value: String = arg.substr(flag.length())
			if value.is_valid_int():
				return int(value)
	return default_value


func _check(criterion: String, passed: bool, detail: String) -> void:
	print("M3A_ACCEPT (%s) %s %s" % [criterion, "PASS" if passed else "FAIL", detail])
	if not passed:
		_failures.append("(%s) %s" % [criterion, detail])


## Review item 2's own twin of _check(), printing "M3A_THROW" lines and
## appending to _throw_failures (folded into _failures once the whole throw
## phase finishes -- see _ready()'s own comment) so the two phases' pass/fail
## accounting never mixes in the raw per-criterion output.
func _throw_check(criterion: String, passed: bool, detail: String) -> void:
	print("M3A_THROW (%s) %s %s" % [criterion, "PASS" if passed else "FAIL", detail])
	if not passed:
		_throw_failures.append("(%s) %s" % [criterion, detail])


## Review item 2: a generic poll, mirroring _wait_for_connection()'s own
## deadline-then-one-more-check shape (a `while` loop can exit right as the
## deadline ticks over without re-testing the condition one last time; every
## existing wait helper in this file already re-checks after the loop for
## exactly that reason). `check` is called at most once per 0.05s tick, cheap
## enough for the Dictionary/int reads every call site here passes it.
func _wait_for_condition(check: Callable, timeout_seconds: float) -> bool:
	var deadline_ms: int = Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline_ms:
		if bool(check.call()):
			return true
		await get_tree().create_timer(0.05).timeout
	return bool(check.call())
