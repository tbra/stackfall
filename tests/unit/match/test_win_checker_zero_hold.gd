extends GutTest
## A zero capture hold never divides by zero: with no capture the progress ring reads empty.


func test_zero_hold_with_no_capture_reads_zero_progress() -> void:
	var checker: WinChecker = WinChecker.new(PackedVector2Array([Vector2.ZERO]), 0.0)
	assert_eq(checker.capture_progress(), 0.0)
	assert_eq(checker.winner(), WinChecker.NO_TEAM)
