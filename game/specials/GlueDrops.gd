class_name GlueDrops
extends Node
## Monitors only a charged drop. The host bonds its real collision contacts
## to the disc or another block; ordinary blocks incur no contact-monitor cost.

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
	if _tuning.absorb_impact:
		_absorb_impact(target)
	var joint: Generic6DOFJoint3D = Generic6DOFJoint3D.new()
	joint.node_a = _block.get_path()
	joint.node_b = target.get_path()
	var bond: GlueJoint = GlueJoint.new()
	bond.add_child(joint)
	_block.add_child(bond)
	bond.bind(
		joint, _block, target, _tuning.break_force, _tuning.break_separation_m, _tuning.break_speed_mps, _tuning.break_shock_mps
	)
	return true


## The bond is stored under whichever charged Block first saw the contact.
## Looking on both Blocks prevents a second joint if both were charged.
func _has_bond(a: Block, b: PhysicsBody3D) -> bool:
	for child: Node in a.get_children():
		if child is GlueJoint and (child as GlueJoint).bodies_match(a, b):
			return true
	if b is Block:
		for child: Node in b.get_children():
			if child is GlueJoint and (child as GlueJoint).bodies_match(a, b):
				return true
	return false


## Glue is inelastic (Bontago-1pi.85.65): the charged block's momentum relative to
## what it hit is soaked up when the bond forms, so a block landing off an edge
## does not carry its impact spin into the pair and topple it off the support.
## The bond forms a tick after first contact, so the impact is already partly
## resolved; this zeroes the relative velocity and the glued block's spin.
func _absorb_impact(target: PhysicsBody3D) -> void:
	var partner_velocity: Vector3 = (target as RigidBody3D).linear_velocity if target is RigidBody3D else Vector3.ZERO
	_block.linear_velocity = partner_velocity
	_block.angular_velocity = Vector3.ZERO
	if target is RigidBody3D:
		(target as RigidBody3D).angular_velocity = Vector3.ZERO
