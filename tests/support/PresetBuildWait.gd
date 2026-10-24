class_name PresetBuildWait
extends RefCounted
## The sandbox presets pre-place their towers once the disc's tilt spring has
## rested (some tens of physics ticks after the match starts or the field resets),
## so a test counts physics ticks until the expected number of blocks stands.

## Far longer than the spring's rest hold; a build that never happens fails the
## caller's count assertion instead of hanging.
const MAX_BUILD_WAIT_TICKS: int = 300


static func wait_for_blocks(tree: SceneTree, expected: int, replaced: Array[Node] = []) -> void:
	var waited: int = 0
	while live_blocks(replaced).size() < expected and waited < MAX_BUILD_WAIT_TICKS:
		await tree.physics_frame
		waited += 1


## The blocks standing now that are not in `replaced` (the towers a reset is
## about to take down) and not queued for deletion.
static func live_blocks(replaced: Array[Node] = []) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in Match.blocks_parent().get_children():
		if not replaced.has(child) and not child.is_queued_for_deletion():
			out.append(child)
	return out
