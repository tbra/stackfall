class_name MatchPlacement
extends RefCounted
## Match's one authoritative entry point (spec 2.6): request_place(), pose
## validation, the pure outcome-resolution seam, spawn/burn and the blocks-
## spawned counter.
##
## Split out of autoload/Match.gd; see its header comment for the state machine this placement logic
## serves.

## How far inside Field's kill-plane box a burned block's spawn point is kept, as a fraction of the
## box's half-extent. _burn_block() adds an outward impulse (TerritoryTuning.reject_impulse /
## reject_upward_fraction) before the body falls through kill_plane_y, so the clamp must leave slack
## for that impulse's horizontal travel (about 26 m/s for reject_impulse=30 and
## reject_upward_fraction=0.35, roughly field_radius*2 of travel); otherwise a clamped hostile burn
## could leave the box before reaching kill_plane_y and free-fall forever (see request_place()).
##
## DECISION: 0.5, not 0.9, so the reserved slack equals the clamp radius itself (>= 150 m on the
## smallest map).
const _BURN_CLAMP_MARGIN: float = 0.5

var _match: MatchAutoload = null

## request_throw() reads throw_max_speed from this; preloaded here rather than added as a field on
## autoload/Match.gd.
var _special_tuning: SpecialTuning = preload("res://config/gifts/special_tuning.tres")
var _glue_drop_tuning: GlueDropTuning = preload("res://config/gifts/glue_drop_tuning.tres")
var _ghost_tuning: GhostTuning = preload("res://config/blocks/tuning/ghost_tuning.tres")

## SpecialDef-by-id cache, rebuilt once per match. `_special_defs_config` is compared by identity
## against `_match.config`: start_match() replaces that field with a fresh duplicate every match, so
## a changed reference means a new match started.
var _special_defs_by_id: Dictionary = {}
var _special_defs_config: MatchConfig = null

## _attach_pending_special()'s per-id warning gate. DECISION: warn once per distinct bad id for the
## life of the process, not per match or per occurrence, so a stuck drawer/roster bug surfaces
## without a push_warning on every spawn drowning other warnings.
var _warned_special_ids: Dictionary = {}

## per-slot last aim (unit camera forward), see note_aim().
var _aim_by_slot: Dictionary = {}


## in-place gift activation (see MatchGiftActivation).
var _activation: MatchGiftActivation = MatchGiftActivation.new()


func setup(match_ref: MatchAutoload) -> void:
	_match = match_ref
	_activation.setup(match_ref)


# --- The one intent gate ---------------------------------

## Which host-side entry point is asking _intent_gate().
enum IntentKind {
	PLACE,  ## request_place, a player's own release
	AUTO_DROP,  ## request_place, the host's forced release (exempt from the release lock)
	THROW,  ## request_throw
	GIFT_USE,  ## MatchGifts.request_use_gift_slot (no world nodes needed, no release lock)
	PROJECTILE,  ## spawn_special_projectile: authority + live state + world only, no seat
}


## Whether `slot_id` may spend its gift slot now (the host/live/turn/held-shape preamble).
func can_use_gift_slot(slot_id: int) -> bool:
	return _intent_gate(slot_id, -1, IntentKind.GIFT_USE) == &""


## The shared host-side guard preamble of every authoritative intent, in the
## one order the copies agreed on: host, live match state, world nodes, slot
## range, feed_seq replay defence, seat/home alive, turn gate, held shape and
## the one-release-per-interval lock. Returns &"" when allowed, otherwise the
## refusal reason (PlacementRules.REASON_NO_BLOCK, or REASON_NOT_YOUR_TURN for
## an off-turn seat). Callers keep only their kind-specific checks (pose,
## held special, aim, territory) after it and map the reason to their own
## return type (bool/null for GIFT_USE/PROJECTILE). `feed_seq < 0` is the
## trusted-local "don't check" sentinel (see request_place's doc comment).
## DECISION: the dead-home check ranks before the turn gate for every kind.
func _intent_gate(slot_id: int, feed_seq: int, kind: IntentKind) -> StringName:
	if not _match._is_host():
		return PlacementRules.REASON_NO_BLOCK
	if not MatchAutoload.is_live(_match.state()):
		return PlacementRules.REASON_NO_BLOCK
	# The gift slot never touched the field or block parent, so it never required them.
	if kind != IntentKind.GIFT_USE and (_match._field == null or _match._blocks_parent == null):
		return PlacementRules.REASON_NO_BLOCK
	if kind == IntentKind.PROJECTILE:
		return &""
	if slot_id < 0 or slot_id >= _match.slot_count():
		return PlacementRules.REASON_NO_BLOCK
	if feed_seq >= 0 and feed_seq != _match.feed_seq(slot_id):
		return PlacementRules.REASON_NO_BLOCK
	var seat: PlayerSlot = _match.slot(slot_id)
	if seat == null or not seat.home_flag_alive:
		return PlacementRules.REASON_NO_BLOCK
	if (
		_match.config.turn_based
		and slot_id != _match.active_slot()
	):
		return PlacementRules.REASON_NOT_YOUR_TURN
	if _match.held_shape(slot_id) == null:
		return PlacementRules.REASON_NO_BLOCK
	# The release lock: a forced auto-drop is what ends it, and the gift slot ignores it (a locked
	# slot may still use a slotted gift).
	if (kind == IntentKind.PLACE or kind == IntentKind.THROW) and _match.is_release_locked(slot_id):
		return PlacementRules.REASON_NO_BLOCK
	return &""


# --- The one authoritative entry point (spec 2.6) ---------------------------

## Every placement in the game goes through here, local or remote. `origin` is
## the world position the block's local origin would sit at, `orientation_index`
## the BlockOrientations index and `free_quat` the free rotation layered on it
## (spec 1.4). `auto_drop` is true when the slot's timer ran out rather than
## the player clicking, which is the only case where the host relocates the
## block to the closest valid point instead of rejecting it (spec 1.4).
##
## Returns PlacementRules.REASON_OK on success, otherwise the REASON_* that
## explains the refusal, which is also emitted as Events.placement_rejected.
##
## Supersedes spec 1.5's older "thrown
## off the map with a visible reject animation" line for this case: a
## refused *deliberate* (auto_drop == false) placement spawns nothing and
## consumes nothing — the piece stays held, feed_seq does not advance, and
## the caller may try again. A refused auto-drop that finds no valid point to
## relocate to still spawns the block and throws it off the map, since spec
## 2.5's forced release has nowhere else to put it; one that does find a
## valid point relocates there instead and emits Events.placement_relocated.
##
## net/MatchNet.gd wraps this in an @rpc intent that checks the caller's peer id against `slot_id`
## and changes nothing else. `feed_seq` is the value of feed_seq(slot_id) the caller last saw; -1
## means "don't check". A stale value means a replay, a double click inside one round trip, or a
## race with an auto-drop, and is refused with REASON_NO_BLOCK -- the whole of the "Never
## duplicated, never lost" defence (1).
##
## The -1 sentinel is for **trusted local callers only**: the local controllers, the host's own
## timer and the tests. It never arrives here from the wire -- net/MatchNet.gd refuses any negative
## remote feed_seq before calling in -- because a client that could quote -1 would opt out of
## defence (1) altogether.
##
## A pose that cannot be evaluated at all (a non-finite origin, a free
## quaternion that is not a finite unit rotation, or an orientation index
## outside BlockOrientations' table) is refused with REASON_NO_BLOCK before
## anything is touched. That is not a rule — the ghost can never produce such
## a pose — but the authority's own guard against corrupt or hostile input
## (spec 2.6: "The host checks every intent before acting on it"); MatchNet
## refuses the same poses at the wire so they are normally never seen here.
func request_place(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	auto_drop: bool,
	feed_seq: int = -1
) -> StringName:
	# Spec 2.6: the host decides every placement. A client that somehow got
	# here locally must not spawn anything; it waits for the host's spawn.
	var gate_kind: IntentKind = IntentKind.AUTO_DROP if auto_drop else IntentKind.PLACE
	var refusal: StringName = _intent_gate(slot_id, feed_seq, gate_kind)
	if refusal != &"":
		return refusal
	# A forced release of a held throwable gift
	# is the manual throw along the slot's last known aim, not a drop in place.
	if auto_drop and _try_expiry_throw(slot_id, origin, orientation_index, free_quat, feed_seq):
		return PlacementRules.REASON_OK
	var acting_slot: PlayerSlot = _match.slot(slot_id)
	var shape: BlockShape = _match.held_shape(slot_id)
	# DECISION: the release lock (enforced in _intent_gate for manual releases only) reuses
	# REASON_NO_BLOCK rather than a new PlacementRules.REASON_*; auto_drop is exempt because it is
	# the host's own forced release that ends the lock.
	if not is_pose_well_formed(origin, orientation_index, free_quat):
		return PlacementRules.REASON_NO_BLOCK

	var basis: Basis = Basis(free_quat) * BlockOrientations.get_basis(orientation_index)
	var local_origin: Vector3 = _match._field.to_local(origin)
	var team_id: int = acting_slot.team_id
	# Legality is judged under the rotated footprint's centre, not under the pivot `origin`
	# (spec 2.5): `centre_shift` is the disk-local pivot-to-centre vector, and every disk point
	# below up to the final pivot conversion is a centre point.
	var centre_shift: Vector2 = _centre_shift_disk(slot_id, shape, origin, basis)
	var probe_origin: Vector3 = origin + _centre_shift_world(slot_id, shape, basis)
	var disk_origin: Vector2 = Vector2(local_origin.x, local_origin.z) + centre_shift

	# DECISION: every MatchConfig.HoleMode uses one raycast straight down from `origin` plus
	# PlacementRules.validate_point() (spec 2.5 "Placement legality": one ray from the ghost's
	# middle, no whole-footprint territory test). validate_point() also rejects a contested/holed
	# point under the raster fill, so it reports every case the footprint chain used to;
	# footprint_cells() stays only for the bots' footprint scoring.
	var result: PlacementRules.Result
	var relocated: Vector2 = PlacementRules.NO_ORIGIN
	var hit: Variant = _match._field.raycast_down_disk_local(probe_origin)
	if hit == null:
		# Only possible off the rim with nothing beneath (Field.gd's own
		# contract for raycast_down_disk_local); disk_origin keeps the flat
		# projection computed above, which is what the burn clamp below
		# throws from.
		result = _hole_column_result(slot_id, disk_origin)
	else:
		disk_origin = hit as Vector2
		result = PlacementRules.validate_point(disk_origin, _match.raster(), team_id)
		# DECISION (sandbox rule, spec 1.2 "Sandbox: no territory limits"): only the two
		# territory-ownership outcomes are waived; OFF_DISK (the hit == null branch above), HOLE and
		# GOAL_ZONE all stay refused. PlacementRules stays config-agnostic, so this call site, which
		# already knows config.sandbox, applies the waiver.
		result = _apply_territory_waiver(slot_id, result)  # held gift waives territory (host state)
	if result != PlacementRules.Result.VALID and auto_drop:
		relocated = PlacementRules.closest_valid_point(disk_origin, _match.raster(), team_id, _match._territory_tuning)
	var outcome: Dictionary = _resolve_outcome(result, auto_drop, relocated)
	var reason: StringName = outcome["reason"]

	if reason != PlacementRules.REASON_OK and not auto_drop:
		# DECISION: a manual out-of-zone release is refused outright, not burned: nothing is spawned
		# or consumed, feed_seq does not move and the release lock is untouched, so the caller may
		# simply try again. The burn/clamp path below is therefore reachable only for
		# auto_drop == true, where spec 1.4's
		# forced release still has to land somewhere. See Events.placement_rejected.
		Events.placement_rejected.emit(slot_id, reason)
		return reason

	var final_disk_origin: Vector2 = relocated if outcome["use_relocation"] else disk_origin
	if reason != PlacementRules.REASON_OK:
		# Burn path: the last cursor MatchNet stored for a remote slot is finite but arbitrary
		# (is_pose_well_formed() only refuses non-finite poses). Left unclamped, a block would spawn
		# and be thrown from that raw point, land outside Field's kill plane and free-fall forever:
		# a leaked RigidBody3D plus permanent snapshot traffic. Field sizes the box at
		# map_def.field_radius * Field.KILL_PLANE_RADIUS_FACTOR.
		final_disk_origin = _clamp_disk_origin_for_burn(final_disk_origin)

	# `origin` is the shape's bottom-centre pivot (GhostPreview/BlockFactory both pivot there,
	# rotated-shape corrected; see GhostPreview's DECISION) but final_disk_origin is the
	# legality point (the rotated footprint's centre), so the pivot the body spawns at is that
	# point minus the pivot-to-centre shift -- applied exactly once, here.
	var final_disk_centre: Vector2 = final_disk_origin
	var final_pivot_disk: Vector2 = final_disk_centre - centre_shift
	var final_world_origin: Vector3 = _match._field.to_global(Vector3(
		final_pivot_disk.x, local_origin.y, final_pivot_disk.y
	))
	if reason == PlacementRules.REASON_OK:
		# an in-place gift activates here, with no carrier body.
		# An ordinary piece (held id &"") never queries the special roster.
		var held_id: StringName = _match.held_special(slot_id)
		var in_place_def: SpecialDef = _resolve_deliverable_special(held_id) if held_id != &"" else null
		if in_place_def != null and in_place_def.activates_in_place and _activation.try_activate(slot_id, in_place_def, final_disk_centre):
			_match._feed._consume_and_refeed(slot_id, auto_drop)
			if _match.config.turn_based:
				_match._lifecycle.begin_turn_settle_wait()
			return PlacementRules.REASON_OK
		# Host-side spawn validation (see _lift_pose_clear()). A sky-drop gift (Anvil) spawns high
		# above the validated point and falls; there is nothing up there to clear, so the lift
		# search is skipped for it.
		var sky_height_m: float = in_place_def.sky_drop_height_m if in_place_def != null else 0.0
		var sky_origin: Variant = _sky_spawn_origin(shape, final_world_origin, basis, in_place_def) if sky_height_m > 0.0 else null
		if sky_origin != null:
			final_world_origin = sky_origin as Vector3
		else:
			var lifted: Variant = _lift_pose_clear(shape, final_world_origin, basis, auto_drop, _held_deliverable_gift(slot_id) if reason == PlacementRules.REASON_OK else &"")
			if lifted == null:
				Events.placement_rejected.emit(slot_id, PlacementRules.REASON_NO_BLOCK)
				return PlacementRules.REASON_NO_BLOCK
			final_world_origin = lifted as Vector3
	# only a non-burn spawn delivers the gift (a burn keeps it queued).
	var gift_id: StringName = _held_deliverable_gift(slot_id) if reason == PlacementRules.REASON_OK else &""
	var spawned: Block = _spawn_block(shape, final_world_origin, basis, slot_id, true, gift_id)
	if reason != PlacementRules.REASON_OK:
		# Burn: only an auto-drop reaches here (a manual refusal returned above). It found no valid
		# point to relocate to, so it still spawns the block, throws it off the map and consumes it.
		#
		# DECISION: a burn must NOT pop/attach the pending special -- _attach_pending_special() is
		# deliberately not called on this path, so a forced auto-drop with nowhere valid to land
		# never destroys a queued special; it stays queued for the slot's next spawn.
		#
		# closest_valid_point() falls back to a full-disk scan, so this is reachable only when the
		# slot's team owns no valid point anywhere (home flag down and every stack lost). That is
		# rare, so a distinct warning is worth its noise.
		push_warning(
			"MatchPlacement: auto-drop burn for slot %d -- no valid point anywhere on the disk (%s)"
			% [slot_id, reason]
		)
		_burn_block(spawned, final_pivot_disk)
		if _match._feed.is_held_gift(slot_id):
			_match._gifts.defer_held_special_after_burn(slot_id)
		Events.placement_rejected.emit(slot_id, reason)
	else:
		# The block actually landed somewhere valid -- at the caller's own
		# spot, or (see below) relocated -- so this is the one path allowed
		# to consume the pending special.
		var is_glue_activation: bool = _match.held_special(slot_id) == &"glue"
		# DECISION: a Jumping Bean never takes a glue charge (it would
		# be bonded and unable to hop); the charge stays for the next ordinary drop.
		var is_bean: bool = _match.held_special(slot_id) == &"jumping_bean"
		_attach_pending_special(spawned, slot_id)
		# A Glue impact grants charges for FUTURE successful drops. Exclude its
		# own activation block even if an earlier Glue buff is still active.
		# This path is never reached by a rejected click, burn, throw or
		# spawn_special_projectile(), so those cannot spend a charge.
		if not is_glue_activation and not is_bean and gift_id == &"" and _match.consume_glue_drop(slot_id):
			var bonding: GlueDrops = GlueDrops.new()
			spawned.add_child(bonding)
			bonding.bind(spawned, _glue_drop_tuning)
			Events.glue_drop_charged.emit(spawned)
		if outcome["use_relocation"]:
			# this auto-drop *did* find a valid point and
			# landed there instead of at the caller's raw ghost position --
			# tell the owning client where, so its cursor and camera can jump
			# to match (game/player/PlayerController.gd's _on_placement_relocated).
			Events.placement_relocated.emit(slot_id, final_disk_origin)

	_match._feed._consume_and_refeed(slot_id, auto_drop)
	if _match.config.turn_based:
		_match._lifecycle.begin_turn_settle_wait()

	return reason


## Spec 1.6's throw: releases a pending special with velocity instead of dropping it in place (spec
## 2.6: the host clamps velocity to throw_max_speed). Mirrors request_place() guard-for-guard
## through the pose-well-formed gate, then diverges: a throw only ever fires a pending special
## (REASON_NOT_A_SPECIAL otherwise, checked before the raycast), a refused throw is never burned --
## the piece stays held exactly like a refused manual placement -- and the release velocity is
## always clamped rather than ever being a refusal reason.
##
## `velocity` carries the unit camera forward (see the aim DECISION below); the host derives the
## launch velocity from it. `feed_seq`/the -1 sentinel are exactly request_place()'s own contract.
func request_throw(
	slot_id: int,
	origin: Vector3,
	orientation_index: int,
	free_quat: Quaternion,
	velocity: Vector3,
	feed_seq: int = -1
) -> StringName:
	var refusal: StringName = _intent_gate(slot_id, feed_seq, IntentKind.THROW)
	if refusal != &"":
		return refusal
	var acting_slot: PlayerSlot = _match.slot(slot_id)
	var shape: BlockShape = _match.held_shape(slot_id)
	# DECISION: the release lock is unconditional for a throw (_intent_gate's
	# THROW kind); a throw has no auto_drop equivalent.
	if not is_pose_well_formed(origin, orientation_index, free_quat) or not velocity.is_finite():
		return PlacementRules.REASON_NO_BLOCK
	if _match.held_special(slot_id) == &"":
		return ThrowRules.REASON_NOT_A_SPECIAL
	# DECISION: the camera forward rides the unchanged throw RPC's
	# `velocity` slot (no new RPC, no replicated camera pose exists to read instead); the host
	# validates length/finiteness and drops the upward part for effects that cannot aim up.
	var held_def: SpecialDef = _resolve_deliverable_special(_match.held_special(slot_id))
	var throw_mode: GiftThrow.Mode = GiftThrow.mode_for(held_def)
	if throw_mode == GiftThrow.Mode.NONE and held_def != null:
		return ThrowRules.REASON_NOT_A_SPECIAL
	# DECISION: every gift release is camera-aimed. The unit camera forward is the ONLY thing read
	# from the client's `velocity` slot (finite, length band; otherwise refused without consuming);
	# the host derives launch velocity and spawn point from it and SpecialTuning alone (GiftAim), so
	# a client-supplied speed is never trusted.
	var aim_direction: Vector3 = GiftThrow.sanitize_aim(velocity, _special_tuning)
	if aim_direction == Vector3.ZERO:
		return PlacementRules.REASON_NO_BLOCK
	var launch_velocity: Vector3 = Vector3.ZERO
	if held_def == null or throw_mode == GiftThrow.Mode.THROW:
		# An unresolved def (spawns as a plain block) takes the same ballistic throw.
		launch_velocity = GiftAim.throw_velocity(aim_direction, _special_tuning, _throw_range_scale())
		if launch_velocity == Vector3.ZERO:
			return PlacementRules.REASON_NO_BLOCK
	elif held_def.effect != null and held_def.effect.may_aim_upward():
		# Any aim, upward included (Rocket).
		if GiftAim.sanitize_launch_direction(aim_direction) == Vector3.ZERO:
			return PlacementRules.REASON_NO_BLOCK
	elif GiftAim.sanitize_downward_direction(aim_direction) == Vector3.ZERO:
		# Paintball keeps the "not upward" rule: a purely vertical aim would be consumed and
		# fall unlaunched, so it is refused without consuming.
		return PlacementRules.REASON_NO_BLOCK

	var gift_id: StringName = _held_deliverable_gift(slot_id)
	# the overlap/lift check must test the basis _spawn_block() will use.
	var basis: Basis = _spawn_basis(gift_id, Basis(free_quat) * BlockOrientations.get_basis(orientation_index))
	var local_origin: Vector3 = _match._field.to_local(origin)
	var team_id: int = acting_slot.team_id
	# Same legality point as request_place(): the rotated footprint's centre, not the pivot.
	var centre_shift: Vector2 = _centre_shift_disk(slot_id, shape, origin, basis)
	var probe_origin: Vector3 = origin + _centre_shift_world(slot_id, shape, basis)

	# Exactly request_place()'s own raycast-then-point-test;
	# ThrowRules.validate_release_point() delegates to the identical
	# PlacementRules.validate_point() so a throw and a placement can never
	# disagree about what "your own territory" means at a point.
	var result: PlacementRules.Result
	var disk_origin: Vector2 = Vector2(local_origin.x, local_origin.z) + centre_shift
	var hit: Variant = _match._field.raycast_down_disk_local(probe_origin)
	if hit == null:
		result = _hole_column_result(slot_id, disk_origin)
	else:
		disk_origin = hit as Vector2
		result = ThrowRules.validate_release_point(disk_origin, _match.raster(), team_id)
		# DECISION (sandbox rule): the throw-path twin of request_place()'s sandbox waiver, same
		# waived outcomes. Gifts may also be "dropped anywhere", so a host-held gift (always true
		# here, see the NOT_A_SPECIAL guard above) waives territory on the throw path too.
		result = _apply_territory_waiver(slot_id, result)
	if result != PlacementRules.Result.VALID:
		# A refused throw keeps the piece in hand, like a refused click, and never burns: nothing
		# spawns or is consumed, and the caller may simply try again.
		var reason: StringName = ThrowRules.reason_for(result)
		Events.placement_rejected.emit(slot_id, reason)
		return reason

	# The map-size range scaling applies to the ballistic THROW only; an AIMED launch
	# (Rocket/Paintball) keeps the plain throw_max_speed clamp.
	var speed_cap: float = _special_tuning.throw_max_speed
	if held_def == null or throw_mode == GiftThrow.Mode.THROW:
		speed_cap *= GiftAim.speed_factor(_throw_range_scale())
	var clamped_velocity: Vector3 = launch_velocity.limit_length(speed_cap)
	# disk_origin is the legality point (the footprint's centre); the body spawns at its pivot.
	var pivot_disk: Vector2 = disk_origin - centre_shift
	var world_origin: Vector3 = _match._field.to_global(Vector3(pivot_disk.x, local_origin.y, pivot_disk.y))
	# The throw spawns at the client-sent pose too, so it gets the same host overlap validation (a
	# manual intent: refused, the special stays in hand, when no lift clears it). The projectile
	# spawns on the camera line (cursor point moved back along the aim, never below
	# gift_aim_min_height_m over the surface); territory was validated at the cursor above.
	world_origin = GiftAim.spawn_point(world_origin, aim_direction, _match._field.surface_y(), _special_tuning)
	# Rocket/Magnet spawn already facing their flight line, so the first replicated pose is never
	# upright. The overlap/lift check tests that same faced basis (null = upright).
	var faced: Variant = launch_facing_basis(held_def, throw_mode, aim_direction, clamped_velocity)
	var overlap_basis: Basis = faced as Basis if faced != null else basis
	if faced != null and throw_mode == GiftThrow.Mode.AIMED and gift_id != &"":
		# the faced body's model must start where the held model is drawn.
		world_origin = BlockFactory.muzzle_matched_origin(world_origin, overlap_basis, shape, _match._physics_tuning, gift_id)
	var lifted: Variant = _lift_pose_clear(shape, world_origin, overlap_basis, false, gift_id)
	if lifted == null:
		Events.placement_rejected.emit(slot_id, PlacementRules.REASON_NO_BLOCK)
		return PlacementRules.REASON_NO_BLOCK
	world_origin = lifted as Vector3
	var spawned: Block = _spawn_block(shape, world_origin, basis, slot_id, true, gift_id, faced)
	spawned.linear_velocity = clamped_velocity
	# DECISION: spec 2.7 names "thrown specials" as their own continuous_cd case, not conditioned on
	# the 15 m/s speed. request_throw() only reaches this line for a pending special, so every
	# thrown body qualifies unconditionally; no second threshold tunable is needed.
	spawned.continuous_cd = true
	# DECISION: a throw is never a burn -- every earlier return refused anything that would not land
	# -- so this is always the one call that pops/attaches the pending special (request_place()'s
	# matching call is conditional).
	_attach_pending_special(spawned, slot_id)
	if throw_mode == GiftThrow.Mode.AIMED:
		held_def.effect.apply_launch(spawned, aim_direction)

	_match._feed._consume_and_refeed(slot_id, false)
	if _match.config.turn_based:
		_match._lifecycle.begin_turn_settle_wait()

	return PlacementRules.REASON_OK


## records the unit camera forward a slot last reported (the cursor packet's
## aim on the wire, the local controller's own camera for the host seat, a bot's planned aim).
## Host only; an unusable value forgets the slot's aim. It is never trusted: the expiry throw
## runs it through request_throw()'s own GiftThrow.sanitize_aim() like a manual release.
func note_aim(slot_id: int, forward: Vector3) -> void:
	if not _match._is_host() or slot_id < 0 or slot_id >= _match.slot_count():
		return
	if not forward.is_finite() or forward == Vector3.ZERO:
		_aim_by_slot.erase(slot_id)
		return
	_aim_by_slot[slot_id] = forward


## Drops the aim noted for `slot_id` (a new piece was issued to it).
func forget_aim(slot_id: int) -> void:
	_aim_by_slot.erase(slot_id)


## the expiry half of request_place(). True when a held, throwable gift was
## released as a manual throw along the slot's last noted aim (same validation, arc and range:
## it IS request_throw()). False leaves the caller's ordinary forced drop to run.
## DECISION: no usable aim, a non-throwable special, an unresolved gift, an
## off-disk cursor or a refused throw (nothing is burned by a refused throw) fall back to the
## ordinary auto-drop, which relocates to the nearest valid release point; non-throwable
## specials therefore follow their manual-release path (placed where the ghost is).
func _try_expiry_throw(slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion, feed_seq: int) -> bool:
	if not _aim_by_slot.has(slot_id) or _match.held_special(slot_id) == &"":
		return false
	var held_def: SpecialDef = _resolve_deliverable_special(_match.held_special(slot_id))
	if held_def == null or GiftThrow.mode_for(held_def) == GiftThrow.Mode.NONE:
		return false
	var aim: Vector3 = _aim_by_slot[slot_id]
	if GiftThrow.sanitize_aim(aim, _special_tuning) == Vector3.ZERO:
		return false
	if not is_pose_well_formed(origin, orientation_index, free_quat):
		return false
	# An off-disk cursor would make the throw emit a refusal the forced drop then repeats.
	var expiry_shape: BlockShape = _match.held_shape(slot_id)
	var expiry_basis: Basis = Basis(free_quat) * BlockOrientations.get_basis(orientation_index)
	if _match._field.raycast_down_disk_local(origin + _centre_shift_world(slot_id, expiry_shape, expiry_basis)) == null:
		return false
	return request_throw(slot_id, origin, orientation_index, free_quat, aim, feed_seq) == PlacementRules.REASON_OK


## Spawn entry point for a special's own SpecialEffect to create a brand-new projectile at runtime
## (e.g. Volcano's lava orbs), outside a player's placement/throw gesture. Host-only through the
## shared intent gate: returns null and spawns nothing off-host. Not a player intent, so it consumes
## no feed slot and runs no PlacementRules/ThrowRules point check -- the caller (an effect's
## physics_tick(), which SpecialBehavior only runs host-side) already decided the exact world pose
## and velocity.
## Follows _spawn_block()'s exact pipeline (BlockFactory.build ->
## _blocks_parent.add_child -> Events.block_placed [allocates net_id] ->
## replicate_spawn), then binds and arms a SpecialBehavior from
## `orb_def`/`orb_tuning` via the same _arm_special_behavior() helper
## _attach_pending_special() uses (see that function's own doc comment for
## why this is a separate helper rather than a duplicate of those four
## lines), then sets the launch velocity. Spec 2.7 names "lava orbs" as
## their own continuous_cd case alongside "any body moving faster than
## 15 m/s" -- `orb_tuning.ccd_speed_threshold_mps` is that same 15 m/s
## number, so continuous_cd is armed whenever this spawn's own speed clears
## it, independent of which special is spawning.
##
## DECISION: guards with the same state/_field/_blocks_parent null checks as request_place() (via
## _intent_gate), not only authority: a call arriving mid-teardown (an effect's physics_tick() still
## queued as a match aborts) would otherwise crash inside _spawn_block() instead of returning null.
func spawn_special_projectile(
	shape: BlockShape,
	world_origin: Vector3,
	basis: Basis,
	owner_slot: int,
	initial_velocity: Vector3,
	orb_def: SpecialDef,
	orb_tuning: SpecialTuning
) -> Block:
	if _intent_gate(owner_slot, -1, IntentKind.PROJECTILE) != &"":
		return null
	if shape == null:
		return null

	# is_player_placement = false: an effect's own projectile spawn (e.g. Volcano's 8-14 lava orbs)
	# must not inflate `owner_slot`'s blocks_placed stat.
	var spawned: Block = _spawn_block(shape, world_origin, basis, owner_slot, false)
	# DECISION: a null orb_tuning falls back to the match's preloaded _special_tuning, the same
	# resource _attach_pending_special() uses, instead of crashing the host on the ccd read below
	# when a .tres leaves its tuning export unset.
	var effective_tuning: SpecialTuning = orb_tuning if orb_tuning != null else _special_tuning
	if orb_def != null:
		_arm_special_behavior(spawned, orb_def, effective_tuning)
	spawned.linear_velocity = initial_velocity
	spawned.continuous_cd = initial_velocity.length() > effective_tuning.ccd_speed_threshold_mps
	return spawned


## spawn pose of a sky-drop gift (Anvil), derived on the host from the
## validated drop point, never from the client's hover height: the top of whatever is below
## the point (disc surface or the highest block, a downward ray) plus sky_drop_height_m,
## clamped hover_ceiling_margin below NetConfig.pos_max_y so the carrier stays inside the
## snapshot position band. Returns null when that pose overlaps a body (DECISION: the caller
## then falls back to the ordinary validated release point, lifted clear as usual).
func _sky_spawn_origin(shape: BlockShape, origin: Vector3, basis: Basis, def: SpecialDef) -> Variant:
	if _match._blocks_parent == null or not _match._blocks_parent.is_inside_tree():
		return null
	var world: World3D = _match._blocks_parent.get_viewport().world_3d
	if world == null:
		return null
	var ceiling_y: float = _match._net_config.pos_max_y - _ghost_tuning.hover_ceiling_margin
	var surface_y: float = _match._field.to_global(Vector3(0.0, _match._field.surface_y(), 0.0)).y
	var top_y: float = surface_y
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		Vector3(origin.x, ceiling_y, origin.z), Vector3(origin.x, surface_y - 1.0, origin.z), Field.PLACEMENT_QUERY_MASK
	)
	var hit: Dictionary = world.direct_space_state.intersect_ray(ray)
	if not hit.is_empty():
		top_y = maxf(top_y, (hit["position"] as Vector3).y)
	var sky_y: float = minf(top_y + def.sky_drop_height_m, ceiling_y)
	var sky_origin: Vector3 = Vector3(origin.x, sky_y, origin.z)
	if _pose_overlaps(world.direct_space_state, shape, sky_origin, basis, _ghost_tuning, def.id):
		return null
	return sky_origin


## The client lifts its ghost clear of placed blocks as a prediction, but a late
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
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	var cap: float = tuning.spawn_clearance_max_raise
	var raise: float = ClearanceRaise.first_clear_raise(
			func(r: float) -> bool: return _pose_overlaps(space, shape, origin + Vector3.UP * r, basis, tuning, gift_id),
			tuning.spawn_clearance_step, cap, tuning.spawn_clearance_bisect_steps, tuning.spawn_clearance)
	if raise == ClearanceRaise.NOT_CLEARED:
		return origin + Vector3.UP * cap if auto_drop else null
	return origin + Vector3.UP * raise


func _pose_overlaps(space: PhysicsDirectSpaceState3D, shape: BlockShape, origin: Vector3, basis: Basis, tuning: GhostTuning, gift_id: StringName = &"") -> bool:
	var physics: PhysicsTuning = _match._physics_tuning
	# the same boxes the client ghost tests (BlockFactory.overlap_probe_*)
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3.ONE * BlockFactory.overlap_probe_size(physics, gift_id)
	for centre: Vector3 in BlockFactory.overlap_probe_centers(shape, physics, gift_id):
		var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		params.shape = box
		params.transform = Transform3D(basis, origin + basis * centre)
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


## Pure decision step factored out of request_place() so it can be unit-tested against manufactured
## PlacementRules.Result / relocation values without a working territory solve. `initial_result` is
## what validate_point() said about the desired spot; `relocated` is what closest_valid_point()
## found (or PlacementRules.NO_ORIGIN), computed by the caller since that search needs a real
## raster.
##
## Returns {"reason": StringName, "use_relocation": bool}: the reason request_place() should return,
## and whether the block should land at `relocated` (true) or stay at the original spot and be
## thrown off the map (false, with reason != REASON_OK) -- spec 1.5's burn rule: any release on an
## invalid spot burns the block; auto-drop gets one relocation attempt first.
func _resolve_outcome(
	initial_result: PlacementRules.Result, auto_drop: bool, relocated: Vector2
) -> Dictionary:
	if initial_result == PlacementRules.Result.VALID:
		return {"reason": PlacementRules.REASON_OK, "use_relocation": false}
	if auto_drop and not PlacementRules.is_no_origin(relocated):
		return {"reason": PlacementRules.REASON_OK, "use_relocation": true}
	return {"reason": PlacementRules.reason_for(initial_result), "use_relocation": false}


## Dry run of request_place()'s territory check, for the ghost's valid/red/
## hatched tint (spec 1.4). One raycast plus one point test, matching
## request_place() under every MatchConfig.HoleMode; safe to
## call every frame.
func preview_placement(
	slot_id: int, origin: Vector3, orientation_index: int, free_quat: Quaternion
) -> PlacementRules.Result:
	if not MatchAutoload.is_live(_match.state()) or _match.cell_grid() == null or _match.raster() == null or _match._field == null:
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
	# always matches what the host would decide.
	var preview_basis: Basis = Basis(free_quat) * BlockOrientations.get_basis(orientation_index)
	var preview_shape: BlockShape = _match.held_shape(slot_id)
	var probe_origin: Vector3 = origin + _centre_shift_world(slot_id, preview_shape, preview_basis)
	var hit: Variant = _match._field.raycast_down_disk_local(probe_origin)
	if hit == null:
		var local_probe: Vector3 = _match._field.to_local(probe_origin)
		return _hole_column_result(slot_id, Vector2(local_probe.x, local_probe.z))
	var preview_result: PlacementRules.Result = PlacementRules.validate_point(hit as Vector2, _match.raster(), team_id)
	# mirrors request_place(): a held gift ignores territory.
	return _apply_territory_waiver(slot_id, preview_result)


## World-space pivot-to-legality-point vector for `slot_id`'s held piece in pose `basis` (spec 2.5
## "Placement legality": the rotated footprint's centre). A gift is spawned upright whatever pose
## the intent carried (_spawn_basis()), so it is judged upright too. The full 3D offset is returned;
## callers use only its horizontal part to pick the column (raycast_down_disk_local() casts down).
func _centre_shift_world(slot_id: int, shape: BlockShape, basis: Basis) -> Vector3:
	if shape == null or _match._physics_tuning == null:
		return Vector3.ZERO
	var judged_basis: Basis = _spawn_basis(_held_deliverable_gift(slot_id), basis)
	return PlacementPoint.legality_point(Vector3.ZERO, shape, judged_basis, _match._physics_tuning.cube_size)


## The same shift as a disk-local (x, z) vector, correct while the field tilts (to_local is affine,
## so the difference of two converted points is the converted vector).
func _centre_shift_disk(slot_id: int, shape: BlockShape, origin: Vector3, basis: Basis) -> Vector2:
	var shifted: Vector3 = _match._field.to_local(origin + _centre_shift_world(slot_id, shape, basis))
	var base: Vector3 = _match._field.to_local(origin)
	return Vector2(shifted.x - base.x, shifted.z - base.z)


## the one territory waiver shared by request_place(),
## request_throw() and preview_placement(): sandbox (no territory limits) or a
## held gift turns OUTSIDE_TERRITORY / CONTESTED into VALID;
## every other result (OFF_DISK, HOLE, GOAL_ZONE, ...) is unchanged.
func _apply_territory_waiver(slot_id: int, result: PlacementRules.Result) -> PlacementRules.Result:
	var territory: bool = (
		result == PlacementRules.Result.OUTSIDE_TERRITORY
		or result == PlacementRules.Result.CONTESTED
	)
	if (_match.config.sandbox or _match.held_special(slot_id) != &"") and territory:
		return PlacementRules.Result.VALID
	# DECISION: a held gift may be used above a hole or a goal zone; only the gift waives these (a
	# plain block and the sandbox keep refusing them); OFF_DISK still refuses.
	if _match.held_special(slot_id) != &"" and (
		result == PlacementRules.Result.HOLE or result == PlacementRules.Result.GOAL_ZONE
	):
		return PlacementRules.Result.VALID
	return result


## Over an open hole cell the down-ray finds no
## floor (null). A held gift whose flat disk projection is still inside the disk is then usable
## there (it spawns at the sent pose and falls normally); anything else stays OFF_DISK.
## DECISION: a hole under the gift is not a rim overhang, so it must not read as OFF_DISK.
func _hole_column_result(slot_id: int, disk_xz: Vector2) -> PlacementRules.Result:
	if _match.held_special(slot_id) == &"":
		return PlacementRules.Result.OFF_DISK
	var grid: CellGrid = _match.raster().grid()
	var coords: Vector2i = grid.world_to_cell(disk_xz)
	if grid.in_bounds(coords.x, coords.y) and grid.is_in_disk(coords.x, coords.y):
		return PlacementRules.Result.VALID
	return PlacementRules.Result.OFF_DISK


## the basis a thrown/launched Rocket or Magnet carrier spawns with (nose along
## its flight line), or null when the gift keeps the upright spawn pose. Pure.
static func launch_facing_basis(
	def: SpecialDef, mode: GiftThrow.Mode, aim_direction: Vector3, throw_velocity: Vector3
) -> Variant:
	if def == null:
		return null
	if def.effect != null and def.effect.faces_launch(mode, aim_direction, throw_velocity):
		return def.effect.launch_facing(mode, aim_direction, throw_velocity)
	return null


## The basis a spawn actually uses: a gift is always upright, a plain block keeps the pose.
func _spawn_basis(gift_id: StringName, requested: Basis) -> Basis:
	return Basis.IDENTITY if gift_id != &"" else requested


## `slot_id`'s own colour tints every mesh of the block it places.
##
## DECISION: the slot's own PlayerSlot.color, not a separate per-team colour.
## MatchConfig.team_of_slot() is the identity function today (every slot is its own team), so
## PlayerSlot.color already is that slot's team colour. If team colours are ever disambiguated from
## per-slot colours, this is the one line to change.
##
## `is_player_placement` (default true) distinguishes a genuine player placement/auto-drop from
## spawn_special_projectile()'s effect spawns, the only caller passing false. See MatchStats.gd's
## header comment for why blocks_placed cannot simply listen on Events.block_placed.
func _spawn_block(
	shape: BlockShape,
	world_origin: Vector3,
	basis: Basis,
	slot_id: int,
	is_player_placement: bool = true,
	gift_id: StringName = &"",
	faced_basis: Variant = null
) -> Block:
	var acting_slot: PlayerSlot = _match.slot(slot_id)
	var color: Color = acting_slot.color if acting_slot != null else Color.WHITE
	var block: Block = BlockFactory.build(shape, _match._physics_tuning, slot_id, color)
	_match._blocks_parent.add_child(block)
	# a gift is never rotated by its owner (rotate actions are no-ops while
	# one is held), so the host spawns it upright whatever pose the intent carried.
	var pose_basis: Basis = _spawn_basis(gift_id, basis)
	if faced_basis is Basis:
		pose_basis = faced_basis as Basis
	block.global_transform = Transform3D(pose_basis, world_origin)
	# a used gift is delivered as its gift model, not as a
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
	if _match._replicator != null:
		_match._replicator.replicate_spawn(block, block.net_id)
	# _spawn_block() does NOT itself pop/attach a pending special (see _attach_pending_special()'s DECISION): a
	# burned block must not consume the queue, and only the caller knows whether the spawn it asked
	# for will be burned.
	return block


## Pops the head id `slot_id`'s queue was holding (the special TYPE was already drawn at claim time
## by MatchGifts' weighted drawer) and, if it resolves to a real, roster-enabled SpecialDef,
## attaches a bound SpecialBehavior. Called explicitly by request_place() (only on its non-burn
## path) and request_throw() (always -- a throw is never a burn); a placed special arms exactly like
## a thrown one, only the launch velocity differs.
##
## DECISION: deliberately NOT called from _spawn_block(): popping there ran before the caller knew
## whether the block was about to be burned (a forced auto-drop with nowhere valid to land), so an
## unlucky expiry could destroy a queued special for nothing. Each call site decides for itself,
## only on a path that keeps the block.
##
## Both call sites are host-only, so every attach and every Events.special_triggered forward this
## produces happens on the host only.
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


## host-only (behaviors only exist host-side). Removes a
## completed gift body through the normal block-removal bus: BlockRegistry
## drops it and bumps the territory revision, MatchNet replicates the despawn.
## DECISION: uses Events.REASON_GIFT_DESPAWN, which neither the kill-plane
## burst (BlockEffectsManager) nor blocks_lost (MatchStats) react to.
func _on_gift_completed(block: Block) -> void:
	if block == null or not is_instance_valid(block) or block.is_queued_for_deletion():
		return
	Events.block_removed.emit(block, String(Events.REASON_GIFT_DESPAWN))
	block.queue_free()


## the held gift id `slot_id` would deliver if it spawned
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
		# The default drawer's placeholder: MatchGifts has not installed its real weighted drawer
		# (empty roster). Safe default: spawn exactly as an ordinary block.
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


## The bind+arm mechanics _attach_pending_special() uses for a gift-drawn special, factored out so
## spawn_special_projectile() can bind a runtime-built SpecialDef/SpecialTuning pair (e.g. a Volcano
## lava orb) the same way without duplicating these four lines.
func _arm_special_behavior(block: Block, def: SpecialDef, tuning: SpecialTuning) -> SpecialBehavior:
	var behavior: SpecialBehavior = SpecialBehavior.new()
	block.add_child(behavior)
	behavior.bind(block, def, tuning)
	behavior.triggered.connect(_on_special_behavior_triggered.bind(block.net_id))
	return behavior


## Forwards SpecialBehavior's `triggered` signal into Events.special_triggered. `net_id` is bound at
## connect time in _arm_special_behavior() rather than read from `block` here, so a freed block
## between trigger and forward can never matter.
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


## Keeps a burn's disk-local spawn point (x/z only, in Field's local space) inside Field's kill
## plane, so a body that gets thrown off never free-falls past it. Preserves direction and only
## shortens the vector, so an on-disk or near-disk burn (the overwhelming common case) is returned
## unchanged -- this only fires for the far-off-disk case a hostile or buggy client can still
## produce.
##
## DECISION: the safe radius is derived from Field's KILL_PLANE_RADIUS_FACTOR (the one
## _build_kill_plane() uses to size the box) times this match's map_def.field_radius, rather than a
## new literal here, so the clamp and the box can never drift apart.
func _clamp_disk_origin_for_burn(disk_origin: Vector2) -> Vector2:
	if _match._field == null or _match._field.map_def == null:
		return disk_origin
	var half_extent: float = (
		_match._field.map_def.field_radius * Field.KILL_PLANE_RADIUS_FACTOR * 0.5 * _BURN_CLAMP_MARGIN
	)
	return disk_origin.limit_length(half_extent)


## Spec 1.5: a rejected block "is thrown off the map with a visible reject animation". Only an
## auto_drop (a forced release with no valid relocation point) reaches this; a manual release is
## refused before a block is spawned. The impulse points radially outward from the disk center,
## blended with an upward component (TerritoryTuning.reject_impulse / reject_upward_fraction) so it
## visibly launches rather than just sliding.
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
## PlacementRules.closest_valid_point() relocates from there as usual.
func default_ghost_origin(slot_id: int) -> Vector3:
	var target: PlayerSlot = _match.slot(slot_id)
	if target == null or _match._field == null:
		return Vector3.ZERO
	# the first block starts back from the beacon (away from the
	# field centre, the camera's side), not on top of it. Shared by the player's
	# first ghost (set_home_position) and the host's AFK auto-drop.
	var local_home: Vector3 = Vector3(target.home_position.x, 0.0, target.home_position.y)
	return _match._field.to_global(_ghost_tuning.home_spawn_back_position(local_home))


func _clear_blocks() -> void:
	_aim_by_slot.clear()
	# In-place activation anchors (Earthquake etc.) are not under _blocks_parent; free them on every
	# reset/abort too, not only via the lifetime backstop.
	_activation.clear()
	if _match._blocks_parent == null:
		return
	for child: Node in _match._blocks_parent.get_children():
		child.queue_free()


## this match's thrown-gift range scale (GiftAim.range_scale of the field radius);
## 1.0 while no field exists.
func _throw_range_scale() -> float:
	if _match._field == null or _match._field.map_def == null:
		return 1.0
	return GiftAim.range_scale(_match._field.map_def.field_radius, _special_tuning)
