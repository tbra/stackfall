class_name GlueDrops
extends Node
## Monitors only a charged drop. The host fuses its real collision contacts
## (GlueFusion) with the disc or another block; ordinary blocks incur no contact-monitor cost.

var _block: Block = null
var _tuning: GlueDropTuning = null


func bind(block: Block, tuning: GlueDropTuning) -> void:
	_block = block
	_tuning = tuning
	block.contact_monitor = true
	block.max_contacts_reported = maxi(block.max_contacts_reported, tuning.max_contacts_reported)


func _physics_process(_delta: float) -> void:
	if _block == null or not is_instance_valid(_block) or _tuning == null:
		return
	if not _block.contact_monitor or _block.fused_carrier() != null:
		return
	for body: Node3D in _block.get_colliding_bodies():
		try_bond(body)


## Public seam for deterministic tests; live play calls this only for actual
## contacts reported by the charged RigidBody3D in _physics_process().
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
	# The block is now a follower with no shapes of its own: nothing left to monitor.
	set_physics_process(false)
	queue_free()
	return true


## "Bonded" now means "already in the same fused body" (Bontago-1pi.85.74.3).
func _has_bond(a: Block, b: PhysicsBody3D) -> bool:
	var carrier: RigidBody3D = a.fused_carrier()
	if carrier == null:
		return false
	if b == carrier:
		return true
	if b is Field:
		return carrier is FusedBody and (carrier as FusedBody).is_disc_anchored()
	return b is Block and (b as Block).fused_carrier() == carrier
