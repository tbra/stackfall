extends GutTest
## Bontago-1pi.18.6 (QoL experiment 4): the ground ring a goal beacon shows at the
## effective claim radius while the bigger-claim-radius toggle is on, and nothing at
## all while it is off. The radius must be the value the host uses for capture
## (Match.qol_claim_radius() -> MatchTerritory._claim_radius()).

const MAP_RADIUS: float = 20.0
const RING_NODE_NAME: StringName = &"ClaimRadiusRing"
const MULTIPLIER: float = 2.5
const OVER_CEILING_MULTIPLIER: float = 9.0

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
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
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
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


func _flat_flag() -> GoalFlag:
	var flag: GoalFlag = (load("res://game/GoalFlag.tscn") as PackedScene).instantiate() as GoalFlag
	add_child_autofree(flag)
	return flag


## Largest and smallest horizontal distance of the ring mesh's vertices from the centre.
func _radial_extent(mesh: Mesh) -> Vector2:
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var low: float = INF
	var high: float = 0.0
	for vertex: Vector3 in vertices:
		var distance: float = Vector2(vertex.x, vertex.z).length()
		low = minf(low, distance)
		high = maxf(high, distance)
		assert_almost_eq(vertex.y, 0.0, 0.0001, "the ring mesh is flat")
	return Vector2(low, high)


# --- toggle off: nothing is created -----------------------------------------------

func test_toggle_off_creates_no_ring_and_claim_radius_is_zero() -> void:
	var flags: Array[GoalFlag] = _place(_qol(false))
	assert_eq(flags.size(), 1)
	assert_eq(Match.qol_claim_radius(), 0.0)
	var flag: GoalFlag = flags[0]
	assert_null(flag.claim_ring_node(), "no node is built while the toggle is off")
	assert_null(flag.find_child(RING_NODE_NAME, false, false))
	assert_false(flag.claim_ring_visible())
	assert_eq(flag.claim_ring_radius(), 0.0)


func test_toggle_off_leaves_the_beacon_children_identical_to_a_bare_flag() -> void:
	var bare: GoalFlag = _flat_flag()
	var flags: Array[GoalFlag] = _place(_qol(false))
	assert_eq(flags[0].get_child_count(), bare.get_child_count(), "same node count, nothing new")


func test_no_qol_snapshot_and_no_match_config_both_read_zero() -> void:
	Match.start_match(_config(null))
	assert_eq(Match.qol_claim_radius(), 0.0, "a null qol (before the shared snapshot) never draws")
	var saved: MatchConfig = Match.config
	Match.config = null
	assert_eq(Match.qol_claim_radius(), 0.0, "no config yet is safe")
	Match.config = saved


# --- toggle on: one ring per beacon at the capture radius ---------------------------

func test_toggle_on_draws_one_ring_per_goal_at_the_host_capture_radius() -> void:
	var flags: Array[GoalFlag] = _place(_qol(true), 3)
	assert_eq(flags.size(), 3)
	var expected: float = _base_radius() * MULTIPLIER
	assert_almost_eq(Match.qol_claim_radius(), expected, 0.0001)
	assert_eq(Match.qol_claim_radius(), Match._territory._claim_radius(), "the exact helper capture uses")
	assert_eq(Match.qol_claim_radius(), Match.config.qol.effective_goal_radius(_base_radius()))
	for flag: GoalFlag in flags:
		assert_not_null(flag.claim_ring_node())
		assert_true(flag.claim_ring_visible())
		assert_almost_eq(flag.claim_ring_radius(), expected, 0.0001)
		assert_eq(flag.find_children(RING_NODE_NAME, "MeshInstance3D", false, false).size(), 1, "exactly one ring node")


func test_ring_mesh_band_is_centred_on_the_claim_radius_with_the_tuned_width() -> void:
	var flag: GoalFlag = _place(_qol(true))[0]
	var tuning: BeaconVisualTuning = flag.beacon_visuals
	var radius: float = Match.qol_claim_radius()
	var extent: Vector2 = _radial_extent(flag.claim_ring_node().mesh)
	assert_almost_eq(extent.x, radius - tuning.claim_ring_width * 0.5, 0.001, "inner edge")
	assert_almost_eq(extent.y, radius + tuning.claim_ring_width * 0.5, 0.001, "outer edge")
	assert_almost_eq(flag.claim_ring_node().position.y, tuning.claim_ring_lift, 0.0001, "lift from tuning")


func test_ring_material_is_flat_translucent_and_takes_color_and_alpha_from_tuning() -> void:
	var flag: GoalFlag = _place(_qol(true))[0]
	var tuning: BeaconVisualTuning = flag.beacon_visuals
	var material: StandardMaterial3D = flag.claim_ring_node().material_override as StandardMaterial3D
	assert_not_null(material)
	assert_eq(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_almost_eq(material.albedo_color.a, tuning.claim_ring_alpha, 0.0001)
	assert_almost_eq(material.albedo_color.r, tuning.claim_ring_color.r, 0.0001)
	assert_lt(material.albedo_color.a, 0.6, "subtle by default")
	assert_eq(flag.claim_ring_node().cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func test_multiplier_is_clamped_to_the_ceiling_in_the_drawn_radius() -> void:
	var flag: GoalFlag = _place(_qol(true, OVER_CEILING_MULTIPLIER))[0]
	assert_almost_eq(
		flag.claim_ring_radius(),
		_base_radius() * QolExperiments.GOAL_RADIUS_MULTIPLIER_MAX,
		0.0001, "same clamp as capture"
	)


func test_ring_follows_the_replicated_config_qol_like_a_client() -> void:
	# A client receives MatchConfig.to_dict() over the wire; its ring must come from the
	# replicated qol block alone, with no client-side authority.
	var host_config: MatchConfig = _config(_qol(true))
	var wire: Dictionary = host_config.to_dict()
	var replicated: QolExperiments = MatchConfig.from_dict(wire).qol
	assert_not_null(replicated)
	Match.start_match(_config(replicated))
	_field.place_flags(2, Match.config.player_colors, 1)
	assert_almost_eq(_field.goal_flags()[0].claim_ring_radius(), _base_radius() * MULTIPLIER, 0.0001)


# --- GoalFlag.set_claim_ring contract ------------------------------------------------

func test_set_claim_ring_zero_or_invalid_removes_the_ring() -> void:
	var flag: GoalFlag = _flat_flag()
	flag.set_claim_ring(6.0)
	assert_not_null(flag.claim_ring_node())
	flag.set_claim_ring(0.0)
	assert_null(flag.claim_ring_node(), "turning the radius off drops the node")
	await get_tree().process_frame
	assert_null(flag.find_child(RING_NODE_NAME, false, false), "and it leaves the tree")
	flag.set_claim_ring(NAN)
	flag.set_claim_ring(-3.0)
	assert_null(flag.claim_ring_node(), "negative and non-finite radii draw nothing")


func test_set_claim_ring_same_radius_reuses_the_mesh_and_a_new_radius_rebuilds_it() -> void:
	var flag: GoalFlag = _flat_flag()
	flag.set_claim_ring(6.0)
	var node: MeshInstance3D = flag.claim_ring_node()
	var mesh: Mesh = node.mesh
	flag.set_claim_ring(6.0)
	assert_same(flag.claim_ring_node(), node, "no second node")
	assert_same(flag.claim_ring_node().mesh, mesh, "no per-call rebuild")
	flag.set_claim_ring(8.0)
	assert_same(flag.claim_ring_node(), node, "still one node")
	assert_ne(flag.claim_ring_node().mesh, mesh, "a changed radius rebuilds the mesh")
	assert_almost_eq(_radial_extent(flag.claim_ring_node().mesh).y, 8.0 + flag.beacon_visuals.claim_ring_width * 0.5, 0.001)


func test_processing_a_flag_with_a_ring_allocates_no_new_nodes() -> void:
	var flag: GoalFlag = _flat_flag()
	flag.set_claim_ring(6.0)
	var children: int = flag.get_child_count()
	var mesh: Mesh = flag.claim_ring_node().mesh
	for _i: int in range(30):
		flag._process(0.016)
	assert_eq(flag.get_child_count(), children)
	assert_same(flag.claim_ring_node().mesh, mesh, "the ring is static between radius changes")


# --- tuning defaults: new exports are subtle, positive and hinted ---------------------

func test_ring_tuning_defaults_are_subtle_and_sane() -> void:
	var tuning: BeaconVisualTuning = load("res://config/beacon_visual_tuning.tres") as BeaconVisualTuning
	assert_gt(tuning.claim_ring_alpha, 0.0)
	assert_lt(tuning.claim_ring_alpha, 0.6)
	assert_gt(tuning.claim_ring_width, 0.0)
	assert_gt(tuning.claim_ring_lift, 0.0)
	assert_gte(tuning.claim_ring_segments, 12)
