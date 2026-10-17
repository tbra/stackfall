class_name GlueDrops
extends Node
## Monitors only a charged drop. The host fuses its real collision contacts
## (GlueFusion) with the disc or another block; ordinary blocks incur no contact-monitor cost.

const WINDOW_GROUP: StringName = &"glue_drop_window"

var _block: Block = null
var _tuning: GlueDropTuning = null
var _window_left: float = -1.0


func bind(block: Block, tuning: GlueDropTuning) -> void:
	_block = block
	_tuning = tuning
	block.contact_monitor = true
	block.max_contacts_reported = maxi(block.max_contacts_reported, tuning.max_contacts_reported)


func _physics_process(delta: float) -> void:
	if _block == null or not is_instance_valid(_block) or _tuning == null:
		return
	if _window_left >= 0.0:
		_window_tick(delta)
		return
	if not _block.contact_monitor or _block.fused_carrier() != null:
		return
	for body: Node3D in _block.get_colliding_bodies():
		try_bond(body)


## Public seam for deterministic tests; live play calls this only for actual
## contacts reported by the charged RigidBody3D in _physics_process().
## The first successful fuse opens the settle window (see _begin_window).
func try_bond(other: Node3D) -> bool:
	if _block == null or not is_instance_valid(_block) or other == null or not is_instance_valid(other):
		return false
	if other == _block or not (other is Block or other is Field):
		return false
	var target: PhysicsBody3D = other as PhysicsBody3D
	if target == null or _has_bond(_block, target):
		return false
	# GlueFusion applies absorb_impact itself and refuses gifts / over-cap groups.
	# Runs from _physics_process (outside the physics step), so reparenting shapes is safe.
	if GlueFusion.fuse(_block, target, _tuning) == null:
		return false
	_begin_window()
	return true


## DECISION: bonding to every touched body would glue a block bridging two stacks to
## both. After the first fuse the block is a shapeless follower, so for `fuse_window_s`
## the contacts of the CHARGED block's own shapes on the carrier are fused too (default
## 0.25 s ~ the first settle; 0 = first tick only), then GlueDrops frees itself. Only the
## charged block's shapes count: a body touching some other member of the group is not
## fused, and the disc anchors the group only when the charged block's own shape touches it.
func _begin_window() -> void:
	if _window_left >= 0.0:
		return
	_window_left = _tuning.fuse_window_s
	var carrier: FusedBody = _block.fused_carrier() as FusedBody
	if carrier != null and _window_left > 0.0:
		_enable_monitor(carrier)
		add_to_group(WINDOW_GROUP)
	if _window_left <= 0.0:
		_finish()


func _enable_monitor(carrier: FusedBody) -> void:
	carrier.contact_monitor = true
	carrier.max_contacts_reported = maxi(carrier.max_contacts_reported, _tuning.max_contacts_reported)


func _window_tick(delta: float) -> void:
	var carrier: FusedBody = _block.fused_carrier() as FusedBody
	if carrier == null:
		_finish()
		return
	if not carrier.contact_monitor:
		_enable_monitor(carrier)
	for body: Node3D in _own_contacts(carrier):
		try_bond(body)
	_window_left -= delta
	if _window_left <= 0.0:
		_finish()


## Bodies touching the charged block's own shapes (not the rest of the carrier).
func _own_contacts(carrier: FusedBody) -> Array[Node3D]:
	var result: Array[Node3D] = []
	# Contact shape indices predate this frame's shape edits (a member left, a merge): skip a tick
	# rather than attribute a contact to the wrong member's shape.
	if carrier.shape_change_frame == Engine.get_physics_frames():
		return result
	var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(carrier.get_rid())
	if state == null:
		return result
	var own: Array[CollisionShape3D] = carrier.member_shapes(_block)
	for index: int in range(state.get_contact_count()):
		var owner_id: int = carrier.shape_find_owner(state.get_contact_local_shape(index))
		if owner_id < 0 or not own.has(carrier.shape_owner_get_owner(owner_id) as CollisionShape3D):
			continue
		var body: Node3D = state.get_contact_collider_object(index) as Node3D
		if body != null and not result.has(body):
			result.append(body)
	return result


func _finish() -> void:
	set_physics_process(false)
	if is_in_group(WINDOW_GROUP):
		remove_from_group(WINDOW_GROUP)
	if _block != null and is_instance_valid(_block):
		var carrier: FusedBody = _block.fused_carrier() as FusedBody
		if carrier != null and is_instance_valid(carrier) and not _other_window_open(carrier):
			carrier.contact_monitor = false
	queue_free()


## Another charged drop still in its window on `carrier` keeps the contact reports on.
func _other_window_open(carrier: FusedBody) -> bool:
	if not is_inside_tree():
		return false
	for node: Node in get_tree().get_nodes_in_group(WINDOW_GROUP):
		var other: GlueDrops = node as GlueDrops
		if other != null and other != self and is_instance_valid(other._block) and other._block.fused_carrier() == carrier:
			return true
	return false


## A bond means "already in the same fused body".
func _has_bond(a: Block, b: PhysicsBody3D) -> bool:
	var carrier: RigidBody3D = a.fused_carrier()
	if carrier == null:
		return false
	if b == carrier:
		return true
	if b is Field:
		return carrier is FusedBody and (carrier as FusedBody).is_disc_anchored()
	return b is Block and (b as Block).fused_carrier() == carrier
