extends Node
## Client-side apply of host -> client match events (Bontago-1pi.11.77.16, S3c-C1).
##
## A child of the MatchNet autoload, built by MatchNet.late_activate() so the
## ~400-line validation/dispatch below is compiled after the first frame instead
## of with the autoload. The RPC entry point stays MatchNet.net_match_event()
## (path /root/MatchNet unchanged, protocol unchanged); it forwards here after
## its own awaiting-world gate. No RPC lives on this node.

## The owning MatchNet autoload (or a test instance); set before first use.
var _net: Node = null


func _session() -> Variant:
	return _net._session()


func _authority() -> Variant:
	return _net._authority()


## Validates and applies one host-authored match event. Every guard that used
## to live in net_match_event is unchanged.
func apply_event(event: StringName, args: Array) -> void:
	match event:
		MatchNet.EVENT_CAT_STARTED:
			if _session().is_host() or args.size() != 4 or not args[0] is int or not args[1] is int:
				return
			if not args[2] is Vector3 or (not args[3] is float and not args[3] is int):
				return
			var cat_id: int = args[0]
			var cat_slot: int = args[1]
			var cat_duration: float = float(args[3])
			if not Quantize.is_wire_id(cat_id) or cat_slot < 0 or cat_slot >= _authority().slot_count():
				return
			if not (args[2] as Vector3).is_finite() or not is_finite(cat_duration) or cat_duration <= 0.0 or cat_duration > 60.0:
				return
			_authority().apply_replicated_cat_start(cat_id, cat_slot, args[2], cat_duration)
		MatchNet.EVENT_CAT_ENDED:
			if _session().is_host() or args.size() != 1 or not args[0] is int:
				return
			if not Quantize.is_wire_id(args[0]):
				return
			_authority().end_cat(args[0])
		MatchNet.EVENT_STATE_CHANGED:
			_authority().apply_replicated_state_change(int(args[0]))
		MatchNet.EVENT_COUNTDOWN:
			_authority().apply_replicated_countdown(int(args[0]))
			Events.countdown_tick.emit(int(args[0]))
		MatchNet.EVENT_LOADING_GATE:
			_apply_loading_gate_snapshot(args)
		MatchNet.EVENT_TURN_CHANGED:
			# DECISION (net/MatchNet.gd): offline and in hot-seat,
			# Events.turn_changed means "it is this slot's turn". In real-time
			# networked play there are no turns — every slot plays at once
			# (owner decision, docs/archive/M3a_PLAN.md question 1) — and what the
			# signal actually does on a receiving instance is point the HUD
			# and the ghost at the controls that are live here, which is
			# always your own slot. Mirroring the host's value verbatim would
			# aim this client's whole UI at another player, so outside
			# hot-seat a client substitutes its own slot. ui/HUD.gd and
			# game/PlayerController.gd therefore need no networking of their
			# own.
			var turn_slot: int = int(args[0])
			var running: MatchConfig = _authority().config
			# Turn-based (M6 B4) mirrors the host's slot verbatim like hot-seat:
			# the client-side active-slot gate and turn banner must agree with
			# the host on whose turn it is.
			if running != null and not running.is_sequential_play():
				turn_slot = int(_session().local_slot())
			if turn_slot < 0:
				return
			_authority().apply_replicated_turn(turn_slot)
			Events.turn_changed.emit(turn_slot)
		MatchNet.EVENT_FEED_ISSUED:
			_authority().apply_replicated_feed(
				int(args[0]),
				StringName(args[1]),
				StringName(args[2]),
				int(args[3]) if args.size() > 3 else -1,
				float(args[4]) if args.size() > 4 else -1.0,
				bool(args[5]) if args.size() > 5 else false
			)
			Events.feed_block_issued.emit(int(args[0]), StringName(args[1]), StringName(args[2]))
		MatchNet.EVENT_FEED_EXPIRED:
			Events.feed_timer_expired.emit(int(args[0]))
		MatchNet.EVENT_GIFT_SLOT:
			if _session().is_host() or args.size() != 4 or not args[0] is int or not args[1] is Array:
				return
			if not (args[2] is String or args[2] is StringName) or not (args[3] is String or args[3] is StringName):
				return
			if args[0] < 0 or args[0] >= _authority().slot_count() or (args[1] as Array).size() > QolExperiments.GIFT_SLOT_CAPACITY_CEILING:
				return
			var slot_contents: Array = []
			for entry: Variant in args[1]:
				if not (entry is String or entry is StringName) or not _net._gift_special_id_wire_ok(String(entry)):
					return
				slot_contents.append(StringName(entry))
			var activated_special: StringName = StringName(args[2])
			var carrier_id: StringName = StringName(args[3])
			if activated_special != &"" and (not _net._gift_special_id_wire_ok(String(activated_special)) or _authority()._feed._shape_by_id(carrier_id) == null):
				return
			_authority().apply_replicated_gift_slot(args[0], slot_contents, activated_special, carrier_id)
		MatchNet.EVENT_QOL_FEED:
			if _session().is_host() or args.size() != 3 or not args[0] is int or not args[1] is int or not args[2] is bool:
				return
			if args[0] < 0 or args[0] >= _authority().slot_count():
				return
			_authority().apply_replicated_qol(args[0], args[1], args[2])
			Events.qol_feed_changed.emit(args[0], args[1], args[2])
		MatchNet.EVENT_PLACEMENT_REJECTED:
			# Bontago-1pi.52: an input boundary like every other wire payload
			# here, and a refusal is the refused player's own feedback: the
			# host now sends it to the owning peer alone, so anything naming a
			# slot this instance does not drive (an older host's broadcast, the
			# host's own seat) is dropped rather than sounded.
			if _session().is_host() or args.size() != 2 or not args[0] is int:
				return
			if not (args[1] is String or args[1] is StringName):
				return
			var rejected_slot: int = args[0]
			if rejected_slot < 0 or rejected_slot >= _authority().slot_count():
				return
			if String(args[1]).length() > MatchNet.REJECT_REASON_MAX_LENGTH:
				return
			if not bool(_session().is_local_slot(rejected_slot)):
				return
			Events.placement_rejected.emit(rejected_slot, StringName(args[1]))
		MatchNet.EVENT_PLACEMENT_RELOCATED:
			# Bontago-1pi.52: an input boundary like the refusal above, with
			# the same own-seat-only rule: the host sends this to the owning
			# peer alone, so another seat's relocation (an older host's
			# broadcast) or a malformed or out-of-disk point never reaches
			# the cursor/camera jump.
			if _session().is_host() or args.size() != 2 or not args[0] is int or not args[1] is Vector2:
				return
			var relocated_slot: int = args[0]
			var relocated_point: Vector2 = args[1]
			if _authority().config == null or relocated_slot < 0 or relocated_slot >= _authority().slot_count():
				return
			var point_bound: float = float(_authority().circle_wire_xz_bound())
			if not relocated_point.is_finite() or absf(relocated_point.x) > point_bound or absf(relocated_point.y) > point_bound:
				return
			if not bool(_session().is_local_slot(relocated_slot)):
				return
			Events.placement_relocated.emit(relocated_slot, relocated_point)
		MatchNet.EVENT_PLAYER_ELIMINATED:
			_authority().apply_replicated_elimination(int(args[0]))
			Events.player_eliminated.emit(int(args[0]), int(args[1]))
		MatchNet.EVENT_MATCH_WON:
			Events.match_won.emit(int(args[0]))
		MatchNet.EVENT_MODE_STATE:
			# Bontago-22y.11: display-only mirror; a client never derives an
			# outcome from it. Malformed payloads are dropped, not defaulted.
			if args.size() < 1:
				return
			var mode_state: Dictionary = ResultsValidation.validate_mode_state(args[0])
			if mode_state.is_empty():
				return
			_authority().apply_replicated_mode_state(mode_state)
		MatchNet.EVENT_MATCH_RESULTS:
			# Bontago-1pi.13: an input boundary exactly like every other wire
			# payload in this dispatch -- a malformed or truncated args array
			# (an older/ancient build) must not reach a results-screen
			# consumer half-typed. See MatchStats.validate_results_payload()'s
			# own doc comment for why this rejects rather than defaults.
			if args.size() < 1:
				return
			var validated: Dictionary = ResultsValidation.validate_results_payload(args[0])
			if validated.is_empty():
				return
			Events.match_results_ready.emit(validated)
		MatchNet.EVENT_LIVE_SCORES:
			if _session().is_host() or args.size() < 1:
				return
			var live: Dictionary = ResultsValidation.validate_results_payload(args[0])
			if live.is_empty():
				return
			_authority().stats().apply_live_snapshot(live)
		MatchNet.EVENT_GIFT_FLIGHT:
			if args.size() != 3 or not args[0] is int or not args[1] is Vector3 or not args[2] is Vector3:
				return
			var gift_id: int = args[0]
			var origin: Vector3 = args[1]
			var landing: Vector3 = args[2]
			if gift_id < 0 or not origin.is_finite() or not landing.is_finite():
				return
			if not is_finite(origin.distance_to(landing)) or origin.y < landing.y:
				return
			if _net._gift_wire_phases.has(gift_id) and int(_net._gift_wire_phases[gift_id]) != MatchNet.GiftWirePhase.LEGACY:
				return
			_authority().apply_replicated_gift_flight(gift_id, origin, landing)
			_net._set_gift_wire_phase(gift_id, MatchNet.GiftWirePhase.FALLING)
			Events.gift_flight_spawned.emit(gift_id, origin, landing)
		MatchNet.EVENT_GIFT_LANDED:
			if args.size() != 2 or not args[0] is int or not args[1] is Vector3:
				return
			var gift_id: int = args[0]
			var landing: Vector3 = args[1]
			if gift_id < 0 or not landing.is_finite() or _net._gift_wire_phases.get(gift_id, -1) != MatchNet.GiftWirePhase.FALLING:
				return
			var state: Dictionary = _authority().gift_state(gift_id)
			if state.is_empty() or not landing.is_equal_approx(state["landing"]):
				return
			_authority().apply_replicated_gift_landed(gift_id, landing)
			_net._set_gift_wire_phase(gift_id, MatchNet.GiftWirePhase.LANDED)
			Events.gift_landed.emit(gift_id, landing)
		MatchNet.EVENT_GIFT_SPAWNED:
			if args.size() != 2 or not args[0] is int or not args[1] is Vector2:
				return
			var gift_id: int = int(args[0])
			var position: Vector2 = args[1] as Vector2
			if _net._gift_spawn_notified.has(gift_id) or not _net._gift_wire_ok(gift_id, position) or _net._gift_wire_phases.get(gift_id, -1) in [MatchNet.GiftWirePhase.LEGACY, MatchNet.GiftWirePhase.LANDED, MatchNet.GiftWirePhase.REMOVED]:
				return
			if not _net._gift_wire_phases.has(gift_id):
				_net._set_gift_wire_phase(gift_id, MatchNet.GiftWirePhase.LEGACY)
			_authority().apply_replicated_gift_spawned(gift_id, position)
			_net._gift_spawn_notified[gift_id] = true
			Events.gift_spawned.emit(gift_id, position)
		MatchNet.EVENT_GIFT_CLAIMED:
			if args.size() != 4 or not args[0] is int or not args[1] is int or not (args[2] is String or args[2] is StringName) or not (args[3] is String or args[3] is StringName):
				return
			var claimed_gift_id: int = int(args[0])
			if claimed_gift_id < 0 or _net._gift_wire_phases.get(claimed_gift_id, -1) == MatchNet.GiftWirePhase.REMOVED:
				return
			var slot_id: int = int(args[1])
			# Review fix (Must #1): bounds-check slot_id here too, next to the
			# id<0 check above, so a garbage value never even reaches
			# MatchGifts.apply_replicated_claim() (which now also refuses it,
			# defense in depth) or the Events bus other listeners read.
			if slot_id < 0 or slot_id >= _authority().slot_count():
				return
			# Orchestrator amendment 1 (M4 P2b): the third argument is the
			# special id drawn for this claim. A short args array (an older
			# or malformed sender) is dropped rather than defaulted, unlike
			# MatchNet.EVENT_FEED_ISSUED's optional trailing fields -- there is no
			# safe "not sent" default for a special id the way there is for
			# an unset feed_time_left.
			if args.size() < 3:
				return
			var special_id: StringName = StringName(args[2])
			if not _net._gift_special_id_wire_ok(String(special_id)):
				return
			var gift_shape_id: StringName = StringName(args[3])
			if _authority()._feed._shape_by_id(gift_shape_id) == null:
				return
			_net._set_gift_wire_phase(claimed_gift_id, MatchNet.GiftWirePhase.REMOVED)
			if _authority().gift_slot_enabled():
				# Bontago-1pi.18.2: the gift went to the slot (MatchNet.EVENT_GIFT_SLOT),
				# not the block queue; only the crate visual is retired here.
				_authority().apply_replicated_gift_expired(claimed_gift_id)
			else:
				_authority().apply_replicated_gift_claimed(claimed_gift_id, slot_id, special_id)
				_authority()._feed.apply_replicated_next_gift(slot_id, gift_shape_id)
			Events.gift_claimed.emit(claimed_gift_id, slot_id, special_id)
		MatchNet.EVENT_GIFT_EXPIRED:
			if args.size() != 1 or not args[0] is int:
				return
			var expired_gift_id: int = int(args[0])
			if expired_gift_id < 0 or _net._gift_wire_phases.get(expired_gift_id, -1) == MatchNet.GiftWirePhase.REMOVED:
				return
			_net._set_gift_wire_phase(expired_gift_id, MatchNet.GiftWirePhase.REMOVED)
			_authority().apply_replicated_gift_expired(expired_gift_id)
			Events.gift_expired.emit(expired_gift_id)
		MatchNet.EVENT_SPECIAL_TRIGGERED:
			# M4 P2c-ii: mirrors game/specials/SpecialBehavior.gd's own trigger
			# to every client -- a client runs no SpecialBehavior of its own
			# (Events.special_triggered is only ever emitted host-side, see
			# _on_special_triggered() above), so this dispatch is the only
			# place a client ever learns a special fired; it is a purely
			# read-model/effects signal (Known limitations: no remote arm/
			# trigger visuals yet), never fed back into Match.
			#
			# Review fix (Should #1): a short args array (an older or
			# malformed sender) is dropped before any args[1..3] read, exactly
			# MatchNet.EVENT_GIFT_CLAIMED's own args.size() guard above -- args[0]
			# alone is safe to read unconditionally (net_match_event's own
			# dispatch never calls with an empty array), but nothing past it
			# is, and no partial state (a queued net_id with no matching
			# emit) may result from a truncated payload.
			if args.size() < 4:
				return
			var triggered_net_id: int = int(args[0])
			if triggered_net_id < 0:
				return
			var triggered_def_id: StringName = StringName(args[1])
			if not _net._special_id_wire_ok(String(triggered_def_id)):
				return
			var triggered_position: Vector3 = args[2] as Vector3
			if not triggered_position.is_finite():
				return
			var chain_depth: int = int(args[3])
			if chain_depth < 0 or chain_depth > _net._special_tuning.max_chain_depth:
				return
			Events.special_triggered.emit(triggered_net_id, triggered_def_id, triggered_position, chain_depth)
		MatchNet.EVENT_SPECIAL_CONSUMED:
			# DECISION (net/MatchNet.gd, Bontago-1en.21): unlike this match's
			# other cases, this one guards `_session().is_host()` itself rather than
			# relying only on net_match_event's own @rpc("authority", ...)
			# annotation -- a well-behaved client never sends this RPC at all
			# (only the host ever fires Events.special_consumed for a real
			# pop; see MatchGifts.pop_pending_special()'s own doc comment),
			# so this dispatch has no legitimate host-side caller. Popping
			# the host's own authoritative queue a second time for an
			# already-spent special (a stale duplicate, or a spoofed direct
			# call) would silently desync it from every client's mirror with
			# no wire message able to undo it, so the host refuses to ever
			# apply one to itself, belt-and-braces on top of the RPC config.
			if _session().is_host():
				return
			# Bontago-1en.21: a short args array (an older or malformed
			# sender) is dropped before either arg is read, exactly
			# MatchNet.EVENT_GIFT_CLAIMED's/MatchNet.EVENT_SPECIAL_TRIGGERED's own guard.
			if args.size() < 2:
				return
			var consumed_slot_id: int = int(args[0])
			if consumed_slot_id < 0 or consumed_slot_id >= _authority().slot_count():
				return
			var consumed_special_id: StringName = StringName(args[1])
			# Only the syntactic shape check, not _net._gift_special_id_wire_ok()'s
			# roster-membership tightening: exactly MatchNet.EVENT_SPECIAL_TRIGGERED's
			# own reasoning (_net._known_special_ids()'s doc comment above) -- a
			# special already popped and consumed on the host is by
			# construction an id MatchNet.EVENT_GIFT_CLAIMED already roster-checked
			# when it was queued; nothing here needs to reject one a
			# client's own (possibly stale) roster cache does not recognise.
			if not _net._special_id_wire_ok(String(consumed_special_id)):
				return
			_authority().apply_replicated_special_consumed(consumed_slot_id, consumed_special_id)
			Events.special_consumed.emit(consumed_slot_id, consumed_special_id)
		MatchNet.EVENT_GLUE_CHARGES:
			if _session().is_host() or args.size() != 3:
				return
			if not args[0] is int or not args[1] is int or not args[2] is int:
				return
			var glue_slot: int = args[0]
			var charges: int = args[1]
			var revision: int = args[2]
			if glue_slot < 0 or glue_slot >= _authority().slot_count():
				return
			if charges < 0 or charges > 100 or revision <= 0:
				return
			_authority().apply_replicated_glue_charges(glue_slot, charges, revision)
		MatchNet.EVENT_BLOCK_DISSOLVE_STARTED:
			# Bontago-1pi.11.41: presentation only. An unknown id (a spawn the
			# client never built) or a malformed payload is dropped.
			if _session().is_host() or args.size() != 1 or not args[0] is int:
				return
			var dissolving_id: int = args[0]
			if not Quantize.is_wire_id(dissolving_id):
				return
			var dissolve_registry: Node = _authority().registry()
			if dissolve_registry == null:
				return
			var dissolving: BlockBody = dissolve_registry.block_for_net_id(dissolving_id)
			if dissolving == null or not is_instance_valid(dissolving):
				return
			Events.block_dissolve_started.emit(dissolving, dissolving_id, _net._hole_dissolve_tuning.dissolve_delay_s)
		MatchNet.EVENT_SLOT_REPLAY:
			if _session().is_host():
				return
			_net._apply_slot_replay(args)
		MatchNet.EVENT_MATCH_CLOCK:
			if _session().is_host() or args.size() != 1 or not (args[0] is float or args[0] is int):
				return
			var clock: float = float(args[0])
			if not is_finite(clock) or clock < 0.0:
				return
			# DECISION (Bontago-8or.11): the client's read model of the match
			# timer is written directly, the way this file already reaches
			# _lifecycle/_feed elsewhere -- autoload/Match.gd and
			# MatchLifecycle.gd are outside this package. A client never
			# ticks it; timed modes keep it current through MatchNet.EVENT_MODE_STATE.
			_authority()._lifecycle._match_timer_left = clock
		MatchNet.EVENT_BLOCK_OWNER_CHANGED:
			if _session().is_host() or args.size() != 2 or not args[0] is int or not args[1] is int:
				return
			var painted_id: int = args[0]
			var painted_slot: int = args[1]
			if not Quantize.is_wire_id(painted_id) or painted_slot < 0 or painted_slot >= _authority().slot_count():
				return
			_authority().apply_replicated_block_owner(painted_id, painted_slot)
		MatchNet.EVENT_BLOCK_GLUED:
			if _session().is_host() or args.size() != 2 or not args[0] is int or not args[1] is bool:
				return
			var glued_id: int = args[0]
			if not Quantize.is_wire_id(glued_id):
				return
			var glued_registry: Node = _authority().registry()
			if glued_registry == null:
				return
			var glued_block: BlockBody = glued_registry.block_for_net_id(glued_id)
			if glued_block != null and is_instance_valid(glued_block):
				_net._set_block_coated(glued_block, args[1])
		MatchNet.EVENT_BLOCK_FROZEN:
			if _session().is_host() or args.size() != 2 or not args[0] is int or not args[1] is bool:
				return
			var frozen_id: int = args[0]
			if not Quantize.is_wire_id(frozen_id):
				return
			var frozen_registry: Node = _authority().registry()
			if frozen_registry == null:
				return
			var frozen_block: BlockBody = frozen_registry.block_for_net_id(frozen_id)
			if frozen_block == null or not is_instance_valid(frozen_block):
				return
			if frozen_block.is_frozen_visual() != args[1]:
				frozen_block.set_frozen_visual(args[1])
				Events.block_frozen_changed.emit(frozen_id, args[1])
		_:
			pass


## Bontago-1pi.42, client: the replayed loading-gate snapshot [ready_ids,
## required_ids, open], applied through the same Events a live broadcast uses (the
## lifecycle's mirror and the loading screen listen to those). Host-authored only;
## every field is validated like Net._rpc_loading_ready_state (wire limit, ids).
func _apply_loading_gate_snapshot(args: Array) -> void:
	if _session().is_host() or args.size() != 3:
		return
	if not args[0] is PackedInt32Array or not args[1] is PackedInt32Array or not args[2] is bool:
		return
	var ready_ids: PackedInt32Array = args[0]
	var required_ids: PackedInt32Array = args[1]
	if ready_ids.size() > _net.config.max_peers or required_ids.size() > _net.config.max_peers:
		return
	for peer_id: int in ready_ids:
		if peer_id < Net.HOST_PEER_ID:
			return
	for peer_id: int in required_ids:
		if peer_id < Net.HOST_PEER_ID:
			return
	Events.loading_ready_changed.emit(ready_ids, required_ids)
	if bool(args[2]):
		Events.loading_gate_opened.emit()
