extends GutTest
## tools/shot_targets.gd: argument / shot-list parsing, validation, naming and contact-sheet layout.

const OUT: String = "--out=/tmp/shots"


func _parse(extra: Array[String], reader: Callable = Callable()) -> Dictionary:
	var args: PackedStringArray = PackedStringArray([OUT])
	args.append_array(PackedStringArray(extra))
	return ShotTargets.parse_args(args, reader)


func test_out_is_required() -> void:
	var result: Dictionary = ShotTargets.parse_args(PackedStringArray(["--target=main_menu"]))
	assert_string_contains(String(result["error"]), "--out")


func test_single_shot_from_flags() -> void:
	var result: Dictionary = _parse(["--target=lobby", "--kind=hosted", "--seats=8", "--style=board", "--sheet"])
	assert_eq(result["error"], "")
	assert_true(result["sheet"])
	var shots: Array = result["shots"]
	assert_eq(shots.size(), 1)
	var shot: Dictionary = shots[0]
	assert_eq(shot["target"], ShotTargets.TARGET_LOBBY)
	assert_eq(shot["seats"], 8)
	assert_eq(shot["kind"], ShotTargets.LOBBY_HOSTED)
	assert_eq(shot["style"], 3)
	assert_eq(shot["name"], "lobby_hosted_8seats_board")


func test_lobby_shot_names_a_roster_tile_style_and_the_teams_toggle() -> void:
	var shot: Dictionary = ShotTargets.normalize_shot({"target": "lobby", "style": "tiles_cap", "teams": true})
	assert_eq(shot["error"], "")
	assert_eq(shot["style"], LobbySeatVariants.Style.TILES_CAP)
	assert_true(shot["teams"])
	assert_eq(ShotTargets.STYLES.size(), LobbySeatVariants.NAMES.size(), "every row style can be captured")


func test_shots_json_overrides_flag_defaults() -> void:
	var json: String = '[{"target":"match","watch":true,"bots":4,"mode":"ctf"},{"target":"sandbox","overlays":["f4"]},{"target":"main_menu"}]'
	var result: Dictionary = _parse(["--shots=" + json, "--frames=10", "--hud=0"])
	assert_eq(result["error"], "")
	var shots: Array = result["shots"]
	assert_eq(shots.size(), 3)
	assert_eq(shots[0]["target"], ShotTargets.TARGET_MATCH)
	assert_true(shots[0]["watch"])
	assert_eq(shots[0]["bots"], 4)
	assert_eq(shots[0]["frames"], 10, "flags are the defaults for every json shot")
	assert_eq(shots[0]["hud"], 0)
	assert_eq(shots[1]["overlays"], PackedStringArray(["f4"]))


func test_bad_json_and_empty_list_fail() -> void:
	assert_ne(_parse(["--shots=[{"])["error"], "")
	assert_ne(_parse(["--shots=[]"])["error"], "")
	assert_ne(_parse(["--shots=[1]"])["error"], "")


func test_validation_rejects_bad_values() -> void:
	assert_ne(ShotTargets.normalize_shot({})["error"], "", "target is required")
	assert_ne(ShotTargets.normalize_shot({"target": "nowhere"})["error"], "")
	assert_ne(ShotTargets.normalize_shot({"target": "lobby", "bogus": 1})["error"], "", "unknown key")
	assert_ne(ShotTargets.normalize_shot({"target": "lobby", "style": "fancy"})["error"], "")
	assert_ne(ShotTargets.normalize_shot({"target": "sandbox", "overlays": ["f7"]})["error"], "")
	assert_ne(ShotTargets.normalize_shot({"target": "sandbox", "cam": "1,2"})["error"], "")
	assert_ne(ShotTargets.normalize_shot({"target": "scene"})["error"], "", "scene needs path")
	assert_ne(ShotTargets.normalize_shot({"target": "match", "follow": 1})["error"], "", "follow needs watch")
	assert_ne(ShotTargets.normalize_shot({"target": "match", "mode": "chess"})["error"], "")
	assert_ne(ShotTargets.normalize_shot({"target": "sandbox", "preset": "nope"})["error"], "")
	assert_ne(ShotTargets.normalize_shot({"target": "sandbox", "frames": -1})["error"], "")


func test_duplicate_names_get_suffixes_and_files_are_sanitised() -> void:
	var result: Dictionary = _parse(["--shots=[{\"target\":\"main_menu\"},{\"target\":\"main_menu\"},{\"target\":\"sandbox\",\"name\":\"a b/c\"}]"])
	assert_eq(result["error"], "")
	var shots: Array = result["shots"]
	assert_eq(shots[0]["name"], "main_menu")
	assert_eq(shots[1]["name"], "main_menu_2")
	assert_eq(shots[2]["name"], "a_b_c")
	assert_eq(ShotTargets.file_name(shots[0], Vector2i(1920, 1080)), "main_menu_1920x1080.png")


func test_sheet_layout_respects_the_size_cap() -> void:
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3440, 1440)]:
		for count: int in [1, 3, 7, 40]:
			var layout: Dictionary = ShotTargets.sheet_layout(count, size)
			var columns: int = layout["columns"]
			var width: int = columns * int(layout["cell_w"]) + ShotTargets.SHEET_GAP * (columns + 1)
			assert_lte(width, ShotTargets.SHEET_MAX_W)
			var rows: int = ceili(float(mini(count, int(layout["per_page"]))) / float(columns))
			var height: int = rows * int(layout["row_h"]) + ShotTargets.SHEET_GAP * (rows + 1)
			assert_lte(height, ShotTargets.SHEET_MAX_H, "one page of %d x %s shots" % [count, size])
			assert_gte(int(layout["pages"]) * int(layout["per_page"]), count)
	assert_gt(int(ShotTargets.sheet_layout(40, Vector2i(1920, 1080))["pages"]), 1, "many shots paginate")


func test_menu_targets_dispatch_to_the_menu_setup() -> void:
	# A bare Node has no _main_menu, so each menu-family target fails fast with the menu error
	# (proves the dispatch reached the right branch without booting Main).
	var host: Node = autofree(Node.new())
	add_child(host)
	var vp: SubViewport = autofree(SubViewport.new())
	host.add_child(vp)
	var main: Node = autofree(Node.new())
	host.add_child(main)
	for target: String in [ShotTargets.TARGET_MAIN_MENU, ShotTargets.TARGET_MENU, ShotTargets.TARGET_OPTIONS]:
		var shot: Dictionary = ShotTargets.normalize_shot({"target": target})
		var error: String = await ShotTargets.setup(host, vp, main, shot)
		assert_string_contains(error, "no main menu", target)


func test_finish_setup_reports_unusable_setup_keys() -> void:
	var host: Node = autofree(Node.new())
	add_child(host)
	var vp: SubViewport = autofree(SubViewport.new())
	host.add_child(vp)
	var main: Node = autofree(Node.new())
	host.add_child(main)
	var follow: Dictionary = ShotTargets.normalize_shot({"target": "match", "watch": true, "follow": 0, "frames": 0})
	assert_string_contains(await ShotTargets.finish_setup(host, vp, main, follow), "spectator")
	var sky: Dictionary = ShotTargets.normalize_shot({"target": "sandbox", "sky": "night", "frames": 0})
	assert_string_contains(await ShotTargets.finish_setup(host, vp, main, sky), "no skybox")
	var plain: Dictionary = ShotTargets.normalize_shot({"target": "sandbox", "frames": 2})
	assert_eq(await ShotTargets.finish_setup(host, vp, main, plain), "")


func test_sky_ids_are_cycle_or_a_locked_id_and_rng_seed_is_a_non_negative_int() -> void:
	for sky_id: String in ["cycle", "sunset", "dawn", "night"]:
		assert_eq(ShotTargets.normalize_shot({"target": "match", "sky": sky_id})["error"], "", sky_id)
	assert_string_contains(str(ShotTargets.normalize_shot({"target": "match", "sky": "nope"})["error"]), "unknown sky")
	var seeded: Dictionary = ShotTargets.normalize_shot({"target": "match", "rng_seed": "42"})
	assert_eq(seeded["error"], "")
	assert_eq(seeded["rng_seed"], 42)
	assert_ne(str(ShotTargets.normalize_shot({"target": "match", "rng_seed": "-3"})["error"]), "")
	assert_eq(ShotTargets.normalize_shot({"target": "match"})["rng_seed"], ShotTargets.NO_VALUE)


func test_backdrop_seed_pins_the_global_rng_and_rejects_a_negative_seed() -> void:
	var args: PackedStringArray = PackedStringArray(["--out=x", "--shots=[{\"target\":\"match\",\"backdrop_seed\":7}]"])
	assert_eq(str(ShotTargets.parse_args(args)["error"]), "")
	var first: float = randf()
	ShotTargets.parse_args(args)
	assert_eq(randf(), first)
	assert_ne(str(ShotTargets.normalize_shot({"target": "match", "backdrop_seed": "-1"})["error"]), "")


func test_loading_shot_parses_its_fade_fraction() -> void:
	var shot: Dictionary = ShotTargets.normalize_shot({"target": "loading"})
	assert_eq(shot["error"], "")
	assert_eq(shot["fade"], 1.0, "fully shown by default")
	assert_eq(ShotTargets.normalize_shot({"target": "loading", "fade": "0.5"})["fade"], 0.5)
	assert_eq(ShotTargets.normalize_shot({"target": "loading", "fade": 0})["error"], "", "0 is a valid fraction")
	assert_ne(ShotTargets.normalize_shot({"target": "loading", "fade": 1.5})["error"], "")
	assert_ne(ShotTargets.normalize_shot({"target": "loading", "fade": "x"})["error"], "")


func test_loading_target_without_a_loading_screen_fails_fast() -> void:
	var host: Node = autofree(Node.new())
	add_child(host)
	var vp: SubViewport = autofree(SubViewport.new())
	host.add_child(vp)
	var main: Node = autofree(Node.new())
	host.add_child(main)
	var error: String = await ShotTargets.setup(host, vp, main, ShotTargets.normalize_shot({"target": "loading"}))
	assert_string_contains(error, "no loading screen")


func test_show_loading_raises_the_screen_and_freezes_the_backdrop_fade() -> void:
	var screen: LoadingScreen = autofree(load("res://ui/menus/LoadingScreen.tscn").instantiate() as LoadingScreen)
	add_child(screen)
	var slots: Array[PlayerSlot] = [PlayerSlot.new(0, 0, "A", Color.WHITE)]
	var error: String = await ShotTargets.show_loading(screen, screen, MatchConfig.new(), slots, 0.4)
	assert_eq(error, "")
	assert_true(screen.visible, "the loading screen is up")
	var backdrop: LoadingBackdrop = screen.find_child("Backdrop", true, false) as LoadingBackdrop
	assert_not_null(backdrop.texture)
	assert_almost_eq(backdrop.modulate.a, 0.4, 0.001, "mid-fade is held, not left to the tween")
	error = await ShotTargets.show_loading(screen, screen, MatchConfig.new(), slots, 1.0)
	assert_almost_eq(backdrop.modulate.a, 1.0, 0.001, "fully shown")
	screen.cancel()
