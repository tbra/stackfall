class_name MatchPlacement
extends RefCounted
## Match's one authoritative entry point (spec 3.4): request_place(), pose
## validation, the pure outcome-resolution seam, spawn/burn and the blocks-
## spawned counter.
##
## Split out of autoload/Match.gd (pure refactor: no behaviour change). See
## that file's own header comment for the state machine this placement logic
## serves.

## Bontago-mv0.1.11, revised Bontago-mv0.2.6 (independent-review finding C):
## how far inside Field's kill-plane box a burned block's spawn point is kept,
## as a fraction of the box's half-extent. _burn_block() then adds an outward
## impulse (TerritoryTuning.reject_impulse / reject_upward_fraction) before
## the body falls through kill_plane_y, so the clamp must leave enough slack
## for that impulse's own horizontal travel, not just spawn the body inside
## the box.
##
## DECISION (autoload/Match.gd, Bontago-mv0.2.6): 0.9 left only
## `field_radius` (30-60 m across the shipped maps) of slack to the box edge.
## reject_impulse=30 on a mass-1 block with reject_upward_fraction=0.35 gives
## a horizontal launch speed of impulse * (1 - up_fraction) / sqrt((1 -
## up_fraction)^2 + up_fraction^2) ~= 26 m/s and enough hang time falling to
## kill_plane_y (-40) to travel roughly field_radius*2 outward -- more than
## the old margin's slack, so a maximally clamped hostile burn could exit the
## box footprint before it ever reached kill_plane_y and free-fall forever
## (see this file's own request_place() comment on the leaked-RigidBody3D
## failure this clamp exists to prevent). Halving the margin to 0.5 (clamp
## radius = half the box half-extent) makes the reserved slack equal to the
## clamp radius itself (>= 150 m on the smallest map), comfortably above the
## worst-case impulse travel above, without touching _burn_block()'s impulse
## for a legitimate near-disk burn (docs/M2_PLAN.md owner decision 2) --
## proven by tests/unit/test_match_flow.gd's
## test_repro_burn_clamp_margin_lets_a_maximally_clamped_burn_escape_the_kill_plane.
const _BURN_CLAMP_MARGIN: float = 0.5

var _match: MatchAutoload = null

## Blocks _spawn_block() has built since the match started. The acceptance
## harness asserts blocks_spawned() == sum(intents_accepted) + auto_drops
## across the session (docs/M3a_PLAN.md, "Proving placements are never
## duplicated or lost").
var _blocks_spawned: int = 0

## M4 P2c: request_throw()'s own tunable (throw_max_speed) -- preloaded here
## rather than added to autoload/Match.gd's field set (that file, per this
## package's own file ownership, gets only a one-line forward), the same way
## Match.gd itself preloads _physics_tuning/_territory_tuning etc.
var _special_tuning: SpecialTuning = preload("res://config/special_tuning.tres")
var _glue_drop_tuning: GlueDropTuning = preload("res://config/glue_drop_tuning.tres")
var _ghost_tuning: GhostTuning = preload("res://config/ghost_tuning.tres")
# DECISION (Bontago-1pi.14 round 3): numeric guards, not gameplay tunables --
# a floor so a zero/negative step cannot loop forever, and float slack so the
# final step landing on the cap is still tried.
const MIN_CLEARANCE_STEP: float = 0.001
const CLEARANCE_CAP_EPSILON: float = 0.0001

## _spawn_block()'s SpecialDef-by-id cache (M4 P2c), rebuilt once per match:
## `_special_defs_config` is compared by *identity*, not equality, against
## `_match.config` -- autoload/match/MatchLifecycle.gd's start_match()
## replaces that field with a fresh `match_config.duplicate(true)` every
## match, so a changed reference alone means "a new match started", with no
## reset() hook of this package's own needed on a file it does not own.
var _special_defs_by_id: Dictionary = {}
var _special_defs_config: MatchConfig = null

## _attach_pending_special()'s per-id warning gate: an empty config/specials/
## roster (P3-P5 not landed yet) or a misconfigured drawer would otherwise
## push_warning on every single spawn once gifts are common, drowning any
## other warning in the log. DECISION (autoload/match/MatchPlacement.gd, M4
## P2c): warn once per distinct bad id for the life of the process rather
## than once per match or every occurrence -- surfaces a genuinely stuck
## drawer/roster bug without spamming it.
var _warned_special_ids: Dictionary = {}


## Bontago-1pi.85.35: in-place gift activation (see MatchGiftActivation).
var _activation: MatchGiftActivation = MatchGiftActivation.new()


func setup(match_ref: MatchAutoload) -> void:
	_match = match_ref
	_activation.setup(match_ref)


# --- The one authoritative entry point (spec 3.4) ---------------------------

## Every placement in the game goes through here, local or remote. `origin` is
## the world position the block's local origin would sit at, `orientation_index`
## the BlockOrientations index and `free_quat` the free rotation layered on it
## (spec 2.5). `auto_drop` is true when the slot's timer ran out rather than
## the player clicking, which is the only case where the host relocates the
## block to the closest valid point instead of rejecting it (spec 2.5).
##
## Returns PlacementRules.REASON_OK on success, otherwise the REASON_* that
## explains the refusal, which is also emitted as Events.placement_rejected.
##
## Bontago-mv0.24 (owner test 2026-09-22, supersedes spec 2.2's older "thrown
## off the map with a visible reject animation" line for this case): a
## refused *deliberate* (auto_drop == false) placement spawns nothing and
## consumes nothing — the piece stays held, feed_seq does not advance, and
## the caller may try again. A refused auto-drop that finds no valid point to
## relocate to still spawns the block and throws it off the map, since spec
## 2.5's forced release has nowhere else to put it; one that does find a
## valid point relocates there instead and emits Events.placement_relocated.
##
## M3a wraps this in net/MatchNet.gd's `@rpc("any_peer", "call_remote",
## "reliable")` intent, which checks the caller's peer id against `slot_id`
## and changes nothing else. `feed_seq` is the value of feed_seq(slot_id) the
## caller last saw; -1 means "don't check", which is what every M2 call site
## passes by omitting it. A value that is not current means the intent is a
## replay, a double click inside one round trip, or a race with an auto-drop,
## and is refused with REASON_NO_BLOCK — the whole of docs/M3a_PLAN.md's
## "Never duplicated, never lost" defence (1).
##
## The -1 sentinel is a courtesy for **trusted local callers only**: the M2
## controllers, the host's own timer and the tests. It never arrives here from
## the wire — net/MatchNet.gd refuses any negative remote feed_seq before
## calling in — because a client that could quote -1 would opt out of defence
## (1) altogether.
##
## A pose that cannot be evaluated at all (a non-finite origin, a free
## quaternion that is not a finite unit rotation, or an orientation index
## outside BlockOrientations' table) is refused with REASON_NO_BLOCK before
## anything is touched. That is not a rule — the ghost can never produce such
## a pose — but the authority's own guard against corrupt or hostile input
## (spec 3.4: "The host checks every intent before acting on it"); MatchNet
## refuses the same poses at the wire so they are normally never seen here.
func request_place(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	auto_drop: bool,
	feed_seq: int = -1
) -> StringName:
	# Spec 3.4: the host decides every placement. A client that somehow got
	# here locally must not spawn anything; it waits for the host's spawn.
	if not _match._is_host():
		return PlacementRules.REASON_NO_BLOCK
	if not MatchLifecycle.is_live_state(_match.state()) or _match._field == null or _match._blocks_parent == null:
		return PlacementRules.REASON_NO_BLOCK
	if slot_id < 0 or slot_id >= _match.slot_count():
		return PlacementRules.REASON_NO_BLOCK
	if feed_seq >= 0 and feed_seq != _match.feed_seq(slot_id):
		return PlacementRules.REASON_NO_BLOCK
	var acting_slot: PlayerSlot = _match.slot(slot_id)
	if not acting_slot.home_flag_alive:
		return PlacementRules.REASON_NO_BLOCK
	if (
		(_match.config.hot_seat or _match.config.turn_based)
		and slot_id != _match.active_slot()
	):
		return PlacementRules.REASON_NOT_YOUR_TURN
	var shape: BlockShape = _match.held_shape(slot_id)
	if shape == null:
		return PlacementRules.REASON_NO_BLOCK
	if not auto_drop and _match.is_release_locked(slot_id):
		# Bontago-mv0.10 (spec 2.4 "[ORIGINAL target]" cadence): this slot
		# already spent this interval's one release early and is only
		# preparing/aiming the next piece; it may not be released again
		# before the interval boundary unlocks it.
		#
		# DECISION (autoload/Match.gd): reuses REASON_NO_BLOCK rather than a
		# new PlacementRules.REASON_* constant -- PlacementRules.gd lives in
		# core/, which this package does not own, and REASON_NO_BLOCK already
		# means exactly "nothing was spent" to every caller: MatchNet's
		# _consumed_a_block() already classifies it as a no-op, and the ghost
		# already reacts to any non-OK, non-territory reason without a burn.
		# auto_drop is exempt because it is never a player's own click -- it
		# is the host's own forced release at the interval boundary, which is
		# exactly what ends the lock (see _consume_and_refeed()).
		return PlacementRules.REASON_NO_BLOCK
	if not is_pose_well_formed(origin, orientation_index, free_quat):
		return PlacementRules.REASON_NO_BLOCK

	var basis: Basis = Basis(free_quat) * BlockOrientations.get_basis(orientation_index)
	var local_origin: Vector3 = _match._field.to_local(origin)
	var disk_origin: Vector2 = Vector2(local_origin.x, local_origin.z)
	var team_id: int = acting_slot.team_id

	# DECISION (autoload/Match.gd, Bontago-cmc.7): every MatchConfig.HoleMode
	# now uses one raycast straight down from `origin` plus
	# PlacementRules.validate_point(), not just the old v2-only OFF default.
	# SPEC.md's 2026-09-20 evidence audit, 2.5 "Placement legality": "cast one
	# ray straight down from the ghost's middle... Do not require the whole
	# footprint to fit... not permission to reintroduce footprint territory
	# tests." validate_point() itself now also rejects a contested/holed point
	# under the legacy fill (TerritoryRaster._fill_legacy(), which
	# TEMPORARY/PERMANENT still run every solve), so the point path alone
	# already reports every case the footprint chain used to.
	# footprint_cells()/validate()/closest_valid_origin() stay compiled for
	# tests/bench/bench_territory.gd's legacy regression row and their own
	# direct unit tests only; this call site never reaches them.
	var result: PlacementRules.Result
	var relocated: Vector2 = PlacementRules.NO_ORIGIN
	var hit: Variant = _match._field.raycast_down_disk_local(origin)
	if hit == null:
		# Only possible off the rim with nothing beneath (Field.gd's own
		# contract for raycast_down_disk_local); disk_origin keeps the flat
		# projection computed above, which is what the burn clamp below
		# throws from.
		result = PlacementRules.Result.OFF_DISK
	else:
		disk_origin = hit as Vector2
		result = PlacementRules.validate_point(disk_origin, _match.raster(), team_id)
		# DECISION (autoload/match/MatchPlacement.gd, docs/M6_PLAN.md package
		# B1, spec 2.7 "Sandbox: no territory limits"): only the two
		# territory-ownership outcomes are waived here -- OFF_DISK (the
		# hit == null branch above, which never reaches this remap), HOLE and
		# GOAL_ZONE all stay refused, since the spec line is "no territory
		# limits", not "place blocks in the void or through a hole/goal
		# zone". core/rules/PlacementRules.gd itself stays config-agnostic;
		# this is the one call site that already knows about config.sandbox
		# (autoload/match/MatchLifecycle.gd:121's own precedent).
		result = _apply_territory_waiver(slot_id, result)  # Bontago-sen.1: held gift waives territory (host state)
	if result != PlacementRules.Result.VALID and auto_drop:
		relocated = PlacementRules.closest_valid_point(disk_origin, _match.raster(), team_id, _match._territory_tuning)
	var outcome: Dictionary = _resolve_outcome(result, auto_drop, relocated)
	var reason: StringName = outcome["reason"]

	if reason != PlacementRules.REASON_OK and not auto_drop:
		# DECISION (autoload/match/MatchPlacement.gd, Bontago-mv0.24, owner test
		# 2026-09-22): a manual out-of-zone release is refused outright, not
		# burned -- the previous "thrown off the map with a visible reject
		# animation" spawn (spec 2.2) is unreachable from here now; nothing is
		# spawned or consumed, feed_seq does not move, and _match._feed's
		# release lock (if any) is never touched, so the caller may simply try
		# again. This makes the far-off-disk burn/clamp path below (and
		# net/MatchNet.gd's matching _consumed_a_block()) reachable only for
		# auto_drop == true, where spec 2.5's forced release still has to land
		# somewhere. See Events.placement_rejected's own doc comment.
		Events.placement_rejected.emit(slot_id, reason)
		return reason

	var final_disk_origin: Vector2 = relocated if outcome["use_relocation"] else disk_origin
	if reason != PlacementRules.REASON_OK:
		# Bontago-mv0.1.11: this is the burn path (docs/M2_PLAN.md owner
		# decision 2 below), now reachable only for auto_drop == true (see the
		# early return above) -- the last cursor MatchNet stored for a remote
		# slot is finite-but-arbitrary (spec 3.4: "The host checks every intent
		# before acting on it"; is_pose_well_formed() above only refuses
		# non-finite poses, not far-off-disk ones). Left unclamped, a block
		# spawns and is thrown from that raw point, lands outside Field's kill
		# plane, and free-falls forever: a leaked RigidBody3D plus permanent
		# snapshot traffic for it (Field.gd's _build_kill_plane, not owned
		# here, sizes the box at map_def.field_radius *
		# Field.KILL_PLANE_RADIUS_FACTOR).
		final_disk_origin = _clamp_disk_origin_for_burn(final_disk_origin)

	# Bontago-mv0.12 + Bontago-cmc.7, updated Bontago-mv0.17 item 3: `origin`
	# is the shape's bottom-centre pivot (GhostPreview/BlockFactory both pivot
	# there now, rotated-shape corrected -- see GhostPreview's own DECISION)
	# and the point test above works on that same x/z, so final_disk_origin
	# already is the frame the spawned body's origin needs -- no cell-
	# (0, 0, 0) offset and no height correction to add back here.
	var final_world_origin: Vector3 = _match._field.to_global(Vector3(
		final_disk_origin.x, local_origin.y, final_disk_origin.y
	))
	if reason == PlacementRules.REASON_OK:
		# Bontago-1pi.85.35: an in-place gift activates here, with no carrier body.
		# An ordinary piece (held id &"") never queries the special roster.
		var held_id: StringName = _match.held_special(slot_id)
		var in_place_def: SpecialDef = _resolve_deliverable_special(held_id) if held_id != &"" else null
		if in_place_def != null and in_place_def.activates_in_place and _activation.try_activate(slot_id, in_place_def, final_disk_origin):
			_match._feed._consume_and_refeed(slot_id, auto_drop)
			if _match.config.hot_seat:
				_match.advance_turn()
			elif _match.config.turn_based:
				_match._lifecycle.begin_turn_settle_wait()
			return PlacementRules.REASON_OK
		# Bontago-1pi.14 round 3: host-side spawn validation (see _lift_pose_clear()).
		var lifted: Variant = _lift_pose_clear(shape, final_world_origin, basis, auto_drop, _held_deliverable_gift(slot_id) if reason == PlacementRules.REASON_OK else &"")
		if lifted == null:
			Events.placement_rejected.emit(slot_id, PlacementRules.REASON_NO_BLOCK)
			return PlacementRules.REASON_NO_BLOCK
		final_world_origin = lifted as Vector3
	# Bontago-t8x.1: only a non-burn spawn delivers the gift (a burn keeps it queued).
	var gift_id: StringName = _held_deliverable_gift(slot_id) if reason == PlacementRules.REASON_OK else &""
	var spawned: Block = _spawn_block(shape, final_world_origin, basis, slot_id, true, gift_id)
	if reason != PlacementRules.REASON_OK:
		# Owner decision (docs/M2_PLAN.md, "Invalid release — burn the block"),
		# narrowed by Bontago-mv0.24 to auto-drop only (see above): a forced
		# release that finds no valid point to relocate to still spawns the
		# block and throws it off the map; it is still consumed either way.
		#
		# DECISION (autoload/match/MatchPlacement.gd, Bontago-1en.13 review
		# fix, spec 2.5's OPEN "how expiry handles a held special"): a burn
		# must NOT pop/attach the pending special -- _attach_pending_special()
		# is deliberately not called on this path, so an unlucky forced
		# auto-drop that finds nowhere valid to land never destroys a queued
		# special; it stays queued for the slot's next spawn instead.
		#
		# Bontago-xtq.23: PlacementRules.closest_valid_point() now falls back
		# to a full-disk scan (see its own doc comment), so this line is only
		# reachable when slot_id's team genuinely owns no valid point
		# anywhere -- home flag down and every stack lost, not merely far
		# from the ghost. That should be rare enough in a live match that a
		# distinct warning, rather than silence, is worth its noise: a future
		# run that hits this a lot again points straight back here instead of
		# reading as an ordinary relocation.
		push_warning(
			"MatchPlacement: auto-drop burn for slot %d -- no valid point anywhere on the disk (%s)"
			% [slot_id, reason]
		)
		_burn_block(spawned, final_disk_origin)
		if _match._feed.is_held_gift(slot_id):
			_match._gifts.defer_held_special_after_burn(slot_id)
		Events.placement_rejected.emit(slot_id, reason)
	else:
		# The block actually landed somewhere valid -- at the caller's own
		# spot, or (see below) relocated -- so this is the one path allowed
		# to consume the pending special.
		var is_glue_activation: bool = _match.held_special(slot_id) == &"glue"
		_attach_pending_special(spawned, slot_id)
		# A Glue impact grants charges for FUTURE successful drops. Exclude its
		# own activation block even if an earlier Glue buff is still active.
		# This path is never reached by a rejected click, burn, throw or
		# spawn_special_projectile(), so those cannot spend a charge.
		if not is_glue_activation and _match.consume_glue_drop(slot_id):
			var bonding: GlueDrops = GlueDrops.new()
			spawned.add_child(bonding)
			bonding.bind(spawned, _glue_drop_tuning)
		if outcome["use_relocation"]:
			# Bontago-mv0.24: this auto-drop *did* find a valid point and
			# landed there instead of at the caller's raw ghost position --
			# tell the owning client where, so its cursor and camera can jump
			# to match (game/PlayerController.gd's _on_placement_relocated).
			Events.placement_relocated.emit(slot_id, final_disk_origin)

	_match._feed._consume_and_refeed(slot_id, auto_drop)
	if _match.config.hot_seat:
		_match.advance_turn()
	elif _match.config.turn_based:
		_match._lifecycle.begin_turn_settle_wait()

	return reason


## Spec 2.5's throw: releases a pending special with velocity instead of
## dropping it in place (spec 2.5: "Throw strength scales with drag distance,
## capped at throw_max_speed = 25 m/s"; spec 3.4: "request_throw(slot_id,
## pos, orient, velocity): the host clamps velocity to throw_max_speed").
## Mirrors request_place() guard-for-guard (docs/M4_P2_PACKAGES.md P2c:
## "check-for-check identical") through the pose-well-formed gate, then
## diverges: a throw only ever fires a pending special (REASON_NOT_A_SPECIAL
## otherwise, checked before the raycast -- there is nothing to test a point
## for without one), a refused throw is never burned -- the piece stays held
## exactly like a refused manual placement (Bontago-mv0.24's own contract,
## see that function's doc comment) -- and the release velocity is always
## clamped rather than ever being a refusal reason.
##
## `velocity` is world-space, the throw gesture's own launch vector (P2d
## builds it from drag distance/direction, capped again on that side too --
## this clamp is the authoritative one). `feed_seq`/the -1 sentinel are
## exactly request_place()'s own contract.
func request_throw(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	velocity: Vector3,
	feed_seq: int = -1
) -> StringName:
	if not _match._is_host():
		return PlacementRules.REASON_NO_BLOCK
	if not MatchLifecycle.is_live_state(_match.state()) or _match._field == null or _match._blocks_parent == null:
		return PlacementRules.REASON_NO_BLOCK
	if slot_id < 0 or slot_id >= _match.slot_count():
		return PlacementRules.REASON_NO_BLOCK
	if feed_seq >= 0 and feed_seq != _match.feed_seq(slot_id):
		return PlacementRules.REASON_NO_BLOCK
	var acting_slot: PlayerSlot = _match.slot(slot_id)
	if not acting_slot.home_flag_alive:
		return PlacementRules.REASON_NO_BLOCK
	if (
		(_match.config.hot_seat or _match.config.turn_based)
		and slot_id != _match.active_slot()
	):
		return PlacementRules.REASON_NOT_YOUR_TURN
	var shape: BlockShape = _match.held_shape(slot_id)
	if shape == null:
		return PlacementRules.REASON_NO_BLOCK
	if _match.is_release_locked(slot_id):
		# DECISION (autoload/match/MatchPlacement.gd, M4 P2c): request_place()
		# only checks this when `not auto_drop` -- a throw has no auto_drop
		# equivalent at all (the feed timer's forced release always drops
		# wherever the ghost sits, never throws it), so this is unconditional,
		# the same branch request_place() takes for every one of its own
		# deliberate (non-auto_drop) releases.
		return PlacementRules.REASON_NO_BLOCK
	if not is_pose_well_formed(origin, orientation_index, free_quat) or not velocity.is_finite():
		return PlacementRules.REASON_NO_BLOCK
	if _match.held_special(slot_id) == &"":
		return ThrowRules.REASON_NOT_A_SPECIAL
	# Bontago-1pi.85.16 (owner answer 1pi.85.1): only Bomb/Magnet/Jumping Bean are thrown (on a
	# fixed trajectory) and Rocket/Paintball take an aimed launch direction; every other gift
	# refuses a throw (nothing burned, the piece stays held). The client's `velocity` is never
	# used as a launch velocity: THROW keeps only its horizontal heading, AIMED treats it as the
	# camera forward and validates it.
	# DECISION (Bontago-1pi.85.16): the camera forward rides the unchanged throw RPC's
	# `velocity` slot (no new RPC, no replicated camera pose exists to read instead); the host
	# validates length/finiteness and drops the upward part in RocketEffect.
	var held_def: SpecialDef = _resolve_deliverable_special(_match.held_special(slot_id))
	var throw_mode: GiftThrow.Mode = GiftThrow.mode_for(held_def)
	if throw_mode == GiftThrow.Mode.NONE and held_def != null:
		return ThrowRules.REASON_NOT_A_SPECIAL
	# DECISION (Bontago-1pi.85.29): every gift release is camera-aimed now. The unit camera
	# forward is the ONLY thing read from the client's `velocity` slot (finite, length band,
	# 85.21 refusals without consuming); the host derives launch velocity and spawn point from
	# it and SpecialTuning alone (GiftAim), so a client-supplied speed is never trusted.
	var aim_direction: Vector3 = GiftThrow.sanitize_aim(velocity, _special_tuning)
	if aim_direction == Vector3.ZERO:
		return PlacementRules.REASON_NO_BLOCK
	var launch_velocity: Vector3 = Vector3.ZERO
	if held_def == null or throw_mode == GiftThrow.Mode.THROW:
		# An unresolved def (spawns as a plain block) takes the same ballistic throw (85.21).
		launch_velocity = GiftAim.throw_velocity(aim_direction, _special_tuning)
		if launch_velocity == Vector3.ZERO:
			return PlacementRules.REASON_NO_BLOCK
	elif held_def.effect is RocketEffect:
		# Owner 2026-10-06 (1pi.85.34 Q3): any aim, upward included.
		if RocketEffect.sanitize_launch_direction(aim_direction) == Vector3.ZERO:
			return PlacementRules.REASON_NO_BLOCK
	elif RocketEffect.sanitize_downward_direction(aim_direction) == Vector3.ZERO:
		# Paintball keeps the "not upward" rule: a purely vertical aim would be consumed and
		# fall unlaunched, so it is refused without consuming.
		return PlacementRules.REASON_NO_BLOCK

	var gift_id: StringName = _held_deliverable_gift(slot_id)
	# Bontago-1pi.85.21: the overlap/lift check must test the basis _spawn_block() will use.
	var basis: Basis = _spawn_basis(gift_id, Basis(free_quat) * BlockOrientations.get_basis(orientation_index))
	var local_origin: Vector3 = _match._field.to_local(origin)
	var team_id: int = acting_slot.team_id

	# Exactly request_place()'s own raycast-then-point-test (Bontago-cmc.7);
	# ThrowRules.validate_release_point() delegates to the identical
	# PlacementRules.validate_point() so a throw and a placement can never
	# disagree about what "your own territory" means at a point.
	var result: PlacementRules.Result
	var disk_origin: Vector2 = Vector2(local_origin.x, local_origin.z)
	var hit: Variant = _match._field.raycast_down_disk_local(origin)
	if hit == null:
		result = PlacementRules.Result.OFF_DISK
	else:
		disk_origin = hit as Vector2
		result = ThrowRules.validate_release_point(disk_origin, _match.raster(), team_id)
		# DECISION (autoload/match/MatchPlacement.gd, docs/M6_PLAN.md package
		# B1): the throw-path twin of request_place()'s own sandbox remap
		# above -- same waived outcomes, same reasoning.
		# DECISION (Bontago-sen.1): orchestrator ruling -- owner says gifts may be
		# "dropped anywhere", so a host-held gift (always true here, see the
		# NOT_A_SPECIAL guard above) waives territory on the throw path too.
		result = _apply_territory_waiver(slot_id, result)
	if result != PlacementRules.Result.VALID:
		# docs/M4_P2_PACKAGES.md P2c: "a refused throw keeps the piece in
		# hand, like a refused click; never burns" -- mirrors request_place()'s
		# manual-refusal path (Bontago-mv0.24): nothing spawns, nothing is
		# consumed, and the caller may simply try again.
		var reason: StringName = ThrowRules.reason_for(result)
		Events.placement_rejected.emit(slot_id, reason)
		return reason

	var clamped_velocity: Vector3 = launch_velocity.limit_length(_special_tuning.throw_max_speed)
	var world_origin: Vector3 = _match._field.to_global(Vector3(disk_origin.x, local_origin.y, disk_origin.y))
	# Bontago-1pi.14 round 3: the throw spawns at the client-sent pose too, so
	# it gets the same host overlap validation (a manual intent: refused, the
	# special stays in hand, when no lift clears it).
	# Bontago-1pi.85.29: the projectile spawns on the camera line (cursor point moved back along
	# the aim, never below gift_aim_min_height_m over the surface); territory was validated at
	# the cursor above.
	world_origin = GiftAim.spawn_point(world_origin, aim_direction, _match._field.surface_y(), _special_tuning)
	var lifted: Variant = _lift_pose_clear(shape, world_origin, basis, false, gift_id)
	if lifted == null:
		Events.placement_rejected.emit(slot_id, PlacementRules.REASON_NO_BLOCK)
		return PlacementRules.REASON_NO_BLOCK
	world_origin = lifted as Vector3
	var spawned: Block = _spawn_block(
		shape, world_origin, basis, slot_id, true, gift_id
	)
	spawned.linear_velocity = clamped_velocity
	# DECISION (autoload/match/MatchPlacement.gd, M4 P2c): spec 3.5 names
	# "thrown specials" as their own continuous_cd case in the same sentence
	# as "any body moving faster than 15 m/s", but as a case of its own, not
	# conditioned on that speed -- request_throw() only ever reaches this line
	# for a pending special (REASON_NOT_A_SPECIAL above refuses every other
	# call), so every thrown body qualifies unconditionally; no second
	# threshold tunable is read or needed here.
	spawned.continuous_cd = true
	# DECISION (autoload/match/MatchPlacement.gd, Bontago-1en.13 review fix):
	# a throw is never a burn -- every earlier return above already refused
	# anything that would not land -- so this is always the one call that
	# pops/attaches the pending special this throw is spending (see
	# request_place()'s matching call, which is conditional, for why this one
	# is not).
	_attach_pending_special(spawned, slot_id)
	if throw_mode == GiftThrow.Mode.AIMED:
		_apply_aim_direction(spawned, held_def, aim_direction)

	_match._feed._consume_and_refeed(slot_id, false)
	if _match.config.hot_seat:
		_match.advance_turn()
	elif _match.config.turn_based:
		_match._lifecycle.begin_turn_settle_wait()

	return PlacementRules.REASON_OK


## Bontago-1pi.85.16: hands the validated camera forward to the effect that flies along it.
## The Rocket keeps any pitch (1pi.85.34 Q3); Paintball drops an upward part.
func _apply_aim_direction(block: Block, def: SpecialDef, direction: Vector3) -> void:
	if def.effect is RocketEffect:
		RocketEffect.set_launch_direction(block, direction)
	elif def.effect is PaintballEffect:
		PaintballEffect.set_launch_direction(block, direction)


## M4 P4-SPAWN (docs/M4_SPECIALS_PACKAGES.md "P4-SPAWN", prerequisite for
## Volcano): the entry point a special's own SpecialEffect uses to spawn a
## brand-new projectile at runtime -- e.g. Volcano's lava orbs -- rather than
## through a player's own placement/throw gesture. Host-only, using
## request_place()'s own authority guard: returns null and spawns nothing
## off-host. Not a player intent, so unlike request_place()/request_throw()
## this consumes no feed slot and runs no PlacementRules/ThrowRules point
## check -- the caller (an effect's physics_tick(), which SpecialBehavior
## only ever runs host-side, see game/specials/SpecialBehavior.gd) already
## decided the exact world pose and velocity to spawn at.
##
## Follows _spawn_block()'s exact pipeline (BlockFactory.build ->
## _blocks_parent.add_child -> Events.block_placed [allocates net_id] ->
## replicate_spawn), then binds and arms a SpecialBehavior from
## `orb_def`/`orb_tuning` via the same _arm_special_behavior() helper
## _attach_pending_special() uses (see that function's own doc comment for
## why this is a separate helper rather than a duplicate of those four
## lines), then sets the launch velocity. Spec 3.5 names "lava orbs" as
## their own continuous_cd case alongside "any body moving faster than
## 15 m/s" -- `orb_tuning.ccd_speed_threshold_mps` is that same 15 m/s
## number, so continuous_cd is armed whenever this spawn's own speed clears
## it, independent of which special is spawning.
##
## DECISION (autoload/match/MatchPlacement.gd, M4 P4-SPAWN): also guards on
## the same state()/_field/_blocks_parent null checks request_place() opens
## with, even though the brief names only the authority guard -- without them
## a call arriving mid-teardown (e.g. an effect's physics_tick() still queued
## the instant a match aborts) would crash inside _spawn_block() instead of
## returning null the way every other guard here does.
func spawn_special_projectile(
	shape: BlockShape,
	world_origin: Vector3,
	basis: Basis,
	owner_slot: int,
	initial_velocity: Vector3,
	orb_def: SpecialDef,
	orb_tuning: SpecialTuning
) -> Block:
	if not _match._is_host():
		return null
	if not MatchLifecycle.is_live_state(_match.state()) or _match._field == null or _match._blocks_parent == null:
		return null
	if shape == null:
		return null

	# is_player_placement = false (Bontago-1pi.13 review fix): an effect's own
	# projectile spawn (e.g. Volcano's 8-14 lava orbs) must not inflate
	# `owner_slot`'s blocks_placed stat.
	var spawned: Block = _spawn_block(shape, world_origin, basis, owner_slot, false)
	# DECISION (autoload/match/MatchPlacement.gd, Bontago-1en.19 review): a null
	# orb_tuning falls back to the match's preloaded _special_tuning, the same
	# resource _attach_pending_special() uses, instead of crashing the host on
	# the ccd read below when a .tres leaves its tuning export unset.
	var effective_tuning: SpecialTuning = orb_tuning if orb_tuning != null else _special_tuning
	if orb_def != null:
		_arm_special_behavior(spawned, orb_def, effective_tuning)
	spawned.linear_velocity = initial_velocity
	spawned.continuous_cd = initial_velocity.length() > effective_tuning.ccd_speed_threshold_mps
	return spawned


## Bontago-1pi.14 round 3 (owner playtest: dropped blocks get shoved): the
## client lifts its ghost clear of placed blocks as a prediction, but a late
## replication, a rotation or a hostile client can still send a pose that
## interpenetrates a placed block, and Jolt then ejects the older body. The
## host never trusts the pose: it tests the block's collision boxes at that
## transform against every placed body and, if they overlap, lifts the pose
## straight up by the minimum clearance (same rule/tunables as
## PlayerController._raise_ghost_until_clear(), so host and client agree).
## Returns the (possibly lifted) origin, or null when no lift within
## GhostTuning.spawn_clearance_max_raise clears it.
##
## DECISION: an unresolvable manual release is refused like any invalid intent
## (nothing spent); an unresolvable auto-drop still spawns at the maximum lift
## because the forced release must never lose the block.
func _lift_pose_clear(shape: BlockShape, origin: Vector3, basis: Basis, auto_drop: bool, gift_id: StringName = &"") -> Variant:
	var tuning: GhostTuning = _ghost_tuning
	# DECISION: unconditional -- this is intent validation, not the client's
	# predictive lift, so GhostTuning.spawn_clearance_enabled does not gate it.
	if _match._blocks_parent == null:
		return origin
	var world: World3D = _match._blocks_parent.get_viewport().world_3d if _match._blocks_parent.is_inside_tree() else null
	if world == null:
		return origin
	if not _pose_overlaps(world.direct_space_state, shape, origin, basis, tuning, gift_id):
		return origin
	var step: float = maxf(tuning.spawn_clearance_step, MIN_CLEARANCE_STEP)
	var cap: float = tuning.spawn_clearance_max_raise
	var low: float = 0.0
	var high: float = -1.0
	var raise_try: float = step
	while raise_try <= cap + CLEARANCE_CAP_EPSILON:
		var r: float = minf(raise_try, cap)
		if not _pose_overlaps(world.direct_space_state, shape, origin + Vector3.UP * r, basis, tuning, gift_id):
			high = r
			break
		low = raise_try
		raise_try += step
	if high < 0.0:
		return origin + Vector3.UP * cap if auto_drop else null
	for _i: int in range(tuning.spawn_clearance_bisect_steps):
		var mid: float = (low + high) * 0.5
		if _pose_overlaps(world.direct_space_state, shape, origin + Vector3.UP * mid, basis, tuning, gift_id):
			low = mid
		else:
			high = mid
	return origin + Vector3.UP * minf(high + tuning.spawn_clearance, cap)


func _pose_overlaps(space: PhysicsDirectSpaceState3D, shape: BlockShape, origin: Vector3, basis: Basis, tuning: GhostTuning, gift_id: StringName = &"") -> bool:
	var physics: PhysicsTuning = _match._physics_tuning
	# Bontago-1pi.85.32: a gift that spawns enlarged is tested as its one scaled cube (bottom-anchored
	# at the gift cell, like BlockFactory.apply_gift_visual), not as the 1x carrier cells.
	var gift_scale: float = BlockFactory.activation_scale_for(gift_id) if gift_id != &"" else 1.0
	if gift_id != &"" and not is_equal_approx(gift_scale, 1.0):
		var big: BoxShape3D = BoxShape3D.new()
		big.size = Vector3.ONE * ((physics.cube_size - physics.cube_margin) * gift_scale)
		var centre: Vector3 = BlockFactory.gift_cell_center(shape, physics) + Vector3.UP * ((gift_scale - 1.0) * (physics.cube_size - physics.cube_margin) * 0.5)
		var big_params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		big_params.shape = big
		big_params.transform = Transform3D(basis, origin + basis * centre)
		big_params.collide_with_bodies = true
		big_params.collide_with_areas = false
		big_params.collision_mask = Field.PLACEMENT_QUERY_MASK
		for hit: Dictionary in space.intersect_shape(big_params, tuning.collision_probe_max_bodies):
			if hit.get("collider") is RigidBody3D:
				return true
		return false
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3.ONE * (physics.cube_size - physics.cube_margin)
	var pivot: Vector3 = shape.bottom_center()
	for cell: Vector3i in shape.cells:
		var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		params.shape = box
		params.transform = Transform3D(basis, origin + basis * ((Vector3(cell) - pivot) * physics.cube_size))
		params.collide_with_bodies = true
		params.collide_with_areas = false
		params.collision_mask = Field.PLACEMENT_QUERY_MASK
		for overlap: Dictionary in space.intersect_shape(params, tuning.collision_probe_max_bodies):
			if overlap.get("collider") is RigidBody3D:
				return true
	return false


## Whether a pose can be evaluated at all: a finite origin, a free quaternion
## that is a finite unit rotation (Basis(q) of anything else is a scaled or
## NaN matrix, and the footprint built from it is garbage), and an orientation
## index inside BlockOrientations' 24-entry table (get_basis() does not check;
## see BlockOrientations.is_valid_index). Pure and cheap, so request_place()
## and preview_placement() both call it on every pose. Height is deliberately
## not judged here: the allowed band is a wire concern (what a snapshot can
## carry) and lives at net/MatchNet.gd's boundary, so that the host's own
## ghost — exact by construction — is never second-guessed.
func is_pose_well_formed(origin: Vector3, orientation_index: int, free_quat: Quaternion) -> bool:
	if not origin.is_finite():
		return false
	if not free_quat.is_finite() or not free_quat.is_normalized():
		return false
	return BlockOrientations.is_valid_index(orientation_index)


## Pure decision step factored out of request_place() so it can be unit-tested
## against manufactured PlacementRules.Result / relocation values without a
## working P1 territory solve (docs/M2_PLAN.md's P2 brief: "use fakes/stubs
## for territory results — the P1 stubs exist and compile"). `initial_result`
## is what validate() said about the desired spot; `relocated` is what
## closest_valid_origin() found (or PlacementRules.NO_ORIGIN), already
## computed by the caller since that search itself needs a real raster.
##
## Returns {"reason": StringName, "use_relocation": bool}: the reason
## request_place() should return, and whether the block should land at
## `relocated` (true) or stay at the original spot and be thrown off the map
## (false, with reason != REASON_OK) — spec 2.2's "burn the block" rule
## (docs/M2_PLAN.md owner decision 2): any release on an invalid spot burns
## the block; auto-drop gets one relocation attempt first.
func _resolve_outcome(
	initial_result: PlacementRules.Result, auto_drop: bool, relocated: Vector2
) -> Dictionary:
	if initial_result == PlacementRules.Result.VALID:
		return {"reason": PlacementRules.REASON_OK, "use_relocation": false}
	if auto_drop and not PlacementRules.is_no_origin(relocated):
		return {"reason": PlacementRules.REASON_OK, "use_relocation": true}
	return {"reason": PlacementRules.reason_for(initial_result), "use_relocation": false}


## Dry run of request_place()'s territory check, for the ghost's valid/red/
## hatched tint (spec 2.5). One raycast plus one point test, matching
## request_place() under every MatchConfig.HoleMode (Bontago-cmc.7); safe to
## call every frame.
func preview_placement(
	slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion
) -> PlacementRules.Result:
	if not MatchLifecycle.is_live_state(_match.state()) or _match.cell_grid() == null or _match.raster() == null or _match._field == null:
		return PlacementRules.Result.EMPTY
	if slot_id < 0 or slot_id >= _match.slot_count():
		return PlacementRules.Result.EMPTY
	if _match.held_shape(slot_id) == null:
		return PlacementRules.Result.EMPTY
	if not is_pose_well_formed(origin, orientation_index, free_quat):
		return PlacementRules.Result.EMPTY

	var team_id: int = _match.team_of(slot_id)
	# Runs the exact same raycast + point test request_place() will use, on
	# whichever machine calls it (host or a client's own frozen-body world;
	# see Field.raycast_down_disk_local's DECISION), so the ghost's tint
	# always matches what the host would decide (docs/TERRITORY_V2_PLAN.md).
	var hit: Variant = _match._field.raycast_down_disk_local(origin)
	if hit == null:
		return PlacementRules.Result.OFF_DISK
	var preview_result: PlacementRules.Result = PlacementRules.validate_point(hit as Vector2, _match.raster(), team_id)
	# Bontago-sen.1: mirrors request_place(): a held gift ignores territory.
	return _apply_territory_waiver(slot_id, preview_result)


## Bontago-1pi.87: the one territory waiver shared by request_place(),
## request_throw() and preview_placement(): sandbox (no territory limits) or a
## held gift (Bontago-sen.1) turns OUTSIDE_TERRITORY / CONTESTED into VALID;
## every other result (OFF_DISK, HOLE, GOAL_ZONE, ...) is unchanged.
func _apply_territory_waiver(slot_id: int, result: PlacementRules.Result) -> PlacementRules.Result:
	if (_match.config.sandbox or _match.held_special(slot_id) != &"") and (
		result == PlacementRules.Result.OUTSIDE_TERRITORY
		or result == PlacementRules.Result.CONTESTED
	):
		return PlacementRules.Result.VALID
	return result


## The basis a spawn actually uses: a gift is always upright, a plain block keeps the pose.
func _spawn_basis(gift_id: StringName, requested: Basis) -> Basis:
	return Basis.IDENTITY if gift_id != &"" else requested


## Bontago-mv0.11: `slot_id`'s own colour tints every mesh of the block it
## places.
##
## DECISION (autoload/Match.gd): the slot's own PlayerSlot.color, not a
## separate per-team colour. MatchConfig.team_of_slot() is the identity
## function today (TeamMode beyond OFF is not implemented yet -- every slot is
## still its own team; see MatchConfig.team_count()'s own comment), so
## PlayerSlot.color, set from config.player_colors[slot_id] in _build_slots(),
## already *is* that slot's team colour. If team colours are ever
## disambiguated from per-slot colours, this is the one line that needs to
## change to a team-colour lookup instead.
## Bontago-1pi.13 review fix: `is_player_placement` (default true, so
## request_place()/request_throw()'s own call sites below need no change)
## distinguishes a genuine player placement/auto-drop from
## spawn_special_projectile()'s own effect spawns -- that function's own call
## site is the only one that ever passes false. See MatchStats.gd's header
## comment for why blocks_placed cannot simply listen on Events.block_placed
## the way every other counter listens on its own Events signal.
func _spawn_block(
	shape: BlockShape,
	world_origin: Vector3,
	basis: Basis,
	slot_id: int,
	is_player_placement: bool = true,
	gift_id: StringName = &""
) -> Block:
	var acting_slot: PlayerSlot = _match.slot(slot_id)
	var color: Color = acting_slot.color if acting_slot != null else Color.WHITE
	var block: Block = BlockFactory.build(shape, _match._physics_tuning, slot_id, color)
	_match._blocks_parent.add_child(block)
	# Bontago-1pi.85.16: a gift is never rotated by its owner (rotate actions are no-ops while
	# one is held), so the host spawns it upright whatever pose the intent carried.
	block.global_transform = Transform3D(_spawn_basis(gift_id, basis), world_origin)
	# Bontago-t8x.1: a used gift is delivered as its gift model, not as a
	# plain block. The body keeps the held piece's collision (it is the
	# gift's physical carrier) but shows the gift; the id rides the spawn RPC.
	if gift_id != &"":
		BlockFactory.apply_gift_visual(block, shape, _match._physics_tuning, gift_id)
	# block_placed is what makes BlockRegistry allocate the net_id, so the
	# replication below has to come after it: the reliable spawn RPC must
	# carry the same id the (unreliable) snapshots will address the body by.
	Events.block_placed.emit(block, shape.id)
	if is_player_placement:
		_match._stats.record_block_placed(slot_id)
	_blocks_spawned += 1
	if _match._replicator != null:
		_match._replicator.replicate_spawn(block, block.net_id)
	# M4 P2c: unlike every earlier revision of this file, _spawn_block() does
	# NOT itself pop/attach a pending special -- see _attach_pending_special()'s
	# own doc comment (DECISION, Bontago-1en.13 review fix): a burned block
	# must not consume the queue, and only the caller (request_place()/
	# request_throw()) knows at this point whether the spawn it just asked for
	# is going to be burned. Each call site calls _attach_pending_special()
	# itself, only on a path that is never a burn.
	return block


## M4 P2c (docs/M4_P2_PACKAGES.md, orchestrator amendment 1): the special
## TYPE was already drawn at claim time by MatchGifts' own weighted drawer
## (autoload/match/MatchGifts.gd's set_special_drawer()/_ensure_special_
## drawer_installed()) -- this only pops the head id `slot_id`'s queue was
## holding and, if it resolves to a real, roster-enabled SpecialDef, attaches
## a bound SpecialBehavior. Called explicitly by request_place() (only on its
## non-burn path) and request_throw() (always -- a throw is never a burn), a
## placed special arms too, exactly like a thrown one, only the launch
## velocity differs.
##
## DECISION (autoload/match/MatchPlacement.gd, Bontago-1en.13 review fix,
## spec 2.5's OPEN "how expiry handles a held special"): this is
## deliberately NOT called from _spawn_block() itself any more -- popping the
## queue there ran unconditionally, before the caller knew whether the block
## it just spawned was about to be burned (a forced auto-drop with nowhere
## valid to land), so an unlucky expiry could destroy a player's queued
## special for nothing. Each call site now decides for itself, only on a
## path that actually keeps the block.
##
## Both call sites are host-only (request_place()/request_throw() both
## refuse immediately off-host), so every attach and every
## Events.special_triggered forward this produces happens on the host only
## (docs/M4_P2_PACKAGES.md P2c brief).
func _attach_pending_special(block: Block, slot_id: int) -> void:
	var special_id: StringName = _match.pop_pending_special(slot_id)
	if special_id == &"":
		return
	var def: SpecialDef = _resolve_deliverable_special(special_id)
	if def == null:
		return
	var behavior: SpecialBehavior = _arm_special_behavior(block, def, _special_tuning)
	behavior.despawn_when_done = true
	behavior.completed.connect(_on_gift_completed)


## Bontago-t8x.5: host-only (behaviors only exist host-side). Removes a
## completed gift body through the normal block-removal bus: BlockRegistry
## drops it and bumps the territory revision, MatchNet replicates the despawn.
## DECISION: uses Events.REASON_GIFT_DESPAWN, which neither the kill-plane
## burst (BlockEffectsManager) nor blocks_lost (MatchStats) react to.
func _on_gift_completed(block: Block) -> void:
	if block == null or not is_instance_valid(block) or block.is_queued_for_deletion():
		return
	Events.block_removed.emit(block, String(Events.REASON_GIFT_DESPAWN))
	block.queue_free()


## Bontago-t8x.1: the held gift id `slot_id` would deliver if it spawned
## now, or &"" for an ordinary piece or a gift that resolves to no real
## SpecialDef (those spawn as plain blocks, exactly as before). Read before
## the spawn so the visual and the spawn RPC carry the gift id.
func _held_deliverable_gift(slot_id: int) -> StringName:
	var special_id: StringName = _match.held_special(slot_id)
	if special_id == &"" or _resolve_deliverable_special(special_id) == null:
		return &""
	return special_id


func _resolve_deliverable_special(special_id: StringName) -> SpecialDef:
	if special_id == MatchGifts.PENDING_SPECIAL_ID:
		# The default drawer's placeholder -- MatchGifts has not installed its
		# real weighted drawer yet (an empty config/specials/ roster; P3-P5 not
		# landed). Safe default: spawn exactly as an ordinary block.
		_warn_unresolved_special_once(special_id, "no roster installed yet")
		return null
	var def: SpecialDef = _special_def_for_id(special_id)
	var enabled: Array[StringName] = _match.config.enabled_specials if _match.config != null else []
	if def == null:
		_warn_unresolved_special_once(special_id, "unknown special id")
		return null
	if not enabled.is_empty() and not enabled.has(def.id):
		_warn_unresolved_special_once(special_id, "not in this match's enabled_specials")
		return null
	return def


## M4 P4-SPAWN: the actual bind+arm mechanics _attach_pending_special() above
## uses for a gift-drawn special, factored out so spawn_special_projectile()
## below can bind a runtime-built SpecialDef/SpecialTuning pair (e.g. a
## Volcano lava orb) the same way without duplicating these four lines or
## changing _attach_pending_special()'s own behaviour.
func _arm_special_behavior(block: Block, def: SpecialDef, tuning: SpecialTuning) -> SpecialBehavior:
	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	behavior.bind(block, def, tuning)
	behavior.triggered.connect(_on_special_behavior_triggered.bind(block.net_id))
	return behavior


## Forwards SpecialBehavior's own `triggered` signal (game/specials/
## SpecialBehavior.gd, not touched by this package -- orchestrator amendment
## 2) into Events.special_triggered, appended to autoload/Events.gd by this
## package. `net_id` is bound at connect time in _attach_pending_special()
## rather than read from `block` here, so a freed block between trigger and
## forward can never matter.
func _on_special_behavior_triggered(def_id: StringName, position: Vector3, chain_depth: int, net_id: int) -> void:
	Events.special_triggered.emit(net_id, def_id, position, chain_depth)


## Caches SpecialDef.load_all_specials() once per match -- see
## `_special_defs_config`'s own field comment for the identity-check
## rebuild rule.
func _special_def_for_id(special_id: StringName) -> SpecialDef:
	if _special_defs_config != _match.config:
		_special_defs_config = _match.config
		_special_defs_by_id.clear()
		for def: SpecialDef in SpecialDef.load_all_specials():
			_special_defs_by_id[def.id] = def
	return _special_defs_by_id.get(special_id) as SpecialDef


func _warn_unresolved_special_once(special_id: StringName, why: String) -> void:
	if _warned_special_ids.has(special_id):
		return
	_warned_special_ids[special_id] = true
	push_warning("MatchPlacement: spawning %s as an ordinary block (%s)" % [special_id, why])


## Blocks this instance has spawned since the match started. The M3a
## acceptance harness asserts this equals the sum of accepted intents plus
## auto-drops (docs/M3a_PLAN.md).
func blocks_spawned() -> int:
	return _blocks_spawned


## Keeps a burn's disk-local spawn point (x/z only, in Field's local space)
## inside Field's kill plane, so a body that gets thrown off never free-falls
## past it (Bontago-mv0.1.11). Preserves direction and only shortens the
## vector, so an on-disk or near-disk burn (the overwhelming common case) is
## returned unchanged -- this only ever fires for the far-off-disk case a
## hostile or buggy client can still produce.
##
## DECISION (autoload/Match.gd): the safe radius is derived from Field's own
## KILL_PLANE_RADIUS_FACTOR constant (the one _build_kill_plane() already
## uses to size the box) times this match's own map_def.field_radius, rather
## than a new literal or MapDef tunable here, so Match's clamp and Field's
## box can never drift apart. Field.gd is not owned by this package; if that
## constant ever needs to become a per-map tunable, MapDef is the right home
## for it and both Field._build_kill_plane() and this function should read
## it from there instead (follow-up, not done here).
func _clamp_disk_origin_for_burn(disk_origin: Vector2) -> Vector2:
	if _match._field == null or _match._field.map_def == null:
		return disk_origin
	var half_extent: float = (
		_match._field.map_def.field_radius * Field.KILL_PLANE_RADIUS_FACTOR * 0.5 * _BURN_CLAMP_MARGIN
	)
	return disk_origin.limit_length(half_extent)


## Spec 2.2: a rejected block "is thrown off the map with a visible reject
## animation". Bontago-mv0.24 (owner test 2026-09-22): request_place() now
## only reaches this for auto_drop == true (a forced release with no valid
## relocation point) -- a manual release is refused before a block is ever
## spawned. Impulse points radially outward from the disk center, blended
## with an upward component (TerritoryTuning.reject_impulse /
## reject_upward_fraction) so it visibly launches rather than just sliding.
func _burn_block(block: Block, disk_origin: Vector2) -> void:
	if block == null:
		return
	var outward: Vector2 = disk_origin.normalized() if disk_origin.length() > 0.001 else Vector2.RIGHT
	var horizontal_world: Vector3 = (_match._field.global_transform.basis * Vector3(outward.x, 0.0, outward.y)).normalized()
	var up_fraction: float = clampf(_match._territory_tuning.reject_upward_fraction, 0.0, 1.0)
	var impulse_dir: Vector3 = horizontal_world * (1.0 - up_fraction) + Vector3.UP * up_fraction
	if impulse_dir.length() > 0.001:
		impulse_dir = impulse_dir.normalized()
	block.apply_central_impulse(impulse_dir * _match._territory_tuning.reject_impulse)


## Where a slot's block goes when its timer expires and the host has never
## heard a cursor from it — a peer that has not moved its ghost once. Spec
## 2.5's auto-drop [ORIGINAL] drops "from its current ghost position", and
## with no ghost known the slot's own home flag is the honest stand-in;
## PlacementRules.closest_valid_origin() relocates from there as usual.
func default_ghost_origin(slot_id: int) -> Vector3:
	var target: PlayerSlot = _match.slot(slot_id)
	if target == null or _match._field == null:
		return Vector3.ZERO
	# Bontago-1pi.64: the first block starts back from the beacon (away from the
	# field centre, the camera's side), not on top of it. Shared by the player's
	# first ghost (set_home_position) and the host's AFK auto-drop.
	var local_home: Vector3 = Vector3(target.home_position.x, 0.0, target.home_position.y)
	return _match._field.to_global(_ghost_tuning.home_spawn_back_position(local_home))


func _clear_blocks() -> void:
	# Bontago-1pi.85.24 review: in-place activation anchors (Earthquake etc.) are not
	# under _blocks_parent; free them on every reset/abort too, not only via the lifetime backstop.
	_activation.clear()
	if _match._blocks_parent == null:
		return
	for child: Node in _match._blocks_parent.get_children():
		child.queue_free()
