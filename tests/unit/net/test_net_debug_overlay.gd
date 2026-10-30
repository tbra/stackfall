extends GutTest
## F3 network panel (ui/debug/NetDebugOverlay.gd): it shows what its NetStatsSource reports, toggles
## on F3 or Back + Y in every build, polls only while open, and drives the lag/loss simulator
## through the source. Asserts read label text and call counts, not layout.


## Counts read() calls so "hidden means no poll" is observable through the public seam.
class _CountingSource:
	extends FakeNetStatsSource
	var reads: int = 0

	func read() -> NetStats:
		reads += 1
		return super.read()


var _source: _CountingSource = null
var _overlay: NetDebugOverlay = null


func before_each() -> void:
	DebugMode.set_override_for_test(true)
	_source = _CountingSource.new()
	_overlay = null


func after_each() -> void:
	Input.action_release(&"camera_snap_home")
	DebugMode.clear_override_for_test()


## Builds the overlay with the source injected before it enters the tree.
func _make_overlay() -> NetDebugOverlay:
	var scene: PackedScene = load("res://ui/debug/NetDebugOverlay.tscn")
	var overlay: NetDebugOverlay = autofree(scene.instantiate())
	overlay.set(&"source", _source)
	add_child_autofree(overlay)
	_overlay = overlay
	return overlay


func _f3() -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.device = -1
	event.physical_keycode = KEY_F3
	event.pressed = true
	return event


func _pad(button: JoyButton) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	event.pressed = true
	return event


func _toggle() -> void:
	_overlay._unhandled_input(_f3())


func _open(stats: NetStats) -> NetDebugOverlay:
	_source.stats = stats
	var overlay: NetDebugOverlay = _overlay if _overlay != null else _make_overlay()
	if not overlay.visible:
		_toggle()
	return overlay


## Close and reopen so the panel takes a fresh reading.
func _reopen(stats: NetStats) -> void:
	_toggle()
	_source.stats = stats
	_toggle()


func _texts(node: Node) -> String:
	var parts: PackedStringArray = []
	if node is Label:
		parts.append((node as Label).text)
	for child: Node in node.get_children():
		parts.append(_texts(child))
	return "\n".join(parts)


func _text() -> String:
	return _texts(_overlay)


func _find_all(node: Node, type: String, out: Array[Node]) -> void:
	if node.is_class(type):
		out.append(node)
	for child: Node in node.get_children():
		_find_all(child, type, out)


func _sliders() -> Array[Node]:
	var out: Array[Node] = []
	_find_all(_overlay, "HSlider", out)
	return out


func _has_slider_value(expected: float) -> bool:
	for node: Node in _sliders():
		if absf((node as HSlider).value - expected) < 0.001:
			return true
	return false


func _preset_button() -> Button:
	var named: Button = _overlay.find_child("PresetButton", true, false) as Button
	if named != null:
		return named
	var buttons: Array[Node] = []
	_find_all(_overlay, "Button", buttons)
	for node: Node in buttons:
		if (node as Button).text.to_lower().contains("preset"):
			return node as Button
	return null


func _host_stats() -> NetStats:
	var stats: NetStats = NetStats.new()
	stats.role = NetStats.Role.HOST
	stats.local_slot = 0
	var alice: NetStats.PeerRow = NetStats.PeerRow.new()
	alice.peer_id = 101
	alice.slot_id = 2
	alice.name = "Alice"
	alice.rtt_ms = 87.0
	alice.rtt_jitter_ms = 13.0
	var bob: NetStats.PeerRow = NetStats.PeerRow.new()
	bob.peer_id = 102
	bob.slot_id = 4
	bob.name = "Bobby"
	bob.rtt_ms = 142.0
	bob.rtt_jitter_ms = 21.0
	stats.peers = [alice, bob]
	stats.snapshots_per_s = 29.0
	stats.snapshot_bytes_per_s = 4321.0
	stats.last_snapshot_bytes = 1234
	stats.last_snapshot_bodies = 57
	stats.last_snapshot_fragments = 3
	return stats


func _client_stats() -> NetStats:
	var stats: NetStats = NetStats.new()
	stats.role = NetStats.Role.CLIENT
	stats.local_slot = 3
	stats.local_rtt_ms = 64.0
	stats.interp_delay_ms = 83.0
	stats.arrival_jitter_ms = 17.0
	stats.loss_fraction = 0.25
	stats.dropped_unknown = 9137
	stats.snapshots_per_s = 29.0
	stats.snapshot_bytes_per_s = 4321.0
	stats.last_snapshot_bytes = 1234
	stats.last_snapshot_bodies = 57
	return stats


func _intent_row(slot: int, sent: int, accepted: int, refused: int, cursors: int) -> NetStats.IntentRow:
	var row: NetStats.IntentRow = NetStats.IntentRow.new()
	row.slot_id = slot
	row.sent = sent
	row.accepted = accepted
	row.refused = refused
	row.cursors_refused = cursors
	return row


# --- Toggling ------------------------------------------------------------------

func test_f3_toggles_visibility() -> void:
	var overlay: NetDebugOverlay = _make_overlay()
	assert_false(overlay.visible, "starts hidden")
	_toggle()
	assert_true(overlay.visible)
	_toggle()
	assert_false(overlay.visible)


func test_gamepad_y_alone_does_not_toggle() -> void:
	var overlay: NetDebugOverlay = _make_overlay()
	overlay._unhandled_input(_pad(JOY_BUTTON_Y))
	assert_false(overlay.visible, "Y alone is not the debug chord")


func test_gamepad_back_plus_y_toggles() -> void:
	var overlay: NetDebugOverlay = _make_overlay()
	Input.action_press(&"camera_snap_home")
	overlay._unhandled_input(_pad(JOY_BUTTON_Y))
	assert_true(overlay.visible, "Back held + Y opens the panel")


func test_f3_toggles_with_debug_off() -> void:
	DebugMode.set_override_for_test(false)
	var overlay: NetDebugOverlay = _make_overlay()
	_toggle()
	assert_true(overlay.visible, "F3 opens the panel with debug off")
	_toggle()
	assert_false(overlay.visible)
	Input.action_press(&"camera_snap_home")
	overlay._unhandled_input(_pad(JOY_BUTTON_Y))
	assert_true(overlay.visible, "Back + Y opens the panel with debug off")
	overlay._unhandled_input(_pad(JOY_BUTTON_Y))
	assert_false(overlay.visible)


# --- Polling -------------------------------------------------------------------

func test_hidden_panel_makes_no_read_and_opening_makes_one() -> void:
	_make_overlay()
	for i: int in range(6):
		await get_tree().process_frame
	assert_eq(_source.reads, 0, "a hidden panel never reads")
	_toggle()
	assert_eq(_source.reads, 1, "opening reads once at once")
	_toggle()
	var after_close: int = _source.reads
	for i: int in range(6):
		await get_tree().process_frame
	assert_eq(_source.reads, after_close, "closing stops the polling")


# --- Content -------------------------------------------------------------------

func test_offline_panel_says_offline() -> void:
	_open(NetStats.new())
	assert_string_contains(_text().to_lower(), "offline")


func test_host_shows_role_peers_and_their_rtt_and_jitter() -> void:
	_open(_host_stats())
	var text: String = _text()
	assert_string_contains(text.to_lower(), "host")
	assert_string_contains(text, "Alice")
	assert_string_contains(text, "Bobby")
	for fragment: String in ["87", "13", "142", "21"]:
		assert_string_contains(text, fragment)


func test_host_shows_snapshot_rate_and_sizes() -> void:
	_open(_host_stats())
	var text: String = _text()
	assert_string_contains(text, "29")
	assert_true(text.contains("4321") or text.contains("4.3") or text.contains("4.2"), "bytes per second")
	assert_string_contains(text, "1234")
	assert_string_contains(text, "57")


func test_client_shows_rtt_interp_delay_jitter_and_loss_as_percent() -> void:
	_open(_client_stats())
	var text: String = _text()
	assert_string_contains(text.to_lower(), "client")
	for fragment: String in ["64", "83", "17", "9137"]:
		assert_string_contains(text, fragment)
	assert_string_contains(text, "25", "0.25 reads as 25 percent")
	assert_false(text.contains("0.25"), "a fraction is shown as a percent, not raw")
	assert_false(text.contains("2500"), "not multiplied twice")


func test_client_shows_no_host_only_snapshot_figures() -> void:
	_open(_client_stats())
	var text: String = _text()
	assert_false(text.contains("1234"), "last snapshot bytes are host only")
	assert_false(text.contains("57"), "last snapshot bodies are host only")


func test_intents_show_for_a_slot_with_counters_and_not_without() -> void:
	var stats: NetStats = _host_stats()
	stats.intents = [_intent_row(2, 401, 397, 17, 29)]
	_open(stats)
	var text: String = _text()
	assert_string_contains(text, "397")
	assert_string_contains(text, "17")
	assert_string_contains(text, "29")
	var empty: NetStats = _host_stats()
	_reopen(empty)
	text = _text()
	assert_false(text.contains("397"), "no row for a slot with no counters")
	assert_false(text.contains("401"))


func test_client_intents_show_its_own_sent_count() -> void:
	var stats: NetStats = _client_stats()
	stats.intents = [_intent_row(3, 733, 0, 0, 0)]
	_open(stats)
	assert_string_contains(_text(), "733")


func test_reopening_takes_a_fresh_reading() -> void:
	_open(_host_stats())
	assert_string_contains(_text(), "Alice")
	var next: NetStats = _host_stats()
	next.peers[0].name = "Zelda"
	_reopen(next)
	assert_string_contains(_text(), "Zelda")
	assert_false(_text().contains("Alice"))


# --- Simulator -----------------------------------------------------------------

func test_sliders_start_from_the_live_simulation_without_writing_it_back() -> void:
	var stats: NetStats = _client_stats()
	stats.sim_lag_ms = 60.0
	stats.sim_loss = 0.04
	_open(stats)
	assert_true(_has_slider_value(60.0), "a slider starts at sim_lag_ms")
	assert_true(_has_slider_value(0.04), "a slider starts at sim_loss")
	assert_eq(_source.simulation_calls.size(), 0, "showing the values does not apply them")


func test_preset_button_applies_configured_lag_and_loss() -> void:
	var config: NetConfig = load("res://config/net/net_config.tres")
	_open(_client_stats())
	var button: Button = _preset_button()
	assert_not_null(button, "a preset button is reachable")
	button.pressed.emit()
	assert_eq(_source.simulation_calls.size(), 1)
	if _source.simulation_calls.is_empty():
		return
	assert_almost_eq(_source.simulation_calls[0].x, config.sim_preset_lag_ms, 0.01)
	assert_almost_eq(_source.simulation_calls[0].y, config.sim_preset_loss, 0.001)


func test_pad_chord_applies_the_preset_while_open() -> void:
	var config: NetConfig = load("res://config/net/net_config.tres")
	var overlay: NetDebugOverlay = _open(_client_stats())
	Input.action_press(&"camera_snap_home")
	overlay._unhandled_input(_pad(JOY_BUTTON_A))
	assert_eq(_source.simulation_calls.size(), 1)
	if _source.simulation_calls.is_empty():
		return
	assert_almost_eq(_source.simulation_calls[0].x, config.sim_preset_lag_ms, 0.01)
	assert_almost_eq(_source.simulation_calls[0].y, config.sim_preset_loss, 0.001)


func test_accept_without_back_does_not_apply_the_preset() -> void:
	var overlay: NetDebugOverlay = _open(_client_stats())
	overlay._unhandled_input(_pad(JOY_BUTTON_A))
	assert_eq(_source.simulation_calls.size(), 0)


func test_pad_chord_does_nothing_while_hidden() -> void:
	var overlay: NetDebugOverlay = _make_overlay()
	Input.action_press(&"camera_snap_home")
	overlay._unhandled_input(_pad(JOY_BUTTON_A))
	assert_eq(_source.simulation_calls.size(), 0)
	assert_false(overlay.visible)
