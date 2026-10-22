extends GutTest
## HoleBacklog: hole cells the rules want, applied to the disc at a bounded
## rate per drain. Pure logic, driven only through its public calls.

const IN_DISK: PackedInt32Array = [10, 11, 12, 13, 14, 15, 16, 17]


func _cells(values: Array) -> PackedInt32Array:
	return PackedInt32Array(values)


func test_drain_opens_wanted_cells_in_fifo_order_within_the_budget() -> void:
	var backlog: HoleBacklog = HoleBacklog.new()
	backlog.want(_cells([14, 11, 16, 10, 13]), PackedInt32Array(), IN_DISK)

	assert_eq(backlog.drain(2), _cells([14, 11]), "The first two wanted cells open first.")
	assert_eq(backlog.applied_count(), 2)
	assert_eq(backlog.drain(2), _cells([16, 10]), "The next drain carries on in order.")
	assert_eq(backlog.drain(2), _cells([13]), "The last drain returns what is left.")
	assert_eq(backlog.applied_count(), 5)
	assert_true(backlog.drain(2).is_empty(), "An empty backlog opens nothing.")


func test_is_applied_agrees_with_what_drain_returned() -> void:
	var backlog: HoleBacklog = HoleBacklog.new()
	backlog.want(_cells([11, 12, 13]), PackedInt32Array(), IN_DISK)

	assert_false(backlog.is_applied(11), "A wanted cell is not applied before a drain.")
	assert_eq(backlog.applied_count(), 0)
	var opened: PackedInt32Array = backlog.drain(2)
	assert_eq(opened, _cells([11, 12]), "Two of the three open.")
	for cell: int in IN_DISK:
		assert_eq(backlog.is_applied(cell), opened.has(cell), "cell %d" % cell)
	assert_eq(backlog.applied_count(), opened.size())


func test_a_cell_opened_then_closed_before_a_drain_is_reported_opened_but_ends_closed() -> void:
	var backlog: HoleBacklog = HoleBacklog.new()
	backlog.want(_cells([12]), PackedInt32Array(), IN_DISK)
	backlog.want(PackedInt32Array(), _cells([12]), IN_DISK)

	assert_eq(backlog.drain(10), _cells([12]), "Both toggles apply in order; the open is still reported.")
	assert_false(backlog.is_applied(12), "The final state is closed.")
	assert_eq(backlog.applied_count(), 0)


func test_open_close_open_before_a_drain_reports_each_open_and_ends_open() -> void:
	var backlog: HoleBacklog = HoleBacklog.new()
	backlog.want(_cells([12]), PackedInt32Array(), IN_DISK)
	backlog.want(PackedInt32Array(), _cells([12]), IN_DISK)
	backlog.want(_cells([12]), PackedInt32Array(), IN_DISK)

	assert_eq(backlog.drain(10), _cells([12, 12]))
	assert_true(backlog.is_applied(12))
	assert_eq(backlog.applied_count(), 1)


func test_a_budget_below_one_still_applies_one_toggle() -> void:
	var backlog: HoleBacklog = HoleBacklog.new()
	backlog.want(_cells([11, 12]), PackedInt32Array(), IN_DISK)

	assert_eq(backlog.drain(0), _cells([11]), "The budget is clamped to at least one.")
	assert_eq(backlog.drain(-5), _cells([12]))


func test_closing_a_cell_that_was_never_opened_does_nothing() -> void:
	var backlog: HoleBacklog = HoleBacklog.new()
	backlog.want(PackedInt32Array(), _cells([11]), IN_DISK)

	assert_true(backlog.drain(10).is_empty())
	assert_eq(backlog.applied_count(), 0)


func test_closing_an_applied_cell_removes_it_without_reopening_it() -> void:
	var backlog: HoleBacklog = HoleBacklog.new()
	backlog.want(_cells([11, 12]), PackedInt32Array(), IN_DISK)
	backlog.drain(10)

	backlog.want(PackedInt32Array(), _cells([11]), IN_DISK)
	var opened: PackedInt32Array = backlog.drain(10)

	assert_true(opened.is_empty(), "Closing a hole opens nothing.")
	assert_false(backlog.is_applied(11))
	assert_true(backlog.is_applied(12))
	assert_eq(backlog.applied_count(), 1)


func test_wanting_an_already_applied_cell_does_not_report_it_again() -> void:
	var backlog: HoleBacklog = HoleBacklog.new()
	backlog.want(_cells([11]), PackedInt32Array(), IN_DISK)
	backlog.drain(10)
	backlog.want(_cells([11]), PackedInt32Array(), IN_DISK)

	assert_true(backlog.drain(10).is_empty())
	assert_eq(backlog.applied_count(), 1)


func test_cells_outside_the_disk_are_ignored() -> void:
	var backlog: HoleBacklog = HoleBacklog.new()
	backlog.want(_cells([3, 11, 99, 20]), PackedInt32Array(), IN_DISK)

	assert_eq(backlog.drain(10), _cells([11]), "Only the in-disk cell opens.")
	assert_false(backlog.is_applied(3))
	assert_false(backlog.is_applied(99))
	assert_eq(backlog.applied_count(), 1)


func test_clear_forgets_applied_and_waiting_cells() -> void:
	var backlog: HoleBacklog = HoleBacklog.new()
	backlog.want(_cells([11, 12, 13]), PackedInt32Array(), IN_DISK)
	backlog.drain(1)
	assert_eq(backlog.applied_count(), 1, "fixture: one applied, two waiting")

	backlog.clear()

	assert_eq(backlog.applied_count(), 0)
	assert_false(backlog.is_applied(11))
	assert_true(backlog.drain(10).is_empty(), "No waiting cell survives clear().")
