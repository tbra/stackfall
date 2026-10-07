extends GutTest
## Bontago-1pi.85.10 (docs/GIFT_EFFECTS_PLAN.md section 5 C), real physics on a real
## Field (concave disc floor, resting cube blocks):
##
## - SpecialPhysics' sphere query must find blocks lying on the disc floor. The disc is one
##   ConcavePolygonShape3D and intersect_shape returns one hit per triangle, so a capped
##   query next to the floor used to fill with disc triangles and miss the blocks.
## - Bomb acceptance: dropped among six neighbouring blocks it does not explode before the
##   blink ends, explodes within blink_duration_s + 0.1 s, and at least four of the six
##   neighbours leave outward faster than 3 m/s within five ticks.

const SETTLE_FRAMES: int = 40
const QUERY_RADIUS_M: float = 8.0
const RING_RADII_M: Array[float] = [2.5, 4.0, 5.5, 7.0]
const BLOCKS_PER_RING: int = 6
const NEIGHBOUR_COUNT: int = 6
const NEIGHBOUR_RING_M: float = 2.2
const MIN_OUTWARD_SPEED_MPS: float = 3.0
const MIN_NEIGHBOURS_PUSHED: int = 4
const AFTER_BLAST_TICKS: int = 5
const BLINK_SLACK_S: float = 0.1
const DROP_HEIGHT_M: float = 0.6
const MAX_WAIT_FRAMES: int = 400

var _field: Field
var _root: Node3D


const BLAST_PEAK_SPEED_MPS: float = 20.0
const BLAST_MAX_DELTA_V_MPS: float = 100.0

func before_each() -> void:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_gift_blast_blocks"
	map_def.field_radius = 14.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	_field = Field.new()
	_field.map_def = map_def
	add_child_autofree(_field)
	_root = Node3D.new()
	add_child_autofree(_root)


func _block(at: Vector3, slot: int = 0) -> Block:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
	var block: Block = BlockFactory.build(shape, tuning, slot)
	_root.add_child(block)
	block.global_position = at
	return block


func _space() -> PhysicsDirectSpaceState3D:
	return _field.get_world_3d().direct_space_state


## Cube blocks resting in rings around the origin, at several distances so the query
## sphere around the disc centre also overlaps hundreds of floor triangles.
func _ring_blocks() -> Array[Block]:
	var blocks: Array[Block] = []
	var y: float = _field.surface_y() + 0.6
	for radius: float in RING_RADII_M:
		for i: int in BLOCKS_PER_RING:
			var angle: float = TAU * float(i) / float(BLOCKS_PER_RING) + radius
			blocks.append(_block(Vector3(cos(angle) * radius, y, sin(angle) * radius)))
	return blocks


func test_query_finds_every_block_resting_on_the_disc_floor() -> void:
	var blocks: Array[Block] = _ring_blocks()
	await wait_physics_frames(SETTLE_FRAMES)
	var center: Vector3 = Vector3(0.0, _field.surface_y() + 0.5, 0.0)
	var found: Array[RigidBody3D] = SpecialPhysics.query_bodies_in_range(_space(), center, QUERY_RADIUS_M, [])
	for block: Block in blocks:
		assert_true(found.has(block), "block at %s was missed by the floor-side sphere query" % [block.global_position])
	assert_eq(found.size(), blocks.size(), "each block exactly once, nothing else")


func test_blast_pushes_every_block_resting_on_the_disc_floor() -> void:
	var blocks: Array[Block] = _ring_blocks()
	await wait_physics_frames(SETTLE_FRAMES)
	var center: Vector3 = Vector3(0.0, _field.surface_y() + 0.5, 0.0)
	# Old explode(radius, impulse 20, max 100) mapped onto ExplosionTuning: the blast applies delta-v
	# (mass independent) with an upward bias, so only the "every ring block is hit" intent is kept.
	var tuning: ExplosionTuning = ExplosionTuning.new()
	tuning.radius_m = QUERY_RADIUS_M
	tuning.peak_speed_mps = BLAST_PEAK_SPEED_MPS
	tuning.max_delta_v_mps = BLAST_MAX_DELTA_V_MPS
	var no_exclude: Array[RID] = []
	var hit: Array[RigidBody3D] = ExplosionFx.blast(_space(), center, tuning, no_exclude)
	for block: Block in blocks:
		assert_true(hit.has(block), "block at %s was not pushed" % [block.global_position])


## Plan section 5 C: a Bomb dropped among six neighbouring blocks does not explode before its blink
## ends, explodes within blink_duration_s + 0.1 s, and at least four of the six neighbours leave
## outward faster than 3 m/s within five ticks.
func test_bomb_dropped_among_six_blocks_blinks_then_blows_them_away() -> void:
	var y: float = _field.surface_y() + 0.6
	var neighbours: Array[Block] = []
	for i: int in NEIGHBOUR_COUNT:
		var angle: float = TAU * float(i) / float(NEIGHBOUR_COUNT)
		neighbours.append(_block(Vector3(cos(angle) * NEIGHBOUR_RING_M, y, sin(angle) * NEIGHBOUR_RING_M)))
	await wait_physics_frames(SETTLE_FRAMES)

	var def: SpecialDef = load("res://config/specials/bomb.tres") as SpecialDef
	var effect: BombEffect = def.effect as BombEffect
	var bomb: Block = _block(Vector3(0.0, _field.surface_y() + DROP_HEIGHT_M, 0.0))
	var behavior: SpecialBehavior = SpecialBehavior.new()
	bomb.add_child(behavior)
	behavior.bind(bomb, def, SpecialTuning.new())

	for _i: int in MAX_WAIT_FRAMES:
		if behavior.is_triggered():
			break
		await wait_physics_frames(1)
	assert_true(behavior.is_triggered(), "the Bomb exploded")
	assert_gte(behavior.age(), effect.blink_duration_s - 1.0 / 60.0, "no explosion before the blink ended")
	assert_lte(behavior.age(), effect.blink_duration_s + BLINK_SLACK_S, "explosion within blink_duration_s + 0.1 s")

	var center: Vector3 = bomb.global_position
	var outward: Array[Vector3] = []
	for neighbour: Block in neighbours:
		var away: Vector3 = neighbour.global_position - center
		away.y = 0.0
		outward.append(away.normalized())
	# "Within 5 ticks": each neighbour's peak outward speed over the five ticks after the blast
	# (friction and drag bleed it off quickly afterwards).
	var peak: Array[float] = []
	peak.resize(neighbours.size())
	peak.fill(0.0)
	for _tick: int in AFTER_BLAST_TICKS:
		for i: int in neighbours.size():
			peak[i] = maxf(peak[i], neighbours[i].linear_velocity.dot(outward[i]))
		await wait_physics_frames(1)
	var pushed: int = 0
	for i: int in neighbours.size():
		if peak[i] > MIN_OUTWARD_SPEED_MPS:
			pushed += 1
	assert_gte(pushed, MIN_NEIGHBOURS_PUSHED, "at least 4 of 6 neighbours exceed 3 m/s outward within 5 ticks: %s" % [peak])
