extends GutTest
## InputGate unit cases through its public API and the Events bus.

var _gate: InputGate = null


func before_each() -> void:
	_gate = InputGate.new()


func after_each() -> void:
	# The gate is still subscribed here; a reset leaves the bus-fed state clean for the next test.
	Events.match_scope_reset.emit()
	_gate = null


func test_starts_unblocked() -> void:
	assert_false(_gate.is_blocked())
	for blocker: int in InputGate.Blocker.values():
		assert_false(_gate.is_blocked_by(blocker as InputGate.Blocker))


func test_pause_events_toggle_pause_only() -> void:
	Events.pause_menu_opened.emit()
	assert_true(_gate.is_blocked())
	assert_true(_gate.is_blocked_by(InputGate.Blocker.PAUSE))
	assert_false(_gate.is_blocked_by(InputGate.Blocker.CHAT))
	Events.pause_menu_closed.emit()
	assert_false(_gate.is_blocked())


func test_chat_events_toggle_chat_only() -> void:
	Events.chat_input_opened.emit()
	assert_true(_gate.is_blocked_by(InputGate.Blocker.CHAT))
	assert_false(_gate.is_blocked_by(InputGate.Blocker.PAUSE))
	Events.chat_input_closed.emit()
	assert_false(_gate.is_blocked())


func test_results_ready_blocks_until_reset() -> void:
	Events.match_results_ready.emit({})
	assert_true(_gate.is_blocked_by(InputGate.Blocker.RESULTS))
	Events.match_scope_reset.emit()
	assert_false(_gate.is_blocked())


func test_closing_pause_under_chat_stays_blocked() -> void:
	Events.pause_menu_opened.emit()
	Events.chat_input_opened.emit()
	Events.pause_menu_closed.emit()
	assert_true(_gate.is_blocked())
	assert_true(_gate.is_blocked_by(InputGate.Blocker.CHAT))
	assert_false(_gate.is_blocked_by(InputGate.Blocker.PAUSE))
	Events.chat_input_closed.emit()
	assert_false(_gate.is_blocked())


func test_closing_chat_under_pause_stays_blocked() -> void:
	Events.chat_input_opened.emit()
	Events.pause_menu_opened.emit()
	Events.chat_input_closed.emit()
	assert_true(_gate.is_blocked())
	assert_true(_gate.is_blocked_by(InputGate.Blocker.PAUSE))
	Events.pause_menu_closed.emit()
	assert_false(_gate.is_blocked())


func test_is_blocked_by_chat_is_true_only_for_chat() -> void:
	Events.pause_menu_opened.emit()
	Events.match_results_ready.emit({})
	_gate.set_blocker(InputGate.Blocker.PANEL, true)
	assert_false(_gate.is_blocked_by(InputGate.Blocker.CHAT))
	Events.chat_input_opened.emit()
	assert_true(_gate.is_blocked_by(InputGate.Blocker.CHAT))


func test_set_blocker_panel_blocks_and_clears() -> void:
	_gate.set_blocker(InputGate.Blocker.PANEL, true)
	assert_true(_gate.is_blocked())
	assert_true(_gate.is_blocked_by(InputGate.Blocker.PANEL))
	_gate.set_blocker(InputGate.Blocker.PANEL, false)
	assert_false(_gate.is_blocked())


func test_panel_survives_reset_and_clear_match_scope() -> void:
	_gate.set_blocker(InputGate.Blocker.PANEL, true)
	Events.match_scope_reset.emit()
	assert_true(_gate.is_blocked_by(InputGate.Blocker.PANEL))
	_gate.clear_match_scope()
	assert_true(_gate.is_blocked_by(InputGate.Blocker.PANEL))


func test_clearing_panel_under_open_pause_stays_blocked() -> void:
	Events.pause_menu_opened.emit()
	_gate.set_blocker(InputGate.Blocker.PANEL, true)
	_gate.set_blocker(InputGate.Blocker.PANEL, false)
	assert_true(_gate.is_blocked())
	assert_true(_gate.is_blocked_by(InputGate.Blocker.PAUSE))


func test_clear_match_scope_clears_pause_chat_and_results() -> void:
	Events.pause_menu_opened.emit()
	Events.chat_input_opened.emit()
	Events.match_results_ready.emit({})
	_gate.clear_match_scope()
	assert_false(_gate.is_blocked())


func test_set_blocker_chat_is_cleared_by_reset() -> void:
	_gate.set_blocker(InputGate.Blocker.CHAT, true)
	assert_true(_gate.is_blocked_by(InputGate.Blocker.CHAT))
	Events.match_scope_reset.emit()
	assert_false(_gate.is_blocked())
