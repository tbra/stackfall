extends GutTest
## Bontago-xtq.44: ExitRelease drops the process-wide static caches that otherwise pin
## textures, meshes and materials until the engine reports them as leaked at exit.


func after_each() -> void:
	ExitRelease.release_all()


func test_release_all_drops_populated_caches() -> void:
	var shapes: Array[BlockShape] = BlockShape.load_all_shapes()
	assert_false(shapes.is_empty(), "fixture needs a shipped shape")
	var physics: PhysicsTuning = load("res://config/physics_tuning.tres") as PhysicsTuning
	BlockMeshBuilder.build_mesh(shapes[0], physics.cube_size, physics.cube_margin)
	var specials: Array[SpecialDef] = SpecialDef.load_all_specials()
	assert_false(specials.is_empty(), "fixture needs a shipped special")
	SpecialDef.find_by_id(specials[0].id)
	GiftIconTable.shared()
	UiArtTable.shared()
	assert_false(BlockMeshBuilder._mesh_cache.is_empty())
	assert_false(SpecialDef._by_id_cache.is_empty())
	assert_not_null(GiftIconTable._shared)
	ExitRelease.release_all()
	assert_true(BlockMeshBuilder._mesh_cache.is_empty())
	assert_true(SpecialDef._by_id_cache.is_empty())
	assert_null(GiftIconTable._shared)
	assert_null(UiArtTable._shared)
	assert_null(GiftModelTable._shared)
	assert_null(HudFeedbackIconTable._shared)
	assert_null(InputGlyphTable._shared)
	assert_null(DiscSizeTuning._shared)
	assert_null(UiScaleTuning._shared)
	assert_true(BlockFactory._materials_by_color.is_empty())
	assert_true(BlockFactory._outline_materials_by_color.is_empty())


func test_caches_rebuild_lazily_after_release() -> void:
	ExitRelease.release_all()
	assert_not_null(SpecialDef.find_by_id(SpecialDef.load_all_specials()[0].id))
	assert_not_null(GiftIconTable.shared())
