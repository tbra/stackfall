extends GutTest
## Snow (Bontago-22y.6): pure geometry and wire format (core/weather/
## SnowGeometry.gd, config/SnowTuning.gd). No scene tree, no physics.

const EPS: float = 0.0001
const HULL_TOLERANCE_M: float = 0.01


func _tuning() -> SnowTuning:
	return (load("res://config/weather/snow.tres") as SnowTuning).duplicate() as SnowTuning


func test_snow_tres_is_a_snow_tuning_with_an_effect() -> void:
	var def: SnowTuning = load("res://config/weather/snow.tres") as SnowTuning
	assert_not_null(def, "snow.tres uses SnowTuning")
	assert_eq(def.id, &"snow")
	assert_true(load(def.effect_script) is Script, "effect script loads")
	assert_true(load(def.presentation_scene) is PackedScene, "presentation loads")
	assert_gt(def.max_depth_m, 0.0)
	assert_gt(def.depth_levels, 0)
	assert_gt(def.max_block_patches, 0)
	assert_gt(def.cap_segments, 1)
	assert_gt(def.rebuild_patches_per_frame, 0)
	assert_gt(def.max_disc_patches, 0)
	assert_lt(def.flake_amount_low, def.flake_amount, "Low preset draws fewer flakes")


func test_dome_layout_is_deterministic_per_seed() -> void:
	var t: SnowTuning = _tuning()
	var seed_a: int = SnowGeometry.patch_seed(987654321, 12, 3, SnowGeometry.AXIS_UP)
	var seed_b: int = SnowGeometry.patch_seed(987654321, 12, 4, SnowGeometry.AXIS_UP)
	assert_eq(SnowGeometry.dome_params(seed_a, t), SnowGeometry.dome_params(seed_a, t), "same seed, same dome")
	assert_ne(SnowGeometry.dome_params(seed_a, t), SnowGeometry.dome_params(seed_b, t), "another cell differs")
	assert_eq(SnowGeometry.dome_params(seed_a, t).size(), SnowGeometry.DOME_STRIDE)
	assert_ne(SnowGeometry.patch_seed(1, 2, 3, 2), SnowGeometry.patch_seed(1, 3, 2, 2))
	var h: float = SnowGeometry.unit_hash(3, 4)
	assert_true(h >= 0.0 and h < 1.0)
	assert_eq(h, SnowGeometry.unit_hash(3, 4))


func test_domes_stay_inside_the_patch_rounded_and_under_the_cap() -> void:
	var t: SnowTuning = _tuning()
	var edge: float = 0.96
	var n: int = t.cap_segments
	for s: int in range(40):
		var params: PackedFloat32Array = SnowGeometry.dome_params(SnowGeometry.patch_seed(s, 1, 0, 2), t)
		for level: int in range(1, t.depth_levels + 1):
			var points: PackedVector3Array = SnowGeometry.dome_points(params, edge, level, t)
			assert_eq(points.size(), (n + 1) * (n + 1))
			var half: float = edge * SnowGeometry.fill_for_level(level, t) * 0.5
			var highest: float = 0.0
			for j: int in range(n + 1):
				for i: int in range(n + 1):
					var p: Vector3 = points[j * (n + 1) + i]
					assert_true(absf(p.x) <= half + EPS and absf(p.z) <= half + EPS, "inside footprint")
					assert_gte(p.y, t.cap_lift_m - EPS, "never below the surface")
					assert_lte(p.y, SnowGeometry.dome_max_height(level, t) + EPS, "under the cap")
					highest = maxf(highest, p.y)
					if i == 0 or j == 0 or i == n or j == n:
						assert_almost_eq(p.y, t.cap_lift_m, EPS, "rim on the surface (rounded edge)")
			assert_gt(highest, SnowGeometry.dome_height(level, t) * 0.5, "reaches its level")
	assert_lt(SnowGeometry.fill_for_level(1, t), SnowGeometry.fill_for_level(t.depth_levels, t), "light snow is a smaller dusting")
	assert_true(SnowGeometry.dome_points(SnowGeometry.dome_params(1, t), edge, 0, t).is_empty(), "level 0 has no dome")


func test_dome_is_nearly_concave_so_hull_matches_mesh() -> void:
	# Hull top and drawn grid agree when every interior grid point is not
	# below the mean of its 4 neighbours by more than a few millimetres.
	var t: SnowTuning = _tuning()
	var n: int = t.cap_segments
	var worst: float = 0.0
	for s: int in range(40):
		var points: PackedVector3Array = SnowGeometry.dome_points(SnowGeometry.dome_params(s, t), 0.96, t.depth_levels, t)
		for j: int in range(1, n):
			for i: int in range(1, n):
				var c: float = points[j * (n + 1) + i].y
				var mean: float = (points[j * (n + 1) + i - 1].y + points[j * (n + 1) + i + 1].y + points[(j - 1) * (n + 1) + i].y + points[(j + 1) * (n + 1) + i].y) * 0.25
				worst = maxf(worst, mean - c)
	gut.p("worst concavity dip %.4f m" % worst)
	assert_lt(worst, HULL_TOLERANCE_M, "dips the hull would bridge are tiny")


func test_mesh_is_the_grid_front_facing_and_smooth() -> void:
	var t: SnowTuning = _tuning()
	var points: PackedVector3Array = SnowGeometry.dome_points(SnowGeometry.dome_params(5, t), 1.0, 3, t)
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	SnowGeometry.append_dome_triangles(points, t, Transform3D.IDENTITY, vertices, normals)
	assert_gt(vertices.size(), 0)
	assert_eq(vertices.size() % 3, 0)
	for tri: int in range(0, vertices.size(), 3):
		var cross: Vector3 = (vertices[tri + 1] - vertices[tri]).cross(vertices[tri + 2] - vertices[tri])
		assert_lte(cross.y, 0.0, "front face points up (engine winding)")
		for k: int in range(3):
			assert_gt(normals[tri + k].y, 0.0, "smooth normal points out of the snow")
	for v: Vector3 in vertices:
		assert_true(points.has(v), "every drawn vertex is a collider point")
	# A frame maps both identically.
	var frame: Transform3D = SnowGeometry.block_patch_transform(Vector3(0.0, 0.5, 0.0), 0, 1.0)
	var moved: PackedVector3Array = PackedVector3Array()
	var moved_normals: PackedVector3Array = PackedVector3Array()
	SnowGeometry.append_dome_triangles(points, t, frame, moved, moved_normals)
	assert_true(moved[0].is_equal_approx(frame * vertices[0]))


func test_exposed_cells_and_up_axis() -> void:
	var t: SnowTuning = _tuning()
	# A 2-high column plus one cell beside the bottom (an L on its side).
	var centers: PackedVector3Array = PackedVector3Array([
		Vector3(0.0, 0.5, 0.0), Vector3(0.0, 1.5, 0.0), Vector3(1.0, 0.5, 0.0),
	])
	var cells: PackedVector3Array = SnowGeometry.canonical_cells(centers, 1.0)
	var up: PackedInt32Array = SnowGeometry.exposed_cells(cells, SnowGeometry.AXIS_UP, 1.0, t.max_patches_per_block)
	var up_centers: Array[Vector3] = []
	for index: int in up:
		up_centers.append(cells[index])
	assert_eq(up.size(), 2, "column top and the side cell's top")
	assert_true(up_centers.has(Vector3(0.0, 1.5, 0.0)))
	assert_true(up_centers.has(Vector3(1.0, 0.5, 0.0)))
	assert_false(up_centers.has(Vector3(0.0, 0.5, 0.0)), "covered by its own block")
	assert_eq(SnowGeometry.exposed_cells(cells, SnowGeometry.AXIS_UP, 1.0, 1).size(), 1, "per-block cap")
	var min_dot: float = cos(deg_to_rad(t.max_up_tilt_deg))
	assert_eq(SnowGeometry.best_up_axis(Vector3.UP, min_dot), SnowGeometry.AXIS_UP)
	assert_eq(SnowGeometry.best_up_axis(Vector3(1.0, 0.0, 0.0), min_dot), 0, "on its side: +X is up")
	var tilted: Vector3 = Basis(Vector3(0.0, 0.0, 1.0), deg_to_rad(40.0)) * Vector3.UP
	assert_eq(SnowGeometry.best_up_axis(tilted, min_dot), -1, "tipped too far: no snow face")
	var frame: Transform3D = SnowGeometry.block_patch_transform(Vector3(0.0, 0.5, 0.0), 0, 1.0)
	assert_true(frame.basis.y.is_equal_approx(Vector3(1.0, 0.0, 0.0)))
	assert_true(frame.origin.is_equal_approx(Vector3(0.5, 0.5, 0.0)))
	assert_almost_eq(frame.basis.determinant(), 1.0, EPS, "right-handed")


func test_melt_cap_steps_down_to_zero_within_the_melt_time() -> void:
	var t: SnowTuning = _tuning()
	var total: float = t.melt_time_s()
	assert_gt(total, 0.0, "the shipped snow melts over a real duration")
	assert_eq(t.melt_cap_after(0.0), t.depth_levels, "nothing melts at the first instant")
	assert_eq(t.melt_cap_after(total), 0, "all gone when the melt clock ends")
	assert_eq(t.melt_cap_after(total * 2.0), 0)
	var previous: int = t.depth_levels
	var steps: int = 200
	for i: int in range(steps + 1):
		var cap: int = t.melt_cap_after(total * float(i) / float(steps))
		assert_lte(cap, previous, "monotone")
		previous = cap
	assert_gt(t.melt_cap_after(total * 0.99), 0, "the last level goes only at the end")
	assert_eq(t.melt_cap_after(total * 0.51), t.depth_levels / 2, "levels go evenly across the melt")


func test_melt_time_never_outlasts_the_ramp_out() -> void:
	var t: SnowTuning = _tuning()
	t.ramp_out_s = 10.0
	t.melt_duration_s = 25.0
	assert_eq(t.melt_time_s(), 10.0, "the event end clears what is left, so the melt must be done by then")
	t.melt_duration_s = 4.0
	assert_eq(t.melt_time_s(), 4.0)
	t.melt_duration_s = -3.0
	assert_eq(t.melt_time_s(), 0.0, "a negative duration means an instant melt")
	assert_eq(t.melt_cap_after(0.0), 0)


func test_shipped_melt_fits_the_ramp_out_and_flakes_stop_before_it_ends() -> void:
	var t: SnowTuning = load("res://config/weather/snow.tres") as SnowTuning
	assert_lte(t.melt_duration_s, t.ramp_out_s, "melt_duration_s fits the ramp-out as shipped")
	assert_gt(t.melt_duration_s, 0.0)
	assert_gt(t.cover_ease_s, 0.0, "the disc cover eases instead of stepping")
	assert_gt(t.flake_stop_intensity, 0.0, "flakes stop before the intensity reaches zero")
	assert_eq(t.flake_density(1.0, 1.0, true), 1.0)
	assert_eq(t.flake_density(t.flake_stop_intensity, 1.0, true), 0.0, "snowfall is over while melting continues")
	assert_eq(t.flake_density(0.0, 1.0, true), 0.0)
	assert_almost_eq(t.flake_density(0.5, 1.0, false), 0.5, EPS, "building up: density follows the intensity")
	assert_eq(t.flake_density(1.0, 0.0, false), 1.0, "a zero peak cannot divide by zero")


## Bontago-mp0.97 (playtest: snow particles too subtle): the visibility
## numbers were raised from the 22y.6 values and must stay above them.
func test_shipped_flakes_are_more_visible_than_the_original() -> void:
	var t: SnowTuning = load("res://config/weather/snow.tres") as SnowTuning
	assert_gt(t.flake_amount, 1600, "denser than the original 1600")
	assert_gt(t.flake_amount_low, 450, "Low is denser than the original 450 too")
	assert_gt(t.flake_size_m, 0.1, "larger than the original 0.1 m")
	assert_eq(t.flake_color.a, 1.0, "fully opaque flakes")
	assert_gt(t.flake_min_angle, 0.0, "far flakes keep a minimum on-screen size")
	assert_lt(t.flake_min_angle, t.flake_max_angle)
	assert_ne(t.flake_edge_color, t.flake_color, "an outline separates the flake from the sky")
	assert_lt(t.flake_amount_low, t.flake_amount)


func test_wire_round_trip_and_refusals() -> void:
	var t: SnowTuning = _tuning()
	var b: PackedInt32Array = PackedInt32Array()
	SnowGeometry.append_block_record(b, 5, 2, PackedInt32Array([0, 3]), PackedInt32Array([1, 4]))
	SnowGeometry.append_block_record(b, 9, 0, PackedInt32Array([1]), PackedInt32Array([2]))
	var d: PackedInt32Array = PackedInt32Array([10, 1, 44, 3])
	var good: Dictionary = SnowGeometry.make_state(77, 2, b, d)
	var data: Dictionary = SnowGeometry.sanitize_state(good, t, 100)
	assert_false(data.is_empty())
	assert_eq(int(data["seed"]), 77)
	assert_eq(int(data["cover"]), 2)
	assert_eq((data["blocks"] as Dictionary).size(), 2)
	assert_eq(((data["blocks"] as Dictionary)[5] as Array)[2], PackedInt32Array([1, 4]))
	assert_eq((data["disc"] as Dictionary)[44], 3)
	var empty: Dictionary = SnowGeometry.make_state(1, 0, PackedInt32Array(), PackedInt32Array())
	assert_false(SnowGeometry.sanitize_state(empty, t, 100).is_empty(), "empty is valid (clears)")

	var bad: Array[Variant] = []
	bad.append("nope")
	var extra: Dictionary = good.duplicate()
	extra["x"] = 1
	bad.append(extra)
	var version: Dictionary = good.duplicate()
	version["v"] = SnowGeometry.WIRE_VERSION + 1
	bad.append(version)
	var deep_cover: Dictionary = good.duplicate()
	deep_cover["c"] = t.depth_levels + 1
	bad.append(deep_cover)
	var untyped: Dictionary = good.duplicate()
	untyped["b"] = [5, 2, 1, 0, 1]
	bad.append(untyped)
	var too_deep: PackedInt32Array = PackedInt32Array()
	SnowGeometry.append_block_record(too_deep, 5, 2, PackedInt32Array([0]), PackedInt32Array([t.depth_levels + 1]))
	bad.append(SnowGeometry.make_state(1, 0, too_deep, PackedInt32Array()))
	var bad_axis: PackedInt32Array = PackedInt32Array([5, 6, 1, 0, 1])
	bad.append(SnowGeometry.make_state(1, 0, bad_axis, PackedInt32Array()))
	var dup: PackedInt32Array = PackedInt32Array([5, 2, 1, 0, 1, 5, 2, 1, 1, 1])
	bad.append(SnowGeometry.make_state(1, 0, dup, PackedInt32Array()))
	var truncated: PackedInt32Array = PackedInt32Array([5, 2, 2, 0, 1])
	bad.append(SnowGeometry.make_state(1, 0, truncated, PackedInt32Array()))
	var over: PackedInt32Array = PackedInt32Array([5, 2, t.max_patches_per_block + 1])
	for k: int in range(t.max_patches_per_block + 1):
		over.append_array(PackedInt32Array([k, 1]))
	bad.append(SnowGeometry.make_state(1, 0, over, PackedInt32Array()))
	bad.append(SnowGeometry.make_state(1, 0, PackedInt32Array(), PackedInt32Array([3])))
	bad.append(SnowGeometry.make_state(1, 0, PackedInt32Array(), PackedInt32Array([101, 1])))
	bad.append(SnowGeometry.make_state(1, 0, PackedInt32Array(), PackedInt32Array([3, 0])))
	bad.append(SnowGeometry.make_state(1, 0, PackedInt32Array([0, 2, 1, 0, 1]), PackedInt32Array()))
	for index: int in range(bad.size()):
		assert_true(SnowGeometry.sanitize_state(bad[index], t, 100).is_empty(), "malformed #%d refused" % index)
