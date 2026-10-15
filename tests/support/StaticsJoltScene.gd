class_name StaticsJoltScene
extends RefCounted
## Bontago-1t5.72.3 (STATICS_DESIGN 6.1): the real-Jolt harness of the statics agreement suite. A scripted stack of
## real blocks settles on a real Field behind a quiet gate; the bot's model (BotStackProbe snapshot + BotStability)
## predicts whether one more piece, probed with the real column ray, would stand; the piece is then dropped through
## the bot's spawn pose and the settled outcome is compared with the prediction. Test-only support.

const PHYSICS_TUNING: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
const STACK_TUNING: BotStackTuning = preload("res://config/bots/bot_stack_tuning.tres")
const BOT_TUNING: BotTuning = preload("res://config/bots/bot_tuning.tres")
## Field radius of the scripted world (metres): big enough that nothing reaches the rim.
const FIELD_RADIUS_M: float = 20.0
## Consecutive quiet ticks that count as settled, and the cap before the scenario fails its set-up.
const QUIET_TICKS: int = 5
const SETTLE_CAP_TICKS: int = 240
## Ticks the dropped piece gets to land and the stack to react.
const OUTCOME_TICKS: int = 180
## A body is quiet below this speed (m/s).
const QUIET_SPEED_MPS: float = 0.15
## A pre-existing body that moved more than this (m) or turned more than STAND_MAX_TILT_RAD did not stand.
const STAND_MAX_MOVE_M: float = 0.1
const STAND_MAX_TILT_RAD: float = 0.15
## The piece stays up while its pivot (at its bottom face) is within this of its plane; a fallen piece is a cube or more below.
const STAND_MAX_SINK_M: float = 0.2
## The piece is dropped this far above its plane (m), as test_bot_slender does.
const DROP_LIFT_M: float = 0.02
const _OBSERVER_TEAM: int = 0

var field: Field = null
var registry: BlockRegistry = null
var blocks_root: Node3D = null
var bodies: Array[Block] = []
var _test: GutTest = null
var _map: MapDef = null


func _init(test: GutTest) -> void:
	_test = test


## Builds the world; call from before_each.
func build_world() -> void:
	Match.set_process(false)
	Match.abort_match()
	_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_map.field_radius = FIELD_RADIUS_M
	field = _test.autofree(Field.new())
	field.map_def = _map
	_test.add_child_autofree(field)
	blocks_root = _test.autofree(Node3D.new())
	_test.add_child_autofree(blocks_root)
	registry = _test.autofree(BlockRegistry.new())
	_test.add_child_autofree(registry)
	Match.register_world(field, registry, blocks_root)
	bodies.clear()


## Call from after_each.
func teardown() -> void:
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


## The orientation index of `shape` that is upright (tallest) or lying (height 1) with its long axis along x.
func orientation(shape: BlockShape, upright: bool) -> int:
	var best: BotStatics.OrientationInfo = null
	for info: BotStatics.OrientationInfo in BotStatics.orientation_infos(shape):
		if upright:
			if best == null or info.height > best.height:
				best = info
		elif info.height == 1.0:
			if best == null or _x_span(info) > _x_span(best):
				best = info
	return best.index


func _x_span(info: BotStatics.OrientationInfo) -> float:
	var lo: float = INF
	var hi: float = -INF
	for p: Vector2 in info.cubes:
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
	return hi - lo


func info_of(shape: BlockShape, orient: int) -> BotStatics.OrientationInfo:
	return BotStatics.orientation_info(shape, orient)


## A probed candidate that puts the centre of mass of `shape` in `orient` over `com_xz` (disc-local, metres).
func candidate(shape: BlockShape, orient: int, com_xz: Vector2) -> BotCandidate:
	var cube: float = PHYSICS_TUNING.cube_size
	var info: BotStatics.OrientationInfo = info_of(shape, orient)
	var c: BotCandidate = BotCandidate.new()
	c.orientation_index = orient
	c.origin = com_xz - info.com * cube
	c.support_height = float(_ray(c.origin)["height"])
	var points: PackedVector2Array = BotStatics.contact_probe_points(c, info, cube, info.contact.size())
	c.probe_points = points
	c.cell_support.resize(points.size())
	c.support_bodies.resize(points.size())
	var highest: float = BotThink.NO_SUPPORT
	for i: int in points.size():
		var hit: Dictionary = _ray(points[i])
		c.cell_support[i] = BotThink.NO_SUPPORT
		c.support_bodies[i] = -1
		if not bool(hit["hit"]):
			continue
		var height: float = float(hit["height"])
		c.cell_support[i] = height
		c.support_bodies[i] = int(hit["body"])
		if highest == BotThink.NO_SUPPORT or height > highest:
			highest = height
	if highest != BotThink.NO_SUPPORT:
		c.support_height = highest
	return c


## {hit, height, body}: Field.raycast_disk_column, the bot's own support ray.
func _ray(xz: Vector2) -> Dictionary:
	var hit: Dictionary = field.raycast_disk_column(field.direct_space(), xz)
	if hit.is_empty():
		return {"hit": false, "height": 0.0, "body": -1}
	var block: Block = hit.get("collider") as Block
	return {
		"hit": true,
		"height": field.to_local(hit["position"] as Vector3).y,
		"body": block.get_instance_id() if block != null else -1,
	}


## Spawns `shape` the way the send path does: through BotController.spawn_pose at the candidate's resting plane.
func spawn(shape: BlockShape, c: BotCandidate, plane_y: float) -> Block:
	var block: Block = BlockFactory.build(shape, PHYSICS_TUNING)
	blocks_root.add_child(block)
	var pose: Vector3 = BotController.spawn_pose(shape, c.orientation_index, c.origin, plane_y + DROP_LIFT_M, PHYSICS_TUNING)
	block.global_basis = BlockOrientations.get_basis(c.orientation_index)
	block.global_position = field.world_from_disk_local(Vector2(pose.x, pose.z), pose.y)
	bodies.append(block)
	Events.block_placed.emit(block, shape.id)
	return block


## Scripted scene body: dropped onto whatever is under `com_xz`, then the scene settles. Null if it never settles.
func put(shape: BlockShape, orient: int, com_xz: Vector2) -> Block:
	var c: BotCandidate = candidate(shape, orient, com_xz)
	var block: Block = spawn(shape, c, c.support_height)
	if not await settle():
		return null
	return block


## Waits until every body is quiet for QUIET_TICKS in a row; a scene that never gets quiet fails its set-up.
func settle() -> bool:
	var quiet: int = 0
	for _tick: int in SETTLE_CAP_TICKS:
		await _test.wait_physics_frames(1)
		var calm: bool = true
		for block: Block in bodies:
			if is_instance_valid(block) and block.linear_velocity.length() > QUIET_SPEED_MPS:
				calm = false
		quiet = quiet + 1 if calm else 0
		if quiet >= QUIET_TICKS:
			return true
	_test.fail_test("scene set-up never settled (%d bodies)" % bodies.size())
	return false


## The bot's snapshot of the scene, fully analysed. `max_bodies` below 0 keeps the shipped cap; `centre` is the
## point the snapshot grows from.
func snapshot(centre: Vector2 = Vector2.ZERO, max_bodies: int = -1) -> BotStack:
	var t: BotStackTuning = STACK_TUNING
	if max_bodies >= 0:
		t = STACK_TUNING.duplicate() as BotStackTuning
		t.snapshot_max_bodies = max_bodies
	var stack: BotStack = BotStackProbe.build(
		registry, field, PackedVector2Array([centre]), t, PHYSICS_TUNING.cube_size,
		func(_slot: int) -> int: return _OBSERVER_TEAM
	)
	while not stack.analyse_step(stack.body_count() + 1, t):
		pass
	return stack


## BotStability.evaluate of `c` against `stack` for a tier with worst-case aim error `aim_m`.
func predict(shape: BlockShape, c: BotCandidate, stack: BotStack, aim_m: float) -> BotStability.Result:
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.aim_noise_m = aim_m
	var view: BotWorldView = BotWorldView.new()
	view.cube_size = PHYSICS_TUNING.cube_size
	view.stack = stack
	var req: BotStability.Requirement = BotStability.requirement(
		profile, view, STACK_TUNING, BOT_TUNING.stability_contact_tolerance_m
	)
	return BotStability.evaluate(c, info_of(shape, c.orientation_index), view, req)


## One agreement trial on the settled scene: predict for `com_xz` (aim error `aim_m`, snapshot `stack` or a full
## one), then drop the piece with its centre of mass at `com_xz + shift` and record whether it stood.
## Returns {predicted, stood, slack, margin, binding, plane_y, known, moved_m, tilt_rad, piece_tilt_rad}.
func trial(
	shape: BlockShape, orient: int, com_xz: Vector2, aim_m: float, shift: Vector2 = Vector2.ZERO,
	stack: BotStack = null
) -> Dictionary:
	var snap: BotStack = stack if stack != null else snapshot()
	var planned: BotCandidate = candidate(shape, orient, com_xz)
	var verdict: BotStability.Result = predict(shape, planned, snap, aim_m)
	var actual: BotCandidate = planned if shift == Vector2.ZERO else candidate(shape, orient, com_xz + shift)
	var before: Array[Transform3D] = []
	for block: Block in bodies:
		before.append(block.global_transform)
	var plane_y: float = actual.support_height
	if shift == Vector2.ZERO:
		plane_y = maxf(plane_y, verdict.plane_y)
	var piece: Block = spawn(shape, actual, plane_y)
	await _test.wait_physics_frames(OUTCOME_TICKS)
	var moved: float = 0.0
	var tilt: float = 0.0
	for i: int in before.size():
		var block: Block = bodies[i]
		moved = maxf(moved, block.global_position.distance_to(before[i].origin))
		tilt = maxf(tilt, _turn(before[i].basis, block.global_basis))
	var piece_tilt: float = _turn(BlockOrientations.get_basis(orient), piece.global_basis)
	var piece_y: float = field.to_local(piece.global_position).y
	var stood: bool = (
		moved <= STAND_MAX_MOVE_M and tilt <= STAND_MAX_TILT_RAD and piece_tilt <= STAND_MAX_TILT_RAD
		and piece_y > plane_y - STAND_MAX_SINK_M
	)
	return {
		"predicted": verdict.slack > 0.0, "stood": stood, "slack": verdict.slack, "margin": verdict.piece_margin,
		"binding": verdict.binding, "plane_y": verdict.plane_y, "known": verdict.known, "moved_m": moved,
		"tilt_rad": tilt, "piece_tilt_rad": piece_tilt, "piece_y": piece_y, "drop_plane_y": plane_y,
	}


func _turn(a: Basis, b: Basis) -> float:
	return (a.orthonormalized().inverse() * b.orthonormalized()).get_rotation_quaternion().get_angle()


## "slack 0.123 (binding -1, piece margin 0.5): stood=true moved=0.01 tilt=0.0 piece_tilt=0.0"
static func describe(r: Dictionary) -> String:
	return "predicted=%s slack=%.3f binding=%d piece_margin=%.3f | stood=%s moved=%.3f tilt=%.3f piece_tilt=%.3f piece_y=%.3f drop_plane=%.3f" % [
		r["predicted"], r["slack"], r["binding"], r["margin"], r["stood"], r["moved_m"], r["tilt_rad"],
		r["piece_tilt_rad"], r["piece_y"], r["drop_plane_y"],
	]
