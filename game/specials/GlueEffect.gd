class_name GlueEffect
extends SpecialEffect
## Glue special (spec 2.6 "[NEW] joins touching blocks of yours within 4 m
## with breakable joints"; docs/M8_PLAN.md's P3-GLUE package). Ordinary
## impact/fuse pattern like BombEffect -- no physics_tick()/
## wants_early_trigger() override; everything happens once, in detonate().
##
## DECISION (game/specials/GlueEffect.gd, matches PropellerEffect.gd's own
## documented shared-instance caveat): a SpecialDef's `effect` is one shared
## Resource instance reused by every block spawned with this special during a
## match, so this effect keeps NO mutable per-block/per-activation state on
## itself. Every joint this special creates lives on a separately-instantiated
## `GlueJoint` node (game/specials/GlueJoint.gd) parented under the detonating
## block, never as an instance var here.

## Radius (metres) `detonate()` searches for touching own-owner blocks to
## glue, spec 2.6's "within 4 m".
@export var glue_radius_m: float = 4.0

## Stress threshold (GlueJoint.gd's own units -- see that file's DECISION)
## above which a formed joint breaks. Spec 2.6's "break force 40".
@export var break_force: float = 40.0

## Extra slack (metres) added on top of the two blocks' own collision-shape
## half-extents when deciding whether a pair counts as "touching" -- absorbs
## floating-point/physics jitter around the exact grid pitch (see
## `_are_touching()`'s own DECISION below). Lives here, not on
## config/PhysicsTuning.gd, per this package's brief ("any touching epsilon
## live on the resource").
@export var touching_slack_m: float = 0.05

## Fallback tuning for a Block whose own `tuning` field is still null (e.g. a
## bare test fixture never added to a live match) -- mirrors Block.gd's own
## `_ready()` default so the touching test still uses the project's real
## cube_size/cube_margin rather than an invented magic number.
const _DEFAULT_TUNING: PhysicsTuning = preload("res://config/physics_tuning.tres")


## Queries every OTHER block owned by the same player within `glue_radius_m`
## of the detonating block (`SpecialPhysics.query_bodies_in_range()`'s
## `owner_filter`, the exact seam docs/M8_PLAN.md's P3 section names), then
## forms a joint for every pair in the resulting pool -- including the
## detonating block itself -- that is actually touching.
##
## DECISION (game/specials/GlueEffect.gd, docs/M8_PLAN.md P3): the detonating
## block is included in the candidate pool alongside the queried neighbours
## (not just neighbour-to-neighbour pairs), so a touching neighbour glues
## directly to the block that popped -- the plain reading of spec 2.6's
## "joins touching blocks of yours" (the glue special's own block is one of
## "yours" too, and is very often the one physically touching a neighbour).
func detonate(block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	var space_state: PhysicsDirectSpaceState3D = block.get_world_3d().direct_space_state
	var mover_owner_slot: int = block.owner_slot
	var own_owner_filter: Callable = func(body: RigidBody3D) -> bool:
		var candidate: Block = body as Block
		return candidate != null and candidate.owner_slot == mover_owner_slot

	var neighbors: Array[RigidBody3D] = SpecialPhysics.query_bodies_in_range(
		space_state, block.global_position, glue_radius_m, [block.get_rid()], own_owner_filter
	)

	var pool: Array[Block] = [block]
	for body: RigidBody3D in neighbors:
		var candidate: Block = body as Block
		if candidate != null:
			pool.append(candidate)

	for i: int in range(pool.size()):
		for j: int in range(i + 1, pool.size()):
			var a: Block = pool[i]
			var b: Block = pool[j]
			if _are_touching(a, b):
				_glue_pair(block, a, b)


## Half of a block's own physical collision-cube extent (BlockFactory.gd's own
## `(cube_size - cube_margin) * 0.5` formula, lines ~106/212) -- falls back to
## `_DEFAULT_TUNING` when the block's own `tuning` field is still null.
func _half_extent(tuning: PhysicsTuning) -> float:
	return (tuning.cube_size - tuning.cube_margin) * 0.5


## DECISION (game/specials/GlueEffect.gd, docs/M8_PLAN.md P3): "touching" is
## each block's own collision-shape half-extent sum plus PhysicsTuning's own
## cube_margin, mirroring BlockFactory's placement-adjacency convention
## rather than inventing a new epsilon export on PhysicsTuning -- two blocks
## placed on the same grid, one cube_size apart centre-to-centre, are exactly
## at this threshold (half_extent_a + half_extent_b + cube_margin ==
## cube_size, since half_extent == (cube_size - cube_margin) * 0.5). A small
## additional `touching_slack_m` absorbs jitter around that exact distance
## once physics has settled the blocks (they rarely land at the perfect grid
## pitch to the millimetre).
func _are_touching(a: Block, b: Block) -> bool:
	var tuning_a: PhysicsTuning = a.tuning if a.tuning != null else _DEFAULT_TUNING
	var tuning_b: PhysicsTuning = b.tuning if b.tuning != null else _DEFAULT_TUNING
	var margin: float = (tuning_a.cube_margin + tuning_b.cube_margin) * 0.5
	var threshold: float = _half_extent(tuning_a) + _half_extent(tuning_b) + margin + touching_slack_m
	return a.global_position.distance_to(b.global_position) <= threshold


## Creates one Generic6DOFJoint3D between `a` and `b`, owned by a fresh
## GlueJoint node parented under `host` (the detonating block, already live
## in the scene tree, so both the joint node and the physics-tick node it
## needs have a stable parent to be freed together later).
func _glue_pair(host: Block, a: Block, b: Block) -> void:
	var joint: Generic6DOFJoint3D = Generic6DOFJoint3D.new()
	# NodePath.get_path() is always absolute, so it resolves from wherever
	# this joint ends up parented in the live scene tree, independent of
	# `host`/`a`/`b`'s relative positions to each other.
	joint.node_a = a.get_path()
	joint.node_b = b.get_path()

	var glue_joint: GlueJoint = GlueJoint.new()
	glue_joint.add_child(joint)
	host.add_child(glue_joint)
	glue_joint.bind(joint, a, b, break_force)
