class_name FreezeEffect
extends SpecialEffect
## Freeze gift (spec 2.6 "[NEW] defensive": the owner's own blocks within 6 m
## become static for 20 s). Ordinary impact/fuse special: everything happens
## once, in detonate(). The gift body despawns when the action completes
## (SpecialBehavior.completed), which does not end the freeze: each frozen
## block carries its own release Timer child.
##
## DECISION: a SpecialDef's `effect` is one shared Resource, so this effect keeps
## no per-activation state; the release Timer is a child node of each frozen
## block (a second Freeze on an already frozen block restarts that timer).
##
## DECISION (explosions/Magnet): Freeze deliberately wins. The hold is keyed
## by FREEZE_REASON, and SpecialPhysics.wake_and_impulse() releases only
## Block.FREEZE_REASON_STABLE, so a frozen block ignores blasts and pulls (an
## impulse on a STATIC body is a no-op; wake_and_impulse() skips it) until the
## timer ends. A block already stably frozen keeps that separate hold, so it
## is still frozen after Freeze releases.

@export var freeze_radius_m: float = 6.0
@export var freeze_duration_s: float = 20.0

const FREEZE_REASON: StringName = &"freeze_special"
const TIMER_NAME: StringName = &"FreezeReleaseTimer"
const RIDER_NAME: StringName = &"FreezeFieldRider"


## DECISION (Bontago-8or.2 review): the Freeze hold is KINEMATIC, not STATIC,
## and rides the Field. A STATIC body does not follow the tilting
## AnimatableBody3D disc, so held blocks floated or were swept. Each held
## block stores its field-local transform at hold time and this child
## re-applies field.global_transform * local every physics tick the disc moved.
## Unlike the stable-block hold (StableBlockManager releases it on any disc
## motion, spec 3.5), a Freeze hold is NOT released by a tilt: Freeze is
## defensive, so the tower tilts with the disc as one rigid piece. Moved from
## _physics_process, the node's interpolated visual follows without jitter.
class FieldRider:
	extends Node
	var field: Node3D
	var local: Transform3D = Transform3D.IDENTITY
	var _last_field: Transform3D = Transform3D.IDENTITY

	func bind(target_field: Node3D, body: Node3D) -> void:
		field = target_field
		_last_field = field.global_transform
		local = _last_field.affine_inverse() * body.global_transform

	func _physics_process(_delta: float) -> void:
		var body: Node3D = get_parent() as Node3D
		if body == null or field == null or not is_instance_valid(field):
			return
		var current: Transform3D = field.global_transform
		if current == _last_field:
			return
		_last_field = current
		body.global_transform = current * local


func detonate(block: Block, behavior: SpecialBehavior, _chain_depth: int) -> void:
	if block == null or not block.is_inside_tree():
		return
	if Net.is_client():
		return
	var owner_slot: int = block.owner_slot
	var own_filter: Callable = func(body: RigidBody3D) -> bool:
		var candidate: Block = body as Block
		return candidate != null and candidate.owner_slot == owner_slot
	var neighbors: Array[RigidBody3D] = SpecialPhysics.query_bodies_in_range(
		block.get_world_3d().direct_space_state, block.global_position, freeze_radius_m, [block.get_rid()], own_filter
	)
	for body: RigidBody3D in neighbors:
		var target: Block = body as Block
		if target != null:
			freeze_block(target)
	# DECISION: a gift body that despawns is never frozen itself (it is about
	# to be removed); a bare sandbox/test special that stays is "your own block".
	if behavior == null or not behavior.despawn_when_done:
		freeze_block(block)


## Freezes `target` under FREEZE_REASON and (re)starts its release timer.
## `field` is the disc the hold rides (default Match.field(); none = fixed in
## world space).
func freeze_block(target: Block, field: Node3D = null) -> void:
	# Zero the motion so the registry settles it (a STATIC body keeps no
	# velocity of its own) and it resumes from rest on release.
	target.linear_velocity = Vector3.ZERO
	target.angular_velocity = Vector3.ZERO
	target.request_freeze_static(FREEZE_REASON)
	target.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	if field == null:
		field = Match.field()
	if field != null and is_instance_valid(field):
		var rider: FieldRider = target.get_node_or_null(NodePath(RIDER_NAME)) as FieldRider
		if rider == null:
			rider = FieldRider.new()
			rider.name = RIDER_NAME
			target.add_child(rider)
		rider.bind(field, target)
	_set_visual(target, true)
	var timer: Timer = target.get_node_or_null(NodePath(TIMER_NAME)) as Timer
	if timer == null:
		timer = Timer.new()
		timer.name = TIMER_NAME
		timer.one_shot = true
		target.add_child(timer)
		timer.timeout.connect(_on_release_timeout.bind(target, timer))
	timer.start(freeze_duration_s)


func _on_release_timeout(target: Block, timer: Timer) -> void:
	if is_instance_valid(target):
		release_hold(target)
	if is_instance_valid(timer):
		timer.queue_free()


## Ends the Freeze hold on `target` now (timer, rider, visual, body hold).
## Used by the timer and by HoleDissolver, whose dissolve overrides the hold.
static func release_hold(target: Block) -> void:
	if target == null or not is_instance_valid(target):
		return
	for node_name: StringName in [TIMER_NAME, RIDER_NAME]:
		var node: Node = target.get_node_or_null(NodePath(node_name))
		if node != null:
			target.remove_child(node)
			node.queue_free()
	if not target.is_frozen_visual() and not target.is_freeze_static():
		return
	target.release_freeze_static(FREEZE_REASON)
	_set_visual(target, false)


static func _set_visual(target: Block, frozen: bool) -> void:
	target.set_frozen_visual(frozen)
	if target.net_id > 0:
		Events.block_frozen_changed.emit(target.net_id, frozen)
