class_name MainMatchFlowPort
extends MainFlowPort
## MF0: virtuals Main calls for the match world lifecycle. The bodies are
## empty; game/main/MainMatchFlow.gd (MF3) overrides them. MatchConfig is already in the autoload
## closure, so this port adds nothing heavy to Main's compile closure.


func end_match_world() -> void:
	pass


func on_match_state_changed(_from_state: int, _to_state: int) -> void:
	pass


## True while a match world is built or building; MainMatchFlow overrides it.
func is_world_live() -> bool:
	return false
