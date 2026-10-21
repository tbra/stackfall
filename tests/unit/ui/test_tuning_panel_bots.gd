extends GutTest
## The F4 panel's Bots tab: aim_margin_share is a 0..1 slider with a description, and an edit lands on
## the BotStackTuning instance the bots read (core/ai/BotEvaluator.stack_tuning) on their next think.

const FIELD: String = "aim_margin_share"

var _panel: TuningPanel = null
var _saved_share: float = 0.0


func before_each() -> void:
	_saved_share = BotEvaluator.stack_tuning.aim_margin_share
	_panel = autofree(load("res://ui/debug/TuningPanel.tscn").instantiate())
	add_child_autofree(_panel)
	_panel.rebuild()


func after_each() -> void:
	BotEvaluator.stack_tuning.aim_margin_share = _saved_share


func _slider() -> HSlider:
	for row: Dictionary in _panel._rows:
		if row.get("resource") == _panel.bot_stack_tuning and row.get("property") == FIELD:
			return row.get("control") as HSlider
	return null


func test_panel_edits_the_instance_the_bots_read() -> void:
	assert_same(_panel.bot_stack_tuning, BotEvaluator.stack_tuning)
	var slider: HSlider = _slider()
	assert_not_null(slider, "the Bots tab has an aim_margin_share row")
	slider.value_changed.emit(0.25)
	assert_almost_eq(BotEvaluator.stack_tuning.aim_margin_share, 0.25, 0.0001)


func test_aim_margin_share_is_a_zero_to_one_slider_with_a_description() -> void:
	var slider: HSlider = _slider()
	assert_eq(slider.min_value, 0.0)
	assert_eq(slider.max_value, 1.0)
	assert_false(_panel.hints.description_for("BotStackTuning", FIELD).is_empty())


func test_reset_restores_the_shipped_share() -> void:
	BotEvaluator.stack_tuning.aim_margin_share = 0.4
	_panel.reset_all()
	assert_almost_eq(BotEvaluator.stack_tuning.aim_margin_share, 1.0, 0.0001)


func test_every_bot_tuning_field_shown_has_a_description() -> void:
	var shown: int = 0
	for row: Dictionary in _panel._rows:
		if row.get("resource") == _panel.bot_stack_tuning:
			shown += 1
			assert_false(_panel.hints.description_for("BotStackTuning", String(row["property"])).is_empty(), String(row["property"]))
	assert_gt(shown, 0)
