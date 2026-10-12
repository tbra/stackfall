class_name GlueFusion
extends RefCounted
## Glue fusion (docs/GLUE_FUSION_PLAN.md section 5), host only: fuses a charged Block with
## what it touched (a Block, a FusedBody carrier or the Field disc) into one FusedBody.
## GlueDrops (WP2) is the live caller; nothing here depends on the scene beyond the bodies
## it is handed.


## Fuses `charged` with `target`. Returns the FusedBody now holding `charged`, or null when
## nothing was fused (invalid pair, gift block, already in the same group with no new anchor,
## or `tuning.max_fused_cubes` would be exceeded).
static func fuse(charged: Block, target: PhysicsBody3D, tuning: GlueDropTuning) -> FusedBody:
	if charged == null or not is_instance_valid(charged) or target == null or not is_instance_valid(target):
		return null
	if target == charged or not (target is Block or target is Field):
		return null
	if not charged.is_inside_tree() or charged.gift_id != &"":
		return null
	var field: Field = target as Field
	var partner: Block = null
	var group_b: FusedBody = null
	if field == null:
		var other_block: Block = target as Block
		if other_block.gift_id != &"":
			return null
		group_b = other_block as FusedBody
		if group_b == null:
			group_b = other_block.fused_carrier() as FusedBody
		if group_b == null:
			partner = other_block
	var group_a: FusedBody = charged.fused_carrier() as FusedBody
	if group_a != null and group_a == group_b:
		return null
	var absorb: bool = tuning == null or tuning.absorb_impact
	var cap: int = 0 if tuning == null else tuning.max_fused_cubes
	if cap > 0 and _cubes_after(charged, group_a, partner, group_b) > cap:
		return null

	var newly: Array = []
	var carrier: FusedBody = _pick_carrier(group_a, group_b)
	if carrier == null:
		carrier = _new_carrier(charged, partner, absorb)
		if carrier == null:
			return null
	else:
		if absorb and not carrier.is_disc_anchored():
			carrier.angular_velocity = Vector3.ZERO
	# Ungrouped blocks first, then the other group.
	if group_a == null:
		carrier.adopt(charged)
		newly.append(charged)
	if field == null and partner != null:
		carrier.adopt(partner)
		newly.append(partner)
	for other: FusedBody in [group_a, group_b]:
		if other != null and other != carrier:
			for member: Block in other.members:
				newly.append(member)
			carrier.absorb_group(other)
	if field != null:
		carrier.anchor_to_field(field, charged)
	if not newly.is_empty():
		Events.blocks_fused.emit(carrier, newly)
	return carrier


## The group to keep: a disc-anchored one (its pose is pinned to the disc), else the larger.
static func _pick_carrier(a: FusedBody, b: FusedBody) -> FusedBody:
	if a == null or b == null:
		return a if a != null else b
	if a.is_disc_anchored() != b.is_disc_anchored():
		return a if a.is_disc_anchored() else b
	return a if a.members.size() >= b.members.size() else b


## New carrier at the partner's pose (the settled partner does not jump) with its velocity;
## `absorb` reproduces GlueDrops._absorb_impact (relative velocity and spin soaked up).
static func _new_carrier(charged: Block, partner: Block, absorb: bool) -> FusedBody:
	var template: Block = partner if partner != null else charged
	var parent: Node = template.get_parent()
	if parent == null:
		return null
	var carrier: FusedBody = FusedBody.new()
	carrier.setup_from(template)
	parent.add_child(carrier)
	carrier.global_transform = template.global_transform
	if partner != null:
		carrier.linear_velocity = partner.linear_velocity
		carrier.angular_velocity = Vector3.ZERO if absorb else partner.angular_velocity
	else:
		carrier.linear_velocity = charged.linear_velocity if not absorb else Vector3.ZERO
		carrier.angular_velocity = Vector3.ZERO if absorb else charged.angular_velocity
	return carrier


static func _cubes_after(charged: Block, group_a: FusedBody, partner: Block, group_b: FusedBody) -> int:
	var total: int = 0
	if group_a != null:
		total += group_a.total_cubes()
	else:
		total += charged.cube_count
	if group_b != null:
		total += group_b.total_cubes()
	elif partner != null:
		total += partner.cube_count
	return total
