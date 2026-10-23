class_name FusedBody
extends Block
## Glue fusion: the one Jolt body of a
## group of glued blocks. It owns every member's CollisionShape3D (reparented, local
## pose preserved) and `mass`; the member Blocks stay as identity "followers" (net_id,
## meshes) posed from this body each tick. Never registered, never replicated,
## net_id stays -1. Host-only: only the host builds one (GlueFusion).
##
## A group holding a disc anchor is kinematic and rides the Field (a STATIC body would
## not follow a tilting disc, see game/blocks/StableBlockManager.gd); when the
## last anchored member goes it turns dynamic and falls under normal physics.

## Runs after Field's own _physics_process (priority 0) so an anchored carrier reads the
## disc pose of the same tick. DECISION: a structural ordering constant, not a tunable.
const ANCHOR_PROCESS_PRIORITY: int = 10
## Scan sentinel: no member seen yet (distinct from -1, the real "no slot").
const SLOT_UNSET: int = -2
## Mirrors SnowCaps.LUMP_META (no class edge: it would grow the layer-lint cycle); test-pinned.
const SNOW_LUMP_META: StringName = &"snow_lump"

var members: Array[Block] = []
## instance id (int) -> true; non-empty = disc-anchored.
var anchored_members: Dictionary = {}
## The disc this group is anchored to (null while free).
var anchor_field: FieldBody = null
## carrier -> anchor field pose captured when the anchor formed (carrier = field * anchor_local).
var anchor_local: Transform3D = Transform3D.IDENTITY

## member instance id -> Transform3D of the member in this body's frame.
var _offsets: Dictionary = {}
## member instance id -> Array[CollisionShape3D] this body owns for that member.
var _shapes: Dictionary = {}
var _last_sync_xform: Transform3D = Transform3D.IDENTITY
var _last_sync_linear: Vector3 = Vector3.ZERO
var _last_sync_angular: Vector3 = Vector3.ZERO
var _synced_once: bool = false
var _synced_frame: int = -1
## Consecutive physics ticks the anchored carrier pose has not changed (see GlueDropTuning.anchor_rest_ticks).
var _anchor_still_ticks: int = 0
var _anchor_refresh_frame: int = -1
## GlueDropTuning.anchor_rest_ticks, set by GlueFusion before the carrier enters the tree (an int, not the Resource: naming GlueDropTuning here pulls it into the Main scene closure, layer lint).
var anchor_rest_ticks: int = 1
var _anchor_prev_xform: Transform3D = Transform3D.IDENTITY
## Physics frame of the last add/remove of a collision shape: contact shape indices read from
## the physics state predate it (GlueDrops skips attribution that frame).
var shape_change_frame: int = -1
var _glow_sleeping: bool = false


func _init() -> void:
	name = &"FusedBody"
	_release_checked = true
	process_physics_priority = ANCHOR_PROCESS_PRIORITY


## Copies the physics settings of `template` (the first block the group is built around).
## Call before the body enters the tree.
func setup_from(template: Block) -> void:
	tuning = template.tuning
	physics_material_override = template.physics_material_override
	linear_damp_mode = template.linear_damp_mode
	angular_damp_mode = template.angular_damp_mode
	linear_damp = template.linear_damp
	angular_damp = template.angular_damp
	gravity_scale = template.gravity_scale
	can_sleep = template.can_sleep
	continuous_cd = template.continuous_cd
	collision_layer = template.collision_layer
	collision_mask = template.collision_mask


func is_disc_anchored() -> bool:
	return not anchored_members.is_empty()


func member_shapes(member: Block) -> Array[CollisionShape3D]:
	var result: Array[CollisionShape3D] = []
	if member == null or not _shapes.has(member.get_instance_id()):
		return result
	for shape: CollisionShape3D in (_shapes[member.get_instance_id()] as Array):
		if is_instance_valid(shape):
			result.append(shape)
	return result


func member_offset(member: Block) -> Transform3D:
	return _offsets.get(member.get_instance_id(), Transform3D.IDENTITY) as Transform3D


func total_cubes() -> int:
	var total: int = 0
	for member: Block in members:
		if is_instance_valid(member):
			total += member.cube_count
	return total


## Members with any collision shape origin within `radius` of `center` (world space).
func members_in_sphere(center: Vector3, radius: float) -> Array[Block]:
	var result: Array[Block] = []
	for member: Block in members:
		if is_instance_valid(member) and _member_distance(member, center) <= radius:
			result.append(member)
	return result


func _member_distance(member: Block, world_point: Vector3) -> float:
	var best: float = INF
	for shape: CollisionShape3D in member_shapes(member):
		best = minf(best, shape.global_position.distance_to(world_point))
	return best


## Mass-weighted centre of mass of every member in this body's frame (applied as the
## CUSTOM centre of mass; exposed so tests and callers need not wait for a sync).
func local_center_of_mass() -> Vector3:
	var sum: Vector3 = Vector3.ZERO
	var total: float = 0.0
	for member: Block in members:
		if not is_instance_valid(member):
			continue
		sum += member_offset(member) * member.center_of_mass * member.mass
		total += member.mass
	return sum / total if total > 0.0 else Vector3.ZERO


## A disc-anchored carrier is kinematic and never sleeps for real: it stays out of the awake set.
func _apply_awake(awake: bool) -> void:
	super(awake and not is_disc_anchored())


## Re-derives the carrier's slot (members converted by Paintball).
func refresh_owner() -> void:
	_refresh_mass_and_owner()


## A disc-anchored group is "asleep" once the disc has not moved it for anchor_rest_ticks ticks;
## a tilt (pose change) wakes it so clients keep following the disc.
func net_sleeping() -> bool:
	if is_disc_anchored():
		return _anchor_still_ticks >= anchor_rest_ticks
	return sleeping


## Host glow: followers are frozen kinematic and never fire their own sleeping_state_changed, so
## the carrier's rest state (net_sleeping) drives their "contributing" overlay.
func _on_sleeping_state_changed() -> void:
	super()
	_refresh_member_glow()


func _refresh_member_glow() -> void:
	var rest: bool = net_sleeping()
	if rest == _glow_sleeping:
		return
	_glow_sleeping = rest
	for member: Block in members:
		if is_instance_valid(member):
			member.set_contributing_visual(rest)


# --- Membership -----------------------------------------------------------------

## Takes an unfused, in-tree Block into the group: its shapes move here, it becomes a follower.
func adopt(block: Block) -> void:
	if block == null or members.has(block) or block.is_fused_member():
		return
	var shapes: Array[CollisionShape3D] = []
	for child: Node in block.get_children():
		# Snow lump colliders stay with their block: SnowCaps melts/rebuilds them there.
		if child is CollisionShape3D and not child.has_meta(SNOW_LUMP_META):
			shapes.append(child as CollisionShape3D)
	var com: Vector3 = shapes_center_of_mass(shapes)
	var inverse: Transform3D = global_transform.affine_inverse()
	_take_shapes(block.get_instance_id(), shapes, inverse * block.global_transform)
	var stable_dropped: Dictionary = block._freeze_reasons.duplicate()
	block.become_follower(self, com)
	_offsets[block.get_instance_id()] = inverse * block.global_transform
	members.append(block)
	_watch(block)
	block.reset_physics_interpolation()
	for reason: StringName in stable_dropped.keys():
		if reason != FREEZE_REASON_STABLE:
			request_freeze_static(reason)
	FreezeEffect.transfer_hold(block, self)
	block.set_contributing_visual(_glow_sleeping)
	_after_membership_gain()


## Moves every member (and its shapes) of `other` into this body and frees `other`.
func absorb_group(other: FusedBody) -> void:
	if other == null or other == self:
		return
	var relative: Transform3D = global_transform.affine_inverse() * other.global_transform
	for member: Block in other.members.duplicate():
		var shapes: Array[CollisionShape3D] = other.member_shapes(member)
		_take_shapes(member.get_instance_id(), shapes, relative)
		_offsets[member.get_instance_id()] = relative * other.member_offset(member)
		other._unwatch(member)
		member.retarget_follower(self)
		members.append(member)
		_watch(member)
		member.reset_physics_interpolation()
		member.set_contributing_visual(_glow_sleeping)
	for reason: StringName in other._freeze_reasons.keys():
		if reason != FREEZE_REASON_STABLE:
			request_freeze_static(reason)
	FreezeEffect.transfer_hold(other, self)
	for id: int in other.anchored_members.keys():
		anchored_members[id] = true
	if other.is_disc_anchored() and not is_disc_anchored_field_set():
		anchor_field = other.anchor_field
		anchor_local = anchor_field.global_transform.affine_inverse() * global_transform
	other.members.clear()
	other.anchored_members.clear()
	other._offsets.clear()
	other._shapes.clear()
	other.queue_free()
	if is_disc_anchored():
		_enter_anchor_mode()
	_after_membership_gain()


func is_disc_anchored_field_set() -> bool:
	return anchor_field != null and is_instance_valid(anchor_field)


## Disc fusion: `member` (a member of this body) is glued to `field`; the whole group now
## rides the disc.
func anchor_to_field(field: FieldBody, member: Block) -> void:
	if field == null or member == null or not members.has(member):
		return
	if not is_disc_anchored_field_set():
		anchor_field = field
		anchor_local = field.global_transform.affine_inverse() * global_transform
	anchored_members[member.get_instance_id()] = true
	_enter_anchor_mode()


## Removes one member (dissolved, killed): its shapes leave, mass and COM follow, its
## block_removed fires and the Block is freed. One member left collapses the body.
func remove_member(member: Block, reason: StringName) -> void:
	if member == null or not members.has(member):
		return
	_forget(member, true)
	Events.block_removed.emit(member, String(reason))
	member.queue_free()
	_after_membership_loss()


## Every member leaves (kill plane, black hole): one block_removed each, then the body ends.
func remove_all_members(reason: StringName) -> void:
	for member: Block in members.duplicate():
		if not is_instance_valid(member):
			members.erase(member)
			continue
		# Shapes stay: the whole body is freed below, and this can run inside an Area3D
		# callback (kill plane) where removing shapes is not allowed.
		_forget(member, false)
		Events.block_removed.emit(member, String(reason))
		member.queue_free()
	_after_membership_loss()


## Routes an externally freed/removed member (kill plane, black hole, dissolve outside
## this API) through remove_member. DECISION: shape removal is deferred because the free
## can come from inside a physics callback; bookkeeping, mass and COM update at once.
func _watch(member: Block) -> void:
	var callback: Callable = _on_member_exiting.bind(member)
	if not member.tree_exiting.is_connected(callback):
		member.tree_exiting.connect(callback)


func _unwatch(member: Block) -> void:
	if not is_instance_valid(member):
		return
	var callback: Callable = _on_member_exiting.bind(member)
	if member.tree_exiting.is_connected(callback):
		member.tree_exiting.disconnect(callback)


func _on_member_exiting(member: Block) -> void:
	if not members.has(member) or not is_inside_tree() or is_queued_for_deletion():
		return
	var shapes: Array[CollisionShape3D] = member_shapes(member)
	_forget(member, false)
	for shape: CollisionShape3D in shapes:
		_discard_shape.call_deferred(shape)
	Events.block_removed.emit(member, String(&"freed"))
	_after_membership_loss()


func _discard_shape(shape: CollisionShape3D) -> void:
	shape_change_frame = Engine.get_physics_frames()
	if is_instance_valid(shape):
		if shape.get_parent() == self:
			remove_child(shape)
		shape.queue_free()


func _forget(member: Block, drop_shapes: bool) -> void:
	_unwatch(member)
	var id: int = member.get_instance_id()
	shape_change_frame = Engine.get_physics_frames()
	if drop_shapes:
		for shape: CollisionShape3D in member_shapes(member):
			remove_child(shape)
			shape.queue_free()
	_shapes.erase(id)
	_offsets.erase(id)
	anchored_members.erase(id)
	members.erase(member)


func _after_membership_gain() -> void:
	_refresh_mass_and_owner()
	# A new member needs real physics: the stable-block freeze is dropped (other holds stay).
	release_freeze_static(FREEZE_REASON_STABLE)
	if is_disc_anchored():
		_enter_anchor_mode()
	else:
		wake()
	_synced_once = false
	sync_followers()


func _after_membership_loss() -> void:
	if members.is_empty():
		queue_free()
		return
	# A lost member may have been the support: drop the stable-block freeze like the gain
	# path does (other holds stay) so the rest falls instead of hanging static in the air.
	release_freeze_static(FREEZE_REASON_STABLE)
	if is_disc_anchored_field_set() and not is_disc_anchored():
		_leave_anchor_mode()
	# DECISION: a lone survivor that still holds the disc anchor stays in a one-member body
	# (collapsing it would drop the disc bond); otherwise one member collapses to a Block.
	if members.size() == 1 and not is_disc_anchored():
		_collapse()
		return
	_refresh_mass_and_owner()
	if not is_disc_anchored():
		wake()
	_synced_once = false
	sync_followers()


## One member left and no disc anchor: it gets its shapes back and is a plain dynamic Block.
func _collapse() -> void:
	var survivor: Block = members[0]
	_unwatch(survivor)
	shape_change_frame = Engine.get_physics_frames()
	sync_followers()
	var body_xform: Transform3D = global_transform
	var offset: Transform3D = member_offset(survivor)
	var linear: Vector3 = linear_velocity
	var angular: Vector3 = angular_velocity
	var reasons: Array = _freeze_reasons.keys()
	reasons.erase(FREEZE_REASON_STABLE)
	var inverse: Transform3D = offset.affine_inverse()
	for shape: CollisionShape3D in member_shapes(survivor):
		var local: Transform3D = inverse * shape.transform
		remove_child(shape)
		survivor.add_child(shape)
		shape.transform = local
	_shapes.erase(survivor.get_instance_id())
	members.clear()
	_offsets.clear()
	survivor.global_transform = body_xform * offset
	survivor.release_follower()
	survivor.reset_physics_interpolation()
	survivor.linear_velocity = linear
	survivor.angular_velocity = angular
	for reason: StringName in reasons:
		survivor.request_freeze_static(reason)
	FreezeEffect.transfer_hold(self, survivor)
	if reasons.is_empty():
		survivor.wake()
	Events.fused_member_released.emit(survivor)
	queue_free()


func _refresh_mass_and_owner() -> void:
	var total: float = 0.0
	var slot: int = SLOT_UNSET
	for member: Block in members:
		if not is_instance_valid(member):
			continue
		total += member.mass
		if slot == SLOT_UNSET:
			slot = member.owner_slot
		elif slot != member.owner_slot:
			slot = -1
	if total > 0.0:
		mass = total
	# Jolt's AUTO centre of mass weights by shape volume; members can differ in mass.
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = local_center_of_mass()
	owner_slot = maxi(slot, -1)


## Moves `shapes` under this body for member `member_id`; `shape_frame_to_self` maps the
## frame the shapes' transforms are expressed in (the block, or the source body on a
## merge) into this body's frame.
func _take_shapes(member_id: int, shapes: Array[CollisionShape3D], shape_frame_to_self: Transform3D) -> void:
	var moved: Array[CollisionShape3D] = []
	for shape: CollisionShape3D in shapes:
		var local: Transform3D = shape_frame_to_self * shape.transform
		shape.get_parent().remove_child(shape)
		add_child(shape)
		shape.transform = local
		moved.append(shape)
	_shapes[member_id] = moved
	shape_change_frame = Engine.get_physics_frames()


## Volume-weighted centroid of box shapes in their parent's frame.
static func shapes_center_of_mass(shapes: Array[CollisionShape3D]) -> Vector3:
	var sum: Vector3 = Vector3.ZERO
	var total: float = 0.0
	for shape: CollisionShape3D in shapes:
		var weight: float = 1.0
		if shape.shape is BoxShape3D:
			var size: Vector3 = (shape.shape as BoxShape3D).size
			weight = size.x * size.y * size.z
		sum += shape.transform.origin * weight
		total += weight
	return sum / total if total > 0.0 else Vector3.ZERO


# --- Follower sync and disc anchor ----------------------------------------------------

## Writes every follower's world pose (and mirrored velocities) from this body.
func sync_followers() -> void:
	var xform: Transform3D = global_transform
	var linear: Vector3 = linear_velocity
	var angular: Vector3 = angular_velocity
	_synced_frame = Engine.get_physics_frames()
	if _synced_once and xform == _last_sync_xform and linear == _last_sync_linear and angular == _last_sync_angular:
		return
	_synced_once = true
	_last_sync_xform = xform
	_last_sync_linear = linear
	_last_sync_angular = angular
	for member: Block in members:
		if not is_instance_valid(member):
			continue
		member.global_transform = xform * member_offset(member)
		member.linear_velocity = linear
		member.angular_velocity = angular


func _batch_tick(frame: int, physics_active: bool, damp_on: bool, damp: float, noise_floor: float, impacts_on: bool, impact_min: float, impact_min_sq_lo: float) -> void:
	sync_followers()
	super(frame, physics_active, damp_on, damp, noise_floor, impacts_on, impact_min, impact_min_sq_lo)


func _physics_process(_delta: float) -> void:
	if is_disc_anchored():
		_pose_from_disc()
		if global_transform == _anchor_prev_xform:
			_anchor_still_ticks += 1
		else:
			_anchor_still_ticks = 0
		_anchor_prev_xform = global_transform
	elif _synced_frame != Engine.get_physics_frames():
		sync_followers()
	_refresh_member_glow()


## Re-poses an anchored carrier (and its followers) from the disc as it is right now. Idempotent;
## SnapshotSync calls it before recording so a client sees the disc and the followers of the same
## moment even though this node's own tick (priority 10) runs after the snapshot's.
func refresh_anchor_pose() -> void:
	if not is_disc_anchored():
		return
	# Once per carrier per tick (SnapshotSync asks once per follower); the carrier's own tick
	# (_physics_process) re-poses unconditionally via _pose_from_disc().
	var frame: int = Engine.get_physics_frames()
	if _anchor_refresh_frame == frame:
		return
	_anchor_refresh_frame = frame
	_pose_from_disc()


func _pose_from_disc() -> void:
	if is_disc_anchored_field_set():
		global_transform = anchor_field.global_transform * anchor_local
	sync_followers()


func _enter_anchor_mode() -> void:
	_anchor_still_ticks = 0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	_apply_awake(false)


func _leave_anchor_mode() -> void:
	anchor_field = null
	if _freeze_reasons.is_empty():
		freeze = false
		wake()
	elif get_node_or_null(NodePath(FreezeEffect.RIDER_NAME)) != null:
		# A Freeze hold rides the disc (kinematic), see FreezeEffect.freeze_block.
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	else:
		freeze_mode = RigidBody3D.FREEZE_MODE_STATIC


func request_freeze_static(reason: StringName) -> void:
	super(reason)
	if is_disc_anchored():
		_enter_anchor_mode()


func release_freeze_static(reason: StringName) -> void:
	super(reason)
	if is_disc_anchored():
		_enter_anchor_mode()
