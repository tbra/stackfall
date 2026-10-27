extends GutTest
## Impact sample selection by strength tier x surface, variant rotation, and that every shipped
## variation wav loads headless. Impacts enter the way the game sends them (Events.block_impacted_at,
## emitted by Block on the host and re-emitted from the replicated batch on a client) and are read
## back from the cue player that sounded, against the shipped files.

const OPEN_AIR: Vector3 = Vector3(0.0, 5000.0, 0.0)
const BLOCK_SPOT: Vector3 = Vector3(0.0, 6000.0, 0.0)
const BLOCK_RADIUS_M: float = 0.4
const ROTATION_ROUNDS: int = 24

var _config: AudioConfig
var _shipped_root: String
var _blocks: Array[Block] = []


func before_each() -> void:
	_config = Sfx.config
	_shipped_root = ProjectSettings.globalize_path("res://assets/audio/sfx")
	SfxChildren.stop_all()


func after_each() -> void:
	SfxChildren.stop_all()
	_blocks.clear()


func _speed_for_t(t: float) -> float:
	return _config.impact_speed_min + t * (_config.impact_speed_loud - _config.impact_speed_min)


## The stream on the match-cue player that is playing now, null when silent.
func _played_stream() -> AudioStream:
	var seen: int = 0
	for child: Node in Sfx.get_children():
		var player: AudioStreamPlayer = child as AudioStreamPlayer
		if player == null:
			continue
		if player.playing:
			return player.stream
		seen += 1
		if seen >= _config.max_simultaneous:
			break
	return null


func _shipped(file: String) -> AudioStreamWAV:
	return AudioStreamWAV.load_from_file(_shipped_root.path_join(file))


func _same_sound(a: AudioStream, b: AudioStream) -> bool:
	var first: AudioStreamWAV = a as AudioStreamWAV
	var second: AudioStreamWAV = b as AudioStreamWAV
	return first != null and second != null and first.data == second.data


## Two frozen blocks stacked at BLOCK_SPOT: the impact there lands on block-on-block.
func _stack_two_blocks() -> void:
	for _i: int in range(_config.impact_block_surface_min_blocks):
		var body: Block = Block.new()
		var shape: CollisionShape3D = CollisionShape3D.new()
		var sphere: SphereShape3D = SphereShape3D.new()
		sphere.radius = BLOCK_RADIUS_M
		shape.shape = sphere
		body.add_child(shape)
		body.freeze = true
		body.position = BLOCK_SPOT
		add_child_autofree(body)
		_blocks.append(body)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _impact(speed: float, at: Vector3) -> AudioStream:
	SfxChildren.stop_all()
	Events.block_impacted_at.emit(speed, at)
	return _played_stream()


func _expect_set(speed: float, surface: StringName, tier: StringName, at: Vector3) -> void:
	var stream: AudioStream = _impact(speed, at)
	var matched: bool = false
	for file: String in _config.impact_variation_for(surface, tier):
		var expected: AudioStream = _shipped(file)
		assert_not_null(expected, "fixture: %s ships" % file)
		if _same_sound(expected, stream):
			matched = true
	assert_true(matched, "%s/%s at %.2f m/s must use the %s_%s set" % [surface, tier, speed, surface, tier])


func test_tier_thresholds() -> void:
	assert_eq(_config.impact_tier(_speed_for_t(0.0)), AudioConfig.TIER_SOFT)
	assert_eq(_config.impact_tier(_speed_for_t(0.32)), AudioConfig.TIER_SOFT)
	assert_eq(_config.impact_tier(_speed_for_t(0.35)), AudioConfig.TIER_MEDIUM)
	assert_eq(_config.impact_tier(_speed_for_t(0.66)), AudioConfig.TIER_MEDIUM)
	assert_eq(_config.impact_tier(_speed_for_t(0.70)), AudioConfig.TIER_HARD)
	assert_eq(_config.impact_tier(_speed_for_t(5.0)), AudioConfig.TIER_HARD)


func test_every_variation_file_loads() -> void:
	for surface: StringName in [AudioConfig.SURFACE_BLOCK, AudioConfig.SURFACE_DISC]:
		for tier: StringName in [AudioConfig.TIER_SOFT, AudioConfig.TIER_MEDIUM, AudioConfig.TIER_HARD]:
			var files: Array[String] = _config.impact_variation_for(surface, tier)
			assert_false(files.is_empty(), "%s/%s has variations" % [surface, tier])
			for file: String in files:
				assert_not_null(_shipped(file), "%s should load" % file)


func test_strength_picks_the_matching_sample_set_on_the_disc() -> void:
	_expect_set(_speed_for_t(0.1), AudioConfig.SURFACE_DISC, AudioConfig.TIER_SOFT, OPEN_AIR)
	_expect_set(_speed_for_t(0.5), AudioConfig.SURFACE_DISC, AudioConfig.TIER_MEDIUM, OPEN_AIR)
	_expect_set(_speed_for_t(0.9), AudioConfig.SURFACE_DISC, AudioConfig.TIER_HARD, OPEN_AIR)


func test_an_impact_on_stacked_blocks_picks_the_block_sample_set() -> void:
	await _stack_two_blocks()
	_expect_set(_speed_for_t(0.1), AudioConfig.SURFACE_BLOCK, AudioConfig.TIER_SOFT, BLOCK_SPOT)
	_expect_set(_speed_for_t(0.5), AudioConfig.SURFACE_BLOCK, AudioConfig.TIER_MEDIUM, BLOCK_SPOT)
	_expect_set(_speed_for_t(0.9), AudioConfig.SURFACE_BLOCK, AudioConfig.TIER_HARD, BLOCK_SPOT)


func test_variants_rotate_without_immediate_repeat() -> void:
	var speed: float = _speed_for_t(0.5)
	var seen: Dictionary = {}
	var previous: AudioStream = null
	for _i: int in range(ROTATION_ROUNDS):
		var stream: AudioStream = _impact(speed, OPEN_AIR)
		assert_not_null(stream)
		if previous != null:
			assert_false(_same_sound(stream, previous), "same variant twice in a row")
		previous = stream
		seen[hash((stream as AudioStreamWAV).data)] = true
	assert_eq(seen.size(), 2, "both variants should be used")


func test_below_min_is_silent_and_above_min_plays() -> void:
	assert_null(_impact(_config.impact_speed_min * 0.5, OPEN_AIR), "a soft touch makes no sound")
	assert_not_null(_impact(_config.impact_speed_loud, OPEN_AIR), "a hard hit in open air plays the disc set")
