extends GutTest
## P2a: BotThink's PROBE phase fills BotCandidate.stability_slack with
## BotStability.evaluate.

const CUBE: float = 1.0
const MASS: float = 2.0
const FACE_HALF: float = 0.49
const AIM: float = 0.3
const BLOCK_ID: int = 4242
const SEED: int = 5

var _stack_t: BotStackTuning = preload("res://config/bots/bot_stack_tuning.tres")
var _gen_t: BotGenTuning = preload("res://config/bots/bot_gen_tuning.tres")
var _cube: BlockShape = preload("res://config/blocks/cube.tres")


func _think(with_block: bool) -> BotThink:
	var view: BotWorldView = BotWorldView.new()
	view.cube_size = CUBE
	view.held = _cube
	if with_block:
		var stack: BotStack = BotStack.new()
		stack.cube_size = CUBE
		stack.add_body(BLOCK_ID, 0, Basis.IDENTITY, PackedVector3Array([Vector3(0.0, 0.5, 0.0)]), MASS, true, FACE_HALF)
		stack.analyse_step(stack.body_count() + 1, _stack_t)
		view.stack = stack
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.aim_noise_m = AIM
	profile.stability_raycast_count = 9
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	return BotThink.new(view, profile, rng)


func _info() -> BotStatics.OrientationInfo:
	return BotStatics.orientation_infos(_cube, _gen_t)[0]


func _candidate(x: float, height: float, body: int) -> BotCandidate:
	var info: BotStatics.OrientationInfo = _info()
	var c: BotCandidate = BotCandidate.new()
	c.origin = Vector2(x, 0.0)
	c.orientation_index = info.index
	c.shape_height = CUBE
	c.support_height = height
	c.top_height = height + CUBE
	for offset: Vector2 in info.contact:
		c.probe_points.append(c.origin + offset * CUBE)
		c.cell_support.append(height)
		c.support_bodies.append(body)
	return c


func test_cube_dropped_off_a_block_edge_is_unstable() -> void:
	var think: BotThink = _think(true)
	var c: BotCandidate = _candidate(0.3, CUBE, BLOCK_ID)
	think._judge_stability(c)
	assert_lt(c.stability_slack, 0.0, "0.3 m off a 1x1 top with 0.3 m of aim error")
