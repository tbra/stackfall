class_name MainSandboxFlowPort
extends MainFlowPort
## MF0: virtuals Main calls for the hot-seat, sandbox and tutorial flows.
## The bodies are empty; game/main/MainSandboxFlow.gd (MF1) overrides them.


func start_hot_seat_match() -> void:
	pass


func start_sandbox_match() -> void:
	pass


func start_sandbox_from_menu() -> void:
	pass


func start_gift_demo_from_menu() -> void:
	pass


func start_tower_topple_from_menu() -> void:
	pass


func start_tutorial_from_menu() -> void:
	pass


## Starts a match for a non-lobby mode: MD-F2 overrides this.
func launch(_config: MatchConfig, _extras: ModeExtras) -> void:
	pass


## Attaches the mode's node to the freshly built match world.
func attach_extras(_extras: ModeExtras, _local_player: Node) -> void:
	pass
