class_name MainHeadlessBotsFlowPort
extends MainFlowPort
## MF0: virtuals Main calls for the headless bot-match flow
## (`--headless-host --bots=<n>`). game/main/MainHeadlessBotsFlow.gd (MF2) overrides them.


func start_match_with_args(_args: PackedStringArray, _base_config: MatchConfig) -> void:
	pass


## Tears down the report timer and block_placed hookup; a no-op when none started.
func stop_diagnostics() -> void:
	pass
