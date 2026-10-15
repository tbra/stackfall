extends GutTest
## Glue fusion WP0: the interface stubs exist, type-check and carry defaults.


func test_fused_body_extends_block() -> void:
	var script: GDScript = load("res://game/blocks/FusedBody.gd") as GDScript
	assert_not_null(script, "FusedBody.gd loads")
	var body: FusedBody = FusedBody.new()
	autofree(body)
	assert_true(body is Block, "FusedBody extends Block")
	assert_true(body is BlockBody, "FusedBody reaches BlockBody through Block")
	assert_true(body.members.is_empty(), "members starts empty")
	assert_true(body.anchored_members.is_empty(), "anchored_members starts empty")
	assert_false(body.is_disc_anchored(), "stub is not disc-anchored")
	assert_eq(body.owner_slot_at(Vector3.ZERO), -1, "stub owner slot is -1")
	assert_eq(body.members_in_sphere(Vector3.ZERO, 1.0).size(), 0, "stub finds no members")


func test_plain_block_virtual_defaults() -> void:
	var block: Block = Block.new()
	autofree(block)
	assert_null(block.fused_carrier(), "a plain block has no fused carrier")
	assert_false(block.is_fused_member(), "a plain block is not a fused member")
	assert_eq(block.net_sleeping(), block.sleeping, "net_sleeping mirrors RigidBody3D.sleeping")


func test_events_has_fusion_signals() -> void:
	assert_true(Events.has_signal("blocks_fused"), "Events.blocks_fused exists")
	assert_true(Events.has_signal("fused_member_released"), "Events.fused_member_released exists")


func test_glue_drop_tuning_max_fused_cubes_default() -> void:
	var tuning: GlueDropTuning = GlueDropTuning.new()
	assert_eq(tuning.max_fused_cubes, 0, "max_fused_cubes defaults to 0 (unlimited)")
	var shipped: GlueDropTuning = load("res://config/gifts/glue_drop_tuning.tres") as GlueDropTuning
	assert_eq(shipped.max_fused_cubes, 0, "shipped glue_drop_tuning.tres sets max_fused_cubes = 0")
