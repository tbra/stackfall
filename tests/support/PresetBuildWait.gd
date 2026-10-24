class_name PresetBuildWait
extends RefCounted
## The sandbox presets pre-place their towers once the disc's tilt spring has
## rested (some tens of physics ticks after the match starts or the field resets),
## so a test counts physics ticks until the expected number of blocks stands.

## Far longer than the spring's rest hold; a build that never happens fails the
## caller's count assertion instead of hanging.
const MAX_BUILD_WAIT_TICKS: int = 300


static func wait_for_blocks(tree: SceneTree, expected: int) -> void:
	var waited: int = 0
	while Match.blocks_parent().get_child_count() < expected and waited < MAX_BUILD_WAIT_TICKS:
		await tree.physics_frame
		waited += 1
