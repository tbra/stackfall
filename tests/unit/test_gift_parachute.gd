extends GutTest
## Bontago-mp0.139: the procedural gift-crate parachute. Pure animation state
## (core/gifts/ParachuteAnim.gd), the generated geometry (game/ParachuteMesh.gd),
## the node that shows it (game/GiftParachute.gd) and how GiftCrate.set_falling()
## drives it. The host/client wiring through MatchGifts is covered in
## test_gift_flight.gd; the claim hand-off and hint interplay in
## test_gift_claim_crate_feedback.gd.

const EPSILON: float = 0.0001

var _config: GiftConfig


func before_each() -> void:
	_config = GiftConfig.new()


func _anim() -> ParachuteAnim:
	var anim: ParachuteAnim = ParachuteAnim.new()
	anim.configure(_config)
	return anim


func _triangles(mesh: ArrayMesh) -> PackedVector3Array:
	return mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array


# --- ParachuteAnim: phases ----------------------------------------------------

func test_starts_hidden_and_collapse_from_hidden_does_nothing() -> void:
	var anim: ParachuteAnim = _anim()
	assert_eq(anim.phase, ParachuteAnim.Phase.HIDDEN)
	assert_false(anim.is_visible())
	anim.collapse()
	assert_eq(anim.phase, ParachuteAnim.Phase.HIDDEN, "nothing to collapse before the first fall")
	anim.advance(5.0)
	assert_eq(anim.phase, ParachuteAnim.Phase.HIDDEN)


func test_deploy_inflates_from_a_narrow_stream_then_descends() -> void:
	var anim: ParachuteAnim = _anim()
	anim.deploy()
	assert_eq(anim.phase, ParachuteAnim.Phase.DEPLOYING)
	assert_true(anim.is_visible())
	assert_true(anim.is_falling())
	assert_almost_eq(anim.openness(), 0.0, EPSILON)
	assert_almost_eq(anim.radius_scale(), _config.chute_deploy_start_radius_scale, EPSILON)
	assert_almost_eq(anim.height_scale(), _config.chute_deploy_start_height_scale, EPSILON)
	anim.advance(_config.chute_deploy_s * 0.5)
	assert_eq(anim.phase, ParachuteAnim.Phase.DEPLOYING)
	assert_gt(anim.radius_scale(), _config.chute_deploy_start_radius_scale, "inflating")
	anim.advance(_config.chute_deploy_s * 0.5 + EPSILON)
	assert_eq(anim.phase, ParachuteAnim.Phase.DESCENDING)
	assert_almost_eq(anim.openness(), 1.0, EPSILON)
	assert_true(anim.is_falling())


func test_deploy_curve_hits_both_ends_and_overshoots_when_asked() -> void:
	assert_almost_eq(ParachuteAnim.deploy_curve(0.0, _config.chute_deploy_overshoot), 0.0, EPSILON)
	assert_almost_eq(ParachuteAnim.deploy_curve(1.0, _config.chute_deploy_overshoot), 1.0, EPSILON)
	var peak: float = 0.0
	for step: int in range(1, 20):
		peak = maxf(peak, ParachuteAnim.deploy_curve(float(step) / 20.0, _config.chute_deploy_overshoot))
	assert_gt(peak, 1.0, "the canopy pops slightly past full size before settling")
	assert_lt(ParachuteAnim.deploy_curve(0.25, _config.chute_deploy_overshoot), 0.4, "streams out slowly first")
	for step: int in range(0, 21):
		assert_lte(ParachuteAnim.deploy_curve(float(step) / 20.0, 0.0), 1.0, "no overshoot at 0")
	assert_almost_eq(ParachuteAnim.deploy_curve(2.0, 0.0), 1.0, EPSILON, "t is clamped")


func test_repeated_deploy_does_not_restart_the_animation() -> void:
	var anim: ParachuteAnim = _anim()
	anim.deploy()
	anim.advance(_config.chute_deploy_s * 0.6)
	var progress: float = anim.phase_progress()
	anim.deploy()
	assert_almost_eq(anim.phase_progress(), progress, EPSILON, "a repeated falling notification is harmless")
	anim.advance(_config.chute_deploy_s * 0.5)
	assert_eq(anim.phase, ParachuteAnim.Phase.DESCENDING)
	anim.deploy()
	assert_eq(anim.phase, ParachuteAnim.Phase.DESCENDING, "still open, still falling")


func test_collapse_deflates_sinks_fades_and_ends_hidden() -> void:
	var anim: ParachuteAnim = _anim()
	anim.deploy()
	anim.advance(_config.chute_deploy_s + 0.1)
	anim.collapse()
	assert_eq(anim.phase, ParachuteAnim.Phase.COLLAPSING)
	assert_true(anim.is_visible(), "the canopy must not vanish the instant the crate lands")
	assert_false(anim.is_falling())
	assert_almost_eq(anim.alpha(), 1.0, EPSILON)
	assert_almost_eq(anim.drop_offset(), 0.0, EPSILON)
	var last_height: float = anim.height_scale()
	var last_alpha: float = 1.0
	var last_drop: float = 0.0
	var steps: int = 11
	for _i: int in range(steps):
		anim.advance(_config.chute_collapse_s / float(steps) * 0.99)
		assert_lte(anim.height_scale(), last_height + EPSILON, "deflates monotonically")
		assert_lte(anim.alpha(), last_alpha + EPSILON, "fades monotonically")
		assert_lte(anim.drop_offset(), last_drop + EPSILON, "sinks monotonically")
		last_height = anim.height_scale()
		last_alpha = anim.alpha()
		last_drop = anim.drop_offset()
	assert_eq(anim.phase, ParachuteAnim.Phase.COLLAPSING, "still collapsing just before the end")
	assert_lt(anim.height_scale(), 0.2, "almost flat by the end")
	assert_lt(anim.alpha(), 0.2, "almost gone by the end")
	assert_lt(anim.drop_offset(), -_config.chute_collapse_drop_m * 0.8)
	anim.advance(_config.chute_collapse_s)
	assert_eq(anim.phase, ParachuteAnim.Phase.HIDDEN)
	assert_false(anim.is_visible())
	anim.collapse()
	assert_eq(anim.phase, ParachuteAnim.Phase.HIDDEN, "collapse stays a no-op once hidden")


func test_alpha_holds_until_the_fade_starts() -> void:
	var anim: ParachuteAnim = _anim()
	anim.deploy()
	anim.advance(_config.chute_deploy_s)
	anim.collapse()
	anim.advance(_config.chute_collapse_s * _config.chute_collapse_fade_start * 0.9)
	assert_almost_eq(anim.alpha(), 1.0, EPSILON)
	anim.advance(_config.chute_collapse_s * 0.3)
	assert_lt(anim.alpha(), 1.0)


func test_collapse_during_deploy_starts_from_the_current_pose() -> void:
	var anim: ParachuteAnim = _anim()
	anim.deploy()
	anim.advance(_config.chute_deploy_s * 0.4)
	var radius: float = anim.radius_scale()
	var height: float = anim.height_scale()
	anim.collapse()
	assert_eq(anim.phase, ParachuteAnim.Phase.COLLAPSING)
	# Breathing is part of the sampled scale; allow for its small swing.
	assert_almost_eq(anim.radius_scale(), radius, 0.05)
	assert_almost_eq(anim.height_scale(), height, 0.05)


func test_deploy_again_after_a_collapse_restarts_from_the_stream() -> void:
	var anim: ParachuteAnim = _anim()
	anim.deploy()
	anim.advance(_config.chute_deploy_s)
	anim.collapse()
	anim.advance(_config.chute_collapse_s * 0.5)
	anim.deploy()
	assert_eq(anim.phase, ParachuteAnim.Phase.DEPLOYING)
	assert_almost_eq(anim.openness(), 0.0, EPSILON)
	assert_almost_eq(anim.alpha(), 1.0, EPSILON)
	assert_almost_eq(anim.drop_offset(), 0.0, EPSILON)


func test_sway_is_bounded_zero_when_hidden_and_differs_per_gift() -> void:
	var first: ParachuteAnim = _anim()
	var second: ParachuteAnim = _anim()
	first.set_phase_seed(1.0)
	second.set_phase_seed(2.0)
	assert_eq(first.tilt(), Vector2.ZERO, "no lean without a canopy")
	first.deploy()
	second.deploy()
	first.advance(_config.chute_deploy_s)
	second.advance(_config.chute_deploy_s)
	var apart: bool = false
	for _i: int in range(200):
		first.advance(0.05)
		second.advance(0.05)
		assert_lte(absf(first.tilt().x), _config.chute_sway_tilt_rad + EPSILON)
		assert_lte(absf(first.tilt().y), _config.chute_sway_tilt_rad + EPSILON)
		if first.tilt().distance_to(second.tilt()) > EPSILON:
			apart = true
	assert_true(apart, "two crates must not lean in lockstep")


func test_open_canopy_breathes_within_a_small_band() -> void:
	var anim: ParachuteAnim = _anim()
	anim.deploy()
	anim.advance(_config.chute_deploy_s)
	var low: float = INF
	var high: float = -INF
	for _i: int in range(400):
		anim.advance(0.02)
		low = minf(low, anim.radius_scale())
		high = maxf(high, anim.radius_scale())
	assert_gt(high - low, EPSILON, "it visibly breathes")
	assert_lte(high, 1.0 + _config.chute_breath_amount + EPSILON)
	assert_gte(low, 1.0 - _config.chute_breath_amount - EPSILON)


func test_zero_durations_complete_at_once_without_nan() -> void:
	_config.chute_deploy_s = 0.0
	_config.chute_collapse_s = 0.0
	var anim: ParachuteAnim = _anim()
	anim.deploy()
	anim.advance(0.016)
	assert_eq(anim.phase, ParachuteAnim.Phase.DESCENDING)
	assert_true(is_finite(anim.radius_scale()))
	anim.collapse()
	anim.advance(0.016)
	assert_eq(anim.phase, ParachuteAnim.Phase.HIDDEN)
	anim.advance(NAN)
	anim.advance(-1.0)
	assert_eq(anim.phase, ParachuteAnim.Phase.HIDDEN, "bad deltas are ignored")


# --- ParachuteMesh: geometry --------------------------------------------------

func test_gore_count_is_even_and_at_least_three() -> void:
	_config.chute_gore_count = 7
	assert_eq(ParachuteMesh.gore_count(_config), 8, "odd counts round up so the colours alternate all round")
	_config.chute_gore_count = 0
	assert_eq(ParachuteMesh.gore_count(_config), 4)
	_config.chute_gore_count = 12
	assert_eq(ParachuteMesh.gore_count(_config), 12)


func test_canopy_is_a_light_single_surface_of_alternating_gores() -> void:
	var mesh: ArrayMesh = ParachuteMesh.build_canopy(_config)
	assert_eq(mesh.get_surface_count(), 1, "one ArrayMesh surface")
	var verts: PackedVector3Array = _triangles(mesh)
	var gores: int = ParachuteMesh.gore_count(_config)
	var rings: int = ParachuteMesh.ring_count(_config)
	assert_eq(verts.size(), gores * rings * 4 * 3, "four triangles per gore per ring")
	assert_lt(verts.size() / 3, 400, "stays low-poly")
	var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
	var count_a: int = 0
	var count_b: int = 0
	for color: Color in colors:
		if absf(color.r - _config.chute_color_a.r) < 0.02 and absf(color.g - _config.chute_color_a.g) < 0.02 \
				and absf(color.b - _config.chute_color_a.b) < 0.02:
			count_a += 1
		elif absf(color.g - _config.chute_color_b.g) < 0.02 and absf(color.b - _config.chute_color_b.b) < 0.02:
			count_b += 1
	assert_eq(count_a, count_b, "two colours alternate evenly")
	assert_eq(count_a + count_b, colors.size())
	# Neighbouring gores must differ: the gore at the first triangle vs the gore one panel round.
	var per_gore: int = rings * 4 * 3
	assert_ne(colors[0], colors[per_gore], "adjacent gores alternate colour")
	assert_eq(colors[0], colors[per_gore * 2], "every other gore repeats it")


func test_canopy_is_a_dome_with_an_open_vent_and_a_scalloped_rim() -> void:
	var verts: PackedVector3Array = _triangles(ParachuteMesh.build_canopy(_config))
	var min_radius: float = INF
	var max_radius: float = 0.0
	var min_y: float = INF
	var max_y: float = -INF
	var lifted_rim_vertex: bool = false
	for vertex: Vector3 in verts:
		var radius: float = Vector2(vertex.x, vertex.z).length()
		min_radius = minf(min_radius, radius)
		max_radius = maxf(max_radius, radius)
		min_y = minf(min_y, vertex.y)
		max_y = maxf(max_y, vertex.y)
		if absf(vertex.y - (_config.chute_rim_height_m + _config.chute_scallop_depth_m)) < 0.001 \
				and absf(radius - _config.chute_radius_m) < 0.001:
			lifted_rim_vertex = true
	assert_almost_eq(max_radius, _config.chute_radius_m, 0.001, "the rim seams sit at the configured radius")
	assert_almost_eq(min_y, _config.chute_rim_height_m, 0.001, "nothing hangs below the rim seams")
	var vent_radius: float = _config.chute_radius_m * sin(_config.chute_vent_angle_rad)
	assert_almost_eq(min_radius, vent_radius, 0.001, "the open vent edge at the top")
	assert_gt(min_radius, 0.05, "the vent is a hole, not a point")
	assert_almost_eq(max_y, _config.chute_rim_height_m + _config.chute_dome_height_m * cos(_config.chute_vent_angle_rad), 0.001)
	assert_true(lifted_rim_vertex, "each panel's rim edge is lifted into a scallop")


func test_canopy_normals_face_outward_and_winding_matches() -> void:
	var mesh: ArrayMesh = ParachuteMesh.build_canopy(_config)
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	assert_eq(normals.size(), verts.size())
	var centre: Vector3 = Vector3(0.0, _config.chute_rim_height_m, 0.0)
	var bad: int = 0
	for index: int in range(0, verts.size(), 3):
		var centroid: Vector3 = (verts[index] + verts[index + 1] + verts[index + 2]) / 3.0
		if normals[index].dot(centroid - centre) <= 0.0:
			bad += 1
		# Godot's front face is clockwise: the cross product points away from the normal.
		var facing: Vector3 = (verts[index + 1] - verts[index]).cross(verts[index + 2] - verts[index])
		if facing.dot(normals[index]) >= 0.0:
			bad += 1
	assert_eq(bad, 0, "every triangle is front-facing from outside with an outward normal")


func test_lines_run_rim_to_riser_and_riser_to_crate_corners() -> void:
	var rim: PackedVector3Array = _triangles(ParachuteMesh.build_rim_lines(_config))
	var gores: int = ParachuteMesh.gore_count(_config)
	assert_eq(rim.size(), gores * ParachuteMesh.PRISM_SIDES * 6, "one thin prism per gore seam")
	var reach: float = 0.0
	var low: float = INF
	for vertex: Vector3 in rim:
		reach = maxf(reach, Vector2(vertex.x, vertex.z).length())
		low = minf(low, vertex.y)
	assert_almost_eq(reach, _config.chute_radius_m, _config.chute_line_thickness_m, "lines reach the rim")
	assert_almost_eq(low, 0.0, _config.chute_line_thickness_m, "and converge on the riser")
	var corners: PackedVector3Array = ParachuteMesh.harness_corners(_config)
	assert_eq(corners.size(), 4)
	for corner: Vector3 in corners:
		assert_almost_eq(corner.y, -_config.chute_riser_height_m, EPSILON)
		assert_almost_eq(absf(corner.x), _config.chute_attach_half_extent_m, EPSILON)
		assert_almost_eq(absf(corner.z), _config.chute_attach_half_extent_m, EPSILON)
	var harness: PackedVector3Array = _triangles(ParachuteMesh.build_harness_lines(_config))
	assert_eq(harness.size(), 4 * ParachuteMesh.PRISM_SIDES * 6)


func test_materials_are_double_sided_and_vertex_coloured() -> void:
	var canopy: StandardMaterial3D = ParachuteMesh.canopy_material()
	assert_eq(canopy.cull_mode, BaseMaterial3D.CULL_DISABLED, "double-sided")
	assert_true(canopy.vertex_color_use_as_albedo)
	assert_eq(canopy.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "opaque while open")
	var line: StandardMaterial3D = ParachuteMesh.line_material(_config)
	assert_eq(line.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED)
	assert_eq(line.albedo_color, _config.chute_line_color)


# --- GiftParachute node -------------------------------------------------------

func _make_parachute() -> GiftParachute:
	var parachute: GiftParachute = autofree(GiftParachute.new())
	parachute.setup(_config, GiftCrate.CRATE_SIZE.y * 0.5)
	add_child_autofree(parachute)
	return parachute


func test_node_is_hidden_until_deployed_and_has_the_expected_parts() -> void:
	var parachute: GiftParachute = _make_parachute()
	assert_false(parachute.visible)
	assert_false(parachute.is_active())
	for path: String in ["Body/Harness", "Body/Sway/Inflate/Canopy", "Body/Sway/Inflate/RimLines"]:
		assert_not_null(parachute.get_node_or_null(path), path)
	assert_almost_eq(parachute.position.y, GiftCrate.CRATE_SIZE.y * 0.5 + _config.chute_riser_height_m, EPSILON,
		"the riser sits above the crate's top face")


func test_node_inflates_on_deploy_and_poses_the_scale_node() -> void:
	var parachute: GiftParachute = _make_parachute()
	var inflate: Node3D = parachute.get_node("Body/Sway/Inflate") as Node3D
	parachute.deploy()
	assert_true(parachute.visible)
	assert_almost_eq(inflate.scale.x, _config.chute_deploy_start_radius_scale, EPSILON, "starts as a stream")
	parachute.advance(_config.chute_deploy_s)
	parachute.advance(0.0001)
	assert_almost_eq(inflate.scale.x, 1.0, 0.05, "fully open")
	assert_almost_eq(inflate.scale.y, 1.0, 0.05)
	var sway: Node3D = parachute.get_node("Body/Sway") as Node3D
	parachute.advance(0.7)
	assert_ne(sway.rotation, Vector3.ZERO, "leans while descending")
	assert_lte(absf(sway.rotation.x), _config.chute_sway_tilt_rad + EPSILON)


func test_node_collapse_fades_then_hides_and_restores_opaque() -> void:
	var parachute: GiftParachute = _make_parachute()
	var canopy: MeshInstance3D = parachute.get_node("Body/Sway/Inflate/Canopy") as MeshInstance3D
	var material: StandardMaterial3D = canopy.material_override as StandardMaterial3D
	parachute.deploy()
	parachute.advance(_config.chute_deploy_s + 0.1)
	assert_false(parachute.is_fading())
	assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED)
	parachute.collapse()
	assert_true(parachute.visible, "still there the frame after landing")
	parachute.advance(_config.chute_collapse_s * 0.8)
	assert_true(parachute.is_fading())
	assert_ne(material.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "fade needs blending")
	assert_lt(material.albedo_color.a, 1.0)
	var body: Node3D = parachute.get_node("Body") as Node3D
	assert_lt(body.position.y, 0.0, "it has sunk")
	parachute.advance(_config.chute_collapse_s)
	assert_false(parachute.visible)
	# A later deploy gets a fully opaque canopy back.
	parachute.deploy()
	assert_false(parachute.is_fading())
	assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED)
	assert_almost_eq(material.albedo_color.a, 1.0, EPSILON)
	assert_almost_eq(body.position.y, 0.0, EPSILON)


func test_release_hands_the_parachute_to_a_new_parent_and_frees_it_after_the_collapse() -> void:
	var crate_root: Node3D = autofree(Node3D.new())
	add_child_autofree(crate_root)
	var new_parent: Node3D = autofree(Node3D.new())
	add_child_autofree(new_parent)
	crate_root.global_position = Vector3(3.0, 4.0, 5.0)
	var parachute: GiftParachute = autofree(GiftParachute.new())
	parachute.setup(_config, GiftCrate.CRATE_SIZE.y * 0.5)
	crate_root.add_child(parachute)
	parachute.deploy()
	parachute.advance(_config.chute_deploy_s + 0.1)
	var before: Vector3 = parachute.global_position
	parachute.release_to(new_parent)
	assert_eq(parachute.get_parent(), new_parent)
	assert_eq(parachute.global_position, before, "keeps its world pose")
	assert_eq(parachute.phase(), ParachuteAnim.Phase.COLLAPSING, "it collapses rather than popping out")
	assert_false(parachute.is_queued_for_deletion())
	parachute.advance(_config.chute_collapse_s + 0.1)
	assert_true(parachute.is_queued_for_deletion(), "gone once fully faded")


# --- GiftCrate.set_falling() --------------------------------------------------

func _make_crate() -> GiftCrate:
	var crate: GiftCrate = autofree(GiftCrate.new())
	add_child_autofree(crate)
	return crate


func test_a_crate_nothing_told_to_fall_shows_no_canopy() -> void:
	var crate: GiftCrate = _make_crate()
	var parachute: GiftParachute = crate.parachute()
	assert_not_null(parachute)
	assert_false(crate.is_falling())
	assert_false(parachute.visible, "a landed crate from a replicated spawn has no canopy")
	crate.set_falling(false)
	assert_false(parachute.visible, "landing before ever falling stays hidden")
	assert_eq(parachute.phase(), ParachuteAnim.Phase.HIDDEN)


func test_set_falling_true_deploys_and_false_collapses_instead_of_vanishing() -> void:
	var crate: GiftCrate = _make_crate()
	var parachute: GiftParachute = crate.parachute()
	crate.set_falling(true)
	assert_true(crate.is_falling())
	assert_eq(parachute.phase(), ParachuteAnim.Phase.DEPLOYING)
	assert_true(parachute.visible)
	parachute.advance(crate.gift_config.chute_deploy_s + 0.1)
	assert_eq(parachute.phase(), ParachuteAnim.Phase.DESCENDING)
	crate.set_falling(false)
	assert_false(crate.is_falling())
	assert_eq(parachute.phase(), ParachuteAnim.Phase.COLLAPSING)
	assert_true(parachute.visible, "the canopy is still on screen the moment the crate lands")
	parachute.advance(crate.gift_config.chute_collapse_s + 0.1)
	assert_false(parachute.visible)
	assert_eq(parachute.phase(), ParachuteAnim.Phase.HIDDEN)


func test_set_falling_is_idempotent() -> void:
	var crate: GiftCrate = _make_crate()
	var parachute: GiftParachute = crate.parachute()
	crate.set_falling(true)
	parachute.advance(crate.gift_config.chute_deploy_s * 0.5)
	var progress: float = parachute.anim().phase_progress()
	crate.set_falling(true)
	assert_almost_eq(parachute.anim().phase_progress(), progress, EPSILON, "a second fall notification must not restart the deploy")
	crate.set_falling(false)
	var collapse_progress: float = parachute.anim().phase_progress()
	crate.set_falling(false)
	assert_almost_eq(parachute.anim().phase_progress(), collapse_progress, EPSILON, "nor restart the collapse")


func test_set_falling_before_the_crate_enters_the_tree_still_deploys() -> void:
	var crate: GiftCrate = autofree(GiftCrate.new())
	crate.gift_id = 3
	crate.set_falling(true)
	add_child_autofree(crate)
	assert_eq(crate.parachute().phase(), ParachuteAnim.Phase.DEPLOYING)


func test_the_canopy_animates_from_the_crates_own_process() -> void:
	var crate: GiftCrate = _make_crate()
	crate.set_falling(true)
	var parachute: GiftParachute = crate.parachute()
	var inflate: Node3D = parachute.get_node("Body/Sway/Inflate") as Node3D
	var start: float = inflate.scale.x
	# GiftParachute._process runs with the scene tree; step the node the same way.
	parachute._process(crate.gift_config.chute_deploy_s * 0.5)
	assert_gt(inflate.scale.x, start, "the canopy inflates on its own once falling")
