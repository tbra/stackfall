extends GutTest
## Bontago-1pi.159.15 (N1): UiSpatialFocus wires left/right/up/down from on-screen rects.


## a b
## c d
func _grid() -> Array[Control]:
	var host: Control = Control.new()
	add_child_autofree(host)
	var controls: Array[Control] = []
	for pos: Vector2 in [Vector2(0, 0), Vector2(200, 0), Vector2(0, 100), Vector2(200, 100)]:
		var c: Control = Control.new()
		c.position = pos
		c.size = Vector2(100, 40)
		host.add_child(c)
		controls.append(c)
	return controls


func _n(control: Control, side: Side) -> Control:
	return control.get_node(control.get_focus_neighbor(side)) as Control


func test_wire_picks_neighbours_by_position() -> void:
	var g: Array[Control] = _grid()
	UiSpatialFocus.wire(g, false)
	assert_eq(_n(g[0], SIDE_RIGHT), g[1])
	assert_eq(_n(g[0], SIDE_BOTTOM), g[2])
	assert_eq(_n(g[3], SIDE_LEFT), g[2])
	assert_eq(_n(g[3], SIDE_TOP), g[1])


func test_loop_wraps_to_the_far_side_in_the_same_row() -> void:
	var g: Array[Control] = _grid()
	UiSpatialFocus.wire(g, true)
	assert_eq(_n(g[0], SIDE_LEFT), g[1])
	assert_eq(_n(g[2], SIDE_RIGHT), g[3])
	assert_eq(_n(g[0], SIDE_TOP), g[2])
