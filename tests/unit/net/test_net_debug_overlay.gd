extends GutTest
## docs/archive/M3a_PLAN.md P4: ui/debug/NetDebugOverlay.gd shows Net.stats() verbatim,
## toggles on net_debug_toggle (F3, or gamepad Back+Y — see tools/
## bootstrap_project.gd's DECISION for why the chord is built from two
## actions rather than one InputMap event), and its preset button applies
## NetConfig.sim_preset_lag_ms / sim_preset_loss.
##
## Bontago-mv0.1.12: also covers the per-slot intents/cursors_refused rows,
## through a small local double for net/MatchNet.gd's four counter getters
## (_FakeMatchNetCounters below) -- there is no shared FakeMatchNet fixture
## yet, and this package doesn't own tests/support/, so the double lives
## here rather than there, following the fixture pattern (a scripted answer
## per call) the shared fakes already use.


## Test double for net/MatchNet.gd's read-only per-slot counters
## (intents_sent/accepted/refused, cursors_refused) -- exactly the four
## getters ui/debug/NetDebugOverlay.gd's match_net_provider seam reads.
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
	var scene: PackedScene = load("res://ui/debug/NetDebugOverlay.tscn")
	var overlay: NetDebugOverlay = autofree(scene.instantiate())
	add_child_autofree(overlay)
	var fake: FakeNet = FakeNet.new()
	overlay.net_provider = fake
	overlay.match_net_provider = _FakeMatchNetCounters.new()
	return overlay


func _fake_of(overlay: NetDebugOverlay) -> FakeNet:
	return overlay.net_provider as FakeNet


func after_each() -> void:
	# Synthetic gamepad "holds" use the real Input singleton; release it so
	# one test's chord can't leak into the next.
	Input.action_release(&"camera_snap_home")


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


func test_preset_button_applies_configured_lag_and_loss() -> void:
	var overlay: NetDebugOverlay = _make_overlay()
	var config: NetConfig = overlay.net_config
	overlay._on_preset_pressed()
	var calls: Array[Dictionary] = _fake_of(overlay).set_simulation_calls
	assert_eq(calls.size(), 1)
	assert_almost_eq(float(calls[0].get("lag_ms")), config.sim_preset_lag_ms, 0.01)
	assert_almost_eq(float(calls[0].get("loss")), config.sim_preset_loss, 0.001)


# --- Per-slot cursors_refused / intents rows (Bontago-mv0.1.12) -------------
