extends GutTest
## bots plan for short block timers. The reaction delay and the V2 think deadline are
## clamped so the plan is ready before the auto-drop minus the margin, even with max jitter, and a
## normal timer leaves the schedule exactly as before.

const TICKS_PER_S: int = 60
const SLOT: int = 0
const EPS: float = 0.0001
const SHORT_TIMER_S: float = 1.0


class TimerFakeMatch:
	extends RefCounted
	var time_left: float = 99.0

	func feed_time_left(_slot_id: int) -> float:
		return time_left

	func held_special(_slot_id: int) -> StringName:
		return &""


func _controller(difficulty: MatchConfig.AiDifficulty, fake: TimerFakeMatch) -> BotController:
	var controller: BotController = BotController.new()
	add_child_autofree(controller)
	controller.setup(SLOT, difficulty, null, null)
	controller.set_match_provider(fake)
	return controller


## Plan-ready time (reaction countdown + think ticks) for a fresh piece on a timer of `timer_s`.
func _plan_ready_s(controller: BotController, fake: TimerFakeMatch, timer_s: float) -> float:
	fake.time_left = timer_s
	controller._on_feed_block_issued(SLOT, &"cube", &"cube")
	var countdown: float = controller._countdown
	fake.time_left = timer_s - countdown
	return countdown + float(controller.think_deadline_ticks()) / float(TICKS_PER_S)


func _max_jitter_delay(controller: BotController) -> float:
	return controller._profile.reaction_delay_s + controller.tuning.think_phase_jitter_s


func test_short_timers_plan_before_the_auto_drop_margin() -> void:
	for difficulty: MatchConfig.AiDifficulty in [MatchConfig.AiDifficulty.EASY, MatchConfig.AiDifficulty.HARD]:
		for timer_s: float in [5.0, 2.0]:
			var fake: TimerFakeMatch = TimerFakeMatch.new()
			var controller: BotController = _controller(difficulty, fake)
			controller._think_delay_s = _max_jitter_delay(controller)
			var ready_s: float = _plan_ready_s(controller, fake, timer_s)
			assert_lte(ready_s, timer_s - controller.tuning.timer_plan_margin_s + EPS, "diff %d timer %s" % [difficulty, timer_s])


func test_one_second_timer_actually_clamps_the_easy_delay() -> void:
	# Easy's reaction delay is Hard's 0.2 s now, so a 2 s timer no longer clamps it.
	var fake: TimerFakeMatch = TimerFakeMatch.new()
	var controller: BotController = _controller(MatchConfig.AiDifficulty.EASY, fake)
	controller._think_delay_s = _max_jitter_delay(controller)
	_plan_ready_s(controller, fake, SHORT_TIMER_S)
	var tuning: BotTuning = controller.tuning
	assert_lt(controller._countdown, controller._think_delay_s, "clamped")
	assert_almost_eq(controller._countdown, SHORT_TIMER_S - tuning.timer_plan_margin_s - tuning.timer_min_think_s, EPS)
