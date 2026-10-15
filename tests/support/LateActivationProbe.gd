extends Node
## Test double for S2b: records late_activate calls and whether Main existed at that moment.

var calls: int = 0
var main_present_at_call: bool = true


func late_activate() -> void:
	calls += 1
	main_present_at_call = get_tree().root.get_node_or_null(NodePath("Main")) != null
