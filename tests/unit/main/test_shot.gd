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
	assert_ne(ShotTargets.normalize_shot({"target": "sandbox", "overlays": ["f9"]})["error"], "")
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
	var sky: Dictionary = ShotTargets.normalize_shot({"target": "sandbox", "sky": "nope", "frames": 0})
	assert_string_contains(await ShotTargets.finish_setup(host, vp, main, sky), "unknown sky")
	var plain: Dictionary = ShotTargets.normalize_shot({"target": "sandbox", "frames": 2})
	assert_eq(await ShotTargets.finish_setup(host, vp, main, plain), "")
