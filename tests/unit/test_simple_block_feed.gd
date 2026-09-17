extends GutTest
## The M1 placeholder feed (core/feed/SimpleBlockFeed.gd): a plain random
## pick, replaced by the weighted bag in M2.


func test_next_only_returns_provided_shapes() -> void:
	var cube: BlockShape = load("res://config/blocks/cube.tres")
	var domino: BlockShape = load("res://config/blocks/domino.tres")
	var feed: SimpleBlockFeed = SimpleBlockFeed.new([cube, domino], 1)
	for _i: int in range(50):
		var picked: BlockShape = feed.next()
		assert_true(picked == cube or picked == domino)


func test_eventually_returns_every_shape() -> void:
	var shapes: Array[BlockShape] = [
		load("res://config/blocks/cube.tres"),
		load("res://config/blocks/domino.tres"),
		load("res://config/blocks/bar3.tres"),
	]
	var feed: SimpleBlockFeed = SimpleBlockFeed.new(shapes, 7)
	var seen: Dictionary = {}
	for _i: int in range(200):
		seen[feed.next().id] = true
	for shape: BlockShape in shapes:
		assert_true(seen.has(shape.id), "%s should show up in 200 draws." % shape.id)
