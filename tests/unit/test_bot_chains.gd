extends GutTest
## core/ai/BotChains.gd (Bontago-1t5.22, Bot V2 P3): downstream counts, articulation
## flags, home-connectivity, gap_to and exact multi-cut loss on a hand-built fork.
## Pure: a BotWorldView filled by hand, no scene tree.

const ENEMY_TEAM: int = 1
const OWN_TEAM: int = 0
const ENEMY_HOME: Vector2 = Vector2(-20.0, 0.0)
const OWN_HOME: Vector2 = Vector2(30.0, 30.0)
const RADIUS: float = 3.0
const FAR_POINT: Vector2 = Vector2(10.0, 0.0)
## Fork layout (team 1, rooted at ENEMY_HOME, radius 6): A-B-C chain with a D-E branch off B.
const A: int = 0
const B: int = 1
const C: int = 2
const D: int = 3
const E: int = 4
const ALT: int = 5
const BRIDGE: int = 6

var _view: BotWorldView = null


func _circle(position: Vector2, team: int = ENEMY_TEAM, radius: float = RADIUS) -> void:
	_view.cx.append(position.x)
	_view.cz.append(position.y)
	_view.cr.append(radius)
	_view.cteam.append(team)


func before_each() -> void:
	_view = BotWorldView.new()
	_view.team_id = OWN_TEAM
	_view.slot_id = 0
	_view.own_home = OWN_HOME
	_view.has_home = true
	_view.team_homes = PackedVector2Array([OWN_HOME])
	_view.enemy_homes = PackedVector2Array([ENEMY_HOME])
	_view.enemy_home_teams = PackedInt32Array([ENEMY_TEAM])
	_circle(Vector2(-12.0, 0.0))
	_circle(Vector2(-6.0, 0.0))
	_circle(Vector2(0.0, 0.0))
	_circle(Vector2(-6.0, 5.0))
	_circle(Vector2(-6.0, 10.0))


func test_fork_downstream_and_articulation() -> void:
	var chains: BotChains = BotChains.build(_view)
	assert_eq(chains.downstream(A), 5, "cutting the root-side joint loses the whole chain")
	assert_eq(chains.downstream(B), 4, "the fork joint loses C, D and E plus itself")
	assert_eq(chains.downstream(C), 1, "a tip loses only itself")
	assert_eq(chains.downstream(D), 2, "the branch joint loses E plus itself")
	assert_eq(chains.downstream(E), 1, "the branch tip loses only itself")
	for joint: int in [A, B, D]:
		assert_true(chains.is_articulation(joint), "circle %d is an articulation" % joint)
	for tip: int in [C, E]:
		assert_false(chains.is_articulation(tip), "circle %d is a tip" % tip)
	assert_eq(chains.connected_count(ENEMY_TEAM), 5, "all five circles are home-connected")


func test_cycle_removes_articulation() -> void:
	_circle(Vector2(-13.0, 4.0))
	_circle(Vector2(-10.0, 5.0))
	# ALT touches the home and overlaps A and BRIDGE; BRIDGE overlaps D: a second path home.
	var chains: BotChains = BotChains.build(_view)
	assert_false(chains.is_articulation(A), "A no longer cuts anything with a second path home")
	assert_true(chains.connected(ALT) and chains.connected(BRIDGE), "the extra circles are connected")
	assert_eq(chains.downstream(B), 2, "B now cuts only C: D and E have a route home through the bridge")


func test_unconnected_circle_has_no_downstream() -> void:
	_circle(Vector2(-6.0, 20.0))
	_circle(Vector2(-6.0, 24.0))
	var chains: BotChains = BotChains.build(_view)
	assert_false(chains.connected(ALT), "a floating chain is not home-connected")
	assert_eq(chains.downstream(ALT), 0, "floating circles remove nothing")
	assert_false(chains.is_articulation(ALT), "floating circles are never articulations")
	assert_eq(chains.connected_count(ENEMY_TEAM), 5, "only the rooted five count")


func test_gap_to_uses_connected_land_only() -> void:
	_circle(Vector2(10.0, 12.0), ENEMY_TEAM, 8.0)
	var chains: BotChains = BotChains.build(_view)
	assert_almost_eq(chains.gap_to(ENEMY_TEAM, FAR_POINT), 7.0, 0.001, "tip C at 10 m minus radius 3; the floating r=8 circle is ignored")
	assert_almost_eq(chains.gap_to(ENEMY_TEAM, Vector2(0.0, 0.0)), -3.0, 0.001, "negative inside the land")
	assert_true(is_inf(chains.gap_to(7, FAR_POINT)), "a team without home or circles has no gap")
	assert_almost_eq(chains.gap_to(OWN_TEAM, OWN_HOME), -_view.territory_tuning.home_radius, 0.001, "a home alone gives its own gap")


func test_cut_loss_is_exact_for_multiple_cuts() -> void:
	var chains: BotChains = BotChains.build(_view)
	assert_eq(chains.cut_loss(PackedInt32Array([B])), 4, "single cut equals downstream")
	assert_eq(chains.cut_loss(PackedInt32Array([B, D])), 4, "the branch is already gone with B: no double counting")
	assert_eq(chains.cut_loss(PackedInt32Array([C, E])), 2, "two tips lose two circles")
	assert_eq(chains.cut_loss(PackedInt32Array([D])), 2, "branch joint")
	assert_eq(chains.cut_loss(PackedInt32Array()), 0, "nothing removed")


func test_teammate_home_roots_own_chain() -> void:
	var mate_home: Vector2 = Vector2(-30.0, -30.0)
	_circle(Vector2(-30.0, -25.0), OWN_TEAM)
	assert_false(BotChains.build(_view).connected(5), "floating without the teammate root")
	_view.team_homes.append(mate_home)
	var rooted: BotChains = BotChains.build(_view)
	assert_true(rooted.connected(5), "rooted at a teammate home")
	assert_eq(rooted.downstream(5), 1, "leaf downstream")


func test_dead_own_home_is_not_a_root() -> void:
	_circle(Vector2(30.0, 25.0), OWN_TEAM)
	_view.team_homes = PackedVector2Array()
	var chains: BotChains = BotChains.build(_view)
	assert_false(chains.connected(5), "no living home: nothing is connected")
	assert_true(is_inf(chains.gap_to(OWN_TEAM, Vector2.ZERO)), "no gap without a root")


func test_build_collects_living_team_homes() -> void:
	var tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
	var mate: PlayerSlot = PlayerSlot.new(1, OWN_TEAM, "mate", Color.WHITE, Vector2(-30.0, 0.0))
	var dead: PlayerSlot = PlayerSlot.new(2, OWN_TEAM, "dead", Color.WHITE, Vector2(0.0, 30.0))
	dead.home_flag_alive = false
	var own: PlayerSlot = PlayerSlot.new(0, OWN_TEAM, "own", Color.WHITE, OWN_HOME)
	var slots: Array[PlayerSlot] = [own, mate, dead]
	var circles: Dictionary = {
		"xs": PackedFloat32Array([-30.0, -30.0]),
		"zs": PackedFloat32Array([0.0, 5.0]),
		"radii": PackedFloat32Array([tuning.home_radius, RADIUS]),
		"teams": PackedInt32Array([OWN_TEAM, OWN_TEAM]),
	}
	var view: BotWorldView = BotWorldView.build(
		0, OWN_TEAM, circles, slots, null, PackedVector2Array(), 0.0, null, null, null,
		PackedVector2Array(), PackedVector2Array()
	)
	assert_eq(view.team_homes.size(), 2, "own and living teammate homes, not the dead one")
	assert_true(BotChains.build(view).connected(0), "the circle at the teammate home is connected")
