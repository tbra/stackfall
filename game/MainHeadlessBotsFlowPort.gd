class_name MainHeadlessBotsFlowPort
extends MainFlowPort
## Bontago-1pi.11.84 (MF0): virtuals Main calls for the headless bot-match flow
## (`--headless-host --bots=<n>`). game/MainHeadlessBotsFlow.gd (MF2) overrides them.


func start_match_with_args(_args: PackedStringArray) -> void:
	pass


## Report-tick entry point driven from Main's frame loop while a bot match runs.
func report_tick(_delta: float) -> void:
	pass
