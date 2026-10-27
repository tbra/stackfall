extends GutTest
## PlayerController pushes the block timer to its ghost every processed frame, input gate or not.

const FRAME: float = 1.0 / 60.0

var _saved: MatchContext = null
var _fake: FakeMatchContext = null


func before_each() -> void:
	_saved = MatchContext.installed()
	_fake = FakeMatchContext.new()
	_fake.set_local_held(LocalHeldView.new())
	MatchContext.install(_fake)


func after_each() -> void:
	MatchContext.install(_saved)


func _make_controller() -> PlayerController:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller.set_acting_slot(0)
	return controller


func test_timer_inside_the_warning_lead_pulses_the_ghost() -> void:
	_fake.feed_timer_enabled_value = true
	_fake.feed_time_by_slot[0] = 0.1
	var controller: PlayerController = _make_controller()
	controller.input_gate.set_blocker(InputGate.Blocker.PANEL, true)
	controller._process(FRAME)
	assert_true(controller._ghost.is_pulse_active(), "pushed even with input disabled")


func test_timer_disabled_pushes_no_pulse() -> void:
	_fake.feed_time_by_slot[0] = 0.1
	var controller: PlayerController = _make_controller()
	controller._process(FRAME)
	assert_false(controller._ghost.is_pulse_active())
