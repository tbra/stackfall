class_name TerritoryStage
extends RefCounted
## Stages territory situations through public play so tests need not reach into Match's
## territory driver: time passes only through Match._process, and ownership changes only
## through real tracked blocks (BlockFactory + Events.block_placed, the signal the game's
## own placement emits), solved by the real territory step.
##
## A staged block floats frozen at a height whose influence radius is the cap, so a few of
## them make a home-anchored chain that reaches a goal or a rival home without building a
## physical tower. Call with the match PLAYING, Match.set_process(false) and the test's own
## blocks parent (the one passed to Match.register_world).

const CUBE: BlockShape = preload("res://config/blocks/cube.tres")
const PHYSICS: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
const TERRITORY: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
## A staged block floats this many field-radii above the disk, far over the influence cap.
const FLOAT_HEIGHT_RADII: float = 2.0
## Longest wait, in physics frames, for staged blocks to be counted settled.
const SETTLE_MAX_FRAMES: int = 240
## Slack added to a hold so the last solve step lands inside it.
const HOLD_SLACK_S: float = 0.5


## Passes `seconds` of match time as physics-rate Match._process steps.
static func tick(seconds: float) -> void:
	var step: float = 1.0 / Engine.physics_ticks_per_second
	for _i: int in range(int(ceil(seconds / step))):
		Match._process(step)


## One territory solve step's worth of time.
static func tick_solve() -> void:
	tick(1.0 / TERRITORY.solve_hz)


## Makes `team` own every goal in one connected territory (a chain of staged blocks from
## the home of its first living slot), waits for the blocks to settle and runs one solve.
## The caller then ticks `capture_hold` seconds (or uses hold_goals_for) to latch the win.
static func hold_goals(team: int, blocks_parent: Node3D) -> void:
	var slot_id: int = _living_slot_of_team(team)
	var home: Vector2 = Match.slot(slot_id).home_position
	for goal: Vector2 in Match.circle_render_arrays()["goal_positions"]:
		_bridge(slot_id, home, goal, blocks_parent)
	await _settle()
	tick_solve()


## hold_goals(team) then the whole capture hold, so a hold that completes has latched.
static func hold_goals_for(team: int, blocks_parent: Node3D) -> void:
	await hold_goals(team, blocks_parent)
	tick(TERRITORY.capture_hold + HOLD_SLACK_S)


## Takes every slot in `slots` out of the game through real play: a rival's staged blocks
## cover its home flag until the solve (or, in Elimination, the whole claim hold) takes it.
## An already eliminated slot is skipped. Returns once the outcome has been applied.
static func lose_homes(slots: Array[int], blocks_parent: Node3D) -> void:
	for victim: int in slots:
		if not Match.slot(victim).home_flag_alive:
			continue
		var attacker: int = _rival_of(victim, slots)
		_bridge(attacker, Match.slot(attacker).home_position, Match.slot(victim).home_position, blocks_parent)
	await _settle()
	tick_solve()
	if Match.state() == Match.State.PLAYING and Match.config.hole_mode != MatchConfig.HoleMode.OFF:
		# Overlap modes: the contest must age into a hole under the home first.
		tick(TERRITORY.hole_delay + HOLD_SLACK_S)
	if Match.state() == Match.State.PLAYING and Match.config.game_mode == MatchConfig.GameMode.ELIMINATION:
		tick(TERRITORY.capture_hold + HOLD_SLACK_S)


static func _living_slot_of_team(team: int) -> int:
	for slot_id: int in range(Match.slot_count()):
		if Match.team_of(slot_id) == team and Match.slot(slot_id).home_flag_alive:
			return slot_id
	return -1


## A living slot on another team than `victim`, preferring one not being eliminated.
static func _rival_of(victim: int, doomed: Array[int]) -> int:
	var fallback: int = -1
	for slot_id: int in range(Match.slot_count()):
		if Match.team_of(slot_id) == Match.team_of(victim) or not Match.slot(slot_id).home_flag_alive:
			continue
		if not doomed.has(slot_id):
			return slot_id
		fallback = slot_id
	return fallback


## Floats staged blocks of `slot_id` along the line from `from` to `to`, spaced so each
## overlaps the next, the last one over `to`.
static func _bridge(slot_id: int, from: Vector2, to: Vector2, blocks_parent: Node3D) -> void:
	var reach: float = TERRITORY.influence_max_fraction * Match.config.map_def().field_radius
	var spacing: float = maxf(reach, 1.0)
	var count: int = maxi(1, int(ceil(from.distance_to(to) / spacing)))
	for i: int in range(1, count + 1):
		_float_block(slot_id, from.lerp(to, float(i) / float(count)), blocks_parent)


static func _float_block(slot_id: int, at: Vector2, blocks_parent: Node3D) -> void:
	var block: Block = BlockFactory.build(CUBE, PHYSICS, slot_id)
	var height: float = FLOAT_HEIGHT_RADII * Match.config.map_def().field_radius
	block.position = Match.field().to_global(Vector3(at.x, height, at.y))
	blocks_parent.add_child(block)
	block.freeze = true
	Events.block_placed.emit(block, CUBE.id)


static func _settle() -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	for _i: int in range(SETTLE_MAX_FRAMES):
		await tree.physics_frame
		if (Match.registry() as BlockRegistry).all_settled():
			return
