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


## Lobby Start press (host): overlay up, pre-start frames, then the match starts.
func on_lobby_start_pressed(_config: MatchConfig) -> void:
	pass


## Client side: the host announced a match is loading.
func on_match_loading_announced() -> void:
	pass


func on_loading_territory_updated(_raster: TerritoryRaster, _groups: TerritoryGroups) -> void:
	pass


func on_loading_territory_replicated(_raster: TerritoryRaster) -> void:
	pass


func on_loading_readiness_timed_out() -> void:
	pass
