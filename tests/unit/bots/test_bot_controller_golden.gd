extends GutTest
## Parity floor of the bot controller boundary (P11): eight scripted scenes x three seeds, 24 pieces. For each
## piece the controller thinks once (budgets forced huge, stepped by hand: no physics, no wall clock) and the test
## digests what it read (the BotWorldView of that think) and what it sent (request_place / request_throw /
## note_aim arguments, exact via var_to_str), plus the frame it sent on. A refactor of BotController must keep
## every pinned MD5 below. Jolt is not deterministic across runs, so this pins the controller boundary, not a match.
##
## Pinned from main 4a83eb07 (before P11-Ibotswap). Capture: run the script and read the `GOLDEN <key> <md5>` lines:
##   powershell -NoProfile -File tools/run_gut.ps1 test_bot_controller_golden
## The floor (digests differing across separate Godot processes: two at the default pacing and one with
## --fixed-fps 30) is 0. A changed MD5 is a regression until shown otherwise; never loosen to a tolerance.

const SEEDS: Array[int] = [11, 2222, 33333]
const SCENE_NAMES: Array[String] = [
	"classic_tower", "storm_gusts", "gifts", "incoming_specials", "sudden_death", "sky_stack", "held_special", "tilted",
]
## Scene 7 holds a bomb for the first two seeds and a black hole for the third.
const HELD_SPECIALS: Array[StringName] = [&"bomb", &"bomb", &"black_hole"]

const PINNED: Dictionary = {
	"classic_tower.11": "ed337b4d69c755d3eba27ea63e28db56",
	"classic_tower.2222": "abf219df81a133e170f069fd3f551216",
	"classic_tower.33333": "3e8cd1fb782d763897664e8fea48b769",
	"storm_gusts.11": "65f514260dc230006538740ac03de385",
	"storm_gusts.2222": "4d8221f5c0e0dd3b87d95669123ad8b3",
	"storm_gusts.33333": "87423dcba7163f77b22ecdb417a6ada8",
	"gifts.11": "1d2e8c09d7f7d1feb8b57fa57a55da40",
	"gifts.2222": "dc771cf374a8732179e5725706410d43",
	"gifts.33333": "71bbb720c39ee47aacc6b9faac203c9e",
	"incoming_specials.11": "b3601118f53d8886f510973b664ecf68",
	"incoming_specials.2222": "43891f7c476e9575181b53f0eea24ab5",
	"incoming_specials.33333": "7514515bd1105790d90f8ed759731c51",
	"sudden_death.11": "ed337b4d69c755d3eba27ea63e28db56",
	"sudden_death.2222": "abf219df81a133e170f069fd3f551216",
	"sudden_death.33333": "3e8cd1fb782d763897664e8fea48b769",
	"sky_stack.11": "13e7a073f6504e99a8c08b1a875ec7c8",
	"sky_stack.2222": "8bf7414d933345d07c5e7656dc5c46e1",
	"sky_stack.33333": "7dcd20ce3c78b03eb1d325fd7178ec5e",
	"held_special.11": "95f548d60861237fa42c15d6055d8beb",
	"held_special.2222": "3a510896388cad4ba802c02e11017ac5",
	"held_special.33333": "0408bd3c36e5b58f5210bdae182fdef4",
	"tilted.11": "0695c2e05e05467fd5b5bf55bf3d54e4",
	"tilted.2222": "4a9175f18a92d6554287f1813028754b",
	"tilted.33333": "f3b9013496dbb50b9216423e772320b5",
}


func _stack_at(at: Vector2, cubes: int, slot: int = 0) -> Dictionary:
	return {"at": at, "cubes": cubes, "slot": slot}


func _gust() -> Dictionary:
	return {"x": 2.0, "y": 1.0, "z": -3.0, "a": 0.7, "r": 4.0, "d": 6.0, "s": 2.0, "age": 1.5}


func _special(id: StringName, slot: int, at: Vector3, velocity: Vector3 = Vector3.ZERO, frozen: bool = false) -> Dictionary:
	return {"id": id, "slot": slot, "at": at, "velocity": velocity, "freeze": frozen}


## The scene data of scene `index` (see SCENE_NAMES).
func _scene(index: int) -> Dictionary:
	var own_tower: Array = [_stack_at(Vector2(-4.0, 1.0), 3)]
	match index:
		0:
			return {"stacks": own_tower}
		1:
			return {
				"stacks": own_tower,
				"weather": {"id": WeatherIds.STORM, "intensity": 0.8, "seed": 4242, "event": 3, "gusts": [_gust()]},
			}
		2:
			var gifts: Array[Dictionary] = [
				{"id": 1, "phase": MatchGifts.LANDED, "position": Vector2(3.0, 4.0)},
				{
					"id": 2, "phase": MatchGifts.FALLING, "position": Vector2(-5.0, 2.0),
					"origin": Vector3(-5.0, 10.0, 2.0), "landing": Vector3(-5.0, 0.0, 2.0), "elapsed": 100.0,
				},
				{
					"id": 3, "phase": MatchGifts.FALLING, "position": Vector2(6.0, -6.0),
					"origin": Vector3(6.0, 500.0, -6.0), "landing": Vector3(6.0, 0.0, -6.0), "elapsed": 0.0,
				},
			]
			return {"stacks": own_tower, "gifts_enabled": true, "gift_states": gifts}
		3:
			return {
				"stacks": own_tower,
				"specials": [
					_special(&"bomb", 1, Vector3(2.0, 6.0, 1.0), Vector3(3.0, -4.0, 0.0)),
					_special(&"freeze", 1, Vector3(-1.0, 6.0, 2.0), Vector3(0.0, -5.0, 0.0)),
					_special(&"bomb", 2, Vector3(0.0, 6.0, -2.0), Vector3(1.0, -4.0, 1.0)),
					_special(&"bomb", 1, Vector3(4.0, 6.0, -3.0), Vector3(-2.0, -4.0, 0.0), true),
					_special(&"bomb", 1, Vector3(0.0, 0.5, 3.0)),
				],
			}
		4:
			return {"stacks": own_tower, "sudden_death": true}
		5:
			return {
				"stacks": [_stack_at(Vector2(-4.0, 1.0), 4), _stack_at(Vector2(-3.0, 4.0), 2), _stack_at(Vector2(4.0, 0.0), 3, 1)],
				"mode": MatchConfig.GameMode.REACH_THE_SKY,
				"tower": Vector2(-4.0, 1.0),
			}
		6:
			return {
				"stacks": [
					_stack_at(Vector2(-4.0, 1.0), 3), _stack_at(Vector2(7.0, 5.0), 2, 1), _stack_at(Vector2(9.0, 10.5), 2, 1),
					_stack_at(Vector2(11.0, 16.0), 2, 1),
				],
				"specials": [_special(&"bomb", 1, Vector3(1.0, 0.5, 2.0))],
			}
		_:
			return {"stacks": own_tower, "tilt": true}


## Everything the think read, as one exact text.
func _view_text(view: BotWorldView) -> String:
	var stack_text: Array = []
	if view.stack != null:
		stack_text = [view.stack.body_count(), view.stack.body_team, view.stack.body_mass, view.stack.cube_pos]
	var goal_text: Array = []
	if view.mode_goal != null:
		goal_text = [view.mode_goal.mode, view.mode_goal.has_tower, view.mode_goal.tower_origin]
	return var_to_str([
		view.slot_id, view.team_id, view.mode, view.field_radius, view.live_radius, view.own_home, view.has_home,
		view.team_homes, view.goals, view.goal_zone_radius, view.enemy_homes, view.enemy_home_teams,
		view.cx, view.cz, view.cr, view.cteam, view.held.id if view.held != null else &"",
		view.next_shape.id if view.next_shape != null else &"", goal_text, view.specials, view.gifts,
		view.incoming_points, view.incoming_radii, view.weather_id, view.weather_intensity,
		view.wind_tuning != null, view.wind_dir, view.breeze_tuning != null, view.gust_center, view.gust_radius,
		view.gust_heading, view.gust_power_values, stack_text, view.gravity_local, view.gifts_enabled,
		view.appetite.value,
	])


## The MD5 of one piece: the view of the think, every request it sent, the frame it sent on and the appetite report.
func _digest(scene_index: int, seed_index: int) -> String:
	var held: StringName = HELD_SPECIALS[seed_index] if scene_index == 6 else &""
	var rig: BotGoldenRig = BotGoldenRig.build(self, _scene(scene_index), SEEDS[seed_index], held)
	var sent: bool = rig.run()
	assert_true(sent, "fixture: scene %s seed %d sends a request" % [SCENE_NAMES[scene_index], SEEDS[seed_index]])
	var view: BotWorldView = BotGoldenRig.view_of(rig.controller)
	assert_not_null(view, "fixture: the think read a view")
	var text: String = "%s|%s|%d|%s" % [
		_view_text(view) if view != null else "", "|".join(rig.fake.requests), rig.frames, rig.controller.appetite_report(),
	]
	var md5: String = text.md5_text()
	rig.dispose()
	return md5


func _check_scene(scene_index: int) -> void:
	for seed_index: int in range(SEEDS.size()):
		var key: String = "%s.%d" % [SCENE_NAMES[scene_index], SEEDS[seed_index]]
		var md5: String = _digest(scene_index, seed_index)
		print("GOLDEN %s %s" % [key, md5])
		assert_eq(md5, PINNED.get(key, ""), "golden digest of %s" % key)


func test_classic_tower() -> void:
	_check_scene(0)


func test_storm_weather_and_breeze_gusts() -> void:
	_check_scene(1)


func test_landed_and_falling_gifts() -> void:
	_check_scene(2)


func test_incoming_and_armed_specials() -> void:
	_check_scene(3)


func test_sudden_death_live_radius() -> void:
	_check_scene(4)


func test_reach_the_sky_stack_probe() -> void:
	_check_scene(5)


func test_held_special_plan() -> void:
	_check_scene(6)


func test_tilted_field() -> void:
	_check_scene(7)


func test_the_same_piece_twice_in_one_process_digests_equal() -> void:
	assert_eq(_digest(3, 0), _digest(3, 0), "same scene, same seed, same digest")


func test_different_seeds_digest_differently() -> void:
	assert_ne(_digest(0, 0), _digest(0, 1), "the seed reaches the digest")
