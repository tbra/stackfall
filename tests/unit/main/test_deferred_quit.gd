extends GutTest
## DeferredQuit: the close-request state machine shared by AppLoader and Boot. A close while work
## is in flight is deferred until the work settles and fires exactly once; a close with nothing in
## flight fires at once. quit_callable replaces the real quit (no QuitFlag mark, no tree quit).

var _quit_calls: int = 0


func _count_quit() -> void:
	_quit_calls += 1


func _make() -> DeferredQuit:
	_quit_calls = 0
	var quit: DeferredQuit = DeferredQuit.new()
	quit.quit_callable = _count_quit
	return quit


func test_fresh_state_is_neither_requested_nor_done() -> void:
	var quit: DeferredQuit = _make()
	assert_false(quit.is_requested())
	assert_false(quit.is_done())
	quit.settle(false)
	assert_eq(_quit_calls, 0, "settling without a close request never quits")
	assert_false(quit.is_done())


func test_close_when_idle_quits_at_once() -> void:
	var quit: DeferredQuit = _make()
	quit.on_close_request(false)
	assert_eq(_quit_calls, 1)
	assert_true(quit.is_requested())
	assert_true(quit.is_done())


func test_close_while_busy_is_deferred_until_settled() -> void:
	var quit: DeferredQuit = _make()
	quit.on_close_request(true)
	assert_eq(_quit_calls, 0, "no quit while the in-flight work runs")
	assert_true(quit.is_requested())
	assert_false(quit.is_done())
	quit.settle(true)
	assert_eq(_quit_calls, 0, "still busy: still waiting")
	assert_false(quit.is_done())
	quit.settle(false)
	assert_eq(_quit_calls, 1, "quits when the work settles")
	assert_true(quit.is_done())


func test_quit_fires_exactly_once() -> void:
	var quit: DeferredQuit = _make()
	quit.on_close_request(true)
	quit.settle(false)
	quit.settle(false)
	quit.on_close_request(false)
	quit.on_close_request(true)
	quit.settle(false)
	assert_eq(_quit_calls, 1, "repeated close requests and settles quit once")


func test_second_close_request_after_idle_quit_is_a_no_op() -> void:
	var quit: DeferredQuit = _make()
	quit.on_close_request(false)
	quit.on_close_request(false)
	assert_eq(_quit_calls, 1)


func test_a_valid_quit_callable_does_not_mark_the_process_as_quitting() -> void:
	var was_quitting: bool = QuitFlag.is_quitting()
	var quit: DeferredQuit = _make()
	quit.on_close_request(false)
	assert_eq(QuitFlag.is_quitting(), was_quitting, "the test seam leaves QuitFlag alone (caches stay live)")
