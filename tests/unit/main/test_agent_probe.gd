extends GutTest
## game/debug/AgentProbe.gd: probe detection and mouse-capture gating.

func test_detects_flag_in_user_args() -> void:
	assert_true(AgentProbe.detect(PackedStringArray(), PackedStringArray(["--agent-probe"])))


func test_game_scene_and_plain_launch_not_probe() -> void:
	assert_false(AgentProbe.detect(PackedStringArray(["res://game/main/Main.tscn"]), PackedStringArray()))
	assert_false(AgentProbe.detect(PackedStringArray(["--path", "."]), PackedStringArray(["--host"])))


func test_parse_render_size() -> void:
	assert_eq(AgentProbe.parse_render_size(PackedStringArray(["--render-size=1920x1080"])), Vector2i(1920, 1080))
	assert_eq(AgentProbe.parse_render_size(PackedStringArray(["--render-size=bad"])), Vector2i.ZERO)
	assert_eq(AgentProbe.parse_render_size(PackedStringArray()), Vector2i.ZERO)


func test_probe_mode_never_captures_or_confines_the_mouse() -> void:
	assert_eq(AgentProbe.mouse_mode_for(Input.MOUSE_MODE_CAPTURED, true), Input.MOUSE_MODE_VISIBLE)
	assert_eq(AgentProbe.mouse_mode_for(Input.MOUSE_MODE_CONFINED, true), Input.MOUSE_MODE_VISIBLE)
	assert_eq(AgentProbe.mouse_mode_for(Input.MOUSE_MODE_VISIBLE, true), Input.MOUSE_MODE_VISIBLE)


func test_capture_allowed_outside_probe_mode() -> void:
	assert_eq(AgentProbe.mouse_mode_for(Input.MOUSE_MODE_CAPTURED, false), Input.MOUSE_MODE_CAPTURED)


func test_free_udp_port_is_in_range_and_bindable() -> void:
	var port: int = AgentProbe.free_udp_port()
	assert_between(port, AgentProbe.FREE_PORT_MIN, AgentProbe.FREE_PORT_MIN + AgentProbe.FREE_PORT_SPAN - 1)
	var probe: PacketPeerUDP = PacketPeerUDP.new()
	assert_eq(probe.bind(port), OK, "the returned port should still be free")
	probe.close()


## Contention can push any single draw to the whole-range fallback, so the slice
## preference is only guaranteed in aggregate: some draw lands in this process's slice.
func test_free_udp_port_prefers_this_processs_slice() -> void:
	var slice_index: int = hash(OS.get_process_id()) % (AgentProbe.FREE_PORT_SPAN / AgentProbe.FREE_PORT_SLICE)
	var in_slice: int = 0
	for i: int in 8:
		var port: int = AgentProbe.free_udp_port()
		assert_ne(port, 0, "a free port is found")
		if (port - AgentProbe.FREE_PORT_MIN) / AgentProbe.FREE_PORT_SLICE == slice_index:
			in_slice += 1
	assert_gt(in_slice, 0, "at least one draw comes from this process's slice")


class FakeRig:
	extends Node
	var _yaw: float = 0.0
	var _pitch: float = 0.0
	var _distance: float = 0.0
	var _target: Vector3 = Vector3.ZERO


class FakeMain:
	extends Node
	var _camera_rig: FakeRig = FakeRig.new()


func test_camera_pose_hook_sets_the_rig() -> void:
	var main: FakeMain = autofree(FakeMain.new())
	assert_true(AgentProbe.apply_camera_pose(main, PackedFloat32Array([90.0, -45.0, 12.0, 1.0, 2.0, 3.0])))
	assert_almost_eq(main._camera_rig._yaw, deg_to_rad(90.0), 0.0001)
	assert_almost_eq(main._camera_rig._pitch, deg_to_rad(-45.0), 0.0001)
	assert_eq(main._camera_rig._distance, 12.0)
	assert_eq(main._camera_rig._target, Vector3(1.0, 2.0, 3.0))
	assert_false(AgentProbe.apply_camera_pose(main, PackedFloat32Array([1.0, 2.0])), "wrong part count")
	assert_false(AgentProbe.apply_sky(main, "", -1.0), "no skybox on the fake main")
	main._camera_rig.free()


func test_press_action_hook_delivers_press_and_release() -> void:
	var vp: SubViewport = autofree(SubViewport.new())
	add_child(vp)
	assert_true(AgentProbe.press_action(vp, &"hud_toggle"))
	assert_false(AgentProbe.press_action(vp, &"no_such_action"))
