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
## intents_sent; and, with block_timer held at BLOCK_TIMER_MAX so auto-drop
## never fires, that the number of Events.block_placed spawns equals the sum
## of every slot's intents_accepted. Every client checks that no
## Events.block_replicated net_id repeats and that it replicated at least one
## block, plus P2's Interpolator.dropped_unknown_count() opportunistically
## (only if that autoload exists yet — it isn't P4's package to gate on).

const CONNECT_TIMEOUT_SECONDS: float = 8.0
const MATCHNET_PROBE_TIMEOUT_SECONDS: float = 2.0
const INTENTS_PER_CLIENT: int = 6
const SETTLE_SECONDS_PER_INTENT: float = 0.15
const RESULT_WAIT_SECONDS: float = 5.0
const PLACE_HEIGHT: float = 0.6
## Spacing between a slot's scripted placements, in cube_size multiples, kept
## well inside TerritoryTuning.home_radius (6 m) so every one of them lands
## in the slot's own home circle regardless of map size.
const OFFSET_STEP: float = 1.5

var _failures: Array[String] = []
var _blocks_spawned: int = 0
var _seen_net_ids: Dictionary = {}
var _duplicate_net_id: bool = false

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

	print("M3A_ACCEPT result=%s failures=%d" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	for failure: String in _failures:
		print("M3A_ACCEPT failure %s" % failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


# --- MatchNet, called dynamically until it is a real autoload (see header) --

func _submit_place(slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion, auto_drop: bool) -> void:
	_match_net.call(&"submit_place", slot_id, origin, orientation_index, free_quat, auto_drop, _feed_seq_for(slot_id))


func _intents_sent(slot_id: int) -> int:
	return int(_match_net.call(&"intents_sent", slot_id))


func _intents_accepted(slot_id: int) -> int:
	return int(_match_net.call(&"intents_accepted", slot_id))


func _intents_refused(slot_id: int) -> int:
	return int(_match_net.call(&"intents_refused", slot_id))


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
	# Held at the max so the feed timer can never auto-drop mid-script: every
	# spawned block in this scenario must be traceable to a scripted intent
	# (docs/M3a_PLAN.md "Proving placements are never duplicated or lost").
	config.block_timer = MatchConfig.BLOCK_TIMER_MAX
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

	for slot_id: int in range(Match.config.player_count):
		var home: Vector2 = Match.slot(slot_id).home_position
		for i: int in range(INTENTS_PER_CLIENT):
			var spot: Vector2 = home + _offset_for_index(i)
			var origin: Vector3 = field.world_from_disk_local(spot, PLACE_HEIGHT)
			_submit_place(slot_id, origin, 0, Quaternion.IDENTITY, false)
			await get_tree().create_timer(SETTLE_SECONDS_PER_INTENT).timeout

	await get_tree().create_timer(RESULT_WAIT_SECONDS).timeout

	var accepted_total: int = 0
	for slot_id: int in range(Match.config.player_count):
		var sent: int = _intents_sent(slot_id)
		var accepted: int = _intents_accepted(slot_id)
		var refused: int = _intents_refused(slot_id)
		accepted_total += accepted
		_check(
			"per_slot_accept_refuse_%d" % slot_id, accepted + refused == sent,
			"slot=%d accepted=%d refused=%d sent=%d" % [slot_id, accepted, refused, sent]
		)
	# auto_drops is always 0 here (block_timer held at BLOCK_TIMER_MAX), so
	# docs/M3a_PLAN.md's "blocks_spawned == sum(intents_accepted) + auto_drops"
	# reduces to blocks_spawned == accepted_total.
	_check(
		"blocks_spawned_matches_accepted", _blocks_spawned == accepted_total,
		"blocks_spawned=%d accepted_total=%d" % [_blocks_spawned, accepted_total]
	)


func _wait_for_peer_count(expected: int) -> bool:
	var deadline_ms: int = Time.get_ticks_msec() + int(CONNECT_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline_ms:
		if Net.peer_ids().size() >= expected:
			return true
		await get_tree().create_timer(0.1).timeout
	return Net.peer_ids().size() >= expected


# --- Client ------------------------------------------------------------------

func _run_client() -> void:
	var slot_id: int = Net.local_slot()
	for i: int in range(INTENTS_PER_CLIENT):
		var spot: Vector2 = _offset_for_index(i)
		var origin: Vector3 = Vector3(spot.x, PLACE_HEIGHT, spot.y)
		_submit_place(slot_id, origin, 0, Quaternion.IDENTITY, false)
		await get_tree().create_timer(SETTLE_SECONDS_PER_INTENT).timeout

	await get_tree().create_timer(RESULT_WAIT_SECONDS).timeout

	var sent: int = _intents_sent(slot_id)
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


# --- Helpers -----------------------------------------------------------------

func _offset_for_index(i: int) -> Vector2:
	var column: int = i % 3 - 1
	var row: int = i / 3
	return Vector2(float(column), float(row)) * OFFSET_STEP


func _on_block_placed(_block: RigidBody3D, _shape_id: StringName) -> void:
	_blocks_spawned += 1


func _on_block_replicated(_block: RigidBody3D, net_id: int) -> void:
	if _seen_net_ids.has(net_id):
		_duplicate_net_id = true
	_seen_net_ids[net_id] = true


func _role_flag_was_given() -> bool:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--headless-host" or arg.begins_with("--join="):
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
