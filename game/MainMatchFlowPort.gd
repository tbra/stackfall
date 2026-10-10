class_name MainMatchFlowPort
extends MainFlowPort
## Bontago-1pi.11.84 (MF0): virtuals Main calls for the match world lifecycle. The bodies are
## empty; game/MainMatchFlow.gd (MF3) overrides them. MatchConfig is already in the autoload
## closure, so this port adds nothing heavy to Main's compile closure.


## Awaits internally; Main forwards without await.
func build_match_world(_force_staging_for_test: bool = false) -> void:
	pass


func end_match_world() -> void:
	pass


func spawn_bot_controllers(_config: MatchConfig) -> void:
	pass


func on_match_state_changed(_from_state: int, _to_state: int) -> void:
	pass
