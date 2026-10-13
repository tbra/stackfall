extends GutTest
## Bontago-mp0.150.4: the F4 panel's Arena tab (ui/TuningPanel.gd) switches the
## wired Field's ArenaSideStyle and rebuilds the arena mesh live.

var _panel: TuningPanel = null
var _field: Field = null


func before_each() -> void:
	_field = Field.new()
	# A private copy so editing the style never leaks into the shared .tres.
	_field.arena_side_style = (load("res://config/arena_side_style.tres") as ArenaSideStyle).duplicate() as ArenaSideStyle
	add_child_autofree(_field)
	_panel = autofree(load("res://ui/TuningPanel.tscn").instantiate()) as TuningPanel
	add_child_autofree(_panel)
	_panel.set_field(_field)
	_panel.rebuild()


func _signature() -> Array:
	var overlay: TerritoryOverlay = _field.overlay()
	var mesh: ArrayMesh = overlay.mesh as ArrayMesh
	var vertices: int = 0
	var extent: float = 0.0
	for surface: int in mesh.get_surface_count():
		var surface_vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		vertices += surface_vertices.size()
		for vertex: Vector3 in surface_vertices:
			extent += vertex.y
	return [mesh.get_surface_count(), vertices, snappedf(extent, 0.01)]


func test_arena_tab_exists_with_a_style_dropdown_of_all_named_styles() -> void:
	assert_not_null(_panel._tab_container.get_node_or_null("Arena"), "Arena tab")
	var option: OptionButton = _panel.control_for(_field.arena_side_style, "style") as OptionButton
	assert_not_null(option, "style control is an OptionButton")
	assert_eq(option.item_count, ArenaSideStyle.Style.size())
	assert_eq(option.get_item_text(ArenaSideStyle.Style.LAYERED_PLATES), "Layered plates")
	assert_gt(_panel.row_count_for(_field.arena_side_style), 4, "tunables listed too")


func test_no_arena_tab_without_a_field() -> void:
	var bare: TuningPanel = autofree(load("res://ui/TuningPanel.tscn").instantiate()) as TuningPanel
	add_child_autofree(bare)
	bare.rebuild()
	assert_null(bare._tab_container.get_node_or_null("Arena"))


func test_picking_each_style_rebuilds_the_arena_mesh_and_keeps_territory_configured() -> void:
	var option: OptionButton = _panel.control_for(_field.arena_side_style, "style") as OptionButton
	var overlay: TerritoryOverlay = _field.overlay()
	var material: ShaderMaterial = overlay.material()
	var seen: Array = [_signature()]
	for which: int in [ArenaSideStyle.Style.LAYERED_PLATES, ArenaSideStyle.Style.ROCKY_ISLAND, ArenaSideStyle.Style.MACHINED_DISC, ArenaSideStyle.Style.MACHINED_STYLISED, ArenaSideStyle.Style.MACHINED_DETAILED, ArenaSideStyle.Style.MACHINED_HEAVY, ArenaSideStyle.Style.MONOLITH, ArenaSideStyle.Style.TAPERED_STRATA, ArenaSideStyle.Style.PLATED_DOME]:
		option.select(option.get_item_index(which))
		option.item_selected.emit(option.get_item_index(which))
		assert_eq(_field.arena_side_style.style, which)
		var sig: Array = _signature()
		assert_false(seen.has(sig), "style %d changes the mesh (surfaces, vertices) %s" % [which, str(sig)])
		seen.append(sig)
		assert_same(overlay.material(), material, "territory material kept")
		assert_eq(overlay.get_surface_override_material(0), material, "territory shader on surface 0")
	option.select(option.get_item_index(ArenaSideStyle.Style.CURRENT))
	option.item_selected.emit(option.get_item_index(ArenaSideStyle.Style.CURRENT))
	assert_eq(_signature(), seen[0], "back to CURRENT restores the original mesh")


func test_tunable_edit_rebuilds_and_save_copy_include_arena() -> void:
	var before: Array = _signature()
	_field.arena_side_style.style = ArenaSideStyle.Style.ROCKY_ISLAND
	_panel.apply_arena_style_live()
	var rocky: Array = _signature()
	assert_ne(rocky, before)
	_field.arena_side_style.rock_strata_count = 2
	_panel.apply_arena_style_live()
	assert_ne(_signature(), rocky, "a tunable change rebuilds too")
	assert_true(_panel.build_copy_text().contains("# ArenaSideStyle"))
