extends GutTest
## docs/M3a_PLAN.md P4: ui/NetDebugOverlay.gd shows Net.stats() verbatim,
## toggles on net_debug_toggle (F3, or gamepad Back+Y — see tools/
## bootstrap_project.gd's DECISION for why the chord is built from two
## actions rather than one InputMap event), and its preset button applies
## NetConfig.sim_preset_lag_ms / sim_preset_loss.
##
## Bontago-mv0.1.12: also covers the per-slot intents/cursors_refused rows,
## through a small local double for net/MatchNet.gd's four counter getters
## (_FakeMatchNetCounters below) -- there is no shared FakeMatchNet fixture
## yet, and this package doesn't own tests/unit/support/, so the double lives
## here rather than there, following the fixture pattern (a scripted answer
## per call) the shared fakes already use.


## Test double for net/MatchNet.gd's read-only per-slot counters
## (intents_sent/accepted/refused, cursors_refused) -- exactly the four
## getters ui/NetDebugOverlay.gd's match_net_provider seam reads.
class _FakeMatchNetCounters:
	extends RefCounted
	var intents_sent_by_slot: Dictionary = {}
	var intents_accepted_by_slot: Dictionary = {}
	var intents_refused_by_slot: Dictionary = {}
	var cursors_refused_by_slot: Dictionary = {}

	func intents_sent(slot_id: int) -> int:
		return int(intents_sent_by_slot.get(slot_id, 0))

	func intents_accepted(slot_id: int) -> int:
		return int(intents_accepted_by_slot.get(slot_id, 0))

	func intents_refused(slot_id: int) -> int:
		return int(intents_refused_by_slot.get(slot_id, 0))

	func cursors_refused(slot_id: int) -> int:
		return int(cursors_refused_by_slot.get(slot_id, 0))


func _make_overlay() -> NetDebugOverlay:
	var scene: PackedScene = load("res://ui/NetDebugOverlay.tscn")
	var overlay: NetDebugOverlay = autofree(scene.instantiate())
	add_child_autofree(overlay)
	var fake: FakeNet = FakeNet.new()
	overlay.net_provider = fake
	overlay.match_net_provider = _FakeMatchNetCounters.new()
	return overlay


func _fake_of(overlay: NetDebugOverlay) -> FakeNet:
	return overlay.net_provider as FakeNet


func _fake_counters_of(overlay: NetDebugOverlay) -> _FakeMatchNetCounters:
	return overlay.match_net_provider as _FakeMatchNetCounters


func _slot_label(overlay: NetDebugOverlay, slot_id: int) -> Label:
	var rows: Node = overlay.get_node("%SlotRows")
	return rows.get_child(slot_id) as Label


func after_each() -> void:
	# Synthetic gamepad "holds" use the real Input singleton; release it so
	# one test's chord can't leak into the next.
	Input.action_release(&"camera_snap_home")


func test_hidden_by_default() -> void:
	var overlay: NetDebugOverlay = _make_overlay()
	assert_false(overlay.visible)


func test_f3_toggles_visibility_with_no_gamepad_needed() -> void:
	var overlay: NetDebugOverlay = _make_overlay()
	var key_event: InputEventKey = InputEventKey.new()
	key_event.device = -1
	key_event.physical_keycode = KEY_F3
	key_event.pressed = true
	assert_true(key_event.is_action_pressed(&"net_debug_toggle"))

	overlay._unhandled_input(key_event)
	assert_true(overlay.visible)
	overlay._unhandled_input(key_event)
	assert_false(overlay.visible)


func test_gamepad_y_alone_does_not_toggle() -> void:
	var overlay: NetDebugOverlay = _make_overlay()
	var button_event: InputEventJoypadButton = InputEventJoypadButton.new()
	button_event.device = -1
	button_event.button_index = JOY_BUTTON_Y
	button_event.pressed = true
	assert_true(button_event.is_action_pressed(&"net_debug_toggle"))

	overlay._unhandled_input(button_event)
	assert_false(overlay.visible, "Y alone is rotate_reset, not the debug chord.")


func test_gamepad_back_plus_y_toggles() -> void:
	var overlay: NetDebugOverlay = _make_overlay()
	Input.action_press(&"camera_snap_home")

	var button_event: InputEventJoypadButton = InputEventJoypadButton.new()
	button_event.device = -1
	button_event.button_index = JOY_BUTTON_Y
	button_event.pressed = true

	overlay._unhandled_input(button_event)
	assert_true(overlay.visible, "Back held + Y pressed should toggle the overlay.")


func test_stats_updated_event_refreshes_labels() -> void:
	var overlay: NetDebugOverlay = _make_overlay()
	Events.net_stats_updated.emit({
		"mode": 1,
		"peers": 3,
		"ping_ms": 42.0,
		"snapshot_bps": 3800.0,
		"snapshot_last_bytes": 512,
		"interp_delay_ms": 110.0,
		"loss_pct": 0.02,
	})
	assert_true((overlay.get_node("%ModeLabel") as Label).text.contains("Host"))
	assert_true((overlay.get_node("%ModeLabel") as Label).text.contains("3"))
	assert_true((overlay.get_node("%PingLabel") as Label).text.contains("42"))
	assert_true((overlay.get_node("%SnapshotLabel") as Label).text.contains("512"))
	assert_true((overlay.get_node("%InterpLabel") as Label).text.contains("110"))
	assert_true((overlay.get_node("%LossLabel") as Label).text.contains("2.0"))


func test_preset_button_applies_configured_lag_and_loss() -> void:
	var overlay: NetDebugOverlay = _make_overlay()
	var config: NetConfig = overlay.net_config
	overlay._on_preset_pressed()
	var calls: Array[Dictionary] = _fake_of(overlay).set_simulation_calls
	assert_eq(calls.size(), 1)
	assert_almost_eq(float(calls[0].get("lag_ms")), config.sim_preset_lag_ms, 0.01)
	assert_almost_eq(float(calls[0].get("loss")), config.sim_preset_loss, 0.001)


func test_off_button_zeroes_lag_and_loss() -> void:
	var overlay: NetDebugOverlay = _make_overlay()
	overlay._on_preset_pressed()
	overlay._on_off_pressed()
	var calls: Array[Dictionary] = _fake_of(overlay).set_simulation_calls
	var last: Dictionary = calls[calls.size() - 1]
	assert_almost_eq(float(last.get("lag_ms")), 0.0, 0.01)
	assert_almost_eq(float(last.get("loss")), 0.0, 0.001)


# --- Per-slot cursors_refused / intents rows (Bontago-mv0.1.12) -------------

func test_slot_rows_hidden_with_no_recorded_activity() -> void:
	var overlay: NetDebugOverlay = _make_overlay()
	overlay._refresh_slot_rows()
	for slot_id: int in range(8):
		assert_false(
			_slot_label(overlay, slot_id).visible, "slot %d has no counters yet" % slot_id
		)


func test_slot_row_shows_cursors_refused_count() -> void:
	var overlay: NetDebugOverlay = _make_overlay()
	var counters: _FakeMatchNetCounters = _fake_counters_of(overlay)
	counters.intents_sent_by_slot[2] = 5
	counters.cursors_refused_by_slot[2] = 3
	overlay._refresh_slot_rows()

	var label: Label = _slot_label(overlay, 2)
	assert_true(label.visible)
	assert_true(label.text.contains("3"), label.text)


func test_slot_row_zero_cursors_refused_still_shows_zero() -> void:
	var overlay: NetDebugOverlay = _make_overlay()
	var counters: _FakeMatchNetCounters = _fake_counters_of(overlay)
	# Non-zero elsewhere so the row is visible, but cursors_refused itself is 0.
	counters.intents_accepted_by_slot[1] = 4
	counters.cursors_refused_by_slot[1] = 0
	overlay._refresh_slot_rows()

	var label: Label = _slot_label(overlay, 1)
	assert_true(label.visible)
	assert_true(label.text.contains("cursors refused 0"), label.text)


func test_slot_rows_hidden_for_a_client_even_with_refusals() -> void:
	var overlay: NetDebugOverlay = _make_overlay()
	overlay.net_provider = FakeNet.client(0)
	var counters: _FakeMatchNetCounters = _fake_counters_of(overlay)
	counters.cursors_refused_by_slot[0] = 7
	overlay._refresh_slot_rows()

	assert_false(
		_slot_label(overlay, 0).visible,
		"a client's own copy of these counters never reflects real refusals"
	)


func test_slot_rows_follow_stats_updated_signal() -> void:
	var overlay: NetDebugOverlay = _make_overlay()
	var counters: _FakeMatchNetCounters = _fake_counters_of(overlay)
	counters.cursors_refused_by_slot[3] = 9
	counters.intents_sent_by_slot[3] = 1
	Events.net_stats_updated.emit({"mode": 1, "peers": 1})

	assert_true(_slot_label(overlay, 3).text.contains("9"))


func test_slot_count_changes_are_handled() -> void:
	var overlay: NetDebugOverlay = _make_overlay()
	var counters: _FakeMatchNetCounters = _fake_counters_of(overlay)
	counters.intents_sent_by_slot[0] = 1
	overlay._refresh_slot_rows()
	assert_true(_slot_label(overlay, 0).visible)
	assert_false(_slot_label(overlay, 5).visible)

	# A new slot joins and places.
	counters.intents_sent_by_slot[5] = 1
	overlay._refresh_slot_rows()
	assert_true(_slot_label(overlay, 0).visible)
	assert_true(_slot_label(overlay, 5).visible)

	# A new match resets every counter (net/MatchNet.gd's reset_counters()).
	counters.intents_sent_by_slot.clear()
	overlay._refresh_slot_rows()
	assert_false(_slot_label(overlay, 0).visible)
	assert_false(_slot_label(overlay, 5).visible)
