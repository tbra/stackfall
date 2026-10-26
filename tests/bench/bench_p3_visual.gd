extends Node
## P3 visual floor scene (plan 6.2): a scripted hosted Main + Match put into one of two states for a
## tools/shot capture, so a refactor of the ghost / held-gift drawing can be diffed pixel for pixel.
##   --visual-case=stack  three cubes stacked, the ghost hovering over them (footprint, prism, decal)
##   --visual-case=gift   a bomb gift fed to the local player and held (held-gift presentation)
## The scene runs one scripted step per physics tick and is idle after END_TICK, so a capture taken
## after `frames` >= END_TICK shows a settled state. Capture and diff commands: fixtures/p3_visual_floor.json.
## Input goes into this scene's own viewport (a shot capture renders in a SubViewport, where the
## Input singleton's events never arrive).

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")
const CUBE_PATH: String = "res://config/blocks/cube.tres"
const MAP_PATH: String = "res://config/match/maps/round.tres"
const DEFAULTS_PATH: String = "res://config/match/match_defaults.tres"
const CASE_ARG: String = "--visual-case="
const SEED_ARG: String = "--rng-seed="
const CASE_STACK: String = "stack"
const CASE_GIFT: String = "gift"
const DEFAULT_SEED: int = 20261025
const HOST_SLOT: int = 0
const PLAYER_COUNT: int = 2
const FIELD_RADIUS_M: float = 20.0
const MAX_LOAD_TICKS: int = 3000
const GIFT_ID: StringName = &"bomb"

## Scripted timeline, in ticks since PLAYING.
const STACK_PLACE_TICKS: Array[int] = [30, 150, 270]
const GIFT_PLACE_TICK: int = 30
const GIFT_QUEUE_TICK: int = 150
const GIFT_FEED_TICK: int = 210
const HOVER_TICK: int = 330
const HOVER_NOTCHES: int = 6
const HOVER_SPACING: int = 3
const END_TICK: int = 420

var _case: String = CASE_STACK
var _tick: int = -1
var _load_ticks: int = 0
var _main: Node = null


func _ready() -> void:
	var rng_seed: int = DEFAULT_SEED
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(CASE_ARG):
			_case = arg.substr(CASE_ARG.length())
		elif arg.begins_with(SEED_ARG):
			rng_seed = arg.substr(SEED_ARG.length()).to_int()
	if _case != CASE_STACK and _case != CASE_GIFT:
		push_error("bench_p3_visual: --visual-case must be stack or gift, got '%s'" % _case)
		get_tree().quit(1)
		return
	if not UserPaths.is_isolated_run():
		push_error("bench_p3_visual: not an isolated run, Settings would read the user's settings.cfg")
		get_tree().quit(1)
		return
	Input.use_accumulated_input = false
	seed(rng_seed)
	_build_world(rng_seed)


## The hosted Main of bench_p3_parity: no bot, feed timer off, scripted gifts, one cube shape.
func _build_world(rng_seed: int) -> void:
	assert(Net.host_game(AgentProbe.free_udp_port(), "Hostie") == OK)
	_main = MAIN_SCENE.instantiate()
	var map: MapDef = (load(MAP_PATH) as MapDef).duplicate(true)
	map.field_radius = FIELD_RADIUS_M
	(_main.get_node("Field") as Field).map_def = map
	add_child(_main)
	var config: MatchConfig = (load(DEFAULTS_PATH) as MatchConfig).duplicate(true)
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(map)
	config.rng_seed = rng_seed
	config.ai_count = 0
	config.player_count = PLAYER_COUNT
	config.sandbox = false
	config.scripted_gifts = true
	config.countdown_seconds = 0.0
	var pinned: BlockFeedConfig = Match._block_feed_config.duplicate() as BlockFeedConfig
	pinned.shapes = [load(CUBE_PATH) as BlockShape]
	pinned.weight_overrides = PackedFloat32Array()
	Match._block_feed_config = pinned
	Match.register_world(_main.get_node("Field"), _main.get_node("BlockRegistry"), _main.get_node("BlocksContainer"))
	Match.start_match(config)
	Match.set_feed_timer_enabled(false)


func _physics_process(_delta: float) -> void:
	if _tick < 0 and Match.state() != Match.State.PLAYING:
		_load_ticks += 1
		if _load_ticks > MAX_LOAD_TICKS:
			push_error("bench_p3_visual: world never reached PLAYING")
			get_tree().quit(1)
			set_physics_process(false)
		return
	_tick += 1
	_step()
	if _tick >= END_TICK:
		set_physics_process(false)
		print("BENCH_P3_VISUAL case=%s ready tick=%d" % [_case, _tick])


func _step() -> void:
	if _case == CASE_STACK:
		if _tick in STACK_PLACE_TICKS:
			_click_place()
		if _tick >= HOVER_TICK and _tick < HOVER_TICK + HOVER_NOTCHES * HOVER_SPACING and (_tick - HOVER_TICK) % HOVER_SPACING == 0:
			_wheel(MOUSE_BUTTON_WHEEL_UP)
		return
	if _tick == GIFT_PLACE_TICK or _tick == GIFT_FEED_TICK:
		_click_place()
	if _tick == GIFT_QUEUE_TICK:
		Match.debug_queue_special(HOST_SLOT, GIFT_ID)


func _click_place() -> void:
	_button(MOUSE_BUTTON_LEFT, true)
	_button(MOUSE_BUTTON_LEFT, false)


func _wheel(index: MouseButton) -> void:
	_button(index, true)
	_button(index, false)


func _button(index: MouseButton, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	get_viewport().push_input(event)
