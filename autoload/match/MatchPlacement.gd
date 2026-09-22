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


func setup(match_ref: MatchAutoload) -> void:
	_match = match_ref


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
	if _match.state() != MatchAutoload.State.PLAYING or _match._field == null or _match._blocks_parent == null:
		return PlacementRules.REASON_NO_BLOCK
	if slot_id < 0 or slot_id >= _match.slot_count():
		return PlacementRules.REASON_NO_BLOCK
	if feed_seq >= 0 and feed_seq != _match.feed_seq(slot_id):
		return PlacementRules.REASON_NO_BLOCK
	var acting_slot: PlayerSlot = _match.slot(slot_id)
	if not acting_slot.home_flag_alive:
		return PlacementRules.REASON_NO_BLOCK
	if _match.config.hot_seat and slot_id != _match.active_slot():
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
	var spawned: Block = _spawn_block(shape, final_world_origin, basis, slot_id)
	if reason != PlacementRules.REASON_OK:
		# Owner decision (docs/M2_PLAN.md, "Invalid release — burn the block"),
		# narrowed by Bontago-mv0.24 to auto-drop only (see above): a forced
		# release that finds no valid point to relocate to still spawns the
		# block and throws it off the map; it is still consumed either way.
		_burn_block(spawned, final_disk_origin)
		Events.placement_rejected.emit(slot_id, reason)
	elif outcome["use_relocation"]:
		# Bontago-mv0.24: this auto-drop *did* find a valid point and landed
		# there instead of at the caller's raw ghost position -- tell the
		# owning client where, so its cursor and camera can jump to match
		# (game/PlayerController.gd's _on_placement_relocated).
		Events.placement_relocated.emit(slot_id, final_disk_origin)

	_match._feed._consume_and_refeed(slot_id, auto_drop)
	if _match.config.hot_seat:
		_match.advance_turn()

	return reason


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
	if _match.state() != MatchAutoload.State.PLAYING or _match.cell_grid() == null or _match.raster() == null or _match._field == null:
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
	return PlacementRules.validate_point(hit as Vector2, _match.raster(), team_id)


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
func _spawn_block(shape: BlockShape, world_origin: Vector3, basis: Basis, slot_id: int) -> Block:
	var acting_slot: PlayerSlot = _match.slot(slot_id)
	var color: Color = acting_slot.color if acting_slot != null else Color.WHITE
	var block: Block = BlockFactory.build(shape, _match._physics_tuning, slot_id, color)
	_match._blocks_parent.add_child(block)
	block.global_transform = Transform3D(basis, world_origin)
	# block_placed is what makes BlockRegistry allocate the net_id, so the
	# replication below has to come after it: the reliable spawn RPC must
	# carry the same id the (unreliable) snapshots will address the body by.
	Events.block_placed.emit(block, shape.id)
	_blocks_spawned += 1
	if _match._replicator != null:
		_match._replicator.replicate_spawn(block, block.net_id)
	return block


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
	return _match._field.to_global(Vector3(target.home_position.x, 0.0, target.home_position.y))


func _clear_blocks() -> void:
	if _match._blocks_parent == null:
		return
	for child: Node in _match._blocks_parent.get_children():
		child.queue_free()
