extends GutTest
## Bontago-1t5.66: with fill_share 0 the uniform FILL runs only when no targeted site exists;
## a profile that asks for FILL sites (fill_share > 0) is unchanged.

const MAP_RADIUS: float = 20.0
const CELL: float = 0.5
const HOME_A: Vector2 = Vector2(-15.0, 0.0)
const HOME_B: Vector2 = Vector2(15.0, 0.0)
const SNAKE_TOP_M: float = 1.0
const SNAKE_XS: Array[float] = [-10.0, -8.0, -6.0, -4.0, -2.0]
const TOWER_POS: Vector2 = Vector2(-6.0, 3.0)
const TOWER_TOP_M: float = 4.0
const CANDIDATE_COUNT: int = 110
const SEED: int = 99
const SURFACE_HEIGHT: float = 0.0
const BIG_BUDGET_US: int = 60000000
const THINKS: int = 12
const EASY_FILL_SHARE: float = 0.5

var _territory_tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var _tuning: BotGenTuning = preload("res://config/bots/bot_gen_tuning.tres")
var _cube: BlockShape = preload("res://config/blocks/cube.tres")
var _pillar: BlockShape = preload("res://config/blocks/pillar.tres")
var _slots: Array[PlayerSlot] = []


func before_each() -> void:
	_slots = [
		PlayerSlot.new(0, 0, "a", Color.WHITE, HOME_A),
		PlayerSlot.new(1, 1, "b", Color.WHITE, HOME_B),
	]


func _view(held: BlockShape) -> BotWorldView:
	var grid: CellGrid = CellGrid.new(MAP_RADIUS, CELL)
	var raster: TerritoryRaster = TerritoryRaster.new(grid, _territory_tuning)
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.for_home(HOME_A, 0, 0, _territory_tuning),
		InfluenceCircle.for_home(HOME_B, 1, 1, _territory_tuning),
	]
	var body: int = 1
	for x: float in SNAKE_XS:
		circles.append(InfluenceCircle.for_block(Vector2(x, 0.0), SNAKE_TOP_M, 0, 0, body, _territory_tuning, MAP_RADIUS))
		body += 1
	circles.append(InfluenceCircle.for_block(TOWER_POS, TOWER_TOP_M, 0, 0, body, _territory_tuning, MAP_RADIUS))
	var solver: TerritorySolver = TerritorySolver.new(_territory_tuning)
	raster.update(circles, solver.solve(circles), 0.1, false, false)
	var xs: PackedFloat32Array = PackedFloat32Array()
	var zs: PackedFloat32Array = PackedFloat32Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	var teams: PackedInt32Array = PackedInt32Array()
	for circle: InfluenceCircle in circles:
		xs.append(circle.center.x)
		zs.append(circle.center.y)
		radii.append(circle.radius)
		teams.append(circle.team_id)
	var arrays: Dictionary = {"xs": xs, "zs": zs, "radii": radii, "teams": teams}
	return BotWorldView.build(
		0, 0, arrays, _slots, raster, PackedVector2Array([Vector2.ZERO]), 0.0, held, held, null,
		PackedVector2Array(), PackedVector2Array()
	)


func _profile(fill_share: float) -> BotDifficultyProfile:
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.candidate_count = CANDIDATE_COUNT
	profile.stability_raycast_count = 9
	profile.fill_share = fill_share
	return profile


func _intent(kind: BotIntent.Kind) -> BotIntent:
	var intent: BotIntent = BotIntent.new()
	intent.kind = kind
	intent.target = TOWER_POS
	return intent


func _rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	return rng


func _count_kind(sites: Array[BotCandidate], kind: int) -> int:
	var n: int = 0
	for site: BotCandidate in sites:
		if site.site_kind == kind:
			n += 1
	return n


func _probe(_xz: Vector2) -> Dictionary:
	return {"hit": true, "height": SURFACE_HEIGHT, "own": false}


func _fill_added(fill_share: float, tuning: BotGenTuning) -> int:
	var job: BotCandidateGen.SiteJob = BotCandidateGen.begin(
		_view(_cube), _intent(BotIntent.Kind.ANCHOR), _profile(fill_share), _rng(), tuning
	)
	while not job.fill_step(job.attempts_left()):
		pass
	return _count_kind(job.out, BotCandidateGen.SITE_FILL)


func test_fill_share_zero_does_not_top_up_when_targeted_sites_exist() -> void:
	var job: BotCandidateGen.SiteJob = BotCandidateGen.begin(
		_view(_cube), _intent(BotIntent.Kind.ANCHOR), _profile(0.0), _rng(), _tuning
	)
	var targeted: int = job.out.size()
	assert_gt(targeted, 0, "scene has targeted sites")
	assert_eq(job.attempts_left(), 0, "no FILL draws")
	assert_true(job.fill_step(job.attempts_left()))
	assert_eq(job.out.size(), targeted)
	assert_eq(_count_kind(job.out, BotCandidateGen.SITE_FILL), 0)


func test_fallback_fills_when_no_targeted_site() -> void:
	var intent: BotIntent = _intent(BotIntent.Kind.ANCHOR)
	var view: BotWorldView = _view(_cube)
	view.circle_count()
	var none: BotGenTuning = _tuning.duplicate() as BotGenTuning
	none.tip_share = 0.0
	none.stack_share = 0.0
	none.tower_tip_share = 0.0
	none.tower_stack_share = 0.0
	var job: BotCandidateGen.SiteJob = BotCandidateGen.begin(view, intent, _profile(0.0), _rng(), none)
	assert_eq(job.out.size(), 0, "no targeted site")
	while not job.fill_step(job.attempts_left()):
		pass
	assert_gt(job.out.size(), 0, "FILL still finds sites")


func test_fill_share_positive_is_unchanged() -> void:
	assert_gt(_fill_added(EASY_FILL_SHARE, _tuning), 0, "still fills its share")


func test_hard_think_still_picks_a_tip_and_fill_cost_drops() -> void:
	var fill_us: int = 0
	var total_us: int = 0
	for n: int in range(THINKS):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = SEED + n
		var think: BotThink = BotThink.new(_view(_pillar), _profile(0.0), rng)
		think.collect_stats = true
		think.step(BIG_BUDGET_US, _probe)
		var best: BotCandidate = think.best_candidate()
		assert_not_null(best)
		if best != null:
			assert_ne(best.site_kind, BotCandidateGen.SITE_FILL, "pick is a targeted site")
		var rec: Dictionary = think.stats_record()
		fill_us += (rec["phase_us"] as PackedInt64Array)[BotThink.Phase.FILL]
		total_us += rec["total_us"] as int
	gut.p("FILL_COST fill_us_mean=%d total_us_mean=%d" % [fill_us / THINKS, total_us / THINKS])
