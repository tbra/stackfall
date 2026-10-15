extends GutTest
## Bontago-1pi.159.31: UiFlow / UiStack apply their config gaps as theme separations.


func test_flow_gaps_become_separations() -> void:
	var flow: UiFlow = UiFlow.new()
	add_child_autofree(flow)
	flow.h_gap_px = 3
	flow.v_gap_px = 5
	assert_eq(flow.get_theme_constant("h_separation"), 3)
	assert_eq(flow.get_theme_constant("v_separation"), 5)


func test_stack_gap_becomes_separation() -> void:
	var stack: UiStack = UiStack.new()
	add_child_autofree(stack)
	stack.gap_px = 7
	assert_eq(stack.get_theme_constant("separation"), 7)
