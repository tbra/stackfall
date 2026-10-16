extends GutTest
## QoL experiment 4: the ground ring a goal beacon shows at the
## effective claim radius while the bigger-claim-radius toggle is on, and
## at goal_zone_radius while it is off. With the toggle on the radius must be the value the
## host uses for capture (Match.qol_claim_radius() -> MatchTerritory._claim_radius()).

const MAP_RADIUS: float = 20.0
const RING_NODE_NAME: StringName = &"ClaimRadiusRing"
const MULTIPLIER: float = 2.5

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = MAP_RADIUS
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func after_each() -> void:
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _qol(enabled: bool, multiplier: float = MULTIPLIER) -> QolExperiments:
	var qol: QolExperiments = QolExperiments.new()
	qol.goal_radius_enabled = enabled
	qol.goal_radius_multiplier = multiplier
	return qol


func _config(qol: QolExperiments, goals: int = 1) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.goal_flag_count = goals
	config.rng_seed = 5150
	config.qol = qol
	return config


## Starts a real match (the way Main does) and places the flags through the one
## Field call site that wires the ring.
func _place(qol: QolExperiments, goals: int = 1) -> Array[GoalFlag]:
	Match.start_match(_config(qol, goals))
	var config: MatchConfig = Match.config
	_field.rebuild_for_map(config.map_def())
	_field.place_flags(config.player_count, config.player_colors, config.effective_goal_flag_count())
	return _field.goal_flags()


func _base_radius() -> float:
	return Match._territory_tuning.goal_zone_radius


func _ring_node(flag: GoalFlag) -> MeshInstance3D:
	var found: Array[Node] = flag.find_children(RING_NODE_NAME, "MeshInstance3D", false, false)
	return found[0] as MeshInstance3D if not found.is_empty() else null


## The radius the ring marks, as its shader draws it.
func _ring_radius(flag: GoalFlag) -> float:
	var material: ShaderMaterial = _ring_node(flag).material_override as ShaderMaterial
	return float(material.get_shader_parameter(&"zone_radius"))


# --- toggle off: the zone still draws, at the no-build radius ----

func test_toggle_off_draws_the_zone_at_goal_zone_radius_while_claim_radius_stays_zero() -> void:
	var flags: Array[GoalFlag] = _place(_qol(false), 2)
	assert_eq(flags.size(), 2)
	assert_eq(Match.qol_claim_radius(), 0.0, "the capture rule is unchanged")
	assert_almost_eq(Match.goal_zone_visual_radius(), _base_radius(), 0.0001)
	for flag: GoalFlag in flags:
		assert_not_null(_ring_node(flag), "the zone is built with the experiment off")
		assert_eq(flag.find_children(RING_NODE_NAME, "MeshInstance3D", false, false).size(), 1)
		assert_true(_ring_node(flag).visible)
		assert_almost_eq(_ring_radius(flag), _base_radius(), 0.0001)


# --- toggle on: one ring per beacon at the capture radius ---------------------------

func test_toggle_on_draws_one_ring_per_goal_at_the_host_capture_radius() -> void:
	var flags: Array[GoalFlag] = _place(_qol(true), 3)
	assert_eq(flags.size(), 3)
	var expected: float = _base_radius() * MULTIPLIER
	assert_almost_eq(Match.qol_claim_radius(), expected, 0.0001)
	assert_eq(Match.qol_claim_radius(), Match._territory._claim_radius(), "the exact helper capture uses")
	assert_eq(Match.qol_claim_radius(), Match.config.qol.effective_goal_radius(_base_radius()))
	for flag: GoalFlag in flags:
		assert_not_null(_ring_node(flag))
		assert_true(_ring_node(flag).visible)
		assert_almost_eq(_ring_radius(flag), expected, 0.0001)
		assert_eq(flag.find_children(RING_NODE_NAME, "MeshInstance3D", false, false).size(), 1, "exactly one ring node")


func test_ring_follows_the_replicated_config_qol_like_a_client() -> void:
	# A client receives MatchConfig.to_dict() over the wire; its ring must come from the
	# replicated qol block alone, with no client-side authority.
	var host_config: MatchConfig = _config(_qol(true))
	var wire: Dictionary = host_config.to_dict()
	var replicated: QolExperiments = MatchConfig.from_dict(wire).qol
	assert_not_null(replicated)
	Match.start_match(_config(replicated))
	_field.place_flags(2, Match.config.player_colors, 1)
	assert_almost_eq(_ring_radius(_field.goal_flags()[0]), _base_radius() * MULTIPLIER, 0.0001)


# --- GoalFlag.set_claim_ring contract ------------------------------------------------

# --- tuning defaults: new exports are subtle, positive and hinted ---------------------
