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
	var joint: Generic6DOFJoint3D = Generic6DOFJoint3D.new()
	joint.node_a = _block.get_path()
	joint.node_b = target.get_path()
	var bond: GlueJoint = GlueJoint.new()
	bond.add_child(joint)
	_block.add_child(bond)
	bond.bind(joint, _block, target, _tuning.break_force)
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
