extends GutTest
## Field builds its disk from MapDef/PhysicsTuning and frees anything that
## reaches the kill plane (spec 2.1).
##
## M2 replaced the single cylinder collision with the cell grid spec 3.3 asks
## for; the grid itself is covered by test_field_cells.gd, so what is left here
## is the disk's size, its material and the kill plane.

## DECISION (Bontago-mv0.3): none of this file's assertions depend on the
## map's actual scale (mesh radius tracks whatever map_def says; cell_count()
## just has to be positive, under one trimesh owner; friction and the
## kill plane are size-independent) -- only a couple of tests already used
## round_small.tres (30 m, ~2800 cells); the ones that instead built a plain
## Field.new() (round_medium.tres, ~6300 cells) or explicitly loaded
## round_medium.tres paid its ~11 s collision build (measured) for nothing.
## A shared tiny duplicate replaces all of them.
var _tiny_map: MapDef


func before_each() -> void:
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 6.0


func test_disk_mesh_radius_matches_map_def() -> void:
	var field: Field = autofree(Field.new())
	field.map_def = _tiny_map
	field.tuning = load("res://config/physics_tuning.tres")
	add_child_autofree(field)

	var overlay: TerritoryOverlay = field.overlay()
	assert_not_null(overlay, "Field should build the disk's visible surface.")
	var cylinder: CylinderMesh = overlay.mesh as CylinderMesh
	assert_not_null(cylinder, "The disk is drawn as a cylinder.")
	assert_almost_eq(cylinder.top_radius, field.map_def.field_radius, 0.001)
	assert_almost_eq(cylinder.height, field.map_def.disk_height, 0.001)


func test_disk_collision_covers_the_disk() -> void:
	var field: Field = autofree(Field.new())
	field.map_def = _tiny_map
	add_child_autofree(field)

	# Bontago-ruw: one trimesh on one shape owner, a quad per in-disk cell;
	# this small a disk at cell_size 1 is still a bit over a hundred cells.
	assert_gt(field.cell_count(), 0, "The disk collides as a grid of cells.")
	assert_eq(field.get_shape_owners().size(), 1, "The disk is one shape owner.")
	var owner_id: int = field.get_shape_owners()[0]
	assert_eq(field.shape_owner_get_shape_count(owner_id), 1)
	var mesh: ConcavePolygonShape3D = (
		field.shape_owner_get_shape(owner_id, 0) as ConcavePolygonShape3D
	)
	assert_not_null(mesh, "The disk collides as one trimesh.")
	assert_gte(
		mesh.get_faces().size(),
		field.cell_count() * Field.VERTS_PER_QUAD,
		"At least two triangles per in-disk cell."
	)


func test_disk_friction_matches_tuning() -> void:
	var field: Field = autofree(Field.new())
	field.map_def = _tiny_map
	add_child_autofree(field)
	assert_almost_eq(
		field.physics_material_override.friction,
		field.tuning.disk_friction,
		0.0001
	)


func test_kill_plane_frees_the_body_and_emits_event() -> void:
	var field: Field = autofree(Field.new())
	field.map_def = _tiny_map
	add_child_autofree(field)
	watch_signals(Events)

	var body: RigidBody3D = autofree(RigidBody3D.new())
	add_child_autofree(body)
	field._on_kill_plane_body_entered(body)

	assert_signal_emitted(Events, "block_removed")
	assert_true(body.is_queued_for_deletion(), "The body should be freed once it hits the kill plane.")


# --- clear_match_state() (Beads Bontago-mv0.1.9) -----------------------------
#
# Field is a persistent node -- Main never frees or rebuilds it between
# matches -- so nothing else resets its flags, its overlay's raster reference
# or its open holes when a match ends. These pin clear_match_state() in
# isolation; game/Main.gd calling it from _end_match_world() is covered by
# tests/unit/test_match_lifecycle.gd's real-Main fixture.

func test_clear_match_state_frees_flags_clears_the_overlay_source_and_closes_holes() -> void:
	var field: Field = autofree(Field.new())
	field.map_def = _tiny_map
	add_child_autofree(field)

	field.place_flags(2, PackedColorArray([Color.RED, Color.BLUE]), 1)
	var raster: TerritoryRaster = TerritoryRaster.new(field.grid(), load("res://config/territory_tuning.tres"))
	raster.reset()
	field.set_overlay_source(raster, PackedColorArray([Color.RED, Color.BLUE]))
	var opened: PackedInt32Array = PackedInt32Array([field.grid().in_disk_cells()[0]])
	field.set_hole_cells(opened, PackedInt32Array())
	field._drain_toggles()
	assert_true(field.is_hole_cell(opened[0]), "fixture: the hole is actually applied before clearing")
	assert_not_null(field.overlay()._raster, "fixture: the overlay actually holds the raster before clearing")

	field.clear_match_state()

	assert_true(field.home_flags().is_empty(), "home flags are freed")
	assert_true(field.goal_flags().is_empty(), "goal flags are freed")
	assert_null(field.overlay()._raster, "the overlay keeps no reference to the old raster")
	assert_false(field.is_hole_cell(opened[0]), "the hole this match opened is closed")
	assert_eq(field.pending_toggle_count(), 0, "no queued toggle survives clearing")


func test_clear_match_state_discards_a_toggle_still_in_the_backlog() -> void:
	# A hole enqueued but not yet drained (the backlog is rate-limited per
	# physics frame, spec 3.3) must not survive either -- draining it after
	# the field's match state was otherwise cleared would reopen a hole
	# nothing owns any more.
	var field: Field = autofree(Field.new())
	field.map_def = _tiny_map
	add_child_autofree(field)
	var cell: int = field.grid().in_disk_cells()[0]
	field.set_hole_cells(PackedInt32Array([cell]), PackedInt32Array())
	assert_eq(field.pending_toggle_count(), 1, "fixture: the toggle is queued, not yet drained")

	field.clear_match_state()

	assert_eq(field.pending_toggle_count(), 0)
	field._drain_toggles()
	assert_false(field.is_hole_cell(cell), "the discarded toggle never applies later")
