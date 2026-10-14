extends GutTest
## Bontago-1t5.72.4 (P2a): BotThink's PROBE phase fills BotCandidate.stability_slack / stability_binding with
## BotStability.evaluate.

const CUBE: float = 1.0
const MASS: float = 2.0
const FACE_HALF: float = 0.49
const AIM: float = 0.3
const BLOCK_ID: int = 4242
const EPS: float = 0.001
const EDGE_ORIGIN_X: float = 0.8
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


func test_defaults_mean_not_evaluated() -> void:
	var c: BotCandidate = BotCandidate.new()
	assert_eq(c.stability_slack, INF)
	assert_eq(c.stability_binding, BotStability.BINDING_NONE)


func test_cube_on_the_disc_is_stable_and_nothing_else_moves() -> void:
	var think: BotThink = _think(true)
	var c: BotCandidate = _candidate(5.0, 0.0, -1)
	think._judge_stability(c)
	assert_gt(c.stability_slack, 0.0)
	assert_eq(c.stability_binding, BotStability.BINDING_PIECE)
	assert_almost_eq(c.support_height, 0.0, EPS)
	assert_almost_eq(c.top_height, CUBE, EPS)


func test_cube_dropped_off_a_block_edge_is_unstable() -> void:
	var think: BotThink = _think(true)
	var c: BotCandidate = _candidate(0.3, CUBE, BLOCK_ID)
	think._judge_stability(c)
	assert_lt(c.stability_slack, 0.0, "0.3 m off a 1x1 top with 0.3 m of aim error")


func test_judging_leaves_height_inputs_alone_on_an_edge_overlap_site() -> void:
	var think: BotThink = _think(true)
	var c: BotCandidate = _candidate(EDGE_ORIGIN_X, 0.0, -1)
	var view: BotWorldView = think._view
	var intent: BotIntent = BotIntent.new()
	var before: PackedFloat32Array = BotEvaluator.proxy_terms(c, view, intent)
	think._judge_stability(c)
	assert_almost_eq(c.support_height, 0.0, EPS, "the probed support height is untouched")
	assert_almost_eq(c.top_height, CUBE, EPS)
	assert_almost_eq(c.stability_plane_y, CUBE, EPS, "the model's plane (the host lift) is kept apart")
	var after: PackedFloat32Array = BotEvaluator.proxy_terms(c, view, intent)
	var tip: int = BotIntent.Term.TIP
	assert_almost_eq(after[tip], before[tip] + BotEvaluator.stability_risk(c), EPS, "only the TIP term reads the judge")
	after[tip] = before[tip]
	assert_eq(after, before, "every other score term is identical with the judge on")


func test_no_snapshot_uses_the_probe_only_fallback() -> void:
	var think: BotThink = _think(false)
	var c: BotCandidate = _candidate(1.0, 0.0, -1)
	think._judge_stability(c)
	assert_gt(c.stability_slack, 0.0)

