extends GutTest
## game/AgentProbe.gd (Bontago-fca.1): probe detection and mouse-capture gating.

func after_each() -> void:
	AgentProbe.set_forced_for_test(-1)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_detects_flag_in_user_args() -> void:
	assert_true(AgentProbe.detect(PackedStringArray(), PackedStringArray(["--agent-probe"])))


func test_detects_tools_scene_path() -> void:
	assert_true(AgentProbe.detect(PackedStringArray(["--path", ".", "res://tools/bench_perf_attrib.tscn"]), PackedStringArray()))


func test_game_scene_and_plain_launch_not_probe() -> void:
	assert_false(AgentProbe.detect(PackedStringArray(["res://game/Main.tscn"]), PackedStringArray()))
	assert_false(AgentProbe.detect(PackedStringArray(["--path", "."]), PackedStringArray(["--host"])))


func test_parse_render_size() -> void:
	assert_eq(AgentProbe.parse_render_size(PackedStringArray(["--render-size=1920x1080"])), Vector2i(1920, 1080))
	assert_eq(AgentProbe.parse_render_size(PackedStringArray(["--render-size=bad"])), Vector2i.ZERO)
	assert_eq(AgentProbe.parse_render_size(PackedStringArray()), Vector2i.ZERO)


func test_capture_is_noop_in_probe_mode() -> void:
	AgentProbe.set_forced_for_test(1)
	AgentProbe.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	assert_ne(Input.mouse_mode, Input.MOUSE_MODE_CAPTURED)
	var pc: PlayerController = autofree(PlayerController.new())
	pc.enable_mouse_capture()
	assert_ne(Input.mouse_mode, Input.MOUSE_MODE_CAPTURED)


func test_capture_allowed_outside_probe_mode() -> void:
	AgentProbe.set_forced_for_test(0)
	AgentProbe.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Headless mouse mode may not stick; only assert when the platform honoured it.
	assert_true(captured or DisplayServer.get_name() == "headless")
