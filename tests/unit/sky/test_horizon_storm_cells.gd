extends GutTest
## distant horizon storm cells (game/weather/HorizonStormCells.gd).

const SEED_A: int = 4242
const SEED_SWEEP: int = 40
const FLASH_STEP_S: float = 0.5
const FLASH_STEPS: int = 40
const FADE_STEP_S: float = 0.1
const FADE_STEPS: int = 30

var _config: HorizonStormConfig = null
var _previous_context: MatchContext = null
var _context: FakeMatchContext = null


func before_each() -> void:
	# Shipped default is off; these tests exercise the restored cells.
	_config = (load("res://config/weather/horizon_storm.tres") as HorizonStormConfig).duplicate() as HorizonStormConfig
	_config.enabled = true
	_previous_context = MatchContext.installed()
	_context = FakeMatchContext.new()
	MatchContext.install(_context)


func after_each() -> void:
	MatchContext.install(_previous_context)


func _make(seed_value: int) -> HorizonStormCells:
	_context.has_weather_value = true
	_context.weather_seed_value = seed_value
	var cells: HorizonStormCells = HorizonStormCells.new()
	cells.config = _config
	add_child_autofree(cells)
	return cells


func test_layout_is_deterministic_per_seed() -> void:
	assert_eq(HorizonStormCells.layout(SEED_A, _config), HorizonStormCells.layout(SEED_A, _config))
	var differs: bool = false
	for s: int in range(SEED_SWEEP):
		if HorizonStormCells.layout(s, _config) != HorizonStormCells.layout(s + 1, _config):
			differs = true
	assert_true(differs, "different seeds must give different layouts")


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
	assert_almost_eq(float(cells.get_child(0).get_node("CloudMass").transparency), 0.0, 0.001)
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
		for cell: Node3D in cells.get_children():
			cell._process(FLASH_STEP_S)
			if (cell.get("_bolt") as MeshInstance3D).visible:
				fired = true
	assert_true(fired, "a bolt flashes within %s s" % (FLASH_STEPS * FLASH_STEP_S))

