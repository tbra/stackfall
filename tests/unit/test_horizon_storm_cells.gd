extends GutTest
## Bontago-mp0.126: distant horizon storm cells (vfx/weather/HorizonStormCells.gd).

const SEED_A: int = 4242
const SEED_B: int = 777
const SEED_SWEEP: int = 40
const FLASH_STEP_S: float = 0.5
const FLASH_STEPS: int = 40
const FADE_STEP_S: float = 0.1
const FADE_STEPS: int = 30

var _config: HorizonStormConfig = null


func before_each() -> void:
	_config = load("res://config/horizon_storm.tres") as HorizonStormConfig


func _make(seed_value: int) -> HorizonStormCells:
	var cells: HorizonStormCells = HorizonStormCells.new()
	cells.configure(seed_value)
	add_child_autofree(cells)
	return cells


func test_layout_is_deterministic_per_seed() -> void:
	assert_eq(HorizonStormCells.layout(SEED_A, _config), HorizonStormCells.layout(SEED_A, _config))
	var differs: bool = false
	for s: int in range(SEED_SWEEP):
		if HorizonStormCells.layout(s, _config) != HorizonStormCells.layout(s + 1, _config):
			differs = true
	assert_true(differs, "different seeds must give different layouts")


func test_layout_count_variants_and_bearings_valid() -> void:
	for s: int in range(SEED_SWEEP):
		var entries: Array[Dictionary] = HorizonStormCells.layout(s, _config)
		assert_between(entries.size(), _config.cell_count_min, _config.cell_count_max)
		var styles: Array[int] = []
		for entry: Dictionary in entries:
			assert_false(styles.has(int(entry["style"])), "silhouettes must differ within a storm")
			styles.append(int(entry["style"]))
			assert_gt(float(entry["distance_m"]), _config.distance_m - _config.distance_jitter_m - 0.01)
		if entries.size() == 2:
			var gap: float = absf(angle_difference(deg_to_rad(float(entries[0]["bearing_deg"])), deg_to_rad(float(entries[1]["bearing_deg"]))))
			assert_gte(rad_to_deg(gap), _config.min_bearing_separation_deg - 0.01)


func test_cells_are_built_with_matching_variants_and_far_away() -> void:
	var cells: HorizonStormCells = _make(SEED_B)
	var entries: Array[Dictionary] = HorizonStormCells.layout(SEED_B, _config)
	assert_eq(cells.cells().size(), entries.size())
	for i: int in range(entries.size()):
		assert_eq(int(cells.cells()[i].get("silhouette_style")), int(entries[i]["style"]))
		assert_gt(cells.cells()[i].position.length(), _config.distance_m - _config.distance_jitter_m - 1.0)


func test_no_collision_and_no_shadows() -> void:
	var cells: HorizonStormCells = _make(SEED_A)
	for cell: Node3D in cells.cells():
		for node: Node in cell.find_children("*", "", true, false):
			assert_false(node is CollisionObject3D or node is CollisionShape3D, "no collision: %s" % node.name)
			var geometry: GeometryInstance3D = node as GeometryInstance3D
			if geometry != null:
				assert_eq(geometry.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			var light: Light3D = node as Light3D
			if light != null:
				assert_false(light.shadow_enabled)


func test_hidden_without_storm_and_fades_with_intensity() -> void:
	var cells: HorizonStormCells = _make(SEED_A)
	cells._process(FADE_STEP_S)
	assert_false(cells.visible, "no storm intensity, no cells")
	cells.set_intensity(1.0)
	cells._process(FADE_STEP_S)
	assert_true(cells.visible)
	var first: float = cells.opacity
	assert_between(first, 0.0, 1.0)
	for _i: int in range(FADE_STEPS):
		cells._process(FADE_STEP_S)
	assert_almost_eq(cells.opacity, 1.0, 0.001)
	assert_almost_eq(float(cells.cells()[0].get_node("CloudMass").transparency), 0.0, 0.001)
	cells.set_intensity(0.0)
	cells._process(FADE_STEP_S)
	assert_lt(cells.opacity, 1.0, "fades out, not a snap")
	for _i: int in range(FADE_STEPS):
		cells._process(FADE_STEP_S)
	assert_false(cells.visible)


func test_lightning_timer_fires() -> void:
	var cells: HorizonStormCells = _make(SEED_A)
	var fired: bool = false
	for _i: int in range(FLASH_STEPS):
		for cell: Node3D in cells.cells():
			cell._process(FLASH_STEP_S)
			if (cell.get("_bolt") as MeshInstance3D).visible:
				fired = true
	assert_true(fired, "a bolt flashes within %s s" % (FLASH_STEPS * FLASH_STEP_S))


func test_storm_presentation_owns_cells_and_feeds_intensity() -> void:
	var storm: StormPresentation = StormPresentation.new()
	add_child_autofree(storm)
	var horizon: HorizonStormCells = storm.get_node("HorizonStormCells") as HorizonStormCells
	assert_not_null(horizon)
	storm.set_intensity(0.7)
	assert_almost_eq(horizon.intensity, 0.7, 0.0001)
