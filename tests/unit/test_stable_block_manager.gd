extends GutTest
## game/StableBlockManager.gd (spec 3.5 "Stable-block optimization" [NEW],
## docs/M8_PLAN.md P5): a block asleep past PhysicsTuning.stable_freeze_delay_s
## gets frozen static; waking releases it; below the threshold it's left
## alone. Drives the manager deterministically through its own _tick(delta)
## seam (see that function's own doc comment) instead of waiting real seconds
## or real physics frames -- Net.is_host()/_physics_process() are never
## exercised here, only _tick()/_scan() themselves, the same "test the pure
## seam directly" approach test_physics_tuning.gd already uses for
## Block._damp_rebound().

var _tuning: PhysicsTuning = load("res://config/physics_tuning.tres")

## Bontago-mv0.3's own DECISION (tests/unit/test_block_registry.gd): a
## shrunk-radius duplicate of round_medium.tres, not the shared resource
## itself, so this fixture doesn't pay round_medium's own ~11 s field-build
## cost per test.
var _map_def: MapDef


func before_each() -> void:
	_map_def = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_map_def.field_radius = 20.0


func _make_field() -> Field:
	var field: Field = autofree(Field.new())
	field.map_def = _map_def
	add_child_autofree(field)
	return field


func _make_registry(field: Field) -> BlockRegistry:
	var registry: BlockRegistry = autofree(BlockRegistry.new())
	add_child_autofree(registry)
	registry.configure(field, _map_def)
	return registry


func _make_manager(registry: BlockRegistry) -> StableBlockManager:
	var manager: StableBlockManager = autofree(StableBlockManager.new())
	manager.tuning = _tuning
	add_child_autofree(manager)
	manager.setup(registry)
	return manager


func _place(field: Field, slot: int) -> Block:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = BlockFactory.build(shape, _tuning, slot)
	field.add_child(block)
	Events.block_placed.emit(block, shape.id)
	return block


func test_block_asleep_past_the_delay_gets_frozen_static() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var manager: StableBlockManager = _make_manager(registry)

	var block: Block = _place(field, 0)
	block.sleeping = true

	# One _tick() call whose delta alone crosses both the scan interval and
	# the freeze delay -- see StableBlockManager._tick()'s own doc comment for
	# why a single call this large is equivalent to many smaller real ticks.
	manager._tick(_tuning.stable_freeze_delay_s + 1.0)

	assert_true(block.is_freeze_static(), "asleep past the delay is frozen static")
	assert_true(block.freeze)
	assert_eq(block.freeze_mode, RigidBody3D.FREEZE_MODE_STATIC)


func test_block_asleep_below_the_delay_is_left_untouched() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var manager: StableBlockManager = _make_manager(registry)

	var block: Block = _place(field, 0)
	block.sleeping = true

	manager._tick(_tuning.stable_freeze_delay_s - 1.0)

	assert_false(block.is_freeze_static(), "asleep, but not yet past the delay")
	assert_false(block.freeze)


func test_waking_a_frozen_block_releases_it() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var manager: StableBlockManager = _make_manager(registry)

	var block: Block = _place(field, 0)
	block.sleeping = true
	manager._tick(_tuning.stable_freeze_delay_s + 1.0)
	assert_true(block.is_freeze_static(), "sanity check: frozen first")

	block.sleeping = false
	manager._tick(_tuning.stable_freeze_scan_interval_s)

	assert_false(block.is_freeze_static(), "waking releases this manager's own reason")
	assert_false(block.freeze)
	assert_eq(
		block.freeze_mode,
		RigidBody3D.FREEZE_MODE_STATIC,
		"freeze_mode is left at STATIC after release -- it's inert once freeze is false, nothing resets it"
	)


func test_reaching_the_delay_across_several_ticks_still_freezes() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var manager: StableBlockManager = _make_manager(registry)

	var block: Block = _place(field, 0)
	block.sleeping = true

	# Several scans below the interval accumulate without ever running a scan
	# pass; once accumulated time crosses the interval, a scan runs and its
	# elapsed span is credited to the sleeping block. Repeating this until the
	# cumulative asleep time crosses stable_freeze_delay_s must still freeze
	# it, the same as one big _tick() call.
	var half_interval: float = _tuning.stable_freeze_scan_interval_s * 0.5
	var elapsed: float = 0.0
	while elapsed < _tuning.stable_freeze_delay_s + _tuning.stable_freeze_scan_interval_s:
		manager._tick(half_interval)
		elapsed += half_interval

	assert_true(block.is_freeze_static(), "accumulated asleep time across many small ticks still freezes")


func test_a_second_block_that_wakes_before_the_scan_interval_elapses_is_never_credited() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var manager: StableBlockManager = _make_manager(registry)

	var block: Block = _place(field, 0)
	block.sleeping = true

	# Below the scan interval: no scan pass has run yet, so nothing is
	# credited or released either way.
	manager._tick(_tuning.stable_freeze_scan_interval_s * 0.5)
	assert_false(block.is_freeze_static())

	block.sleeping = false
	manager._tick(_tuning.stable_freeze_scan_interval_s)
	assert_false(block.is_freeze_static(), "never asleep long enough to be frozen in the first place")
