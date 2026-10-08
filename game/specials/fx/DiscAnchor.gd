class_name DiscAnchor
extends RefCounted
## Parents a persistent gift node (black hole field/visual, paintball splash, blast
## puff) under the Field so it keeps its disc-local transform while the disc tilts or
## shakes, the way VolcanoStructure and PropellerStand do (Bontago-1pi.85.66). Without a
## live Field (an isolated unit test) it falls back to `fallback`, the old world parent.


## The node a persistent effect should hang under, or `fallback` without a live Field.
static func parent_for(fallback: Node) -> Node:
	var field: Field = Match.field()
	if field != null and field.is_inside_tree():
		return field
	return fallback


## Adds `node` under parent_for(fallback) and places it at `world_position` (world space
## at spawn; afterwards it follows the parent). Returns the chosen parent.
static func attach(node: Node3D, world_position: Vector3, fallback: Node) -> Node:
	var parent: Node = parent_for(fallback)
	if parent == null:
		return null
	parent.add_child(node)
	node.global_position = world_position
	return parent
